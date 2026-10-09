extends Node
## Global game state (autoloaded as "G"): teams, unit lists, combat data and effects.

const LAYER_WORLD := 1        # hulls, decks, walls, furniture
const LAYER_CHAR := 2         # characters (also their hitboxes)
const LAYER_DOOR := 4         # doors that open and close (kept out of the navigation bake)
const LAYER_PICK := 8         # click targets for ships, fighters and pods in commander view
const PORT := 24680           # multiplayer (UDP)

## Limits per side. Soldiers are unlimited (only resources and cores hold you back).
const CAPS := {"soldiers": 100000, "squads_training": 3, "fighters": 6}

## Research: three branches, three tiers each. Costs circuitry, takes time, needs a working command core.
const TECH := {
	"w1": {"name": "Hardened rounds", "branch": "Weapons", "tier": 1, "cost": 300, "time": 45.0, "desc": "+10% infantry damage"},
	"w2": {"name": "Smart optics", "branch": "Weapons", "tier": 2, "cost": 600, "time": 60.0, "desc": "-35% weapon spread", "needs": "w1"},
	"w3": {"name": "Overcharged cells", "branch": "Weapons", "tier": 3, "cost": 1000, "time": 80.0, "desc": "+15% infantry damage, faster reloads", "needs": "w2"},
	"a1": {"name": "Reinforced plating", "branch": "Armor", "tier": 1, "cost": 300, "time": 45.0, "desc": "+6% damage reduction"},
	"a2": {"name": "Field medicine", "branch": "Armor", "tier": 2, "cost": 600, "time": 60.0, "desc": "Revives restore 80 HP, +1 medpen", "needs": "a1"},
	"a3": {"name": "Reactive exo-suits", "branch": "Armor", "tier": 3, "cost": 1000, "time": 80.0, "desc": "+40% exo boost energy, +6% DR", "needs": "a2"},
	"f1": {"name": "Capacitor banks", "branch": "Fleet", "tier": 1, "cost": 400, "time": 50.0, "desc": "+25% shield regeneration"},
	"f2": {"name": "Armored pods", "branch": "Fleet", "tier": 2, "cost": 700, "time": 65.0, "desc": "Boarding pods +60% armor, +2 boarders", "needs": "f1"},
	"f3": {"name": "Heavy batteries", "branch": "Fleet", "tier": 3, "cost": 1200, "time": 90.0, "desc": "+25% ship and station turret damage", "needs": "f2"},
	"t1": {"name": "Combat conditioning", "branch": "Troops", "tier": 1, "cost": 300, "time": 45.0, "desc": "+15% soldier and crew health"},
	"t2": {"name": "Expanded squads", "branch": "Troops", "tier": 2, "cost": 650, "time": 60.0, "desc": "Trained squads and reinforcements +2 soldiers", "needs": "t1"},
	"t3": {"name": "Veteran cadre", "branch": "Troops", "tier": 3, "cost": 1000, "time": 80.0, "desc": "+10% health, troops move 12% faster", "needs": "t2"},
	"b1": {"name": "Shuttle afterburners", "branch": "Boarding", "tier": 1, "cost": 350, "time": 45.0, "desc": "Boarding shuttles fly 40% faster"},
	"b2": {"name": "Armoured shuttles", "branch": "Boarding", "tier": 2, "cost": 650, "time": 60.0, "desc": "Boarding shuttles twice as tough", "needs": "b1"},
	"b3": {"name": "Rapid launch", "branch": "Boarding", "tier": 3, "cost": 1000, "time": 80.0, "desc": "Boarding shuttle cooldown -40%", "needs": "b2"},
	"l1": {"name": "Extra cargo shuttles", "branch": "Logistics", "tier": 1, "cost": 300, "time": 45.0, "desc": "+1 Darter supply run at a time per station"},
	"l2": {"name": "Express routes", "branch": "Logistics", "tier": 2, "cost": 600, "time": 60.0, "desc": "Darters and supply shuttles fly 40% faster", "needs": "l1"},
	"l3": {"name": "Bulk holds", "branch": "Logistics", "tier": 3, "cost": 900, "time": 75.0, "desc": "Mining craft haul 50% more ore", "needs": "l2"},
	"e1": {"name": "Tuned drives", "branch": "Engineering", "tier": 1, "cost": 400, "time": 50.0, "desc": "Ships +15% speed"},
	"e2": {"name": "Vectored thrusters", "branch": "Engineering", "tier": 2, "cost": 700, "time": 65.0, "desc": "Ships turn 30% faster", "needs": "e1"},
	"e3": {"name": "Hull lattice", "branch": "Engineering", "tier": 3, "cost": 1200, "time": 90.0, "desc": "Ships +20% hull", "needs": "e2"},
	"g1": {"name": "Composite armour", "branch": "Ground", "tier": 1, "cost": 400, "time": 50.0, "desc": "Vehicles +25% health"},
	"g2": {"name": "Fortification", "branch": "Ground", "tier": 2, "cost": 700, "time": 65.0, "desc": "Outpost structures +40% health", "needs": "g1"},
	"g3": {"name": "Rapid fabrication", "branch": "Ground", "tier": 3, "cost": 1000, "time": 80.0, "desc": "Everything builds 25% faster", "needs": "g2"},
}
const TECH_BRANCHES := ["Weapons", "Armor", "Fleet", "Troops", "Boarding", "Logistics", "Engineering", "Ground"]
## What each research gives, summed by effect (see tech_bonus).
const TECH_FX := {
	"troop_hp": [["t1", 0.15], ["t3", 0.10]], "squad_extra": [["t2", 2.0]], "troop_speed": [["t3", 0.12]],
	"shuttle_speed": [["b1", 0.4]], "shuttle_hp": [["b2", 1.0]], "shuttle_cd": [["b3", 0.4]],
	"darter_runs": [["l1", 1.0]], "darter_speed": [["l2", 0.4]], "miner_load": [["l3", 0.5]],
	"ship_speed": [["e1", 0.15]], "ship_turn": [["e2", 0.3]], "ship_hull": [["e3", 0.2]],
	"vehicle_hp": [["g1", 0.25]], "outpost_hp": [["g2", 0.4]], "build_speed": [["g3", 0.25]],
}
var data := {}                # data/weapons_and_armor.json
var economy := {}             # data/economy.json
var vessels: Array = []       # ships and stations (things with interiors)
var characters: Array = []
var fighters: Array = []
var pods: Array = []          # boarding pods and boarding shuttles in flight
var missiles: Array = []      # ship-to-ship missiles in flight
var vehicles: Array = []      # ground vehicles and mechs (campaign surfaces)
var player_team := 1
var possessed: Node = null    # the character the player is driving, or null
var commander: Node = null
var match_node: Node = null
var resources := {}
var time := 0.0
var game_over := false
var rng := RandomNumberGenerator.new()
var profiling := false         # timing counters (us_*) only when a test turns this on
var stats := {}               # counters for the automatic tests: what happened how often
var config := {"mode": "single", "team": 1, "start": "commander", "difficulty": 1}   # from the main menu
var settings := {}            # user://settings.cfg: sensitivity, fov, fullscreen, show_fps, vsync, name
var network: Node             # multiplayer (scripts/network.gd)
var research := {}            # team -> {tech id: true}
var researching := {}         # team -> [tech id, seconds left]
var net_ids := {}             # net id -> node (characters, fighters, pods), for multiplayer
var _next_net_id := 1
var _fx: Array = []           # [node, time_left]
var _mats := {}
var _box_mesh: BoxMesh
var _sphere: SphereMesh


