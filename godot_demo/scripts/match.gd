extends Node3D
## The demo match. One star system:
##   * you (Vanguard, faction 1): a fortress station, a Large warship and a frigate
##   * the rival (Ascendancy, faction 2): the same, at the far end of the system
##   * pirates: a fort dug into an asteroid and a frigate, hostile to everyone
##   * the derelict Calypso, an XL overrun by the infection, which spreads to whatever comes close
## Win by capturing (or destroying) the rival's command core. Lose yours and it's over.

const SHIP := preload("res://scripts/ship.gd")
const STATION := preload("res://scripts/station.gd")
const CHAR := preload("res://scripts/character.gd")
const AI := preload("res://scripts/ai.gd")
const COMMANDER := preload("res://scripts/commander.gd")
const SQUAD := preload("res://scripts/squad.gd")
const SYSTEM := preload("res://scripts/system_gen.gd")
const LOGISTICS := preload("res://scripts/logistics.gd")
const SECTOR := preload("res://scripts/campaign/sector.gd")
const SANDBOX := preload("res://scripts/campaign/sandbox_ai.gd")
const CAMPAIGN := preload("res://scripts/campaign/campaign.gd")
const SURFACE := preload("res://scripts/campaign/surface.gd")
const VEHICLE := preload("res://scripts/campaign/vehicle.gd")
const DEPOT := preload("res://scripts/campaign/depot.gd")
const INFECTION := preload("res://scripts/campaign/infection.gd")
## What each class carries down to a surface (supply ship: 4 MRAPs, 2 APCs, 6 mechs in its
## mech bay; dropship: 2 tanks, 2 IFVs, 4 MRAPs).
const VEHICLE_BAYS := {
	"SMALL_FRIGATE": ["mrap_ai", "mrap_av"],
	"SMALL_SUPPORT": ["mrap_ai", "mrap_aa", "mrap_av", "mrap_ai", "ifv", "ifv", "mech", "mech", "mech", "mech", "mech", "mech"],
	"SMALL_DROP_FRIGATE": ["tank", "tank", "ifv", "ifv", "mrap_ai", "mrap_aa", "mrap_av", "mortar"],
}
## Only supply ships (front bay + mech room) and dropships (stern ramp) carry vehicles.
const VEHICLE_CAP := {"SMALL_SUPPORT": 12, "SMALL_DROP_FRIGATE": 8, "SMALL_FRIGATE": 2}
const HAULERS := ["SMALL_SUPPORT", "SMALL_DROP_FRIGATE", "SMALL_FRIGATE"]


## What a ship's vehicle bay can take (the small frigate's front bay: MRAPs only).
static func can_carry(cls: String, kind: String) -> bool:
	if cls == "SMALL_FRIGATE":
		return kind.begins_with("mrap")
	return VEHICLE_CAP.has(cls)
var on_surface := false
var caches: Array = []
var fog: Node = null                # fog of war / radar (fog.gd)
var outposts: Array = []            # ground installation parts (camps.gd / outpost.gd)              # salvage in abandoned cities (surface)
var ground: Node3D = null           # the open ground (surface): a walkable "vessel"
var city := {}                      # {center, radius} of an abandoned city, if any
var ground_spawns: Array = []       # [local pos, team, roles] put down once the ground is baked
var ground_cover: Array = []        # cover points on the open ground: [pos, low?, direction to the cover]
var ground_vehicles: Array = []     # [world pos, kind, team, faction] put down once the ground is baked
var terrain_P := {}                 # the surface's terrain noise (heights)
var roofs: Array = []               # [mesh, level]: city floors and roofs the cutaway hides

const SHIP_CREW := {
	"LARGE": ["bridge_officer", "bridge_officer", "pilot", "pilot", "engineer", "engineer", "cargo_handler",
		"medical_officer", "scientist", "security", "rifleman", "rifleman", "medic", "squad_leader", "breacher", "heavy"],
	"SMALL_FRIGATE": ["bridge_officer", "engineer", "cargo_handler", "security", "rifleman", "medic"],
}
const STATION_CREW := ["bridge_officer", "engineer", "engineer", "cargo_handler", "medical_officer", "scientist",
	"security", "squad_leader", "rifleman", "rifleman", "medic", "breacher", "heavy", "grenadier"]
const DROP_CREW := ["bridge_officer", "engineer", "cargo_handler", "security", "medic"]
const PIRATE_MINE_CREW := ["engineer", "cargo_handler", "rifleman", "rifleman", "heavy"]
const SUPPORT_CREW := ["bridge_officer", "pilot", "engineer", "cargo_handler", "cargo_handler", "cargo_handler",
	"medical_officer", "security", "rifleman", "rifleman"]
const PIRATE_FORT_CREW := ["engineer", "security", "rifleman", "rifleman", "breacher", "heavy", "squad_leader", "medic"]
const PIRATE_SHIP_CREW := ["engineer", "cargo_handler", "rifleman", "rifleman", "heavy", "squad_leader"]
const DERELICT_BODIES := ["rifleman", "engineer", "security", "cargo_handler", "medic", "heavy", "engineer",
	"rifleman", "bridge_officer", "medical_officer", "scientist", "pilot"]
const MAX_INFECTED_PER_VESSEL := 14

var homes := {}
var mines: Array = []               # ground mining bases: whoever holds one gets its ore
var rocks: Array = []               # big asteroids: [centre, radius]; they stop gunfire
var derelict: Node3D
var pirate_fort: Node3D
var intel := {1: [], 2: [], 3: []}  # what the infection has learned about each side: [time, text]
var ai: Node
var commander: Node
var _pending: Array = []            # [vessel, roles, team, faction] spawned once nav maps are live
var _income_t := 0.0
var income_mult := {1: 1.0, 2: 1.0}
var ready_for_net := false
var squads: Array = []
var map_seed := 0
var system := {}                    # the procedural layout (system_gen.gd)
var logistics: Node
var map_rng := RandomNumberGenerator.new()      # the procedural layout of this match (shared by every client)
var _squad_t := 0.0          # client: vessels exist, snapshots can be applied
# ---- campaign
var campaign_mode := false
var planets: Array = []             # {pos, radius, def}: the system's worlds (ships keep clear of them)
var gates: Array = []               # {to, pos, name}: jump gates to the neighbouring systems
var miner_crafts: Array = []
var derelicts: Array = []
var _camp_t := 0.0
var _save_t := 180.0
var _jumping := false


