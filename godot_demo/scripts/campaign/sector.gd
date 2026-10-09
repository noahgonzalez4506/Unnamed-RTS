extends RefCounted
## Builds the campaign system the player is in: planets, jump gates, the stations and
## ships of every side, the player's own fleet and mining craft, and the targets of any
## jobs that lead here. Called from match.gd when G.config.mode == "campaign".

const GALAXY := preload("res://scripts/campaign/galaxy.gd")
const PLANET := preload("res://shaders/planet.gdshader")
const ATMO := preload("res://shaders/atmosphere.gdshader")
const MINER := preload("res://scripts/campaign/miner.gd")

const PLAYER_STATION_CREW := ["bridge_officer", "engineer", "engineer", "cargo_handler", "medical_officer", "security",
	"rifleman", "rifleman", "medic"]
const TRADE_CREW := ["bridge_officer", "engineer", "cargo_handler", "cargo_handler", "medical_officer", "security", "security"]
const CLAIM_CREW := ["engineer", "cargo_handler", "security"]
const NAVY_CREW := ["bridge_officer", "engineer", "engineer", "cargo_handler", "medical_officer", "security",
	"squad_leader", "rifleman", "rifleman", "medic", "breacher", "heavy"]
const SHIP_CREWS := {
	"SMALL_FRIGATE": ["bridge_officer", "engineer", "cargo_handler", "scientist", "security", "rifleman", "medic"],
	"SMALL_SUPPORT": ["bridge_officer", "pilot", "engineer", "cargo_handler", "cargo_handler", "medical_officer", "scientist", "security"],
	"SMALL_DROP_FRIGATE": ["bridge_officer", "engineer", "cargo_handler", "scientist", "security", "medic"],
	"MEDIUM": ["bridge_officer", "pilot", "engineer", "engineer", "cargo_handler", "medical_officer", "scientist", "scientist", "security", "rifleman", "medic", "squad_leader"],
	"LARGE": ["bridge_officer", "bridge_officer", "pilot", "pilot", "engineer", "engineer", "cargo_handler",
		"medical_officer", "scientist", "security", "rifleman", "rifleman", "medic", "squad_leader", "breacher", "heavy"],
	"XL": ["bridge_officer", "bridge_officer", "pilot", "pilot", "engineer", "engineer", "engineer", "cargo_handler",
		"medical_officer", "scientist", "security", "security", "rifleman", "rifleman", "medic", "squad_leader"],
}
## A ship of ours: its class's standard crew, or the crew the player has set (CREW menu).
static func crew_for(e: Dictionary) -> Array:
	if e.has("crew"):
		return (e["crew"] as Array).duplicate()
	return SHIP_CREWS.get(e["cls"], SHIP_CREWS["SMALL_FRIGATE"]).duplicate()


const TRADER_NAMES := ["Hauler", "Freighter", "Bulk", "Courier", "Tender", "Lighter"]


## The system's layout (for match.system) before anything is built.
static func layout() -> Dictionary:
	var c = G.campaign
	var L: Dictionary = GALAXY.sector(c.galaxy, c.current)
	# pirate dens sit on big rocks: they stop gunfire like any asteroid
	var extra: Array = []
	for st in c.stations_in(c.current):
		if st.get("rock", false):
			var p: Vector3 = L["st_" + st["key"]]
			var rr: float = L.get("rock_" + st["key"], 200.0)
			extra.append([p - Vector3.UP * rr * 0.95, rr])
	L["extra_rocks"] = extra
	return L