var sfx: Node                  # sound effects (sfx.gd)
var dangers: Array = []        # live grenades and breaching rounds: friendly AI keeps clear (danger_for)


func _ready() -> void:
	rng.seed = 12345
	sfx = load("res://scripts/sfx.gd").new()
	add_child(sfx)
	load_settings()
	network = preload("res://scripts/network.gd").new()
	network.name = "Network"
	add_child(network)
	data = _json("res://data/weapons_and_armor.json")
	economy = _json("res://data/economy.json")
	_box_mesh = BoxMesh.new()
	_box_mesh.size = Vector3.ONE
	_sphere = SphereMesh.new()
	_sphere.radius = 0.5
	_sphere.height = 1.0
	_sphere.radial_segments = 12
	_sphere.rings = 6


## Quit the game: silence the sound first and give the audio thread a moment to drop what it
## was mixing (quitting mid-sound leaks the playbacks: "ObjectDB instances leaked at exit").
func quit(code: int = 0) -> void:
	if sfx:
		sfx.silence()
	get_tree().create_timer(0.15, true, false, true).timeout.connect(func(): get_tree().quit(code))


func stat(k: String, n: int = 1) -> void:
	if not profiling and k.begins_with("us_"):
		return
	stats[k] = stats.get(k, 0) + n