func _ready() -> void:
	var args0 := OS.get_cmdline_user_args()
	if "--camptest" in args0 and G.campaign == null:
		G.config = {"mode": "campaign", "team": 1, "start": "commander", "difficulty": 1}
		G.campaign = CAMPAIGN.new_game(4242, "Kestrel Company")
	campaign_mode = G.config.get("mode", "") == "campaign" and G.campaign != null
	G.reset()
	fog = load("res://scripts/fog.gd").new()
	fog.name = "Fog"
	add_child(fog)
	G.match_node = self
	G.sfx.ambience(true)
	map_seed = int(G.config.get("seed", 0))
	if map_seed == 0:
		map_seed = randi() % 1000000 + 1
		G.config["seed"] = map_seed
	if campaign_mode:
		map_seed = int(G.campaign.seed) * 31 + int(G.campaign.current) + 1
	map_rng.seed = map_seed
	on_surface = campaign_mode and not G.campaign.surface.is_empty()
	if on_surface:
		system = SURFACE.layout(G.campaign)
	else:
		system = SECTOR.layout() if campaign_mode else SYSTEM.layout(map_seed)
	_world()
	SYSTEM.build(self, system)
	rocks = SYSTEM.big_rocks(system)
	var t0 := Time.get_ticks_msec()
	if campaign_mode:
		await _campaign_ready(t0)
		return
	var L := system
	homes[1] = _station("STATION_FORTRESS", 1, 1, "Vanguard Bastion", L["home1"], STATION_CREW)
	homes[2] = _station("STATION_FORTRESS", 2, 2, "Ascendancy Spire", L["home2"], STATION_CREW)
	_slot(_ship("LARGE", 1, 1, G.ship_name(1, map_rng), L["flag1"], SHIP_CREW["LARGE"]), "flag1")
	_slot(_ship("SMALL_FRIGATE", 1, 1, G.ship_name(1, map_rng), L["frigate1"], SHIP_CREW["SMALL_FRIGATE"]), "frigate1")
	_slot(_ship("LARGE", 2, 2, G.ship_name(2, map_rng), L["flag2"], SHIP_CREW["LARGE"]), "flag2")
	_slot(_ship("SMALL_FRIGATE", 2, 2, G.ship_name(2, map_rng), L["frigate2"], SHIP_CREW["SMALL_FRIGATE"]), "frigate2")
	# each side's supply ship: carries stores and boarders to the fleet, runs the Darter
	_slot(_ship("SMALL_SUPPORT", 1, 1, G.ship_name(1, map_rng), L["support1"], SUPPORT_CREW), "support1")
	_slot(_ship("SMALL_SUPPORT", 2, 2, G.ship_name(2, map_rng), L["support2"], SUPPORT_CREW), "support2")
	# each side's Paris-class drop frigate: ODST pods for surface installations
	_slot(_ship("SMALL_DROP_FRIGATE", 1, 1, G.ship_name(1, map_rng), L["dropfrig1"], DROP_CREW), "dropfrig1")
	_slot(_ship("SMALL_DROP_FRIGATE", 2, 2, G.ship_name(2, map_rng), L["dropfrig2"], DROP_CREW), "dropfrig2")
	# the pirates' asteroid base: a fort and a mine dug into one big rock
	pirate_fort = _station("GROUND_FORT", 3, 3, "Pirate Haven", L["pirate"], PIRATE_FORT_CREW)
	mines.append(_station("GROUND_MINE", 3, 3, "Haven Diggings", L["pirate_mine"], PIRATE_MINE_CREW))
	if L["field_mine"] >= 0:
		var fl: Dictionary = L["fields"][L["field_mine"]]
		var big: Array = fl["big"].duplicate()
		big.sort_custom(func(a, b): return a["radius"] > b["radius"])
		var rk: Dictionary = big[0]
		var m := _station("GROUND_MINE", 3, 3, "%s Mine" % String(fl["ore"]).capitalize(), rk["pos"] + Vector3.UP * rk["radius"] * 0.55, PIRATE_MINE_CREW)
		m.set_meta("ore", fl["resource"])
		mines.append(m)
	_slot(_ship("SMALL_FRIGATE", 3, 3, G.ship_name(3, map_rng), L["pirate_ship"], PIRATE_SHIP_CREW), "pirate_ship")
	if L["pirate_raider"]:
		_ship("MEDIUM", 3, 3, G.ship_name(3, map_rng), L["raider_pos"], PIRATE_SHIP_CREW + ["rifleman", "breacher", "engineer"])
	derelict = _slot(_ship("LARGE", 4, 4, "Derelict Calypso", L["derelict"], []), "derelict")
	derelict.drifting = true
	derelict.shields = 0.0
	derelict.max_shields = 0.0
	derelict.troops = 0
	derelict.rotation.y = L["derelict_yaw"]
	var client := G.is_client()
	if client:
		_pending.clear()                 # the host sends every character
	# navigation maps go live a few physics frames later (they sync in the background)
	for f in 600:
		await get_tree().physics_frame
		if G.vessels.all(func(v): return v.nav_ok() and v.snap_local(Vector3.ZERO) != Vector3.ZERO):
			break
	for f in 3:
		await get_tree().physics_frame          # (ships mount their guns on their second frame)
	for pc in _pending:
		_crew(pc[0], pc[1], pc[2], pc[3])
	if not client:
		_overrun(derelict)
	logistics = LOGISTICS.new()
	add_child(logistics)
	ai = AI.new()
	ai.pirate_home = pirate_fort.global_position
	var diff: int = int(G.config.get("difficulty", 1))
	ai.attack_after = [150.0, 70.0, 40.0][diff]
	income_mult = {1: 1.0, 2: 1.0}
	var humans: Array = [G.player_team] if G.config.get("mode", "single") != "net" else G.network.commander_teams()
	ai.rival_teams = [1, 2].filter(func(t): return not humans.has(t))
	for t in ai.rival_teams:
		income_mult[t] = [0.7, 1.0, 1.35][diff]
	if not client:
		add_child(ai)
	commander = COMMANDER.new()
	add_child(commander)
	commander.pivot = homes[G.player_team].global_position + Vector3(400 if G.player_team == 1 else -400, 0, 120)
	if G.config.get("start", "commander") == "soldier":
		commander.start_as_soldier()
	ready_for_net = true
	if client:
		G.network.client_ready()
	print("Match set up in %d ms: %d vessels, %d characters" % [Time.get_ticks_msec() - t0, G.vessels.size(), G.characters.size()])
	G.say("Capture or destroy the Ascendancy Spire's command core. Protect your own.", 1)
	G.say("Pirates hold the north. Something is wrong aboard the derelict to the south.", 1)
	var args := OS.get_cmdline_user_args()
	if "--selftest" in args:
		add_child(load("res://tests/match_test.gd").new())
	elif "--shots" in args:
		add_child(load("res://tests/shots.gd").new())
	elif "--perf" in args:
		add_child(load("res://tests/perf_test.gd").new())
	elif "--fleettest" in args:
		add_child(load("res://tests/fleet_test.gd").new())
	elif "--weaponshots" in args:
		add_child(load("res://tests/weapon_shots.gd").new())
	elif "--medtest" in args:
		add_child(load("res://tests/med_test.gd").new())
	elif "--odsttest" in args:
		add_child(load("res://tests/odst_test.gd").new())
	elif "--roomshots" in args:
		add_child(load("res://tests/room_shots.gd").new())
	elif "--logtest" in args:
		add_child(load("res://tests/logistics_test.gd").new())
	elif "--squadtest" in args:
		add_child(load("res://tests/squad_test.gd").new())
	elif "--grenadiertest" in args:
		add_child(load("res://tests/grenadier_test.gd").new())
	elif "--fftest" in args:
		add_child(load("res://tests/ff_test.gd").new())
	elif "--hitchtest" in args:
		add_child(load("res://tests/hitch_test.gd").new())
	elif "--fogtest" in args:
		add_child(load("res://tests/fog_test.gd").new())
	elif "--ridetest" in args:
		add_child(load("res://tests/ride_test.gd").new())
	elif "--evatest" in args:
		add_child(load("res://tests/eva_test.gd").new())
	elif "--breachtest" in args:
		add_child(load("res://tests/breach_test.gd").new())
	elif "--opstest" in args:
		add_child(load("res://tests/ops_test.gd").new())
	elif "--doorshots" in args:
		add_child(load("res://tests/door_shots.gd").new())
	elif "--features" in args:
		add_child(load("res://tests/feature_shots.gd").new())
	elif "--host" in args or "--join" in args:
		add_child(load("res://tests/net_test.gd").new())
	elif "--debug" in args:
		add_child(load("res://tests/debug_test.gd").new())
	elif "--crewtest" in args:
		add_child(load("res://tests/crew_test.gd").new())


func _world() -> void:
	var env := Environment.new()
	var neb: Color = system.get("nebula", Color(0.3, 0.4, 0.8))
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/space_sky.gdshader")
	sm.set_shader_parameter("nebula", neb)
	sky.sky_material = sm
	env.sky = sky
	if system.get("surface", false):
		# under an atmosphere: a lit sky and haze instead of space
		var atmo: Color = system.get("nebula", Color(0.5, 0.7, 1.0))
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(atmo.r, atmo.g, atmo.b).lerp(Color(0.55, 0.65, 0.8), 0.4)
		env.fog_enabled = true
		env.fog_light_color = env.background_color
		env.fog_density = 0.00005
		env.fog_sky_affect = 0.3
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.72)
	env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_hdr_threshold = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = system.get("sun_rot", Vector3(-38, 35, 0))
	sun.light_color = system.get("sun_color", Color.WHITE)
	sun.light_energy = 1.05
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 500.0
	add_child(sun)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var quad := QuadMesh.new()
	quad.size = Vector2(9, 9)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = Color(0.9, 0.93, 1.0)
	quad.material = mat
	mm.mesh = quad
	mm.instance_count = 3000
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in mm.instance_count:
		var d := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 0.0001), d * 11000.0))   # (the sky shader draws the stars now)
	var stars := MultiMeshInstance3D.new()
	stars.multimesh = mm
	stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(stars)


# ------------------------------------------------------------------ building the match

func _folder(kind_: String, fac: int) -> String:
	var tag: String = {1: "F1", 2: "F2", 3: "P", 4: "X"}[fac]
	return "res://models/%s_%s" % [kind_, tag]


func _ship(cls: String, team: int, fac: int, nm: String, pos: Vector3, crew: Array, want_variant: int = 0) -> Node3D:
	# a procedural interior layout, picked by the match seed (same on every client); a campaign
	# ship keeps the layout it was saved with (the roll is still drawn, so others don't change)
	var variant := 0
	var path := "%s/ship_%s.glb" % [_folder("ships", fac), cls]
	var roll: int = 1 + map_rng.randi() % 3
	var vp := "%s/ship_%s_v%d.glb" % [_folder("ships", fac), cls, want_variant if want_variant > 0 else roll]
	if want_variant > 0 and not ResourceLoader.exists(vp):
		vp = "%s/ship_%s_v%d.glb" % [_folder("ships", fac), cls, roll]
	if ResourceLoader.exists(vp):
		path = vp
		variant = int(vp.get_slice("_v", vp.get_slice_count("_v") - 1).get_slice(".", 0))
	var s: Node3D = load(path).instantiate()
	s.set_script(SHIP)
	s.variant = variant
	add_child(s)
	s.setup_ship(cls, team, fac, nm)
	s.bake_navigation()                    # while still at the origin: the nav lives in the ship's own space
	s.position = pos
	if pos.x > 100.0:
		s.rotation.y = PI * 0.5            # rival ships face west, toward you
	elif pos.x < -100.0:
		s.rotation.y = -PI * 0.5
	if team != 4:
		for i in min(2, s.pads.size()):
			s.park_fighter(i)
	G.vessels.append(s)
	_pending.append([s, crew, team, fac])
	return s


func _slot(s: Node3D, slot: String) -> Node3D:
	s.set_meta("slot", slot)                 # (the tests find ships by their slot: names are random)
	return s


func _station(cls: String, team: int, fac: int, nm: String, pos: Vector3, crew: Array) -> Node3D:
	var s: Node3D = load("%s/%s.glb" % [_folder("stations", fac), cls]).instantiate()
	s.set_script(STATION)
	add_child(s)
	s.setup_station(cls, team, fac, nm)
	s.bake_navigation()
	s.position = pos
	G.vessels.append(s)
	_pending.append([s, crew, team, fac])
	return s


func new_squad(team: int, v: Node3D) -> RefCounted:
	var sq: RefCounted = SQUAD.new()
	sq.id = squads.size() + 1
	sq.team = team
	sq.vessel = v
	squads.append(sq)
	return sq


func _crew(v: Node3D, roles: Array, team: int, fac: int) -> void:
	# every manned gun needs a gunner
	if v.kind == "ship" and team != 4 and not roles.is_empty() and not roles.has("gunner") and v.has_method("manned_guns"):
		roles = roles.duplicate()
		for i in v.manned_guns():
			roles.append("gunner")
	v.crew_roster = roles.duplicate()
	var sq: RefCounted = null
	for role in roles:
		var pats: Array = CHAR.JOBS.get(role, ["*_Garrison", "PlayerSpawn_*", "*_ControlRoom", "PodBay_*_Muster"])
		var cands: Array = []
		for p in pats:
			cands += v.marks_like(p)
		var p: Vector3 = v.local_of(cands[randi() % cands.size()]) if not cands.is_empty() else v.random_local()
		var c := spawn_character(v, v.snap_local(p + Vector3(randf_range(-1.2, 1.2), 0, randf_range(-1.2, 1.2))),
			team, fac, role)
		if role == "gunner" and v.has_method("free_gun_for") and v._guns_built:
			var gi: int = v.free_gun_for(c)                  # straight to their post
			if gi >= 0:
				c.position = v.turrets[gi]["seat"] + Vector3.UP * 0.05
		if team == 3:
			c.dr = max(0.0, c.dr - 0.1)            # pirates wear scavenged, patched-up kit
		if c.role in CHAR.COMBAT_ROLES:            # the soldiers aboard form a squad
			if sq == null or sq.members.size() >= 8:
				sq = new_squad(team, v)
			sq.add(c)


## Fill the derelict with the infected and let the growth take most of it.
func _overrun(v: Node3D) -> void:
	for z in v.zones:
		if randf() < 0.65:
			z["infected"] = true
			z["growth"] = randf_range(0.6, 1.0)
	v._update_infection_overlay()
	for i in 12:
		var c := spawn_character(v, v.clear_spot(), 1, 1, DERELICT_BODIES[i % DERELICT_BODIES.size()])
		c._convert(true)


