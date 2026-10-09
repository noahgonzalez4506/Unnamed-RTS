extends RefCounted
## The infection as a strategic threat.
##   On a world: every hive heart grows biomass. Its brood keeps the swarm topped up, the
##   swarm walks the hive's perimeter, and every few minutes it sends an attack wave at the
##   nearest enemy installation (outlaw camps, colonies, Ascendancy outposts, our landing
##   zone). A hive with an abandoned city on its world that gathers enough biomass grows a
##   GRAVEMIND there.
##   Across the galaxy: a gravemind births infected spreader ships. They drift from system
##   to system along the jump lanes and now and then come down on a world and seed a new
##   hive at one of its landing zones. Meet one in space and it's a fight.
##   world[hive key] = {"team": 4, "biomass": b, "gravemind": bool, "gm_t": s}
##   world["infestation"] = {"ships": [{"id", "system", "next"}]}

const CAMPS := preload("res://scripts/campaign/camps.gd")
const GM_BIOMASS := 600.0
const MAX_SPREADERS := 6
const SPREAD_EVERY := 240.0        # campaign seconds between spreader births per gravemind
const HOP_EVERY := 200.0           # ...and between a spreader's moves


## Once a campaign second while we're on a world.
static func surface_tick(m: Node) -> void:
	var c = G.campaign
	for o in m.outposts.duplicate():
		if not is_instance_valid(o) or o.destroyed or o.part != "core" or o.team != 4:
			continue
		var rec: Dictionary = c.world.get(o.base_key, {})
		rec["team"] = 4
		var bm: float = float(rec.get("biomass", 0.0)) + 0.6
		rec["biomass"] = bm
		c.world[o.base_key] = rec
		# attack waves
		var wt: float = float(o.get_meta("wave_t", randf_range(90.0, 150.0))) - 1.0
		if wt <= 0.0:
			wt = randf_range(150.0, 240.0)
			var tgt := _wave_target(m, o)
			if tgt[0] != Vector3.INF and bm >= 30.0:
				rec["biomass"] = bm - 30.0
				_send_wave(m, o, tgt[0], String(tgt[1]))
		o.set_meta("wave_t", wt)
		# the gravemind
		if not rec.get("gravemind", false) and float(rec["biomass"]) >= GM_BIOMASS and not m.city.is_empty():
			rec["gravemind"] = true
			rec["gm_t"] = 0.0
			var cc: Vector3 = m.city["center"]
			CAMPS.gravemind(m, cc, o.base_key, m.system, m.terrain_P)
			G.say("The infection has consumed the abandoned city: a GRAVEMIND has formed there", 1)


## The nearest thing worth swarming: [world pos, name] (or [INF, ""]).
static func _wave_target(m: Node, hive: Node) -> Array:
	var me: Vector3 = hive.global_position
	var best := Vector3.INF
	var nm := ""
	var bd := 3200.0
	for o in m.outposts:
		if is_instance_valid(o) and not o.destroyed and o.part == "core" and o.team != 4:
			var d: float = me.distance_to(o.global_position)
			if d < bd:
				bd = d
				best = o.global_position
				nm = o.display_name
	for v in G.vessels:
		if is_instance_valid(v) and not v.destroyed and v.team != 4 and (v.kind == "station" or v.team == 1):
			var d2: float = Vector2(me.x - v.global_position.x, me.z - v.global_position.z).length()
			if d2 < bd:
				bd = d2
				best = Vector3(v.global_position.x, m.ground_y(v.global_position.x, v.global_position.z), v.global_position.z)
				nm = v.display_name
	if m.ground:
		for c in m.ground.occupants:
			if is_instance_valid(c) and c.team == 1 and c.state == "alive":
				var d3: float = me.distance_to(c.global_position)
				if d3 < bd:
					bd = d3
					best = c.global_position
					nm = "your troops"
	return [best, nm]


static func _send_wave(m: Node, hive: Node, at: Vector3, nm: String) -> void:
	var gnd: Node3D = m.ground
	if gnd == null:
		return
	var n0: int = gnd.occupants.size()
	var roles: Array = []
	for i in 6 + randi() % 4:
		roles.append("x")
	m.spawn_squad(gnd, gnd.near_local(gnd.to_local(hive.global_position) + Vector3(0, 0, 26.0), 8.0), 4, 3, roles, false)
	var wave: Array = []
	for i in range(n0, gnd.occupants.size()):
		wave.append(gnd.occupants[i])
	# a few of the perimeter guards go too
	var extra := 0
	for c in gnd.occupants:
		if extra >= 4:
			break
		if is_instance_valid(c) and c.team == 4 and c.has_meta("perimeter") and c.state == "alive":
			c.remove_meta("perimeter")
			wave.append(c)
			extra += 1
	for c in wave:
		if is_instance_valid(c):
			c.set_meta("wave", at)
			c.set_meta("guard_checked", true)
	G.say("An infected attack wave (%d) is moving on %s" % [wave.size(), nm], 1)
	G.stat("infected_waves")


