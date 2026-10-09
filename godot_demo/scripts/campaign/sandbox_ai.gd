extends Node
## The campaign's computer-run sides, for whichever system the player is in:
##   traders fly between stations and the jump gates, and run from trouble
##   patrols (Vanguard Navy, Ascendancy) guard their stations and fight their enemies
##   pirates prowl round their den and jump anyone weak enough
##   the infection: an infected world sends up spore pods and hive ships at anyone who
##   comes close, and overgrown derelicts fire spores at clean ships nearby

const POD := preload("res://scripts/pod.gd")
const AI := preload("res://scripts/ai.gd")
const MAX_HIVES := 2

var t := 0.0
var _tick := 0.0
var hive_t := 70.0
var spore_t := 150.0


func _physics_process(dt: float) -> void:
	if G.game_over:
		return
	t += dt
	hive_t -= dt
	spore_t -= dt
	_tick -= dt
	if _tick > 0.0:
		return
	_tick = 1.5
	for s in G.vessels:
		if not is_instance_valid(s) or s.kind != "ship" or s.destroyed or s.team == 1 or s.drifting or s.helm != null:
			continue
		if s.has_meta("dock_at") or not s.boarding.is_empty():
			continue
		match String(s.get_meta("role", "")):
			"trader":
				_trader(s)
			"patrol":
				_patrol(s)
			"pirate":
				_pirate(s)
			"hive":
				_hive(s)
	_infected_world()
	_spores()
	_ground_roam()


# ------------------------------------------------------------------ helpers

func _nearest_enemy(s: Node, from: Vector3, radius: float, ships_only: bool = false) -> Node:
	var best: Node = null
	var bd := radius
	for v in G.vessels:
		if not is_instance_valid(v) or v.destroyed or v == s or not G.enemies(s.team, v.team):
			continue
		if not AI.sees(int(s.team), v):
			continue                                     # (in the fog: it hasn't been found)
		if ships_only and v.kind != "ship":
			continue
		if v.get("drifting") == true and s.team != 4:
			continue                                     # leave the derelicts be
		var d: float = from.distance_to(v.global_position)
		if d < bd:
			bd = d
			best = v
	return best


func _engage(s: Node, tgt: Node) -> void:
	s.attack_target = tgt
	var d: float = s.global_position.distance_to(tgt.global_position)
	var big: bool = s.cls in ["MEDIUM", "LARGE", "XL"]
	if d > 1000.0:
		s.move_target = tgt.global_position + (s.global_position - tgt.global_position).normalized() * (800.0 if big else 600.0)
	if big and d < 2400.0 and s.launch_wanted == 0 and s.parked_count() > 0 and randf() < 0.2:
		s.request_fighters()


func _stations_of(pred: Callable) -> Array:
	return G.vessels.filter(func(v): return is_instance_valid(v) and v.kind == "station" and not v.destroyed and pred.call(v))


func _gate_spots() -> Array:
	var out: Array = []
	for g in G.match_node.gates:
		out.append(g["pos"])
	return out


# ------------------------------------------------------------------ traders

func _trader(s: Node) -> void:
	# trouble: run for the nearest friendly station
	var threat := _nearest_enemy(s, s.global_position, 1300.0, true)
	if threat:
		var safe := _stations_of(func(v): return not G.enemies(s.team, v.team))
		safe.sort_custom(func(a, b): return a.global_position.distance_to(s.global_position) < b.global_position.distance_to(s.global_position))
		if not safe.is_empty():
			s.move_target = safe[0].global_position + (s.global_position - safe[0].global_position).normalized() * 350.0
		s.set_meta("wait", 0.0)
		return
	var dest: Vector3 = s.get_meta("dest", Vector3.INF)
	if dest == Vector3.INF or s.global_position.distance_to(dest) < 420.0:
		var w: float = s.get_meta("wait", 0.0) + 1.5
		s.set_meta("wait", w)
		if dest != Vector3.INF and w < 25.0:
			return                                       # trading
		if dest != Vector3.INF and s.get_meta("to_gate", false):
			# through the gate and back in by another: the traffic never stops
			var gs := _gate_spots()
			if gs.size() > 1:
				var g2: Vector3 = gs[randi() % gs.size()]
				s.global_position = g2 + (Vector3.ZERO - g2).normalized() * 250.0
		var spots: Array = []
		for st in _stations_of(func(v): return not G.enemies(s.team, v.team) and v.team != 3):
			spots.append([st.global_position + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * 380.0, false])
		for g in _gate_spots():
			spots.append([g, true])
		if spots.is_empty():
			return
		var pick: Array = spots[randi() % spots.size()]
		s.set_meta("dest", pick[0])
		s.set_meta("to_gate", pick[1])
		s.set_meta("wait", 0.0)
		s.move_target = pick[0]
	elif s.move_target == Vector3.INF:
		s.move_target = dest


# ------------------------------------------------------------------ patrols