## A player (local or remote) spawns as a soldier of their chosen class.
func spawn_player(role: String, v: Node3D, peer: int) -> Node:
	var team: int = v.team
	var spot: Node3D = null
	var pats: Array = ["PlayerSpawn_Deck0", "*_Garrison", "*CMD_ControlRoom", "*GCR_ControlRoom", "*_ControlRoom"]
	if role == "pilot":
		pats = ["Hangar_LandingPad_1", "Hangar_LandingPad_2"] + pats
	for pat in pats:
		var found: Array = v.marks_like(pat)
		if not found.is_empty():
			spot = found[0]
			break
	var p: Vector3 = v.snap_local(v.local_of(spot) + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5)) +
		(Vector3(3.0, 0, 0) if role == "pilot" else Vector3.ZERO)) if spot else v.random_local()
	var c := spawn_character(v, p, team, G.team_fac(team), role)
	c.owner_peer = peer if peer != 1 else 0
	if G.has_tech(team, "a2"):
		c.medpens.append("research_medpen")
	if role == "squad_leader":                       # a squad leader brings a fireteam to lead
		var sq: RefCounted = new_squad(team, v)
		sq.add(c)
		sq.leader = c
		var fire_team := ["rifleman", "rifleman", "medic", "breacher", "heavy"]
		for i in fire_team.size():
			var m := spawn_character(v, v.snap_local(p + Vector3((i % 3) * 0.9 - 0.9, 0, 1.2 + int(i / 3) * 0.9)), team, G.team_fac(team), fire_team[i])
			sq.add(m)
	G.stat("players_spawned")
	return c


func on_spawned_fighter(f: Node, carrier: Node) -> void:
	G.register(f)
	f.set_meta("carrier", carrier)


func spawn_character(v: Node3D, local_p: Vector3, team: int, fac: int, role: String, net_id: int = 0) -> Node:
	var c: CharacterBody3D = CHAR.new()
	v.add_child(c)
	c.position = local_p + Vector3.UP * 0.05
	c.rotation.y = randf() * TAU
	c.setup(v, team, fac, role)
	var hb: float = G.tech_bonus(team, "troop_hp")
	if hb > 0.0:
		c.max_hp *= 1.0 + hb
		c.hp = c.max_hp
	G.register(c, net_id)
	if G.network and G.network.active and multiplayer.is_server():
		G.network.announce_spawn(c)
	return c


## Boarders out of a pod, or a fresh squad out of the barracks.
func spawn_squad(v: Node3D, local_p: Vector3, team: int, fac: int, roles: Array, boarding: bool) -> void:
	var sid := randi() % 100000
	var sq: RefCounted = new_squad(team, v) if team != 4 else null
	var spots := spread_spots(v, local_p, roles.size())
	for i in roles.size():
		var p: Vector3 = spots[i]
		if team == 4:
			var c := spawn_character(v, p, 1, 1, DERELICT_BODIES[randi() % DERELICT_BODIES.size()])
			c._convert(true)
			continue
		if boarding and i > 0:
			# boarders come out of the breach one after another, not as a lump
			get_tree().create_timer(0.35 * i).timeout.connect(_spawn_member.bind(v, local_p, p, team, fac, roles[i], sid, sq))
		else:
			_spawn_member(v, local_p, p, team, fac, roles[i], sid, sq)
	G.stat("squads_spawned")


func _spawn_member(v: Node3D, door_p: Vector3, p: Vector3, team: int, fac: int, role: String, sid: int, sq: RefCounted) -> void:
	if not is_instance_valid(v) or v.destroyed:
		return
	var c := spawn_character(v, door_p, team, fac, role)
	c.squad_id = sid
	if sq:
		sq.add(c)
	c.run = true
	c.go(p, true)                                       # step out and clear the breach point


## n standing spots around p on the deck, at least ~1.1 m apart (fewer if the room is tiny).
func spread_spots(v: Node3D, p: Vector3, n: int) -> Array:
	var out: Array = []
	var tries := 0
	while out.size() < n and tries < 80:
		tries += 1
		var a: float = tries * 2.39996                   # golden-angle spiral
		var r: float = 0.6 + sqrt(float(tries)) * 0.75
		var q: Vector3 = v.snap_local(p + Vector3(cos(a) * r, 0, sin(a) * r))
		if absf(q.y - p.y) > 1.0:
			continue
		var ok := true
		for o in out:
			if (o as Vector3).distance_to(q) < 1.1:
				ok = false
				break
		if ok:
			out.append(q)
	while out.size() < n:
		out.append(v.clear_spot(p, 8.0) if v.has_method("clear_spot") else v.snap_local(p))   # (no piling onto one point)
	return out


## A pod or shuttle with people aboard reaches its target: the riders step out first
## (a player leads), then the troops it carried. A player's own squad stays together.
func disembark(v: Node3D, local_p: Vector3, team: int, fac: int, roles: Array, riders: Array, into = null) -> void:
	var sq: RefCounted = into if into != null and is_instance_valid(into.leader) and into.leader.state == "alive" else null
	for r in riders:                                   # ride-along squad led by a player?
		if sq != null:
			break
		if is_instance_valid(r) and r.squad and (r == G.possessed or r.owner_peer != 0) and r.squad.leader == r:
			sq = r.squad
			break
	if sq == null:
		sq = new_squad(team, v)
	sq.vessel = v
	sq.stack_door = {}
	var i := 0
	var spots := spread_spots(v, local_p, riders.size() + roles.size())
	for r in riders:
		if not is_instance_valid(r) or r.state == "dead":
			continue
		r.disembark_to(v, spots[i])
		if r.squad != sq:
			if r.squad:
				r.squad.remove(r)
			sq.add(r)
		i += 1
	for role in roles:
		var c := spawn_character(v, spots[i], team, fac, role)
		sq.add(c)
		c.run = true
		i += 1
	if sq.leader == null or sq.leader.state != "alive":
		sq._promote()
	G.stat("squads_spawned")
	G.stat("riders_landed", riders.size())


## ODST troopers that land at the same base form one squad there.
func join_drop_squad(c: Node, v: Node3D) -> void:
	var sq: RefCounted = null
	for s_ in squads:
		if s_.vessel == v and s_.team == c.team and s_.members.size() < 8 and s_.get_meta("odst", false):
			sq = s_
			break
	if sq == null:
		sq = new_squad(c.team, v)
		sq.set_meta("odst", true)
	sq.add(c)


## Is a person playing on this side (so boarding ops wait for them)?
func humans_on(team: int) -> bool:
	if G.network and G.network.active:
		for id in G.network.players:
			if int(G.network.players[id].get("team", 0)) == team:
				return true
		return false
	return team == G.player_team


## A fully overgrown compartment pushes out a new infected every so often.
func spawn_swarmer(v: Node3D, z: Dictionary) -> void:
	if G.is_client():
		return                                         # (the host spawns them; snapshots bring them)
	var n := 0
	for c in v.occupants:
		if c.team == 4 and c.state == "alive":
			n += 1
	if n >= MAX_INFECTED_PER_VESSEL:
		return
	var p: Vector3 = v.clear_spot(v.snap_local(z["center"] - Vector3(0, z["half"].y - 0.05, 0)), maxf(2.0, minf(float(z["half"].x), float(z["half"].z))))
	var c := spawn_character(v, p, 1, 1, ["engineer", "cargo_handler", "security"][randi() % 3])
	c._convert(true)


## A robot was converted: the infection now knows what it saw, where and when.
func infection_learn(c: Node) -> void:
	var side: int = c.team
	if not intel.has(side):
		return
	var mem: Array = c.intel
	for m in mem:
		intel[side].append(m)
	var latest := "nothing of note"
	if not mem.is_empty():
		latest = "%s (%d s ago)" % [mem[-1][1], int(G.time - float(mem[-1][0]))]
	G.say("The infection absorbed a %s %s. It now knows: %s" % [G.team_name(side), c.role_label(), latest], side)


func pick_fighter_target(f: Node) -> Node:
	var best: Node = null
	var bd := 3500.0
	for v in G.vessels:
		if is_instance_valid(v) and not v.destroyed and G.enemies(f.team, v.team) and v.team != 4:
			var d: float = f.global_position.distance_to(v.global_position)
			if v.kind == "station":
				d *= 1.5
			if d < bd:
				bd = d
				best = v
	return best


# ------------------------------------------------------------------ orders (from any commander)

## Every commander order comes through here: the local player's directly, a remote
## player's from the network. Units are referred to by network id, vessels by index.
func command(what: String, args: Array) -> void:
	if G.is_client():
		G.network.send_cmd(what, args)
	else:
		run_command(G.player_team, what, args)


