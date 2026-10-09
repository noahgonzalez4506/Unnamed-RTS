extends Node
## Multiplayer (ENet). The host runs the real game: AI, combat, damage, ships.
## Each client
##   * builds the same vessels from the same match setup, then gets every character
##     from the host (with the host's network ids),
##   * drives its own soldier locally (instant movement) and reports where it is,
##     what it shot and what it used,
##   * receives a world snapshot 20 times a second (vessels, characters, fighters,
##     pods, weapon effects) and a slower sync (resources, research, modules, captures,
##     the infection, game over),
##   * sends commander orders as commands the host carries out.
## Sides without a human commander are run by the AI.

signal lobby_changed
signal status(text: String)

const SNAP_HZ := 20.0
const STATES := ["alive", "downed", "dead"]

var active := false
var players := {}                 # peer id -> {name, team, role}
var _ready_peers := {}            # peers whose match scene is loaded
var _snap_t := 0.0
var _slow_t := 0.0
var _me_t := 0.0
var _fx: Array = []               # [kind, a, b, color] effects to forward this tick
var _connected := false


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_gone)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): status.emit("Couldn't connect"); leave())
	multiplayer.server_disconnected.connect(_on_server_gone)


# ------------------------------------------------------------------ lobby

func host(player_name: String) -> bool:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(G.PORT, 8) != OK:
		status.emit("Couldn't open UDP port %d (is another game running?)" % G.PORT)
		return false
	multiplayer.multiplayer_peer = peer
	active = true
	players = {1: {"name": player_name, "team": 1, "role": "commander"}}
	status.emit("Hosting on port %d. Waiting for players..." % G.PORT)
	lobby_changed.emit()
	return true


func join(ip: String, player_name: String) -> bool:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(ip, G.PORT) != OK:
		status.emit("Couldn't start a connection")
		return false
	multiplayer.multiplayer_peer = peer
	active = true
	set_meta("my_name", player_name)
	return true


func leave() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	active = false
	players.clear()
	_ready_peers.clear()
	lobby_changed.emit()


func _on_connected() -> void:
	status.emit("Connected")
	_hello.rpc_id(1, get_meta("my_name", "Player"))


func _on_server_gone() -> void:
	status.emit("The host left")
	leave()
	if G.match_node:
		get_tree().change_scene_to_file("res://menu.tscn")


func _on_peer_connected(_id: int) -> void:
	pass                                           # they introduce themselves with _hello


func _on_peer_gone(id: int) -> void:
	players.erase(id)
	_ready_peers.erase(id)
	if multiplayer.is_server():
		_push_lobby()
		if G.match_node:
			G.say("%s left the match" % str(id), 0)
			for c in G.characters:                 # their soldier goes back to the AI
				if is_instance_valid(c) and c.owner_peer == id:
					c.owner_peer = 0