static func populate(m: Node) -> void:
	var c = G.campaign
	var sys: Dictionary = c.system()
	var L: Dictionary = m.system
	G.standing = c.standing
	G.team_names = {1: c.company}
	# the sides' purses: the player's is the campaign's stores; the rest are deep
	G.resources[1] = c.stores
	for t in [2, 5, 6, 7]:
		G.resources[t] = {"alloys": 99999.0, "circuitry": 9999.0, "cores": 999.0}
	_planets(m, sys)
	_gates(m, L)
	# stations
	for st in c.stations_in(c.current):
		var p: Vector3 = L["st_" + st["key"]]
		var crew: Array = TRADE_CREW
		match st["cls"]:
			"STATION_FORTRESS":
				crew = NAVY_CREW
			"OUTPOST_MINING":
				crew = CLAIM_CREW
			"GROUND_FORT":
				crew = m.PIRATE_FORT_CREW
		var v: Node3D = m._station(st["cls"], int(st["team"]), int(st["fac"]), st["name"], p, crew)
		v.set_meta("key", st["key"])
		if int(st["team"]) == 3:
			m.pirate_fort = v
	for s in c.stations:
		if int(s["system"]) != c.current:
			continue
		var p2 := Vector3(float(s["pos"][0]), 0, float(s["pos"][1]))
		var hv: Node3D = m._station(s["cls"], 1, 1, s["name"], p2, PLAYER_STATION_CREW)
		hv.set_meta("key", s["key"])
		hv.supplies = float(s.get("supplies", 200.0))
		hv.reserve = int(s.get("reserve", 8))
		hv.set_meta("darters", int(s.get("darters", 0)))
		for sg in s.get("segments", []):
			load("res://scripts/campaign/builder.gd").build_segment(hv, sg["type"], Vector3(float(sg["x"]), 0, float(sg["z"])))
			if sg["type"] == "barracks":
				hv.reserve_cap += 20
		if not m.homes.has(1):
			m.homes[1] = hv
	# the player's fleet: where it was left, or coming through the gate it jumped in by
	var gate_in := Vector3.INF
	for g in L["gates"]:
		if int(g["to"]) == c.arrive_from:
			gate_in = g["pos"]
	var k := 0
	for e in c.fleet:
		if int(e["system"]) != c.current or e.get("landed", false):
			continue
		var p3 := Vector3(float(e["pos"][0]), 0, float(e["pos"][1]))
		if e.get("arrive", false) and gate_in != Vector3.INF:
			var inward: Vector3 = (Vector3.ZERO - gate_in).normalized()
			p3 = gate_in + inward * (260.0 + 120.0 * (k / 2)) + inward.cross(Vector3.UP) * (140.0 * (1 if k % 2 == 0 else -1))
			k += 1
		e.erase("arrive")
		var cls: String = e["cls"]
		var s2: Node3D = m._ship(cls, 1, int(e.get("fac", 1)), e["name"], p3, crew_for(e), int(e.get("variant", 0)))
		m.restore_hangar(s2, e)
		s2.rotation.y = float(e.get("yaw", 0.0))
		s2.hull = s2.max_hull * float(e.get("hull", 1.0))
		s2.troops = mini(s2.berth_cap, int(e.get("troops", s2.troops)))
		s2.supplies = float(e.get("supplies", s2.supplies))
		s2.set_meta("fleet_id", int(e["id"]))
		if e.get("core", false):
			s2.set_meta("core_ship", true)
		m.restore_ship_infection(s2, e)
	# the locals
	_npc_ships(m, c, sys, L)
	_job_targets(m, c, L)


## Mining craft come out once the stations exist (called after the crews are aboard).
static func launch_miners(m: Node) -> void:
	var c = G.campaign
	for e in c.miners:
		if int(e["system"]) != c.current:
			continue
		var home: Node3D = null
		for v in G.vessels:
			if v.kind == "station" and v.get_meta("key", "") == e["station"]:
				home = v
		if home == null:
			continue
		var mc: Node3D = MINER.new()
		m.add_child(mc)
		mc.setup(home, e)
		m.miner_crafts.append(mc)