func run_command(team: int, what: String, args: Array, peer: int = 0) -> void:
	var V := func(i): return G.vessels[i] if i >= 0 and i < G.vessels.size() else null
	var commander_peer: bool = peer == 0 or (G.network and G.network.players.get(peer, {}).get("role", "") == "commander")
	# a soldier may only work the ship whose helm they hold, and only their own body
	var may_ship := func(sh: Node) -> bool: return commander_peer or (sh != null and sh.get("helm") != null \
		and is_instance_valid(sh.helm) and sh.helm.owner_peer == peer)
	var own_body := func(id) -> Node:
		var b: Node = G.net_ids.get(id)
		if b == null or not is_instance_valid(b) or b.team != team or b.state != "alive":
			return null
		return b if peer == 0 or b.owner_peer == peer else null
	match what:
		"move":
			var v: Node = V.call(args[1])
			var n := 0
			var moved_squads: Array = []
			for id in args[0]:
				var c: Node = G.net_ids.get(id)
				if c and is_instance_valid(c) and c.team == team and c.vessel == v and c.state == "alive":
					if c.squad and not moved_squads.has(c.squad):
						moved_squads.append(c.squad)
						c.squad.order = {"type": "move", "pos": args[2]}
						var ld: Node = c.squad.leader
						if ld and ld != G.possessed:
							ld.order = {"type": "move", "pos": v.snap_local(args[2]), "vessel": v}
							ld.stop()
					elif not c.squad:
						c.order = {"type": "move", "pos": v.snap_local(args[2] + Vector3((n % 4) * 1.1 - 1.65, 0, int(n / 4) * 1.1)), "vessel": v}
						c.stop()
						n += 1
		"attack":
			var t: Node = G.net_ids.get(args[1])
			for id in args[0]:
				var c: Node = G.net_ids.get(id)
				if c and t and c.team == team:
					c.order = {"type": "attack", "target": t}
		"hold":
			for id in args[0]:
				var c: Node = G.net_ids.get(id)
				if c and c.team == team:
					c.stop()
					c.order = {"type": "hold", "pos": c.position, "vessel": c.vessel}
		"sabotage":
			for id in args[0]:
				var c: Node = G.net_ids.get(id)
				if c == null or c.team != team or not c.vessel.has_method("sabotage") or not G.enemies(team, c.vessel.team):
					continue
				var best: Node3D = null
				var bd := INF
				for m in c.vessel.marks_like("*_SabotagePoint_?"):
					var d: float = c.vessel.local_of(m).distance_to(c.position)
					if d < bd:
						bd = d
						best = m
				if best:
					c.order = {"type": "sabotage", "pos": c.vessel.snap_local(c.vessel.local_of(best)),
						"module": c.vessel._module_of(String(best.name)), "vessel": c.vessel}
		"ship_move":
			var s: Node = V.call(args[0])
			if s and s.team == team and s.kind == "ship":
				s.move_target = args[1]
				if not args[2]:
					s.attack_target = null
		"ship_attack":
			var s2: Node = V.call(args[0])
			var t2: Node = V.call(args[1])
			if s2 and t2 and s2.team == team:
				s2.attack_target = t2
				s2.move_target = Vector3.INF
		"board":
			var s3: Node = V.call(args[0])
			var t3: Node = V.call(args[1])
			var kind_: String = args[2] if args.size() > 2 else "pods"
			if s3 and t3 and s3.team == team and may_ship.call(s3) and not s3.drop_racks.is_empty() and s3.is_surface(t3):
				var spot: Vector3 = args[3] if args.size() > 3 and args[3] is Vector3 else Vector3.INF
				if not s3.order_drop(t3, spot, 6):
					G.say("%s can't drop: needs loaded pods and troops aboard" % s3.display_name, team)
			elif s3 and t3 and s3.team == team and may_ship.call(s3) and s3.has_method("start_boarding"):
				if not s3.boarding.is_empty():
					G.say("%s already has a boarding party mustering" % s3.display_name, team)
				elif not s3.start_boarding(t3, kind_):
					G.say("%s can't board %s: %s" % [s3.display_name, t3.display_name, "the shuttle needs a hangar, 4+ boarders, range 2.6 km and is on a 60 s cooldown"
						if kind_ == "shuttle" else ("an EVA crossing needs an airlock, 4+ boarders and under %d m of open space between the hulls" % int(s3.EVA_RANGE)
						if kind_ == "eva" else "needs to be within 1.5 km, with 4+ boarders aboard")], team)
		"missiles":
			var s6: Node = V.call(args[0])
			var t6: Node = V.call(args[1])
			if s6 and t6 and s6.team == team and may_ship.call(s6) and s6.has_method("fire_missiles"):
				if s6.fire_missiles(t6, 4) == 0:
					G.say("%s: missiles not ready (%d in the racks, 2.6 km range)" % [s6.display_name, s6.missiles], team)
		"lock":
			var s7: Node = V.call(args[0])
			if s7 and s7.team == team and may_ship.call(s7) and s7.has_method("fire_missiles"):
				s7.lock = V.call(args[1])
		"fleet":
			var s8: Node = V.call(args[0])
			if s8 and s8.team == team and may_ship.call(s8):
				fleet_order(s8, args[1])
		"join_board":
			var b9: Node = own_body.call(args[0])
			var s9: Node = V.call(args[1])
			if b9 and s9 and s9.has_method("join_boarding"):
				s9.join_boarding(b9)
		"squad":
			var b10: Node = own_body.call(args[0])
			if b10:
				squad_command(b10, args[1], args[2])
		"requisition":
			var b11: Node = own_body.call(args[0])
			if b11:
				requisition(b11)
		"resupply":
			var s12: Node = V.call(args[0])
			var h: Node = homes.get(team)
			if s12 and h and s12.team == team and s12.kind == "ship" and not h.destroyed:
				logistics.send_to_dock(s12, h)
				G.say("%s returning to %s to dock and resupply" % [s12.display_name, h.display_name], team)
		"fighters":
			var s4: Node = V.call(args[0])
			if s4 and s4.team == team:
				s4.request_fighters()
		"train":
			var s5: Node = V.call(args[0])
			if s5 and s5.team == team and not s5.train_squad():
				G.say("Can't train at %s: %s" % [s5.display_name, s5.train_problem()], team)
		"research":
			if not G.start_research(team, args[0]):
				G.say("Can't research that yet", team)
		"fighter_attack":
			var f: Node = G.net_ids.get(args[0])
			var t4: Node = V.call(args[1])
			if f and t4 and f.team == team:
				f.target = t4


## Orders from a ship's helm to the rest of the fleet: attack my lock, form on me, hold, board my lock.
func fleet_order(flag: Node, op: String) -> void:
	var i := 0
	for v in G.vessels:
		if v == flag or v.kind != "ship" or v.destroyed or v.team != flag.team or v.helm != null or v.drifting or v.is_supply_ship:
			continue
		match op:
			"attack":
				if flag.lock:
					v.attack_target = flag.lock
					v.lock = flag.lock
					v.follow = null
					v.move_target = Vector3.INF
			"form":
				v.follow = flag
				v.attack_target = null
				v.move_target = Vector3.INF
				var row := i / 2
				v.follow_off = Vector3((1 if i % 2 == 0 else -1) * (170.0 + 110.0 * row), 0, 140.0 + 120.0 * row)
			"hold":
				v.follow = null
				v.attack_target = null
				v.move_target = Vector3.INF
			"board":
				if flag.lock and v.boarding.is_empty():
					v.start_boarding(flag.lock, "shuttle" if v.can_shuttle(flag.lock) and i % 2 == 1 else "pods")
		i += 1
	if op == "board" and flag.lock and flag.boarding.is_empty():
		flag.start_boarding(flag.lock, "pods")


## A player's own squad. Keys (first person, when you lead a squad):
##   1 follow   2 hold here   3 move here / stack on the door   4 breach & clear the door
##   5 suppress the aim point   6 regroup on me   7 formation wedge/file/line
##   8 fireteam B to the aim point (again: rejoin)   9 weapons free / tight   0 frag out at the aim point
func squad_command(c: Node, op: String, p: Vector3) -> void:
	var sq = c.squad
	if sq == null or sq.leader != c:
		return
	var v: Node = c.vessel
	var door_at := func(q: Vector3) -> Dictionary:
		var dn: Dictionary = v.door_near(Vector3(q.x, floorf((q.y + 0.5) / 4.0) * 4.0, q.z), 2.2)
		if dn.is_empty() and v.has_method("wall_near"):
			dn = v.wall_near(Vector3(q.x, floorf((q.y + 0.5) / 4.0) * 4.0, q.z), 2.5)
		return dn
	match op:
		"follow":
			sq.order = {}
			sq.stack_door = {}
			sq.clear = {}
			sq.split = {}
		"hold":
			sq.order = {"type": "hold", "pos": p}
		"move":
			sq.order = {"type": "hold", "pos": v.snap_local(p)}
			var d: Dictionary = door_at.call(p)
			if not d.is_empty() and not d["open"] and not d["breached"]:
				sq.stack_door = d
				sq.stack_t = 0.0
				sq.order = {}
		"breach":
			var d2: Dictionary = door_at.call(p)
			if d2.is_empty():
				G.say("No door there to breach", c.team)
				return
			sq.order = {}
			sq.clear = {}
			if d2["breached"] or d2["open"]:
				sq._start_clear(d2)                       # already open: just clear the room
			else:
				d2["clear_after"] = true
				sq.stack_door = d2
				sq.stack_t = 0.0
				if not G.enemies(c.team, v.team) and d2["kind"] != "wall":
					v._set_door(d2, true)                 # our own door: it just opens
		"suppress":
			sq.suppress = {"pos": p, "until": G.time + 8.0}
		"regroup":
			sq.order = {}
			sq.split = {}
			sq.clear = {}
			sq.spacing = 0.7
			sq._regroup_until = G.time + 10.0
			for m in sq.alive():
				m.run = true
		"formation":
			sq.formation = {"wedge": "file", "file": "line", "line": "wedge"}[sq.formation]
			sq.spacing = 1.7 if sq.formation == "line" else 1.0
			G.say("Formation: %s" % sq.formation, c.team)
		"split":
			if sq.split.is_empty():
				sq.split = {"pos": v.snap_local(p)}
			else:
				sq.split = {}
		"fire":
			sq.hold_fire = not sq.hold_fire
			G.say("Weapons %s" % ("tight" if sq.hold_fire else "free"), c.team)
		"grenade":
			var best: Node = null
			var bd := INF
			for m in sq.alive():
				if m != c and not m.grenades.is_empty():
					var dd: float = m.position.distance_to(p)
					if dd < bd and dd < 25.0:
						bd = dd
						best = m
			if best and best._friend_in_blast(v.to_global(p), 6.0):
				G.say("%s: can't throw, friendlies by the aim point" % best.display, c.team)
			elif best:
				best._throw_grenade(v.to_global(p))
				G.say("%s: frag out!" % best.display, c.team)
			else:
				G.say("Nobody has a grenade in range", c.team)


const REQ_COST := {"alloys": 300.0, "cores": 4.0}
const REQ_ROLES := ["rifleman", "rifleman", "medic", "heavy", "breacher", "grenadier"]
var _req_cd := {}                  # team -> seconds until the next reinforcement