func _patrol(s: Node) -> void:
	var tgt := _nearest_enemy(s, s.global_position, 2600.0)
	if tgt:
		_engage(s, tgt)
		return
	s.attack_target = null
	if s.move_target == Vector3.INF:
		var spots: Array = []
		for st in _stations_of(func(v): return v.team == s.team or not G.enemies(s.team, v.team)):
			spots.append(st.global_position)
		spots += _gate_spots()
		if not spots.is_empty():
			var p: Vector3 = spots[randi() % spots.size()]
			s.move_target = p + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * 500.0


# ------------------------------------------------------------------ pirates

func _pirate(s: Node) -> void:
	var den := _stations_of(func(v): return v.team == 3)
	var home: Vector3 = den[0].global_position if not den.is_empty() else s.global_position
	var tgt := _nearest_enemy(s, s.global_position, 2200.0, true)
	if tgt == null:
		tgt = _nearest_enemy(s, home, 2400.0)
	if tgt:
		_engage(s, tgt)
		# raiders board soft targets: pirates love a prize ship
		if s.cls == "MEDIUM" and s.troops >= 8 and tgt.get("shields") != null and tgt.shields <= tgt.max_shields * 0.2 \
				and tgt.kind == "ship" and s.global_position.distance_to(tgt.global_position) < 1400.0 and randf() < 0.3:
			s.start_boarding(tgt, "pods")
		return
	s.attack_target = null
	if s.move_target == Vector3.INF or s.global_position.distance_to(home) > 1400.0:
		var a := randf() * TAU
		s.move_target = home + Vector3(cos(a), 0, sin(a)) * randf_range(400.0, 900.0)


# ------------------------------------------------------------------ the infection

func _infected_planet() -> Dictionary:
	for p in G.match_node.planets:
		if p["def"]["biome"] == "infected":
			return p
	return {}


## Hive ships: hunt anything clean near their world.
func _hive(s: Node) -> void:
	var pl := _infected_planet()
	var c: Vector3 = pl["pos"] if not pl.is_empty() else s.global_position
	var tgt := _nearest_enemy(s, c, 5000.0)
	if tgt:
		_engage(s, tgt)
		if s.global_position.distance_to(tgt.global_position) < 1500.0 and randf() < 0.08:
			_spore_pod(s.to_global(s.aabb.get_center()) + Vector3.UP * 8.0, tgt)
		return
	if s.move_target == Vector3.INF:
		var a := randf() * TAU
		s.move_target = Vector3(c.x, 0, c.z) + Vector3(cos(a), 0, sin(a)) * (float(pl.get("radius", 600.0)) + randf_range(500.0, 1400.0))


## The world itself: when anyone comes near, it sends up spore pods, and now and then a hive ship.
func _infected_world() -> void:
	if hive_t > 0.0:
		return
	var pl := _infected_planet()
	if pl.is_empty():
		hive_t = 9999.0
		return
	hive_t = randf_range(80.0, 140.0)
	var c: Vector3 = pl["pos"]
	var r: float = pl["radius"]
	var near: Array = []
	for v in G.vessels:
		if is_instance_valid(v) and not v.destroyed and v.team != 4 and v.global_position.distance_to(c) < r + 3800.0:
			near.append(v)
	if near.is_empty():
		return
	var tgt: Node = near[randi() % near.size()]
	var up_from: Vector3 = c + (tgt.global_position - c).normalized() * (r + 20.0)
	var hives := G.vessels.filter(func(v): return is_instance_valid(v) and not v.destroyed and v.get_meta("role", "") == "hive")
	if hives.size() < MAX_HIVES and randf() < 0.45:
		var p: Vector3 = Vector3(up_from.x, 0, up_from.z) + (tgt.global_position - up_from).normalized() * 250.0
		var cls := infected_class()
		var hs: Node3D = G.match_node.spawn_runtime_ship(cls, 4, 4 if cls == "LARGE" else 3, "Hive Ship" if cls == "LARGE" else "Infected " + {"SMALL_FRIGATE": "Frigate", "MEDIUM": "Cruiser"}[cls], p, [], "hive")
		overgrow_ship(hs)
		G.say("Something rose from %s: an infected %s" % [pl["def"]["name"], {"SMALL_FRIGATE": "frigate", "MEDIUM": "cruiser", "LARGE": "HIVE SHIP"}[cls]], tgt.team)
		G.stat("hive_ships")
	else:
		_spore_pod(up_from, tgt)


## How big the infection's ships come: small frigates early on, cruisers once it's had
## time to grow (about 40 minutes in), and only late (100+ minutes) the great hive ships.
static func infected_class() -> String:
	var day: float = G.campaign.day if G.campaign else 0.0
	if day < 2400.0:
		return "SMALL_FRIGATE"
	if day < 6000.0:
		return "MEDIUM" if randf() < 0.55 else "SMALL_FRIGATE"
	var k := randf()
	return "LARGE" if k < 0.3 else ("MEDIUM" if k < 0.75 else "SMALL_FRIGATE")