@rpc("any_peer", "reliable")
func _hello(player_name: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	var n1 := players.values().filter(func(p): return p["team"] == 1).size()
	var n2 := players.values().filter(func(p): return p["team"] == 2).size()
	players[id] = {"name": player_name, "team": 2 if n2 < n1 else 1, "role": "soldier"}
	_push_lobby()


func _push_lobby() -> void:
	_lobby.rpc(players)
	lobby_changed.emit()


@rpc("authority", "reliable")
func _lobby(p: Dictionary) -> void:
	players = p
	lobby_changed.emit()


func set_my_choice(team: int, role: String) -> void:
	if multiplayer.is_server():
		_apply_choice(1, team, role)
	else:
		_choice.rpc_id(1, team, role)


@rpc("any_peer", "reliable")
func _choice(team: int, role: String) -> void:
	_apply_choice(multiplayer.get_remote_sender_id(), team, role)


func _apply_choice(id: int, team: int, role: String) -> void:
	if not players.has(id):
		return
	if team > 0:
		players[id]["team"] = team
	if role != "":
		players[id]["role"] = role
	_push_lobby()


func start_match() -> void:
	if multiplayer.is_server():
		_start.rpc(randi() % 1000000 + 1)             # one map seed for everyone: same system, same ships


@rpc("authority", "call_local", "reliable")
func _start(seed_: int = 0) -> void:
	var me: Dictionary = players.get(multiplayer.get_unique_id(), {"team": 1, "role": "soldier"})
	G.config = {"mode": "net", "team": me["team"], "start": me["role"], "difficulty": 1, "seed": seed_}
	get_tree().change_scene_to_file("res://match.tscn")


func commander_teams() -> Array:
	var out: Array = []
	for id in players:
		if players[id]["role"] == "commander" and not out.has(players[id]["team"]):
			out.append(players[id]["team"])
	return out


# ------------------------------------------------------------------ match start

## Client: our match scene (vessels only) is ready; ask for the people.
func client_ready() -> void:
	_client_ready.rpc_id(1)


@rpc("any_peer", "reliable")
func _client_ready() -> void:
	var id := multiplayer.get_remote_sender_id()
	var all: Array = []
	for c in G.characters:
		if is_instance_valid(c) and c.state != "dead":
			all.append(_spawn_data(c))
	_spawn_many.rpc_id(id, all)
	_ready_peers[id] = true


func _spawn_data(c: Node) -> Array:
	return [c.get_meta("net_id", 0), G.vessels.find(c.vessel), c.position, c.rotation.y, c.team, c.faction, c.role,
		STATES.find(c.state), c.owner_peer, c.weapon_model if c.armed else ""]


func announce_spawn(c: Node) -> void:
	var d := _spawn_data(c)
	for id in _ready_peers:
		_spawn_many.rpc_id(id, [d])


@rpc("authority", "reliable")
func _spawn_many(list: Array) -> void:
	for d in list:
		if not G.match_node:
			continue
		if G.net_ids.has(int(d[0])):
			var known: Node = G.net_ids[int(d[0])]
			if int(d[8]) == multiplayer.get_unique_id() and is_instance_valid(known) and G.commander and G.possessed != known:
				G.commander.possess(known)                # it's ours: take control
			continue
		var v: Node = G.vessels[int(d[1])] if int(d[1]) >= 0 and int(d[1]) < G.vessels.size() else null
		if v == null:
			continue
		var team: int = int(d[4])
		var c: Node = G.match_node.spawn_character(v, d[2], 1 if team == 4 else team, int(d[5]), d[6], int(d[0]))
		c.rotation.y = d[3]
		if team == 4:
			c._convert(true)
		if d[9] != "" and d[9] != c.weapon_model:
			c.give_weapon(d[9])
		if int(d[8]) == multiplayer.get_unique_id() and G.commander:
			G.commander.possess(c)


# ------------------------------------------------------------------ host: snapshots

func _physics_process(dt: float) -> void:
	if not active or not G.match_node or multiplayer.multiplayer_peer == null:
		return
	if multiplayer.is_server():
		_snap_t -= dt
		if _snap_t <= 0.0 and not _ready_peers.is_empty():
			_snap_t = 1.0 / SNAP_HZ
			_send_snapshot()
		_slow_t -= dt
		if _slow_t <= 0.0 and not _ready_peers.is_empty():
			_slow_t = 1.0
			_send_slow()


func queue_fx(kind: String, a: Vector3, b: Vector3, col: Color) -> void:
	if active and multiplayer.is_server() and _fx.size() < 120:
		_fx.append([kind, a, b, col])


func _send_snapshot() -> void:
	var vs := PackedFloat32Array()
	for v in G.vessels:
		vs.append_array([v.global_position.x, v.global_position.y, v.global_position.z, v.rotation.y,
			v.get("hull") if v.get("hull") != null else 0.0, v.shields])
	var cs := PackedFloat32Array()
	for c in G.characters:
		if not is_instance_valid(c):
			continue
		var flags := (1 if c.crouch else 0) | (2 if c.rig.aiming else 0) | (4 if c.working else 0) | (8 if c.carrying else 0) \
			| (16 if c.revive_t >= 0.0 else 0) | (32 if c.reload_t >= 0.0 else 0) | (64 if c.piloting else 0) \
			| (128 if c.stun_t > 0.0 else 0)
		if c.role == "grenadier":                      # the kit on the belt: shells (bits 8-10), rounds (11-12)
			flags |= (clampi(c.gl_ammo, 0, 7) << 8) | (clampi(c.breach_ammo, 0, 3) << 11)
		# riding a pod or shuttle: the mag field carries the craft's id (negative) instead
		var mag_or_ride: float = c.mag if c.riding == null or not is_instance_valid(c.riding) else -float(c.riding.get_meta("net_id", 0))
		cs.append_array([c.get_meta("net_id", 0), c.position.x, c.position.y, c.position.z, c.rotation.y,
			STATES.find(c.state), c.hp, Vector2(c.velocity.x, c.velocity.z).length(), flags, c.team, mag_or_ride,
			G.vessels.find(c.vessel)])
	var fs := PackedFloat32Array()
	for f in G.fighters + G.pods + G.missiles:
		if is_instance_valid(f):
			var r: Vector3 = f.global_rotation
			var kind := 1.0 if f in G.fighters else (4.0 if f in G.missiles else (3.0 if f.has_method("_unload") else (5.0 if f.has_method("_deliver") else 2.0)))
			fs.append_array([f.get_meta("net_id", 0), kind, f.global_position.x, f.global_position.y,
				f.global_position.z, r.x, r.y, r.z, f.team, f.faction])
	# characters go out in packet-sized chunks; vessels, craft and effects ride with the first
	var per := 25 * 12
	var first := true
	var i := 0
	while i < cs.size() or first:
		var chunk := cs.slice(i, i + per)
		for id in _ready_peers:
			_snapshot.rpc_id(id, vs if first else PackedFloat32Array(), chunk, fs if first else PackedFloat32Array(),
				_fx if first else [], first)
		first = false
		i += per
	_fx.clear()


@rpc("authority", "unreliable_ordered")
func _snapshot(vs: PackedFloat32Array, cs: PackedFloat32Array, fs: PackedFloat32Array, fx: Array, full: bool) -> void:
	if not G.match_node or not G.match_node.ready_for_net:
		return
	for i in min(G.vessels.size(), vs.size() / 6):
		var v: Node = G.vessels[i]
		var k: int = i * 6
		if v.kind == "ship":
			v.net_pos = Vector3(vs[k], vs[k + 1], vs[k + 2])
			v.net_yaw = vs[k + 3]
			v.hull = vs[k + 4]
		v.shields = vs[k + 5]
	var seen := {}
	var n := 12
	for i in cs.size() / n:
		var k: int = i * n
		var id := int(cs[k])
		seen[id] = true
		var c: Node = G.net_ids.get(id)
		if c == null or not is_instance_valid(c):
			continue
		var vi := int(cs[k + 11])
		if vi >= 0 and vi < G.vessels.size() and G.vessels[vi] != c.vessel:
			c.vessel.leave(c)
			c.reparent(G.vessels[vi])
			c.vessel = G.vessels[vi]
			c.vessel.board(c)
		var st: String = STATES[int(cs[k + 5])]
		c.hp = cs[k + 6]
		if int(cs[k + 9]) == 4 and c.team != 4:
			c._convert(true)
		if st == "downed" and c.state == "alive":
			c.go_down(null)
		elif st == "dead" and c.state != "dead":
			c.die(null)
		elif st == "alive" and c.state == "downed":
			c.revive(null)
		if c == G.possessed:
			# EMP'd on the host: stun our own body too (once per pulse, on the flag's rising edge)
			var stunned := int(cs[k + 8]) & 128 != 0
			if stunned and not c.get_meta("net_stun", false):
				c.stun(2.0)
			c.set_meta("net_stun", stunned)
			var ride := int(cs[k + 10])
			if ride < 0:
				c.riding = G.net_ids.get(-ride)
			elif c.riding != null:
				c.riding = null                        # we're out: go where the host put us
				c.position = Vector3(cs[k + 1], cs[k + 2], cs[k + 3])
				c.visible = true
			continue                                   # our own body moves locally
		c.net_pos = Vector3(cs[k + 1], cs[k + 2], cs[k + 3])
		c.net_yaw = cs[k + 4]
		c.net_speed = cs[k + 7]
		var flags := int(cs[k + 8])
		c.crouch = flags & 1 != 0
		c.rig.aiming = flags & 2 != 0
		c.working = flags & 4 != 0
		c.revive_t = 0.5 if flags & 16 != 0 else -1.0
		c.reload_t = 0.5 if flags & 32 != 0 else -1.0
		if c.team != 4 and c.role != "infected":
			c.rig.twitch = 1.0 if flags & 128 != 0 else 0.0     # EMP'd on the host
		if c.role == "grenadier":
			var ga: int = (flags >> 8) & 7
			var ba: int = (flags >> 11) & 3
			if ga != c.gl_ammo or ba != c.breach_ammo:
				c.gl_ammo = ga
				c.breach_ammo = ba
				c.kit_refresh()
		c.visible = flags & 64 == 0
		if (flags & 8 != 0) != c.carrying:
			c.carrying = flags & 8 != 0
		c.mag = maxi(0, int(cs[k + 10]))
		c.visible = c.visible and int(cs[k + 10]) >= 0
	_seen_chars.merge(seen)
	if not full:
		return
	_apply_craft_and_fx(fs, fx)
	# a new tick begins: anyone missing from the whole previous tick is gone on the host
	var last := _last_seen
	_last_seen = _seen_chars
	_seen_chars = seen.duplicate()
	if last.is_empty():
		return
	for id in G.net_ids.keys():
		var c: Node = G.net_ids[id]
		if is_instance_valid(c) and c.get("rig") != null and not last.has(id) and not _last_seen.has(id) and c != G.possessed:
			c.vessel.leave(c)
			G.characters.erase(c)
			G.net_ids.erase(id)
			c.queue_free()


var _seen_chars := {}
var _last_seen := {}


func _apply_craft_and_fx(fs: PackedFloat32Array, fx: Array) -> void:
	_apply_craft(fs)
	for e in fx:
		match e[0]:
			"t":
				G.tracer(e[1], e[2], e[3], 0.03, 0.05)
			"e":
				G.explosion(e[1], e[2].x, e[3])


func _apply_craft(fs: PackedFloat32Array) -> void:
	var n := 10
	var seen := {}
	for i in fs.size() / n:
		var k: int = i * n
		var id := int(fs[k])
		seen[id] = true
		var f: Node = G.net_ids.get(id)
		if f == null or not is_instance_valid(f):
			if G.possessed and G.possessed.piloting and G.possessed.piloting.get_meta("net_id", -1) == id:
				continue
			f = _craft_puppet(int(fs[k + 1]), int(fs[k + 8]), int(fs[k + 9]))
			G.register(f, id)
			f.global_position = Vector3(fs[k + 2], fs[k + 3], fs[k + 4])
		if G.possessed and G.possessed.piloting == f:
			continue
		f.set("net_pos", Vector3(fs[k + 2], fs[k + 3], fs[k + 4]))
		f.set("net_rot", Vector3(fs[k + 5], fs[k + 6], fs[k + 7]))
	for id in G.net_ids.keys():
		var f: Node = G.net_ids[id]
		if is_instance_valid(f) and (f in G.fighters or f in G.pods or f in G.missiles) and not seen.has(id):
			if G.possessed and G.possessed.piloting == f:
				continue
			G.fighters.erase(f)
			G.pods.erase(f)
			G.missiles.erase(f)
			G.net_ids.erase(id)
			G.explosion(f.global_position, 4.0)
			f.queue_free()


func _craft_puppet(kind: int, team: int, faction: int) -> Node3D:
	if kind == 1:
		var f: Node3D = preload("res://scripts/fighter.gd").new()
		get_tree().root.add_child(f)
		f.setup(null, Transform3D(), team, faction)
		f.stage = 2
		return f
	var p := PodPuppet.new()
	p.team = team
	p.faction = faction
	get_tree().root.add_child(p)
	if kind == 4:                                   # a missile
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.6, 0.6, 3.2)
		m.mesh = bm
		m.material_override = G._mat(Color(0.75, 0.75, 0.8), 0.0)
		p.add_child(m)
		p.trail = true
		G.missiles.append(p)
		return p
	var folder := "ships_X" if team == 4 else ("ships_P" if faction == 3 else "ships_F%d" % faction)
	var model := "ship_XS_DROPSHIP.glb" if kind == 3 else ("ship_XS_DARTER.glb" if kind == 5 else "ship_XS_POD.glb")
	if kind == 5 and not ResourceLoader.exists("res://models/%s/%s" % [folder, model]):
		folder = "ships_F1"
	var inst: Node3D = load("res://models/%s/%s" % [folder, model]).instantiate()
	for sb in inst.find_children("*", "StaticBody3D", true, false):
		(sb as StaticBody3D).collision_layer = 0
	p.add_child(inst)
	G.pods.append(p)
	return p