static func _npc_ships(m: Node, c, sys: Dictionary, L: Dictionary) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = int(sys["seed"]) + int(c.day / 300.0)
	var region: String = sys["region"]
	var stations_here: Array = c.stations_in(c.current)
	var anchor := func(team: int) -> Vector3:
		for st in stations_here:
			if int(st["team"]) == team:
				return L["st_" + st["key"]]
		return Vector3(r.randf_range(-1500, 1500), 0, r.randf_range(-1500, 1500))
	var off := func() -> Vector3:
		return Vector3(r.randf_range(-1, 1), 0, r.randf_range(-1, 1)).normalized() * r.randf_range(350.0, 650.0)
	# patrols
	if region == "vanguard" and c.current != int(c.galaxy["home"]):
		for i in 1 + r.randi() % 2:
			var cls: String = "SMALL_FRIGATE" if i == 0 else "MEDIUM"
			var s: Node3D = m._ship(cls, 5, 1, G.ship_name(1, r), anchor.call(5) + off.call(), SHIP_CREWS[cls])
			s.set_meta("role", "patrol")
	if region == "ascendancy":
		var n := 1 + r.randi() % 2 + (1 if int(sys["id"]) == 1 else 0)
		for i in n:
			var cls2: String = ["SMALL_FRIGATE", "MEDIUM", "LARGE"][mini(i, 2)]
			var s2: Node3D = m._ship(cls2, 2, 2, G.ship_name(2, r), anchor.call(2) + off.call(), SHIP_CREWS[cls2])
			s2.set_meta("role", "patrol")
	# civilian traffic
	for st in stations_here:
		if int(st["team"]) in [6, 7]:
			for i in 1 + r.randi() % 2:
				var t: int = int(st["team"])
				var nm := "%s %s %d" % ["Guild" if t == 6 else "Concord", TRADER_NAMES[r.randi() % TRADER_NAMES.size()], 1 + r.randi() % 90]
				var s3: Node3D = m._ship("SMALL_SUPPORT", t, int(st["fac"]), nm, L["st_" + st["key"]] + off.call(), SHIP_CREWS["SMALL_SUPPORT"])
				s3.set_meta("role", "trader")
			break
	# pirates
	if sys.get("pirates", false):
		var den: Vector3 = anchor.call(3)
		for i in 1 + r.randi() % 2:
			var cls3: String = "SMALL_FRIGATE" if i == 0 or r.randf() < 0.6 else "MEDIUM"
			var s4: Node3D = m._ship(cls3, 3, 3, G.ship_name(3, r), den + off.call(), m.PIRATE_SHIP_CREW)
			s4.set_meta("role", "pirate")
	# the infection: derelicts drifting near the lost world. They're made once per system
	# (their size by how far into the game it is: frigates early, cruisers later, the great
	# hulks late) and remembered: the same ones are there next time, and cleared ones stay gone.
	var dkey := "derelicts_%d" % c.current
	if not c.world.has(dkey):
		var lst: Array = []
		var SANDBOX = load("res://scripts/campaign/sandbox_ai.gd")
		for i in int(sys.get("derelicts", 0)):
			var pl0: Dictionary = sys["planets"][0]
			var dir0 := (Vector3.ZERO - (pl0["pos"] as Vector3)).normalized()
			var p0: Vector3 = (pl0["pos"] as Vector3) + dir0 * (float(pl0["radius"]) + 1800.0 + 600.0 * i) + dir0.cross(Vector3.UP) * r.randf_range(-700, 700)
			lst.append({"cls": SANDBOX.infected_class(), "name": "Derelict %s" % ["Calypso", "Meridian", "Hesper", "Orison", "Tamsin", "Verity"][(i + r.randi()) % 6],
				"pos": [p0.x, p0.z], "yaw": r.randf_range(-PI, PI), "cleared": false})
		c.world[dkey] = lst
	var di := 0
	for rec in c.world[dkey]:
		di += 1
		if rec.get("cleared", false):
			continue
		var dcls: String = rec["cls"]
		var d: Node3D = m._ship(dcls, 4, 4 if dcls == "LARGE" else 3, rec["name"], Vector3(float(rec["pos"][0]), 0, float(rec["pos"][1])), [])
		d.drifting = true
		d.shields = 0.0
		d.max_shields = 0.0
		d.troops = 0
		d.rotation.y = float(rec["yaw"])
		d.set_meta("derelict_rec", "%s/%d" % [dkey, di - 1])
		m.derelicts.append(d)