## A small or medium infected ship (built on an ordinary hull): grown over inside and out.
static func overgrow_ship(s: Node3D) -> void:
	if s == null or s.cls == "LARGE":
		return
	s.get_tree().create_timer(1.0).timeout.connect(func():
		if is_instance_valid(s) and s.get("zones") != null:
			for z in s.zones:
				z["infected"] = true
				z["growth"] = randf_range(0.7, 1.0)
			if s.has_method("_update_infection_overlay"):
				s._update_infection_overlay())


func _spore_pod(from: Vector3, tgt: Node) -> void:
	var entries: Array = tgt.boarding_entries(from)
	if entries.is_empty():
		return
	var e: Array = entries[0]
	var pod: Node3D = POD.new()
	get_tree().root.add_child(pod)
	pod.setup(from, 4, 4, tgt, e[0], e[1], e[2], e[3], ["swarmer", "swarmer", "swarmer", "swarmer"], true)
	G.say("Spore pod inbound at %s!" % tgt.display_name, tgt.team)
	G.stat("spore_pods")


## Overgrown derelicts and hive ships spit spores at clean ships drifting too close.
func _spores() -> void:
	if spore_t > 0.0:
		return
	spore_t = 150.0
	for v in G.vessels:
		if not is_instance_valid(v) or v.destroyed or v.infected_fraction() < 0.3:
			continue
		var tgt: Node = null
		var bd := 2600.0
		for o in G.vessels:
			if o != v and is_instance_valid(o) and not o.destroyed and o.infected_fraction() < 0.05:
				var d: float = v.global_position.distance_to(o.global_position)
				if d < bd:
					bd = d
					tgt = o
		if tgt:
			_spore_pod(v.to_global(v.aabb.get_center()) + Vector3.UP * 8.0, tgt)
			return


## On a surface: outlaw and infected squads wander their ground when there's no fight.
func _ground_roam() -> void:
	var g: Node3D = G.match_node.ground
	if g == null:
		return
	for v in G.vehicles:
		if is_instance_valid(v) and v.team != 1 and v.path_i >= v.path.size() and randf() < 0.08:
			v.order_move(v.global_position + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 160.0)
	for c in g.occupants:
		if not is_instance_valid(c) or c.state != "alive" or c == G.possessed:
			continue
		if c.has_meta("escort"):
			# a convoy's escort: keep up with the MRAP
			var mr = c.get_meta("escort")
			if mr == null or not is_instance_valid(mr):
				c.remove_meta("escort")
			else:
				if c.target == null and (c.squad == null or c.squad.leader == c) \
						and (c.order.is_empty() or (mr.global_position.distance_to(c.global_position) > 30.0 and randf() < 0.5)):
					c.order = {"type": "move", "pos": g.near_local(g.to_local(mr.global_position), 8.0), "vessel": g}
				continue
		if c.has_meta("wave"):
			# an infected attack wave: on to the target, then fight whatever's there
			var at: Vector3 = c.get_meta("wave")
			if c.global_position.distance_to(at) < 25.0:
				c.remove_meta("wave")
			elif c.target == null and c.order.is_empty():
				c.order = {"type": "move", "pos": g.near_local(g.to_local(at), 15.0), "vessel": g}
			continue
		if c.team in [3, 4] and not c.has_meta("guard_checked"):
			# garrisons stay round their camp or hive: walk its perimeter
			c.set_meta("guard_checked", true)
			for o in G.match_node.outposts:
				if is_instance_valid(o) and o.part == "core" and o.team == c.team and o.global_position.distance_to(c.global_position) < 250.0:
					c.set_meta("perimeter", [o.global_position, 70.0])
					break
		if is_instance_valid(c) and c.has_meta("perimeter") and c.state == "alive" and c != G.possessed and c.target == null \
				and c.order.is_empty() and (c.squad == null or c.squad.leader == c) and randf() < 0.35:
			# a dropship's guards: walk to another point on the perimeter
			var pr: Array = c.get_meta("perimeter")
			var a := randf() * TAU
			var rad: float = float(pr[1]) * randf_range(0.5, 1.0)
			var wp: Vector3 = (pr[0] as Vector3) + Vector3(cos(a), 0, sin(a)) * rad
			c.order = {"type": "move", "pos": g.near_local(g.to_local(wp), 20.0), "vessel": g}
			continue
		if not is_instance_valid(c) or c.state != "alive" or c == G.possessed or not (c.team in [3, 4]) or c.has_meta("perimeter"):
			continue
		if c.target != null or not (c.order.is_empty() or c.order.get("type", "") == "hold"):
			continue
		if c.squad and c.squad.leader != c:
			continue
		if randf() < 0.3:
			c.order = {"type": "move", "pos": g.near_local(c.position, 140.0), "vessel": g}