## T in first person: reinforcements join your squad. Aboard a friendly vessel they come up
## from the garrison; aboard an enemy one a nearby friendly ship fires a pod in near you.
func requisition(c: Node) -> void:
	var team: int = c.team
	if _req_cd.get(team, 0.0) > G.time:
		G.say("Reinforcements on cooldown: %d s" % int(_req_cd[team] - G.time), team)
		return
	var r: Dictionary = G.resources.get(team, {})
	if team == 1 and campaign_mode and G.campaign:
		r = G.campaign.stores
		G.resources[1] = r
	var extra_n: int = int(G.tech_bonus(team, "squad_extra"))
	var need_c: float = float(REQ_ROLES.size() + extra_n) if campaign_mode else REQ_COST["cores"]   # campaign: a core per soldier
	var need_a: float = 120.0 if campaign_mode else REQ_COST["alloys"]
	if float(r.get("alloys", 0.0)) < need_a or float(r.get("cores", 0.0)) < need_c:
		G.say("Reinforcements need %d alloys and %d cores (you have %d and %d)" % [int(need_a), int(need_c), int(r.get("alloys", 0.0)), int(r.get("cores", 0.0))], team)
		return
	var sq = c.squad
	if sq == null or sq.leader != c:
		if sq:
			sq.remove(c)
		sq = new_squad(team, c.vessel)
		sq.add(c)
		sq.leader = c
	var v: Node = c.vessel
	if not G.enemies(team, v.team):
		r["alloys"] = float(r["alloys"]) - need_a
		r["cores"] = float(r["cores"]) - need_c
		_req_cd[team] = G.time + 90.0
		var spot: Vector3 = c.position
		var cands: Array = v.marks_like("*_Garrison") + v.marks_like("PodBay_*_Muster") + v.marks_like("PlayerSpawn_*")
		if not cands.is_empty():
			spot = v.local_of(cands[randi() % cands.size()])
		G.say("Reinforcements on the way: 6 soldiers, 15 s", team)
		get_tree().create_timer(15.0).timeout.connect(func():
			if not is_instance_valid(v) or v.destroyed or v.team != team:
				return
			var req_roles: Array = REQ_ROLES.duplicate()
			for xi in extra_n:
				req_roles.append("rifleman")
			for i in req_roles.size():
				var n: Node = spawn_character(v, v.snap_local(spot + Vector3((i % 3) * 0.9 - 0.9, 0, int(i / 3) * 0.9)), team,
					v.faction if v.faction in [1, 2] else team, req_roles[i])
				n.run = true
				if is_instance_valid(sq.leader):
					sq.add(n)
			G.stat("requisitions"))
		return
	# aboard the enemy: a pod from the nearest friendly ship in range
	var best: Node = null
	var bd := 1500.0
	for s in G.vessels:
		if s.kind == "ship" and s.team == team and not s.destroyed and s.troops >= 4:
			var d: float = s.global_position.distance_to(v.global_position)
			if d < bd:
				bd = d
				best = s
	if best == null:
		G.say("No friendly ship with boarders within 1.5 km to send a pod", team)
		return
	r["alloys"] -= REQ_COST["alloys"]
	r["cores"] -= REQ_COST["cores"]
	_req_cd[team] = G.time + 90.0
	best.reinforcement_pod(v, c.global_position, sq)
	G.say("%s is sending a reinforcement pod to you" % best.display_name, team)
	G.stat("requisitions")


func on_ship_captured(s_: Node3D, old: int, new_: int) -> void:
	G.stat("ships_captured")
	if campaign_mode:
		if new_ == 1:
			s_.set_meta("prize", true)                 # it joins the player's fleet
			s_.remove_meta("role")
			G.say("%s is yours: it joins the fleet" % s_.display_name, 1)
			G.change_standing(old, -35.0, "you took one of their ships")
			_reputation_for_kill(old)
		G.campaign.on_vessel_gone(s_, new_)


func on_vessel_destroyed(v: Node3D) -> void:
	G.stat("vessels_destroyed")
	if campaign_mode and v.team == 1 and v.kind == "ship":
		get_tree().create_timer(5.0).timeout.connect(_check_stranded)
	if campaign_mode:
		var by: int = int(v.get_meta("last_hit_team", 0))
		if by == 1:
			G.change_standing(v.team, -30.0, "you destroyed their %s" % v.display_name)
			_reputation_for_kill(v.team)
		G.campaign.on_vessel_gone(v, by)


## Killing pirates, the infected or the Navy's enemies goes down well with the law-abiding.
func _reputation_for_kill(victim_team: int) -> void:
	if victim_team in [3, 4]:
		for t in [5, 6, 7]:
			G.change_standing(t, 2.0)
		G.change_standing(2, 1.0)


func on_station_lost(st: Node3D, new_team: int) -> void:
	if G.game_over:
		return
	if campaign_mode:
		var d: Dictionary = SECTOR.GALAXY.station_def(G.campaign.galaxy, st.get_meta("key", ""))
		if new_team == 1 and not d.is_empty():
			G.change_standing(int(d["team"]), -40.0, "you seized their station")
			_reputation_for_kill(int(d["team"]))
		return
	if st == homes.get(2) and (new_team == 1 or st.destroyed):
		_end(true)
	elif st == homes.get(1) and (new_team != 1 or st.destroyed):
		_end(false)


func _end(won: bool) -> void:
	G.game_over = true
	var msg := "VICTORY" if won else "DEFEAT"
	var sub := "The Ascendancy Spire has fallen." if won else "The Vanguard Bastion has fallen."
	G.say("%s - %s" % [msg, sub], 1)
	if commander:
		commander.banner(msg if G.player_team == 1 else ("DEFEAT" if won else "VICTORY"), sub)
	if G.network and G.network.active:
		G.network.broadcast_banner("GAME OVER", sub)


func _physics_process(dt: float) -> void:
	_squad_t -= dt
	if _squad_t <= 0.0 and not G.is_client():
		_squad_t = 0.25
		for sq in squads.duplicate():
			sq.update(0.25)
			if sq.members.is_empty():
				squads.erase(sq)
	if campaign_mode:
		_campaign_tick(dt)
	_income_t -= dt
	if _income_t > 0.0:
		return
	_income_t = 1.0
	_clear_of_rocks()
	if campaign_mode:
		return
	for m in mines:                                   # a captured mine pays its holder
		if is_instance_valid(m) and not m.destroyed and m.team in [1, 2]:
			var res: String = m.get_meta("ore", "alloys")
			var amt: float = {"alloys": 6.0, "fuel": 4.0, "circuitry": 2.5, "cores": 0.08}.get(res, 4.0)
			var rr: Dictionary = G.resources[m.team]
			rr[res] = rr.get(res, 0.0) + amt
	for team in [1, 2]:
		var h: Node = homes.get(team)
		if h and not h.destroyed and h.team == team:
			var r: Dictionary = G.resources[team]
			r["alloys"] += 14.0 * income_mult.get(team, 1.0)
			r["circuitry"] += 5.0 * income_mult.get(team, 1.0)
			r["cores"] += 0.12 * income_mult.get(team, 1.0)


# ------------------------------------------------------------------ the campaign

func _campaign_ready(t0: int) -> void:
	var c = G.campaign
	if on_surface:
		SURFACE.populate(self)
		DEPOT.restore(self)
		restore_ground_units()
		get_tree().create_timer(4.0).timeout.connect(post_perimeter_guards)
	else:
		SECTOR.populate(self)
	for f in 600:
		await get_tree().physics_frame
		if G.vessels.all(func(v): return v.nav_ok() and v.snap_local(Vector3.ZERO) != Vector3.ZERO):
			break
	for f in 3:
		await get_tree().physics_frame          # (ships mount their guns on their second frame)
	for pc in _pending:
		_crew(pc[0], pc[1], pc[2], pc[3])
	_pending.clear()
	for d in derelicts:
		_overrun(d)
	if ground:
		ground.bake_ground()
		for f in 3:
			await get_tree().physics_frame
		for gs in ground_spawns:
			var n0: int = ground.occupants.size()
			spawn_squad(ground, ground.snap_local(gs[0]), gs[1], 3 if gs[1] in [3, 4] else 1, gs[2], false)
			if gs.size() > 3:
				for i in range(n0, ground.occupants.size()):
					for mk in gs[3]:
						ground.occupants[i].set_meta(mk, gs[3][mk])
		for gv in ground_vehicles:
			var veh: Node3D = VEHICLE.new()
			veh.setup(gv[1], gv[2], gv[3], ground, ground.snap_local(ground.to_local(gv[0])))
			if gv.size() > 5:
				veh.hp = minf(veh.max_hp, float(gv[4]))
				veh.passengers = int(gv[5])
	logistics = LOGISTICS.new()
	add_child(logistics)
	ai = SANDBOX.new()
	add_child(ai)
	SECTOR.launch_miners(self)
	commander = COMMANDER.new()
	add_child(commander)
	var focus: Node = homes.get(1)
	for v in G.vessels:
		if v.team == 1 and v.kind == "ship" and (focus == null or c.arrive_from >= 0):
			focus = v
			break
	commander.pivot = focus.global_position + Vector3(0, 0, 150) if focus else Vector3.ZERO
	commander.zoom = 900.0
	ready_for_net = true
	var sys: Dictionary = c.system()
	print("Campaign system %s set up in %d ms: %d vessels, %d characters" % [sys["name"], Time.get_ticks_msec() - t0, G.vessels.size(), G.characters.size()])
	if on_surface:
		G.say("Landed: %s  ·  TAKE OFF on the command card returns to orbit" % system["name"], 1)
	else:
		G.say("%s  ·  %s" % [sys["name"], {"vanguard": "Vanguard space", "ascendancy": "Ascendancy space", "free": "Free space: no law here",
		"infected": "Quarantine zone: an infected world"}[sys["region"]]], 1)
	if c.arrive_from < 0 and c.day < 1.0:
		G.say("Your company has one frigate, two mining craft and a starter station. O galaxy map, P station services.", 1)
	if "--camptest" in OS.get_cmdline_user_args():
		add_child(load("res://tests/campaign_test.gd").new())


var _haul_t := 10.0