## Ships that jobs point at: bounty targets, derelicts to salvage, extra pirates to clear.
static func _job_targets(m: Node, c, _L: Dictionary) -> void:
	for j in c.jobs:
		if int(j.get("target_system", -1)) == c.current:
			spawn_job(m, j, false)


static func _far_spot() -> Vector3:
	var best := Vector3.ZERO
	for i in 30:
		var a := randf() * TAU
		var p := Vector3(cos(a), 0, sin(a)) * randf_range(1200.0, 2400.0)
		var ok := true
		for v in G.vessels:
			if v.position.distance_to(p) < 700.0:
				ok = false
		for pl in m_planets():
			if Vector2(p.x - pl["pos"].x, p.z - pl["pos"].z).length() < float(pl["radius"]) + 300.0:
				ok = false
		if ok:
			return p
		best = p
	return best


static func m_planets() -> Array:
	return G.match_node.planets if G.match_node else []


## The ship a job points at (a bounty, a derelict, pirates to clear). `runtime`: the system is
## already running (a job just accepted here), so the crew comes aboard as it spawns.
static func spawn_job(m: Node, j: Dictionary, runtime: bool) -> void:
	var mk := func(cls: String, team: int, nm: String, crew: Array) -> Node3D:
		if runtime:
			return m.spawn_runtime_ship(cls, team, team, nm, _far_spot(), crew)
		return m._ship(cls, team, team, nm, _far_spot(), crew)
	match j["kind"]:
		"bounty":
			var s: Node3D = mk.call(j["cls"], 3, "%s's %s" % [j["target_name"], "Frigate" if j["cls"] == "SMALL_FRIGATE" else "Raider"], m.PIRATE_SHIP_CREW + ["rifleman"])
			s.set_meta("job", j["id"])
			s.set_meta("role", "pirate")
			G.say("Bounty target %s is in this system: find it (marked JOB)" % s.display_name, 1)
		"salvage":
			var scls: String = "SMALL_FRIGATE" if (G.campaign == null or G.campaign.day < 2400.0) else "MEDIUM"
			var d: Node3D = (m.spawn_runtime_ship(scls, 4, 3, "Derelict Wanderer", _far_spot(), []) if runtime
				else m._ship(scls, 4, 3, "Derelict Wanderer", _far_spot(), []))
			d.drifting = true
			d.shields = 0.0
			d.max_shields = 0.0
			d.troops = 0
			d.set_meta("job", j["id"])
			m.derelicts.append(d)
			if not runtime:
				pass
			G.say("The derelict to salvage is drifting in this system (marked JOB)", 1)
		"patrol":
			for i in 2:
				var s2: Node3D = mk.call("SMALL_FRIGATE", 3, "Pirate Raider %d" % (i + 1), m.PIRATE_SHIP_CREW)
				s2.set_meta("role", "pirate")
				s2.set_meta("job", j["id"])


# ------------------------------------------------------------------ scenery