class PodPuppet extends Node3D:
	var team := 1
	var faction := 1
	var net_pos := Vector3.INF
	var net_rot := Vector3.ZERO

	var trail := false
	var _last := Vector3.INF

	func _process(dt: float) -> void:
		if net_pos != Vector3.INF:
			global_position = global_position.lerp(net_pos, clampf(dt * 10.0, 0.0, 1.0))
			global_rotation = net_rot
		if trail:
			if _last != Vector3.INF and _last.distance_to(global_position) > 0.5:
				G.tracer(global_position, _last, Color(0.85, 0.85, 0.9), 0.35, 0.35)
			_last = global_position

	func take_hit(_d: float, _f: Vector3 = Vector3.ZERO, _b: Node = null) -> void:
		pass


# ------------------------------------------------------------------ host: slow sync

func _send_slow() -> void:
	var vs: Array = []
	for v in G.vessels:
		var d := {"team": v.team, "destroyed": v.destroyed, "alarm": v.alarm, "zones": [], "doors": []}
		for z in v.zones:
			d["zones"].append([z["infected"], z["growth"]])
		var ds := PackedByteArray()
		for dd in v.doors:     # 0 intact, 1 blown off, 2/3 knocked flat (which way)
			var st := 0
			if dd["breached"]:
				st = 1 if not dd["fallen"] else (2 if (dd.get("push_n", dd["n"]) as Vector3).dot(dd["n"]) >= 0.0 else 3)
			ds.append(st)
		d["doors"] = ds
		var ws := PackedByteArray()
		for wd in v.breach_walls:
			ws.append(1 if wd["breached"] else 0)
		d["walls"] = ws
		d["supplies"] = v.supplies
		if v.kind == "station":
			d["reserve"] = v.reserve
			var m := {}
			for code in v.modules:
				m[code] = v.modules[code]["state"]
			d["modules"] = m
			d["training"] = v.training.size()
		else:
			d["troops"] = v.troops
			d["pads"] = v.pads.map(func(p): return p["parked"] != null)
			d["lock"] = G.vessels.find(v.lock) if v.lock != null and is_instance_valid(v.lock) else -1
		vs.append(d)
	_slow.rpc(vs, G.resources, G.research, G.researching, G.game_over)