func _campaign_tick(dt: float) -> void:
	if G.is_client() or _jumping:
		return
	var c = G.campaign
	_camp_t -= dt
	if _camp_t > 0.0:
		return
	_camp_t = 1.0
	c.day += 1.0
	c.tick_markets(1.0)
	var r: Dictionary = c.stores
	# mining craft working in other systems (or in this one while we're down on a planet: they
	# don't fly in the surface scene) still bring ore home, if their station still stands
	var keys: Array = c.stations.map(func(s): return s["key"])
	for e in c.miners:
		if (int(e["system"]) != c.current or on_surface) and String(e.get("station", "")) in keys:
			r["ore"] = float(r.get("ore", 0.0)) + 1.2
	# refineries: ore into alloys
	var refineries := 0
	var BUILDER = load("res://scripts/campaign/builder.gd")
	BUILDER.tick(1.0)
	for st in c.stations:
		if st["cls"].begins_with("STATION_STARTER") or st["cls"] in ["STATION_HOME", "STATION_INDUSTRIAL"]:
			refineries += 1
		refineries += BUILDER.count_segments(st, "refinery")
	var ore: float = float(r.get("ore", 0.0))
	var use: float = minf(ore, 4.0 * refineries)
	r["ore"] = ore - use
	r["alloys"] = float(r.get("alloys", 0.0)) + use * 0.8
	c.set_meta("alloy_rate", lerpf(float(c.get_meta("alloy_rate", 0.0)), use * 0.8 * 60.0, 0.05))
	# fabricators: crystal + alloys into circuitry (or, with no crystal, alloys alone, slowly)
	var fabs := 0
	for st in c.stations:
		if st["cls"].begins_with("STATION_STARTER") or st["cls"] in ["STATION_HOME", "STATION_INDUSTRIAL"]:
			fabs += 1
		fabs += BUILDER.count_segments(st, "fabricator")
	var cry: float = float(r.get("crystal", 0.0))
	var al: float = float(r.get("alloys", 0.0))
	var made := 0.0
	if cry >= 1.0 and al >= 1.0:
		var n_: float = minf(minf(cry, al), 1.5 * fabs)
		r["crystal"] = cry - n_
		r["alloys"] = al - n_
		made = n_
	elif al > 200.0:
		var n2: float = minf(1.2 * fabs, al - 200.0)          # keeps 200 alloys back for building
		r["alloys"] = al - n2
		made = n2 / 3.0
	r["circuitry"] = float(r.get("circuitry", 0.0)) + made
	c.set_meta("circ_rate", lerpf(float(c.get_meta("circ_rate", 0.0)), made * 60.0, 0.05))
	# reactors breed tritium from fuel (jump drives burn it)
	var reactors := 0
	for st in c.stations:
		reactors += 1 + BUILDER.count_segments(st, "reactor")
	var fuel: float = float(r.get("fuel", 0.0))
	var burn: float = minf(fuel, 0.5 * reactors)
	r["fuel"] = fuel - burn
	r["tritium"] = float(r.get("tritium", 0.0)) + burn * 0.4
	# ground cargo: depots rearm, troops secure salvage for a supply ship to haul
	if on_surface:
		DEPOT.tick(self)
		INFECTION.surface_tick(self)
		load("res://scripts/campaign/outposts.gd").tick(self)
	INFECTION.galaxy_tick(self)
	# salvage caches: a ship of ours set down right beside one recovers it
	for cache in caches.duplicate():
		if not is_instance_valid(cache):
			caches.erase(cache)
			continue
		for v in G.vessels:
			if v.team == 1 and v.kind == "ship" and not v.destroyed and Vector2(v.global_position.x - cache.global_position.x, v.global_position.z - cache.global_position.z).length() < (60.0 if on_surface else 160.0):
				_take_cache(cache, v)
				break
	# salvage in a hold pays out at one of our stations (within 1.5 km)
	if not on_surface:
		for v in G.vessels:
			if v.team != 1 or v.kind != "ship" or v.destroyed or not v.has_meta("fleet_id"):
				continue
			if (c.fleet_entry(int(v.get_meta("fleet_id"))).get("salvage", {}) as Dictionary).is_empty():
				continue
			for st in G.vessels:
				if st.team == 1 and st.kind == "station" and not st.destroyed and st.global_position.distance_to(v.global_position) < 1500.0:
					deliver_salvage(v, st)
					break
	# AUTO HAUL: a landed supply ship loads newly secured salvage by itself
	_haul_t -= 1.0
	if on_surface and _haul_t <= 0.0:
		_haul_t = 10.0
		for v in G.vessels:
			if DEPOT.is_hauler(v) and v.team == 1 and not v.destroyed and v.has_meta("fleet_id") \
					and c.fleet_entry(int(v.get_meta("fleet_id"))).get("auto_haul", false):
				var msg: String = DEPOT.load_cargo(self, v, true)
				if msg != "":
					G.say(msg, 1)
	# ships ordered to jump: through the gate when the first one gets there
	for v in G.vessels:
		if v.team != 1 or v.kind != "ship" or v.destroyed or not v.has_meta("jump_to"):
			continue
		var to: int = int(v.get_meta("jump_to"))
		var gp: Vector3 = _gate_pos(to)
		if gp != Vector3.INF and Vector2(v.global_position.x - gp.x, v.global_position.z - gp.z).length() < 520.0:
			_do_jump(to, gp)
			return
	# the holds: crates for what each ship of ours is carrying
	for v in G.vessels:
		if v.team == 1 and v.kind == "ship" and not v.destroyed and v.has_meta("fleet_id"):
			var e: Dictionary = c.fleet_entry(int(v.get_meta("fleet_id")))
			if not e.is_empty():
				var shown: Dictionary = (e.get("cargo", {}) as Dictionary).duplicate()
				var sv := 0
				for kind in e.get("salvage", {}):
					sv += int(e["salvage"][kind])
				if sv > 0:
					shown["salvage"] = sv * 10                   # (a crate each)
				load("res://scripts/campaign/cargo_view.gd").refresh(v, shown)
				if v.cls == "SMALL_SUPPORT":
					load("res://scripts/campaign/bays.gd").refresh_mech_bay(v, ship_vehicles(v).count("mech"))
				if v.cls == "SMALL_DROP_FRIGATE" and v.get_meta("md_n", -1) != int(e.get("minidrops", 0)):
					# the docked mini dropships ride in cradles on the dropship's back
					v.set_meta("md_n", int(e.get("minidrops", 0)))
					for old in v.find_children("DockedMini*", "", false, false):
						old.free()
					for k in int(e.get("minidrops", 0)):
						var md: Node3D = load("res://scripts/campaign/minidrop.gd").new()
						md.name = "DockedMini%d" % k
						md.faction = v.faction if v.faction in [1, 2] else 1
						md.set_process(false)
						md._model()
						md.position = Vector3(v.aabb.get_center().x, v.aabb.end.y + 1.8, v.aabb.get_center().z + (k - 0.5) * 16.0)
						v.add_child(md)
	_save_t -= 1.0
	if _save_t <= 0.0:
		_save_t = 180.0
		c.snapshot()
		c.save()


func _gate_pos(to: int) -> Vector3:
	for g in gates:
		if int(g["to"]) == to:
			return g["pos"]
	return Vector3.INF


## Send ships to the gate for system `to`; they jump when the first arrives.
func order_jump(ships: Array, to: int) -> bool:
	var gp := _gate_pos(to)
	if gp == Vector3.INF:
		return false
	for s in ships:
		if is_instance_valid(s) and s.team == 1 and s.kind == "ship":
			s.set_meta("jump_to", to)
			s.attack_target = null
			s.follow = null
			if s.has_meta("dock_at"):
				logistics._undock(s)
			s.move_target = gp + (s.global_position - gp).normalized() * 60.0
	return true


const JUMP_TRITIUM := {"SMALL": 10.0, "MEDIUM": 25.0, "LARGE": 50.0, "XL": 90.0}


func _do_jump(to: int, gp: Vector3) -> void:
	# the jump drives need tritium: so much a ship, by size
	var need := 0.0
	for v in G.vessels:
		if v.team == 1 and v.kind == "ship" and not v.destroyed and v.has_meta("jump_to") and int(v.get_meta("jump_to")) == to \
				and v.global_position.distance_to(gp) < 2500.0:
			need += JUMP_TRITIUM.get(SHIP.size_class(v.cls), 10.0)
	var st: Dictionary = G.campaign.stores
	if float(st.get("tritium", 0.0)) < need:
		G.say("Not enough tritium to jump: need %d, have %d (reactors make it from fuel; markets sell it)" % [int(need), int(st.get("tritium", 0.0))], 1)
		for v in G.vessels:
			if v.has_meta("jump_to"):
				v.remove_meta("jump_to")
		return
	st["tritium"] = float(st.get("tritium", 0.0)) - need
	_jumping = true
	var ids: Array = []
	for v in G.vessels:
		if v.team == 1 and v.kind == "ship" and not v.destroyed and v.has_meta("jump_to") and int(v.get_meta("jump_to")) == to \
				and v.global_position.distance_to(gp) < 2500.0:
			ids.append(int(v.get_meta("fleet_id", -1)))
	var c = G.campaign
	c.snapshot()                       # (also adds captured prizes to the fleet)
	for v in G.vessels:
		if v.has_meta("jump_to") and int(v.get_meta("jump_to")) == to and v.has_meta("fleet_id") and not ids.has(int(v.get_meta("fleet_id"))):
			if v.global_position.distance_to(gp) < 2500.0:
				ids.append(int(v.get_meta("fleet_id")))
	G.say("JUMP: %d ship%s to %s" % [ids.size(), "" if ids.size() == 1 else "s", c.system_of(to)["name"]], 1)
	G.stat("jumps")
	G.sfx.ui("jump", 0.0)
	c.jump(to, ids)
	if commander:
		commander.banner("JUMPING", c.system_of(to)["name"])
	await get_tree().create_timer(0.6).timeout
	for n in G.pods + G.missiles + G.fighters:
		if is_instance_valid(n) and n.get_parent() == get_tree().root:
			n.queue_free()
	get_tree().reload_current_scene()


## Push a point out of any planet (ships can't fly through worlds).
func planet_push(p: Vector3, margin: float = 80.0) -> Vector3:
	for pl in planets:
		var c: Vector3 = pl["pos"]
		var r: float = float(pl["radius"]) + margin
		var d := p - c
		if d.length() < r:
			var flat := Vector3(d.x, 0, d.z)
			if flat.length() < 0.1:
				flat = Vector3.RIGHT
			# out sideways, keeping the ship on its plane
			var need := sqrt(maxf(0.0, r * r - d.y * d.y))
			var q := c + flat.normalized() * need
			return Vector3(q.x, p.y, q.z)
	return p


## A ship that arrives while the system is running (hive ships rising, reinforcements).
func spawn_runtime_ship(cls: String, team: int, fac: int, nm: String, pos: Vector3, crew: Array, role: String = "", want_variant: int = 0) -> Node3D:
	var s := _ship(cls, team, fac, nm, pos, crew, want_variant)
	_pending.erase(_pending[-1])
	if role != "":
		s.set_meta("role", role)
	_runtime_crew(s, crew, team, fac)
	return s


func _runtime_crew(s: Node3D, crew: Array, team: int, fac: int) -> void:
	var tree := get_tree()
	for f in 120:
		await tree.physics_frame
		if not is_instance_valid(s) or not is_instance_valid(self):
			return
		if s.nav_ok() and s.snap_local(Vector3.ZERO) != Vector3.ZERO:
			break
	if team == 4:
		_overrun(s)
	elif not crew.is_empty():
		_crew(s, crew, team, fac)


# ------------------------------------------------------------------ landing

## The landable world (with landing zones) nearest these ships, if they're close enough: [planet index, def].
func landing_target(ships: Array) -> Array:
	if not campaign_mode or on_surface or ships.is_empty():
		return []
	var sys: Dictionary = G.campaign.system()
	for i in sys["planets"].size():
		var pl: Dictionary = sys["planets"][i]
		if pl["sites"].is_empty():
			continue
		var d: float = Vector2(ships[0].global_position.x - pl["pos"].x, ships[0].global_position.z - pl["pos"].z).length()
		if d < float(pl["radius"]) + 1500.0:
			return [i, pl]
	return []


func land(ships: Array, site: int = 0) -> String:
	var ok: Array = ships.filter(func(s): return is_instance_valid(s) and s.team == 1 and s.kind == "ship" and s.cls in SURFACE.LANDERS and s.has_meta("fleet_id"))
	if ok.is_empty():
		return "Only small ships, supply ships, mediums and the dropship can land"
	var tgt := landing_target(ok)
	if tgt.is_empty():
		return "Fly within 1.5 km of a world with landing zones first"
	var ids: Array = ok.map(func(s): return int(s.get_meta("fleet_id")))
	G.campaign.land(int(tgt[0]), site % maxi(1, tgt[1]["sites"].size()), ids)
	_reload_world("LANDING", tgt[1]["sites"][site % tgt[1]["sites"].size()]["name"])
	return "Landing"