## Once a campaign second, wherever we are: graveminds birth spreaders, spreaders roam the
## lanes and seed new hives.
static func galaxy_tick(m: Node) -> void:
	var c = G.campaign
	var inf: Dictionary = c.world.get("infestation", {"ships": [], "next_id": 1})
	var ships: Array = inf.get("ships", [])
	for k in c.world.keys():
		var rec = c.world[k]
		if not (rec is Dictionary) or not rec.get("gravemind", false) or rec.get("destroyed", false):
			continue
		rec["gm_t"] = float(rec.get("gm_t", 0.0)) + 1.0
		if float(rec["gm_t"]) < SPREAD_EVERY or ships.size() >= MAX_SPREADERS:
			continue
		rec["gm_t"] = 0.0
		var sys: int = int(String(k).split("_")[0])
		var id: int = int(inf.get("next_id", 1))
		inf["next_id"] = id + 1
		ships.append({"id": id, "system": sys, "next": c.day + HOP_EVERY})
		# if we're looking at this gravemind, watch it launch
		for o in m.outposts:
			if is_instance_valid(o) and o.part == "gravemind" and o.get_meta("gm_of", "") == k:
				o.launch_spreader()
	for sh in ships.duplicate():
		if c.day < float(sh["next"]):
			continue
		var sysd: Dictionary = c.system_of(int(sh["system"]))
		var seeded := false
		if randf() < 0.4:
			var cands: Array = []
			for pi in sysd.get("planets", []).size():
				var pl: Dictionary = sysd["planets"][pi]
				for si in pl.get("sites", []).size():
					var key := "%d_%d_%d_0" % [int(sh["system"]), pi, si]
					var w: Dictionary = c.world.get(key, {})
					if not w.get("destroyed", false) and int(w.get("team", 0)) != 4 							and not w.get("outpost", false) and int(w.get("team", 0)) != 1:   # (not the player's outposts)
						cands.append([key, pl.get("name", "a world")])
			if not cands.is_empty():
				var pick: Array = cands[randi() % cands.size()]
				c.world[pick[0]] = {"team": 4, "biomass": 0.0}
				ships.erase(sh)
				seeded = true
				G.say("An infected spreader came down on %s: a new hive is growing there" % pick[1], 1)
				G.stat("hives_seeded")
		if not seeded:
			var lanes: Array = sysd.get("lanes", [])
			if not lanes.is_empty():
				sh["system"] = int(lanes[randi() % lanes.size()])
			sh["next"] = c.day + HOP_EVERY
	inf["ships"] = ships
	c.world["infestation"] = inf
	_space_spreaders(m, ships)


## Spreaders in the system we're looking at (in space) are real ships you can fight.
static func _space_spreaders(m: Node, ships: Array) -> void:
	var c = G.campaign
	if m.on_surface:
		return
	var live: Dictionary = m.get_meta("spreaders", {})
	for sh in ships.duplicate():
		var id: int = int(sh["id"])
		if int(sh["system"]) != c.current:
			if live.has(id) and is_instance_valid(live[id]):
				G.vessels.erase(live[id])
				live[id].queue_free()
			live.erase(id)
			continue
		if not live.has(id):
			var pls: Array = c.system().get("planets", [])
			var p := Vector3(randf_range(-1500, 1500), 0, randf_range(-1500, 1500))
			if not pls.is_empty():
				var pl: Dictionary = pls[randi() % pls.size()]
				p = (pl["pos"] as Vector3) + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * (float(pl["radius"]) + 500.0)
				p.y = 0.0
			live[id] = m.spawn_runtime_ship("SMALL_FRIGATE", 4, 3, "Infected Spreader", p, [], "hive")
			load("res://scripts/campaign/sandbox_ai.gd").overgrow_ship(live[id])
			G.say("An infected spreader ship is in the system", 1)
		elif not is_instance_valid(live[id]) or live[id].destroyed:
			ships.erase(sh)
			live.erase(id)
			G.say("Infected spreader destroyed", 1)
			G.stat("spreaders_killed")
	m.set_meta("spreaders", live)