func reset() -> void:
	stats.clear()
	dangers.clear()
	vessels.clear()
	characters.clear()
	fighters.clear()
	pods.clear()
	missiles.clear()
	vehicles.clear()
	possessed = null
	game_over = false
	time = 0.0
	resources = {1: {"alloys": 3000.0, "circuitry": 1000.0, "cores": 40.0},
		2: {"alloys": 3000.0, "circuitry": 1000.0, "cores": 40.0}}
	research = {1: {}, 2: {}, 3: {}, 4: {}, 5: {}, 6: {}, 7: {}}
	if config.get("mode", "") != "campaign":
		standing = {}
		team_names = {}
		campaign = null
	researching = {1: [], 2: []}
	if config.get("mode", "") == "campaign" and campaign != null:
		research[1] = campaign.research          # the campaign keeps the player's research across reloads
		researching[1] = (campaign.researching as Array).duplicate()
	net_ids.clear()
	_next_net_id = 1
	_used_names.clear()
	player_team = int(config.get("team", 1))


## Give a node a network id (host side), so clients can find the same unit.
func register(n: Node, id: int = 0) -> int:
	if id == 0:
		id = _next_net_id
		_next_net_id += 1
	else:
		_next_net_id = max(_next_net_id, id + 1)
	net_ids[id] = n
	n.set_meta("net_id", id)
	return id


func is_client() -> bool:
	return network != null and network.active and not multiplayer.is_server()


# ------------------------------------------------------------------ research

func has_tech(team: int, id: String) -> bool:
	return research.get(team, {}).has(id)


func tech_ok(team: int, id: String) -> bool:
	var t: Dictionary = TECH[id]
	return not has_tech(team, id) and (not t.has("needs") or has_tech(team, t["needs"])) \
		and researching.get(team, []).is_empty()


func start_research(team: int, id: String) -> bool:
	if not tech_ok(team, id) or resources.get(team, {}).get("circuitry", 0.0) < TECH[id]["cost"]:
		return false
	resources[team]["circuitry"] -= TECH[id]["cost"]
	researching[team] = [id, float(TECH[id]["time"])]
	say("Research started: %s" % TECH[id]["name"], team)
	return true


func _research_tick(dt: float) -> void:
	for team in researching:
		var r: Array = researching[team]
		if r.is_empty():
			continue
		r[1] -= dt
		if r[1] <= 0.0:
			research[team][r[0]] = true
			say("Research complete: %s (%s)" % [TECH[r[0]]["name"], TECH[r[0]]["desc"]], team)
			researching[team] = []


## Multipliers from research, looked up where they apply.
func dmg_mult(team: int) -> float:
	return 1.0 + (0.1 if has_tech(team, "w1") else 0.0) + (0.15 if has_tech(team, "w3") else 0.0)


func spread_mult(team: int) -> float:
	return 0.65 if has_tech(team, "w2") else 1.0


func tech_bonus(team: int, fx: String) -> float:
	var t := 0.0
	for e in TECH_FX.get(fx, []):
		if has_tech(team, e[0]):
			t += float(e[1])
	return t


func dr_bonus(team: int) -> float:
	return (0.06 if has_tech(team, "a1") else 0.0) + (0.06 if has_tech(team, "a3") else 0.0)


func turret_mult(team: int) -> float:
	return 1.25 if has_tech(team, "f3") else 1.0


func soldiers_of(team: int) -> int:
	var n := 0
	for c in characters:
		if is_instance_valid(c) and c.team == team and c.state != "dead" and not c.is_crew():
			n += 1
	return n


# ------------------------------------------------------------------ settings

func load_settings() -> void:
	var cf := ConfigFile.new()
	settings = {"sens": 1.0, "fov": 85.0, "fullscreen": false, "show_fps": true, "vsync": true, "name": "Commander",
		"last_ip": "127.0.0.1"}
	if cf.load("user://settings.cfg") == OK:
		for k in cf.get_section_keys("game"):
			settings[k] = cf.get_value("game", k)


## Alt-tab / minimise in single player: the game waits (so it doesn't run on unseen and
## come back to a pile of catch-up work); it carries on when the window has focus again.
## Settings "alt_tab_pause" false keeps it running. A multiplayer host never stops.
var _focus_paused := false


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		# (not in tests and picture runs: they run in the background while you use other windows)
		if match_node and not (network and network.active) and settings.get("alt_tab_pause", true) \
				and not get_tree().paused and OS.get_cmdline_user_args().is_empty():
			get_tree().paused = true
			_focus_paused = true
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if _focus_paused:
			_focus_paused = false
			var pm = commander.get("pause_menu") if commander else null
			if not (pm and pm.visible):
				get_tree().paused = false