func take_off() -> void:
	G.campaign.take_off()
	_reload_world("LIFTING OFF", G.campaign.system()["name"])


func _reload_world(title: String, sub: String) -> void:
	_jumping = true
	G.sfx.ui("jump", 0.0)
	if commander:
		commander.banner(title, sub)
	await get_tree().create_timer(0.6).timeout
	for n in G.pods + G.missiles + G.fighters:
		if is_instance_valid(n) and n.get_parent() == get_tree().root:
			n.queue_free()
	get_tree().reload_current_scene()


## A salvage cache recovered. Into `ship`'s hold when a fleet ship takes it (it pays out when
## that ship reaches one of our stations: deliver_salvage); straight into stores otherwise.
func _take_cache(cache: Node3D, ship: Node = null) -> void:
	var c = G.campaign
	var kind: String = cache.get_meta("cache")
	var e: Dictionary = c.fleet_entry(int(ship.get_meta("fleet_id", -1))) if ship and is_instance_valid(ship) else {}
	if not e.is_empty():
		var hold: Dictionary = e.get("salvage", {})
		hold[kind] = int(hold.get(kind, 0)) + 1
		e["salvage"] = hold
		G.say("Salvage (%s) aboard %s: fly it to one of your stations" % [kind, ship.display_name], 1)
	else:
		salvage_reward(kind)
	var key: String = cache.get_meta("city")
	var w: Dictionary = c.world.get(key, {})
	var taken: Array = w.get("taken", [])
	taken.append(int(cache.get_meta("cache_id")))
	w["taken"] = taken
	c.world[key] = w
	G.stat("caches_taken")
	caches.erase(cache)
	cache.queue_free()


## A ship of ours near station `st` hands over the salvage in its hold.
func deliver_salvage(ship: Node, st: Node) -> int:
	var e: Dictionary = G.campaign.fleet_entry(int(ship.get_meta("fleet_id", -1)))
	var hold: Dictionary = e.get("salvage", {})
	var n := 0
	for kind in hold:
		for k in int(hold[kind]):
			salvage_reward(String(kind))
			n += 1
	if n > 0:
		e.erase("salvage")
		G.say("%s delivered %d salvage load%s to %s" % [ship.display_name, n, "" if n == 1 else "s", st.display_name], 1)
		G.stat("salvage_delivered", n)
	return n


## What one salvage cache of `kind` is worth, into the company's stores.
func salvage_reward(kind: String) -> void:
	var c = G.campaign
	var r: Dictionary = c.stores
	match kind:
		"cores":
			r["cores"] = float(r.get("cores", 0.0)) + 4.0
			G.say("Salvage recovered: 4 cores", 1)
		"alloys":
			r["alloys"] = float(r.get("alloys", 0.0)) + 350.0
			r["circuitry"] = float(r.get("circuitry", 0.0)) + 80.0
			G.say("Salvage recovered: 350 alloys and 80 circuitry", 1)
		"research":
			var done := false
			for id in G.TECH:
				if not G.has_tech(1, id):
					G.research[1][id] = true
					G.say("Salvage recovered: research data. Unlocked %s" % G.TECH[id]["name"], 1)
					done = true
					break
			if not done:
				c.credits += 1500
				G.say("Salvage recovered: research data, sold for 1500 cr", 1)


# ------------------------------------------------------------------ on the ground

## A landed ship puts its boarders down on the ground beside it (up to a squad of 8).
func deploy_troops(s: Node) -> int:
	if ground == null or not is_instance_valid(s) or s.troops <= 0:
		return 0
	var n: int = mini(8, s.troops)
	s.troops -= n
	var roles: Array = ["squad_leader", "rifleman", "rifleman", "medic", "breacher", "heavy", "grenadier", "rifleman"].slice(0, n)
	var side: Vector3 = s.global_basis.x * (s.aabb.size.x * 0.5 + 25.0)
	var p: Vector3 = ground.near_local(ground.to_local(s.global_position + side), 15.0)
	spawn_squad(ground, p, s.team, G.team_fac(s.team), roles, false)
	G.say("%s: %d troops on the ground" % [s.display_name, n], s.team)
	G.stat("ground_deploys")
	return n


## Troops near a landed ship climb back aboard.
func recall_troops(s: Node) -> int:
	if ground == null or not is_instance_valid(s):
		return 0
	var n := 0
	for c in ground.occupants.duplicate():
		if c.team == s.team and c.state == "alive" and not c.is_crew() and c != G.possessed \
				and Vector2(c.global_position.x - s.global_position.x, c.global_position.z - s.global_position.z).length() < 120.0 \
				and s.troops < s.berth_cap:
			s.troops += 1
			logistics._remove_person(c)
			n += 1
	return n



## Our troops and vehicles on this landing zone are written to the campaign so they're
## still there when we come back (switching zones, taking off, saving).
func save_ground_units() -> void:
	if ground == null or not on_surface or G.campaign == null or G.campaign.surface.is_empty():
		return
	var c = G.campaign
	var troops: Array = []
	for o in ground.occupants:
		if is_instance_valid(o) and o.team == 1 and o.state == "alive" and not o.has_meta("perimeter") and not o.has_meta("vehicle_crew"):
			troops.append([o.global_position.x, o.global_position.z, o.role])
	var vehs: Array = []
	for v in G.vehicles:
		if is_instance_valid(v) and v.team == 1 and not v.destroyed and v.cargo_of == null and v.ground == ground:
			vehs.append([v.global_position.x, v.global_position.z, v.kind, v.hp, v.passengers])
	c.world[c.units_key(c.current, int(c.surface["planet"]), int(c.surface["site"]))] = {"troops": troops, "vehicles": vehs}


## ...and put back down when the zone loads.
func restore_ground_units() -> void:
	var c = G.campaign
	var key: String = c.units_key(c.current, int(c.surface["planet"]), int(c.surface["site"]))
	var rec: Dictionary = c.world.get(key, {})
	var troops: Array = rec.get("troops", [])
	var i := 0
	while i < troops.size():
		var grp: Array = troops.slice(i, i + 8)
		var roles: Array = grp.map(func(t): return String(t[2]))
		var p0 := Vector3(float(grp[0][0]), 0, float(grp[0][1]))
		p0.y = ground_y(p0.x, p0.z)
		ground_spawns.append([p0, 1, roles])
		i += 8
	for v in rec.get("vehicles", []):
		var pv := Vector3(float(v[0]), 0, float(v[1]))
		pv.y = ground_y(pv.x, pv.z)
		ground_vehicles.append([pv, String(v[2]), 1, G.team_fac(1), float(v[3]), int(v[4])])
	c.world.erase(key)


## Nothing of ours left here (the last ship lost, nobody on the ground): look at our home
## station, switching to its system if it's elsewhere, so a new ship can be built.
func _check_stranded() -> void:
	if not is_instance_valid(self) or _jumping or not campaign_mode:
		return
	for v in G.vessels:
		if is_instance_valid(v) and not v.destroyed and v.team == 1 and (v.kind == "ship" or v.kind == "station"):
			if v.kind == "station" and commander and not on_surface:
				return
			if v.kind == "ship":
				return
	if on_surface and ground:
		for c in ground.occupants:
			if is_instance_valid(c) and c.team == 1 and c.state == "alive":
				return
	var c = G.campaign
	c.snapshot()
	if c.stations.is_empty():
		G.say("No ships and no stations left: the company is finished", 1)
		return
	var st: Dictionary = c.stations[0]
	for s2 in c.stations:
		if s2["key"] == "player_home":
			st = s2
	G.say("No ships left here: back to %s to build a new one (SHIPS menu)" % st["name"], 1)
	switch_zone({"system": int(st["system"]), "planet": -1, "site": -1, "label": st["name"], "here": false})


## A core ship unfolds into a new station of ours where it stands: the ship is used up,
## its crew moves in, and the station starts with a few recruits and supplies.
func deploy_station(s: Node) -> String:
	if not s.has_meta("core_ship"):
		return "Only a station core ship can do that"
	if on_surface:
		return "A station has to be deployed in space"
	var p: Vector3 = Vector3(s.global_position.x, 0, s.global_position.z)
	for v in G.vessels:
		if is_instance_valid(v) and v.kind == "station" and not v.destroyed and v.global_position.distance_to(p) < 1400.0:
			return "Too close to %s (keep 1.4 km clear)" % v.display_name
	for pl in system.get("planets", []):
		if Vector2(p.x - pl["pos"].x, p.z - pl["pos"].z).length() < float(pl["radius"]) + 600.0:
			return "Too close to the planet"
	var c = G.campaign
	var nm: String = "%s %s" % [c.company.get_slice(" ", 0), ["Outpost", "Hold", "Anchorage", "Reach", "Haven", "Depot"][randi() % 6]]
	var key := "player_%d" % c.new_id()
	c.stations.append({"key": key, "system": c.current, "cls": "STATION_STARTER", "name": nm, "pos": [p.x, p.z], "supplies": 150.0, "reserve": 4})
	var st: Node3D = _station("STATION_STARTER", 1, 1, nm, p, SECTOR.PLAYER_STATION_CREW)
	_pending.erase(_pending[-1])
	st.set_meta("key", key)
	st.supplies = 150.0
	st.reserve = 4
	_runtime_crew(st, SECTOR.PLAYER_STATION_CREW, 1, 1)
	var fe: Dictionary = c.fleet_entry(int(s.get_meta("fleet_id", -1)))
	if not fe.is_empty():
		c.fleet.erase(fe)
	G.explosion(s.global_position, 20.0, Color(0.5, 0.8, 1.0))
	for o in s.occupants.duplicate():
		if is_instance_valid(o) and o == G.possessed and commander:
			commander.release()
	G.vessels.erase(s)
	if commander:
		commander.clear_selection()
	s.queue_free()
	G.stat("stations_deployed")
	return "%s deployed: a new station of ours. Build segments on it from the STATION menu" % nm


## A campaign ship's hangar as it was saved (bought craft, losses), instead of the two free
## fighters every new ship gets. Records saved before hangars were kept have none.
func restore_hangar(s: Node3D, e: Dictionary) -> void:
	if not e.has("hangar"):
		return
	for p in s.pads:
		if p["parked"] != null:
			(p["parked"] as Node3D).queue_free()
			p["parked"] = null
	var hangar: Array = e["hangar"]
	for i in mini(hangar.size(), s.pads.size()):
		s.park_fighter(i, String(hangar[i]))