@rpc("authority", "reliable")
func _slow(vs: Array, res: Dictionary, research: Dictionary, researching: Dictionary, over: bool) -> void:
	if not G.match_node or not G.match_node.ready_for_net:
		return
	G.resources = res
	G.research = research
	G.researching = researching
	for i in min(vs.size(), G.vessels.size()):
		var v: Node = G.vessels[i]
		var d: Dictionary = vs[i]
		v.team = d["team"]
		v.alarm = d["alarm"]
		if d["destroyed"] and not v.destroyed:
			v.destroyed = true
		var changed := false
		for j in min(v.zones.size(), d["zones"].size()):
			if v.zones[j]["infected"] != d["zones"][j][0] or abs(v.zones[j]["growth"] - d["zones"][j][1]) > 0.05:
				v.zones[j]["infected"] = d["zones"][j][0]
				v.zones[j]["growth"] = d["zones"][j][1]
				changed = true
		if changed:
			v._update_infection_overlay()
		for j in min(v.doors.size(), d["doors"].size()):
			var st: int = d["doors"][j]
			var dd: Dictionary = v.doors[j]
			if st != 0 and not dd["breached"]:
				v._destroy_door(dd)
				if st == 1:
					(dd["node"] as Node3D).visible = false
				else:
					dd["fallen"] = true
					v._lay_flat(dd, dd["n"] * (1.0 if st == 2 else -1.0))
		if d.has("walls"):
			for j in min(v.breach_walls.size(), d["walls"].size()):
				if d["walls"][j] == 1 and not v.breach_walls[j]["breached"]:
					v.breach_door(v.breach_walls[j])          # blown on the host: open it here too
		if d.has("modules"):
			for code in d["modules"]:
				if v.modules.has(code) and v.modules[code]["state"] != d["modules"][code]:
					v.modules[code]["state"] = d["modules"][code]
					v.show_module_state(code, d["modules"][code])
			v.set_meta("net_training", d["training"])
		if d.has("troops"):
			v.troops = d["troops"]
		if d.has("lock"):
			var li: int = int(d["lock"])
			v.lock = G.vessels[li] if li >= 0 and li < G.vessels.size() else null
		if d.has("supplies"):
			v.supplies = d["supplies"]
		if d.has("reserve"):
			v.reserve = d["reserve"]
	if over and not G.game_over:
		G.game_over = true