static func _planets(m: Node, sys: Dictionary) -> void:
	for pl in sys["planets"]:
		var b: Dictionary = GALAXY.BIOMES[pl["biome"]]
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = pl["radius"]
		sm.height = float(pl["radius"]) * 2.0
		sm.radial_segments = 96
		sm.rings = 48
		mi.mesh = sm
		var mat := ShaderMaterial.new()
		mat.shader = PLANET
		var cols: Array = b["cols"]
		mat.set_shader_parameter("col_deep", cols[0])
		mat.set_shader_parameter("col_low", cols[1])
		mat.set_shader_parameter("col_high", cols[2])
		mat.set_shader_parameter("col_peak", cols[3])
		mat.set_shader_parameter("sea", b["sea"])
		mat.set_shader_parameter("seed", float(int(pl["seed"]) % 1000))
		mat.set_shader_parameter("gas", 1.0 if pl["biome"] == "gas" else 0.0)
		mat.set_shader_parameter("infected", 1.0 if pl["biome"] == "infected" else 0.0)
		mat.set_shader_parameter("lava", 1.0 if pl["biome"] == "lava" else 0.0)
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = pl["pos"]
		mi.rotation = Vector3(0.2, float(int(pl["seed"]) % 360), 0.1)
		m.add_child(mi)
		var atmo: Color = b["atmo"]
		if atmo.a > 0.0:
			var am := MeshInstance3D.new()
			var sa := SphereMesh.new()
			sa.radius = float(pl["radius"]) * 1.08
			sa.height = sa.radius * 2.0
			sa.radial_segments = 64
			sa.rings = 32
			am.mesh = sa
			var amat := ShaderMaterial.new()
			amat.shader = ATMO
			amat.set_shader_parameter("tint", atmo)
			am.material_override = amat
			am.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			am.position = pl["pos"]
			m.add_child(am)
		if pl["biome"] == "gas":
			var ring := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = float(pl["radius"]) * 1.3
			tm.outer_radius = float(pl["radius"]) * 1.75
			tm.rings = 96
			ring.mesh = tm
			ring.scale = Vector3(1, 0.015, 1)
			var rm := StandardMaterial3D.new()
			rm.albedo_color = Color(cols[1].r, cols[1].g, cols[1].b, 0.45)
			rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			ring.material_override = rm
			ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ring.position = pl["pos"]
			ring.rotation = Vector3(0.25, 0.3, 0.08)
			m.add_child(ring)
		var lab := Label3D.new()
		lab.text = "%s\n%s" % [pl["name"], b["label"]]
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.font_size = 64
		lab.pixel_size = 1.6
		lab.modulate = Color(0.85, 0.9, 1.0, 0.75) if pl["biome"] != "infected" else Color(0.85, 0.5, 1.0, 0.85)
		lab.no_depth_test = true
		lab.position = (pl["pos"] as Vector3) + Vector3.UP * (float(pl["radius"]) + 120.0)
		m.add_child(lab)
		m.planets.append({"pos": pl["pos"], "radius": pl["radius"], "def": pl})


static func _gates(m: Node, L: Dictionary) -> void:
	for g in L["gates"]:
		var root := Node3D.new()
		root.position = g["pos"]
		root.look_at_from_position(g["pos"], Vector3.ZERO, Vector3.UP)
		m.add_child(root)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 150.0
		tm.outer_radius = 172.0
		tm.rings = 64
		tm.ring_segments = 12
		ring.mesh = tm
		ring.rotation.x = PI * 0.5
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.35, 0.38, 0.44)
		mat.metallic = 0.7
		mat.roughness = 0.35
		ring.material_override = mat
		root.add_child(ring)
		var field := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 150.0
		disc.bottom_radius = 150.0
		disc.height = 0.5
		field.mesh = disc
		field.rotation.x = PI * 0.5
		var fm := StandardMaterial3D.new()
		fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		fm.albedo_color = Color(0.3, 0.6, 1.0, 0.18)
		field.material_override = fm
		root.add_child(field)
		var lab := Label3D.new()
		lab.text = "JUMP GATE\nto %s" % g["name"]
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.font_size = 64
		lab.pixel_size = 0.9
		lab.modulate = Color(0.55, 0.8, 1.0, 0.9)
		lab.no_depth_test = true
		lab.position = Vector3.UP * 230.0
		root.add_child(lab)
	m.gates = L["gates"]