## Whatever infection was aboard when the ship was last seen is aboard again.
func restore_ship_infection(s: Node3D, e: Dictionary) -> void:
	var n: int = int(e.get("infected", 0))
	var zs: Array = e.get("infected_zones", [])
	if n <= 0 and zs.is_empty():
		return
	var tree := get_tree()
	for f in 240:
		await tree.physics_frame
		if not is_instance_valid(s) or not is_instance_valid(self):
			return
		if s.nav_ok() and s.snap_local(Vector3.ZERO) != Vector3.ZERO:
			break
	for z in zs:
		var zi: int = int(z[0])
		if zi < s.zones.size():
			s.zones[zi]["infected"] = true
			s.zones[zi]["growth"] = float(z[1])
	if not zs.is_empty() and s.has_method("_update_infection_overlay"):
		s._update_infection_overlay()
	for i in n:
		var c := spawn_character(s, s.clear_spot(), 1, 1, DERELICT_BODIES[i % DERELICT_BODIES.size()])
		c._convert(true)
	if n > 0:
		G.say("%s: the infection is still aboard (%d)" % [s.display_name, n], 1)


## Go to another zone where we have ships, stations or ground units.
func switch_zone(z: Dictionary) -> void:
	if z.get("here", false):
		return
	G.campaign.goto_zone(z)
	_reload_world("REDEPLOYING", String(z.get("label", "")))


## In orbit: a supply ship or dropship near one of our stations takes vehicles from its
## depot aboard (up to its bay's room), or puts its own back into the depot.
func _depot_station_for(s: Node) -> Dictionary:
	var c = G.campaign
	for v in G.vessels:
		if is_instance_valid(v) and v.kind == "station" and v.team == 1 and not v.destroyed \
				and v.global_position.distance_to(s.global_position) < 2500.0:
			for st in c.stations:
				if st["key"] == v.get_meta("key", ""):
					return st
	return {}


func load_vehicles(s: Node) -> String:
	if not (s.cls in HAULERS):
		return "%s has no vehicle bay (supply ships and dropships carry vehicles)" % s.display_name
	if on_surface:
		return "On a world: select vehicles and right-click the landed ship to drive them aboard"
	var st := _depot_station_for(s)
	if st.is_empty():
		return "Bring %s within 2.5 km of one of your stations" % s.display_name
	var dep: Array = st.get("vehicles", [])
	var bay: Array = ship_vehicles(s)
	var cap: int = VEHICLE_CAP.get(s.cls, 0)
	var n := 0
	var left: Array = []
	for k in dep:
		if bay.size() < cap and can_carry(s.cls, String(k)):
			bay.append(k)
			n += 1
		else:
			left.append(k)
	dep = left
	st["vehicles"] = dep
	if n == 0:
		return "Nothing loaded: %s" % ("the depot is empty" if dep.is_empty() else "the bay is full (%d)" % cap)
	return "%s: %d vehicles loaded from %s (%d/%d aboard, %d left in the depot)" % [s.display_name, n, st["name"], bay.size(), cap, dep.size()]


func unload_vehicles(s: Node) -> String:
	if on_surface:
		return "On a world use DEPLOY VEHICLES"
	var st := _depot_station_for(s)
	if st.is_empty():
		return "Bring %s within 2.5 km of one of your stations" % s.display_name
	var bay: Array = ship_vehicles(s)
	var dep: Array = st.get("vehicles", [])
	var n := bay.size()
	dep.append_array(bay)
	bay.clear()
	st["vehicles"] = dep
	return "%s: %d vehicles parked in the %s depot" % [s.display_name, n, st["name"]]


## A landed dropship's security detail comes out and walks a perimeter round it (two
## fireteams, ~110 m out) instead of standing about inside. Its boarders stay aboard as
## deployable infantry.
func post_perimeter_guards() -> void:
	if ground == null or not on_surface:
		return
	for s in G.vessels:
		if not is_instance_valid(s) or s.destroyed or s.team != 1 or s.kind != "ship" or s.cls != "SMALL_DROP_FRIGATE":
			continue
		var sec: Array = s.occupants.filter(func(c): return is_instance_valid(c) and c.state == "alive" and c.role == "security" and c != G.possessed)
		var n: int = clampi(sec.size(), 4, 8)
		for c in sec:
			logistics._remove_person(c)
		var center: Vector3 = s.global_position
		for k in 2:
			var cnt: int = n / 2 + (n % 2 if k == 0 else 0)
			var roles: Array = ["squad_leader"]
			for i in cnt - 1:
				roles.append("medic" if i == 1 else "rifleman")
			var side: Vector3 = s.global_basis.x * (s.aabb.size.x * 0.5 + 30.0) * (1.0 if k == 0 else -1.0)
			var p: Vector3 = ground.near_local(ground.to_local(center + side), 15.0)
			var before: int = ground.occupants.size()
			spawn_squad(ground, p, 1, G.team_fac(1), roles, false)
			for i in range(before, ground.occupants.size()):
				var c: Node = ground.occupants[i]
				if is_instance_valid(c):
					c.set_meta("perimeter", [center, 110.0])
		G.say("%s: security detail is walking the perimeter" % s.display_name, 1)


## The vehicles a ship of ours carries (its campaign record), filled with its standard bay on first use.
func ship_vehicles(s: Node) -> Array:
	var e: Dictionary = G.campaign.fleet_entry(int(s.get_meta("fleet_id", -1))) if G.campaign else {}
	if e.is_empty():
		return []
	if not e.has("vehicles"):
		e["vehicles"] = VEHICLE_BAYS.get(s.cls, []).duplicate()
	return e["vehicles"]


## A vehicle we ordered aboard reached the ramp of a landed supply ship or dropship.
func board_vehicle(v: Node, s: Node) -> bool:
	var bay: Array = ship_vehicles(s)
	if not can_carry(s.cls, v.kind):
		G.say("%s's bay only takes MRAPs" % s.display_name, 1)
		return false
	if bay.size() >= int(VEHICLE_CAP.get(s.cls, 0)):
		G.say("%s's vehicle bay is full" % s.display_name, 1)
		return false
	bay.append(v.kind)
	s.troops = mini(s.berth_cap, s.troops + v.passengers)
	load("res://scripts/campaign/bays.gd").ramp_down(s)
	get_tree().create_timer(4.0).timeout.connect(func():
		if is_instance_valid(s):
			load("res://scripts/campaign/bays.gd").ramp_up(s))
	G.say("%s drove aboard %s (%d/%d)" % [v.display_name, s.display_name, bay.size(), VEHICLE_CAP.get(s.cls, 0)], 1)
	G.vehicles.erase(v)
	v.queue_free()
	return true


## A landed ship drives its vehicles out down the ramp (IFVs with a squad aboard).
func deploy_vehicles(s: Node) -> int:
	if ground == null:
		return 0
	var bay: Array = ship_vehicles(s)
	var n: int = bay.size()
	load("res://scripts/campaign/bays.gd").drive_out(s, bay)      # (takes each off the bay as it rolls out)
	G.say("%s: ramp down, %d vehicles rolling out" % [s.display_name, n], s.team)
	return n


## Our vehicles within 150 m of a landed ship drive back aboard (if there's room).
func recall_vehicles(s: Node) -> int:
	var bay: Array = ship_vehicles(s)
	var cap: int = VEHICLE_CAP.get(s.cls, 0)
	var n := 0
	for v in G.vehicles.duplicate():
		if v.team == s.team and bay.size() < cap and can_carry(s.cls, v.kind) and Vector2(v.global_position.x - s.global_position.x, v.global_position.z - s.global_position.z).length() < 150.0:
			bay.append(v.kind)
			s.troops = mini(s.berth_cap, s.troops + v.passengers)
			G.vehicles.erase(v)
			v.queue_free()
			n += 1
	return n



## Ground height (world y) under a point on a surface.
func ground_y(x: float, z: float) -> float:
	return SURFACE.GROUND_Y - 2.0 + SURFACE.height(terrain_P, system, x, z)


## Where a ship should be on a surface: sitting on the ground when stopped (so its ramp
## reaches), cruising 60 m over the highest ground under its hull when moving.
func surface_alt(s: Node) -> float:
	var half: float = s.aabb.size.z * 0.5
	var g := -1.0e9
	for k in [-1.0, 0.0, 1.0]:
		var p: Vector3 = s.global_position - s.global_basis.z * half * k
		g = maxf(g, ground_y(p.x, p.z))
	var moving: bool = s.move_target != Vector3.INF or (s.attack_target != null and is_instance_valid(s.attack_target))
	return g - s.aabb.position.y + (60.0 if moving else 1.0)



## Send one of a dropship's mini dropships to a point on the ground. A follower moves into
## the free cradle a little later.
func send_minidrop(s: Node, world_p: Vector3) -> String:
	if ground == null:
		return "Mini dropships deploy on a planet's surface: land first"
	var e: Dictionary = G.campaign.fleet_entry(int(s.get_meta("fleet_id", -1)))
	if e.is_empty() or int(e.get("minidrops", 0)) <= 0:
		return "%s has no mini dropship docked (build them in the UNITS menu)" % s.display_name
	e["minidrops"] = int(e["minidrops"]) - 1
	var md: Node3D = load("res://scripts/campaign/minidrop.gd").new()
	add_child(md)
	md.setup(s, world_p)
	if int(e.get("minidrop_reserve", 0)) > 0:
		e["minidrop_reserve"] = int(e["minidrop_reserve"]) - 1
		e["minidrops_following"] = int(e.get("minidrops_following", 0)) + 1     # (a save counts it as docked)
		get_tree().create_timer(20.0).timeout.connect(func():
			e["minidrops_following"] = maxi(0, int(e.get("minidrops_following", 0)) - 1)
			e["minidrops"] = int(e.get("minidrops", 0)) + 1
			G.say("A following mini dropship docked on %s" % e["name"], 1))
	return "Mini dropship away from %s" % s.display_name


## Nobody sits inside a big asteroid (arrivals, spawns): push them out to its surface.
func _clear_of_rocks() -> void:
	if on_surface or rocks.is_empty():
		return
	for v in G.vessels:
		if not is_instance_valid(v) or v.destroyed or v.kind != "ship":
			continue
		var r: float = v.aabb.size.length() * 0.5 + 40.0
		for rk in rocks:
			var c: Vector3 = rk[0]
			var off: Vector3 = v.global_position - c
			var need: float = float(rk[1]) + r
			if off.length() < need:
				var dir: Vector3 = off.normalized() if off.length() > 1.0 else Vector3.UP
				v.global_position = c + dir * need