@rpc("authority", "reliable")
func _say(text: String, team: int) -> void:
	if G.commander:
		G.commander.log_event(text, team)


func broadcast_say(text: String, team: int) -> void:
	if active and multiplayer.is_server() and not _ready_peers.is_empty():
		for id in _ready_peers:
			_say.rpc_id(id, text, team)


@rpc("authority", "reliable")
func _banner(title: String, sub: String) -> void:
	if G.commander:
		G.commander.banner(title, sub)


func broadcast_banner(title: String, sub: String) -> void:
	if active and multiplayer.is_server():
		_banner.rpc(title, sub)


# ------------------------------------------------------------------ client -> host

func send_my_state(c: Node) -> void:
	_me_t -= get_physics_process_delta_time()
	if _me_t > 0.0:
		return
	_me_t = 1.0 / 30.0
	_my_state.rpc_id(1, c.get_meta("net_id", 0), c.position, c.rotation.y, c.look_pitch, c.crouch, c.ads)


@rpc("any_peer", "unreliable_ordered")
func _my_state(id: int, pos: Vector3, yaw: float, pitch: float, crouch: bool, ads: bool) -> void:
	var c: Node = G.net_ids.get(id)
	if c == null or not is_instance_valid(c) or c.owner_peer != multiplayer.get_remote_sender_id() or c.state != "alive":
		return
	c.position = pos
	c.rotation.y = yaw
	c.look_pitch = pitch
	c.crouch = crouch
	c.ads = ads
	c.rig.aiming = ads or c.armed