func save_settings() -> void:
	var cf := ConfigFile.new()
	for k in settings:
		cf.set_value("game", k, settings[k])
	cf.save("user://settings.cfg")
	apply_settings()


func apply_settings() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if settings.get("fullscreen", false)
		else DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if settings.get("vsync", true)
		else DisplayServer.VSYNC_DISABLED)


func _json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Missing " + path)
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func _process(dt: float) -> void:
	var _t0 := Time.get_ticks_usec()
	_fx_tick(minf(dt, 0.25))                     # (a hitch doesn't fire every clock-driven timer at once)
	stat("us_fx", Time.get_ticks_usec() - _t0)


func _fx_tick(dt: float) -> void:
	time += dt
	if match_node and not game_over:
		_research_tick(dt)
	for i in range(_fx.size() - 1, -1, -1):
		var e: Array = _fx[i]
		e[1] -= dt
		if e[1] <= 0.0 or not is_instance_valid(e[0]):
			if is_instance_valid(e[0]):
				e[0].queue_free()
			_fx.remove_at(i)
		elif e.size() > 2:                      # growing / fading explosion
			var n: Node3D = e[0]
			var t: float = 1.0 - e[1] / e[2]
			n.scale = Vector3.ONE * e[3] * (0.3 + t)


# ------------------------------------------------------------------ teams

## Every side in the game. 1-4 fight the skirmish; the campaign adds the Vanguard Navy (5)
## and the two civilian peoples: the Union Merchant Guild (6, Vanguard space) and the
## Concord Free Traders (7, Ascendancy space). In the campaign the player is team 1: their
## own company, built on Vanguard ships and kit (faction 1).
const TEAMS := {
	1: {"name": "Vanguard", "long": "Vanguard (F1)", "fac": 1, "color": Color(0.35, 0.75, 1.0)},
	2: {"name": "Ascendancy", "long": "Ascendancy (F2)", "fac": 2, "color": Color(1.0, 0.3, 0.25)},
	3: {"name": "Pirate", "long": "Pirates", "fac": 3, "color": Color(0.8, 0.8, 0.8)},
	4: {"name": "Infected", "long": "The infection", "fac": 4, "color": Color(0.8, 0.45, 1.0)},
	5: {"name": "Vanguard Navy", "long": "Vanguard Navy", "fac": 1, "color": Color(0.3, 0.45, 1.0)},
	6: {"name": "Union Guild", "long": "Union Merchant Guild", "fac": 1, "civ": true, "color": Color(0.45, 0.95, 0.6)},
	7: {"name": "Concord", "long": "Concord Free Traders", "fac": 2, "civ": true, "color": Color(1.0, 0.75, 0.3)},
}
## Between the computer-run sides (campaign): who shoots whom. Pirates and the infection fight everyone.
const AT_WAR := [[2, 5]]
var team_names := {}          # campaign: 1 -> the player's company name
var standing := {}            # campaign: team -> the player's standing with it (-100..100); empty in skirmish
var campaign = null           # campaign.gd while a campaign is running
var cut_height := 10000.0     # the commander's cutaway height (also the "cut_height" shader global)


# ---- ship names: the Vanguard name ships like a navy with long memories (UNV), the
# Ascendancy for doctrines and cold abstractions (ASC), pirates for whatever made them laugh.
const VG_NAMES := ["Autumn's Vigil", "Dawn Ascending", "In Iron Clad", "Forward Resolve", "Winter's Promise",
	"Pillar of Ember", "Heart of Thunder", "Spirit of Valor", "Steadfast Mercy", "Long Watch", "Faithful Lantern",
	"Breath of Dawn", "Shield of Marathon", "Cradle of Hope", "Vigilant Hearth", "Point of Return", "Tide of Morning",
	"Burden of Valor", "Light of Aurora", "Ember's Oath", "Unbroken Line", "Silent Bastion", "Grace Under Fire",
	"Second Sunrise", "Last Light", "Hymn of Iron", "Valiant Tide", "Song of Kepler", "Lantern of Reach",
	"Bright Endurance", "Promise Kept", "Stalwart Heart", "Requiem for Mars", "Courage Undimmed", "Hope Eternal"]
const ASC_A := ["Exalted", "Sovereign", "Ruinous", "Silent", "Ascendant", "Radiant", "Absolute", "Endless", "Unbroken",
	"Hollow", "Crimson", "Zero", "Infinite", "Severed", "Black", "Perfect", "Final"]
const ASC_B := ["Cipher", "Paragon", "Meridian", "Verdict", "Accord", "Dominion", "Will", "Edict", "Harbinger", "Requiem",
	"Vector", "Singularity", "Reckoning", "Nexus", "Apex", "Doctrine", "Logic", "Axiom", "Ascension", "Coalescence"]
const PIRATE_NAMES := ["Scrapjaw", "Black Gull", "Rotten Luck", "Gutter Queen", "Iron Mange", "Salvage Right", "Bad Debt",
	"Last Laugh", "Rust Widow", "Cheap Shot", "Knife Money", "No Refunds", "Grudge", "Bilge Rat"]
var _used_names := {}


func ship_name(fac: int, r: RandomNumberGenerator = null) -> String:
	if r == null:
		r = rng
	for tries in 40:
		var n := ""
		match fac:
			2:
				n = "ASC %s %s" % [ASC_A[r.randi() % ASC_A.size()], ASC_B[r.randi() % ASC_B.size()]]
			3:
				n = "%s" % PIRATE_NAMES[r.randi() % PIRATE_NAMES.size()]
			_:
				n = "UNV %s" % VG_NAMES[r.randi() % VG_NAMES.size()]
		if not _used_names.has(n):
			_used_names[n] = true
			return n
	return "%s %d" % ["UNV" if fac != 2 else "ASC", r.randi() % 900 + 100]


func set_cut(h: float) -> void:
	if h != cut_height:
		cut_height = h
		RenderingServer.global_shader_parameter_set("cut_height", h)


func team_color(team: int) -> Color:
	if team in [1, 2, 3]:
		return Color(0.35, 0.75, 1.0) if team == 1 else (Color(1.0, 0.3, 0.25) if team == 2 else Color(0.8, 0.8, 0.8))
	return TEAMS.get(team, TEAMS[3])["color"] if team != 4 else Color(0.8, 0.8, 0.8)


func team_name(team: int) -> String:
	if team_names.has(team):
		return team_names[team]
	return TEAMS.get(team, {"long": "Unknown"})["long"]


func team_short(team: int) -> String:
	if team_names.has(team):
		return String(team_names[team]).get_slice(" ", 0)
	return TEAMS.get(team, {"name": ""})["name"]


## The kit and hull designs a side uses: 1 Vanguard, 2 Ascendancy, 3 pirate, 4 infected.
func team_fac(team: int) -> int:
	return TEAMS.get(team, {"fac": 1})["fac"]


func is_civilian(team: int) -> bool:
	return TEAMS.get(team, {}).get("civ", false)


func enemies(a: int, b: int) -> bool:
	if a == b or a == 0 or b == 0:
		return false
	if standing.is_empty():
		return true                                  # skirmish: everyone else is the enemy
	if a in [3, 4] or b in [3, 4]:
		return true
	if a == 1 or b == 1:
		return standing.get(b if a == 1 else a, 0.0) < -25.0
	return [mini(a, b), maxi(a, b)] in AT_WAR


## Campaign: the player did something to side t (shot at it, finished a job for it...).
func change_standing(t: int, by: float, why: String = "") -> void:
	if standing.is_empty() or t in [0, 1, 3, 4]:
		return
	var was: float = standing.get(t, 0.0)
	var now: float = clampf(was + by, -100.0, 100.0)
	standing[t] = now
	if was >= -25.0 and now < -25.0:
		say("The %s now consider you HOSTILE%s" % [team_name(t), (": " + why) if why != "" else ""], 1)
	elif was < -25.0 and now >= -25.0:
		say("The %s no longer consider you hostile" % team_name(t), 1)
	# the Navy and the Ascendancy are at war: hurting one pleases the other a little
	if by < 0.0 and t in [2, 5]:
		var other: int = 5 if t == 2 else 2
		standing[other] = clampf(standing.get(other, 0.0) - by * 0.25, -100.0, 100.0)


func say(text: String, team: int = 0) -> void:
	print("[%6.1f] %s" % [time, text])
	if commander and commander.has_method("log_event"):
		commander.log_event(text, team)
	if network and network.active and multiplayer.is_server():
		network.broadcast_say(text, team)