## At a ship's helm on a client: stream the controls to the host, which flies the ship.
func send_helm(v: Node) -> void:
	_helm_t -= get_process_delta_time()
	if _helm_t > 0.0 or G.possessed == null:
		return
	_helm_t = 1.0 / 20.0
	_helm_in.rpc_id(1, G.possessed.get_meta("net_id", 0), G.vessels.find(v), v.helm_throttle, v.helm_turn,
		v.manual_aim, v.manual_fire)


var _helm_t := 0.0


@rpc("any_peer", "unreliable_ordered")
func _helm_in(id: int, vi: int, throttle: float, turn: float, aim: Vector3, fire: bool) -> void:
	var c: Node = G.net_ids.get(id)
	if c == null or not is_instance_valid(c) or c.owner_peer != multiplayer.get_remote_sender_id():
		return
	if vi < 0 or vi >= G.vessels.size() or G.vessels[vi].get("helm") != c:
		return
	var sh: Node = G.vessels[vi]
	sh.helm_throttle = clampf(throttle, -1.0, 1.0)
	sh.helm_turn = clampf(turn, -1.0, 1.0)
	sh.manual_aim = aim
	sh.manual_fire = fire


func send_fire(c: Node, from: Vector3, dir: Vector3) -> void:
	_fire.rpc_id(1, c.get_meta("net_id", 0), from, dir)


@rpc("any_peer", "unreliable_ordered")
func _fire(id: int, from: Vector3, dir: Vector3) -> void:
	var c: Node = G.net_ids.get(id)
	if c and is_instance_valid(c) and c.owner_peer == multiplayer.get_remote_sender_id() and c.state == "alive":
		c.fire(from, dir)


func send_action(c: Node, what: String, args: Array) -> void:
	if c:
		_action.rpc_id(1, c.get_meta("net_id", 0), what, args)