# ------------------------------------------------------------------ combat data

func weapon_stats(faction: int, model: String) -> Dictionary:
	var ws: Dictionary = data.get("weapons", {}).get(str(faction), {})
	for cls in ws:
		if ws[cls]["model"] == model:
			var d: Dictionary = ws[cls].duplicate()
			d["class"] = cls
			return d
	return {}


func role_data(faction: int, role: String) -> Dictionary:
	return data.get("roles", {}).get(str(faction), {}).get(role, {})


# ------------------------------------------------------------------ physics helpers

func ray(from: Vector3, to: Vector3, exclude: Array = [], mask: int = LAYER_WORLD | LAYER_DOOR | LAYER_CHAR) -> Dictionary:
	var space := get_tree().root.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	q.exclude = exclude
	return space.intersect_ray(q)


# ------------------------------------------------------------------ effects

func _mat(c: Color, energy: float = 3.0) -> StandardMaterial3D:
	var key := "%s_%s" % [c.to_html(), energy]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = c
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = energy
		_mats[key] = m
	return _mats[key]


func tracer(from: Vector3, to: Vector3, c: Color, width: float = 0.04, life: float = 0.06) -> void:
	var len := from.distance_to(to)
	if len < 0.05:
		return
	var m := MeshInstance3D.new()
	m.mesh = _box_mesh
	m.material_override = _mat(c, 4.0)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().root.add_child(m)
	m.global_position = (from + to) * 0.5
	var up := Vector3.UP if abs((to - from).normalized().dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	m.look_at(to, up)
	m.scale = Vector3(width, width, len)
	_fx.append([m, life])


func flash(pos: Vector3, c: Color, energy: float = 4.0, rng_m: float = 4.0, life: float = 0.05) -> void:
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = energy
	l.omni_range = rng_m
	get_tree().root.add_child(l)
	l.global_position = pos
	_fx.append([l, life])


func explosion(pos: Vector3, size: float, c: Color = Color(1.0, 0.55, 0.15)) -> void:
	if sfx and size >= 2.5:
		sfx.play("big_boom" if size >= 10.0 else "boom", pos, -2.0 if size >= 10.0 else -8.0, size >= 6.0)
	if network and network.active and multiplayer.is_server():
		network.queue_fx("e", pos, Vector3(size, 0, 0), c)
	var m := MeshInstance3D.new()
	m.mesh = _sphere
	m.material_override = _mat(c, 6.0)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().root.add_child(m)
	m.global_position = pos
	_fx.append([m, 0.5, 0.5, size])
	flash(pos, c, 10.0, size * 3.0, 0.4)


## Damage every character within `radius` of `pos` (grenades, charges).
## The live grenade or breaching round (thrown by someone not hostile to `team_`) whose blast
## would reach world point `p` (plus `margin`), with nothing solid in between, or null.
func danger_for(team_: int, p: Vector3, margin: float = 0.0) -> Node:
	for d in dangers:
		if not is_instance_valid(d) or enemies(team_, int(d.team)):
			continue
		var dp: Vector3 = d.danger_point()
		if p.distance_to(dp) < float(d.danger_radius()) + margin \
				and ray(dp + Vector3.UP * 0.3, p + Vector3.UP * 1.0, [], LAYER_WORLD | LAYER_DOOR).is_empty():
			return d
	return null


func blast(pos: Vector3, radius: float, damage: float, attacker: Node) -> void:
	explosion(pos, radius * 0.8)
	for v in vessels:
		if is_instance_valid(v) and not v.destroyed:
			v.blast_doors(pos, radius, damage)
	for c in characters.duplicate():
		if not is_instance_valid(c) or c.state == "dead":
			continue
		var d: float = c.global_position.distance_to(pos)
		if d < radius:
			var hit := ray(pos + Vector3.UP * 0.3, c.global_position + Vector3.UP * 1.0, [], LAYER_WORLD | LAYER_DOOR)
			if hit.is_empty():
				c.take_damage(damage * (1.0 - d / radius * 0.6), attacker, pos)


## A background-baked ground navigation tile is ready (the ground may be gone by now).
func nav_tile_baked(map: RID, nm: NavigationMesh, ground_ref: WeakRef) -> void:
	var g = ground_ref.get_ref()
	if g == null or not is_instance_valid(g) or g.nav_map != map:
		return
	g.tile_baked(nm)