@rpc("any_peer", "reliable")
func _action(id: int, what: String, args: Array) -> void:
	var c: Node = G.net_ids.get(id)
	if c == null or not is_instance_valid(c) or c.owner_peer != multiplayer.get_remote_sender_id():
		return
	match what:
		"reload":
			if c.reload_t < 0.0 and not c.spare.is_empty():
				c.reload_t = float(c.wstats.get("reload_s", 2.0))
		"grenade":
			c._throw_grenade(args[0], args.size() > 1 and bool(args[1]))
		"gl":
			if c.role == "grenadier":
				c.fire_launcher(args[0], args[1])
		"breach":
			if c.role == "grenadier":
				c.fire_breach_round(args[0], args[1])
		"medpen":
			if not c.medpens.is_empty():
				c.rig.show_slot(c.medpens.pop_back(), false)
				c.hp = min(c.max_hp, c.hp + 40)
		"use":                                         # E on a client: what commander.interact does here
			var v: Node = c.vessel
			if v.has_method("defuse_near") and v.defuse_near(c.position, c.team):
				return
			if v.has_method("room_near") and G.enemies(c.team, v.team):
				var room: String = v.room_near(c.position, 3.0)
				if room != "":
					v.plant_demo(c.position, room, c.team)
					return
			c.player_use({})
		"sabotage":
			if c.vessel.has_method("sabotage") and G.enemies(c.team, c.vessel.team):
				c.vessel.sabotage(args[0], c.team)
		"purge":
			c.purging = args[0]
		"helm":                                        # [vessel index, taking it / leaving it]
			var vi: int = args[0]
			if vi < 0 or vi >= G.vessels.size():
				return
			var sh: Node = G.vessels[vi]
			if sh.kind != "ship" or sh.team != c.team:
				return
			if bool(args[1]):
				if sh.helm == null or not is_instance_valid(sh.helm) or sh.helm.state != "alive":
					sh.helm = c
					c.piloting = sh
					sh.move_target = Vector3.INF
					sh.attack_target = null
			elif sh.helm == c:
				sh.helm = null
				sh.manual_aim = Vector3.INF
				sh.manual_fire = false
				sh.helm_throttle = 0.0
				sh.helm_turn = 0.0
				c.piloting = null
		"fighter_hit":
			var vi: int = args[0]
			if vi >= 0 and vi < G.vessels.size():
				G.vessels[vi].take_hit(3.0, args[1])
			elif args.size() > 2 and int(args[2]) > 0:
				var t: Node = G.net_ids.get(int(args[2]))
				if t and is_instance_valid(t) and t.has_method("take_hit") and G.enemies(c.team, int(t.get("team"))):
					t.take_hit(3.0, args[1])


func request_spawn(role: String, vessel_index: int) -> void:
	_spawn_req.rpc_id(1, role, vessel_index)


@rpc("any_peer", "reliable")
func _spawn_req(role: String, vi: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	if vi < 0 or vi >= G.vessels.size() or not players.has(id):
		print("NET spawn refused: unknown player %d or vessel %d (players %s)" % [id, vi, players.keys()])
		return
	var v: Node = G.vessels[vi]
	if v.team != players[id]["team"] or v.destroyed:
		print("NET spawn refused: %s is team %d, player is team %d" % [v.display_name, v.team, players[id]["team"]])
		return
	for c in G.characters:                         # one body per player
		if is_instance_valid(c) and c.owner_peer == id and c.state == "alive":
			return
	var c: Node = G.match_node.spawn_player(role, v, id)
	if c:
		announce_spawn(c)                          # again, now that it has its owner


func send_cmd(what: String, args: Array) -> void:
	_cmd.rpc_id(1, what, args)


@rpc("any_peer", "reliable")
func _cmd(what: String, args: Array) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not players.has(id):
		return
	# soldiers may give their own squad orders, ask for reinforcements, join a boarding party,
	# and (at a helm) work the ship they're flying; the rest is for commanders
	if players[id]["role"] != "commander" and not what in ["squad", "requisition", "join_board", "lock", "fleet", "board", "missiles"]:
		return
	G.match_node.run_command(players[id]["team"], what, args, id)
