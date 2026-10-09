extends "res://scripts/vessel.gd"
## A warship: flies, fights with its turrets, launches boarding pods and fighters,
## and is lost if its hull fails or its bridge is captured.

const POD := preload("res://scripts/pod.gd")
const FIGHTER := preload("res://scripts/fighter.gd")
const MISSILE := preload("res://scripts/missile.gd")
const SHUTTLE := preload("res://scripts/shuttle.gd")
const DROPPOD := preload("res://scripts/drop_pod.gd")
const DROP_RANGE := 2600.0
const MISSILE_LOAD := {"XL": 16, "LARGE": 12, "MEDIUM": 8, "SMALL_FRIGATE": 6, "SMALL_SUPPORT": 4, "SMALL_DROP_FRIGATE": 4}
const MISSILE_RANGE := 2600.0
const SHUTTLE_RANGE := 2600.0
const MUSTER_HUMAN := 30.0          # seconds people get to reach the pods / shuttle
const MUSTER_AI := 6.0              # an all-AI side just loads up
const BOARD_ROLES := ["squad_leader", "rifleman", "breacher", "medic", "rifleman", "heavy", "rifleman", "grenadier",
	"rifleman", "breacher", "rifleman", "medic"]
const STATS := {
	"XL": {"hull": 30000.0, "shields": 11000.0, "speed": 30.0, "turn": 0.12, "troops": 48},
	"LARGE": {"hull": 15000.0, "shields": 5500.0, "speed": 42.0, "turn": 0.18, "troops": 24},
	"MEDIUM": {"hull": 7200.0, "shields": 2800.0, "speed": 55.0, "turn": 0.25, "troops": 16},
	"SMALL_FRIGATE": {"hull": 2600.0, "shields": 1000.0, "speed": 80.0, "turn": 0.45, "troops": 0},
	"SMALL_SUPPORT": {"hull": 2000.0, "shields": 800.0, "speed": 75.0, "turn": 0.45, "troops": 0},
	"SMALL_DROP_FRIGATE": {"hull": 2400.0, "shields": 900.0, "speed": 78.0, "turn": 0.45, "troops": 12},
}
const BOLT_SPEED := 700.0
const POD_RANGE := 1500.0

# ---- guns. Fleet composition matters: a gun's penetration against a hull's armour scales its
# damage, so a swarm of light guns barely scratches a big ship, while big guns are slow to
# traverse and less accurate against small fast targets.
const TURRET_SPECS := {
	"ciws": {"r": 0.75, "len": 2.6, "barrels": 1, "dmg": 7.0, "cd": 0.5, "range": 800.0, "pen": 0.5, "acc": 1.0, "turn": 4.5, "pd": true},
	"light": {"r": 1.4, "len": 4.5, "barrels": 2, "dmg": 12.0, "cd": 1.8, "range": 1500.0, "pen": 1.0, "acc": 1.0, "turn": 2.2},
	"medium": {"r": 2.3, "len": 7.0, "barrels": 2, "dmg": 30.0, "cd": 2.4, "range": 1800.0, "pen": 2.0, "acc": 0.9, "turn": 1.4},
	"large": {"r": 3.4, "len": 10.0, "barrels": 3, "dmg": 85.0, "cd": 3.2, "range": 2100.0, "pen": 3.0, "acc": 0.75, "turn": 0.9},
	"xl": {"r": 5.0, "len": 15.0, "barrels": 3, "dmg": 230.0, "cd": 4.6, "range": 2500.0, "pen": 4.0, "acc": 0.65, "turn": 0.6},
}
const ARMOR := {"SMALL": 1.0, "MEDIUM": 2.0, "LARGE": 3.0, "XL": 4.0}
## The dropship's two belly-mounted 120 mm guns: indirect area fire at ground targets only
## (surface bases, troops and landed craft), never precise. Napalm rounds can be toggled on.
const ARTY := {"r": 1.8, "len": 7.0, "barrels": 1, "dmg": 160.0, "cd": 5.5, "range": 2600.0, "pen": 3.0, "acc": 1.0, "turn": 1.0, "arty": true}
var napalm := false
## [gun, mount (top / bottom / port / starboard), across (-1..1 of the half-beam), along (-0.5 bow .. 0.5 stern)]
const LAYOUTS := {
	"SMALL": [["light", "top", 0.0, -0.22], ["light", "top", 0.0, 0.12], ["light", "bottom", 0.0, -0.05],
		["ciws", "top", -0.75, 0.32], ["ciws", "top", 0.75, 0.32]],
	"MEDIUM": [["medium", "top", 0.0, -0.3], ["medium", "top", 0.0, -0.1], ["medium", "top", 0.0, 0.14],
		["ciws", "top", -0.75, 0.33], ["ciws", "top", 0.75, 0.33], ["ciws", "bottom", 0.0, -0.25]],
	"LARGE": [["large", "port", 0.0, -0.2], ["large", "port", 0.0, 0.12], ["large", "starboard", 0.0, -0.2], ["large", "starboard", 0.0, 0.12],
		["ciws", "top", -0.75, -0.32], ["ciws", "top", 0.75, -0.32], ["ciws", "top", -0.75, 0.32], ["ciws", "top", 0.75, 0.32]],
	"XL": [["large", "top", 0.0, -0.3], ["large", "top", 0.0, 0.22], ["large", "bottom", 0.0, -0.3], ["large", "bottom", 0.0, 0.22],
		["xl", "port", 0.0, -0.05], ["xl", "starboard", 0.0, -0.05],
		["ciws", "top", -0.75, -0.4], ["ciws", "top", 0.75, -0.4], ["ciws", "top", 0.0, 0.42],
		["ciws", "bottom", -0.75, -0.4], ["ciws", "bottom", 0.75, -0.4], ["ciws", "bottom", 0.0, 0.42]],
}
## Gunners each manned gun needs (the CIWS run themselves).
const GUNNERS := {"SMALL": 3, "MEDIUM": 3, "LARGE": 4, "XL": 6}
var _guns_built := false
var _gun_frames := 0

var hull := 1000.0
var max_hull := 1000.0
var shields := 0.0
var max_shields := 0.0
var speed := 50.0
var turn_rate := 0.3
var troops := 0                    # boarders in the troop berths, ready for pods and shuttles
var berth_cap := 24
var move_target := Vector3.INF
var attack_target: Node = null
var bolts: Array = []              # [mesh, from, to, t, total, target, dmg]
var pads: Array = []               # {name, local, parked (Node3D or null)}
var launch_wanted := 0
var repairs: Array = []            # {pos (local), amount}: hull damage waiting for an engineer
var selected := false
var since_hit := 99.0
var drifting := false              # the derelict: no engines, no shields
var helm: Node = null              # a player at the helm (commander.gd steers through helm_*)
var helm_throttle := 0.0
var helm_turn := 0.0
var manual_aim := Vector3.INF      # the helmsman's aim point: every turret that can bear fires at it
var manual_fire := false
var net_pos := Vector3.INF         # client side: where the host says the ship is
var net_yaw := 0.0
var missiles := 0                  # ship-to-ship missiles in the racks
var max_missiles := 0
var missile_cd := 0.0
var _restock_t := 0.0
var shuttle_cd := 0.0
var has_shuttle := false           # a boarding shuttle aboard (hangar pad, or docked at an airlock)
var shuttle_out: Node = null       # the shuttle while it's flying
var _parked_shuttle: Node3D
var is_supply_ship := false        # SMALL_SUPPORT: carries stores and boarders for the fleet
var drop_racks: Array = []         # SMALL_DROP_FRIGATE: racked ODST pods (Node3D, visible = loaded)
var pod_racks: Array = []          # boarding pods racked in the troop deck: {name, rack (visible = loaded), hatch}
var lock: Node = null              # the helm's target lock (a vessel)
var boarding := {}                 # a boarding op mustering: {target, kind, count, t, total}
var follow: Node = null            # "form on me": keep station on this ship
var follow_off := Vector3.ZERO     # where, in the leader's space
var _ai_missile_t := 0.0
var _sel: MeshInstance3D


func setup_ship(cls_: String, team_: int, faction_: int, name_: String) -> void:
	kind = "ship"
	setup_vessel(cls_, team_, faction_, name_)
	var st: Dictionary = STATS.get(cls, STATS["MEDIUM"])
	max_hull = st["hull"]
	hull = max_hull
	max_shields = st["shields"]
	shields = max_shields
	speed = st["speed"] * 1.15 * (1.0 + G.tech_bonus(team_, "ship_speed"))
	turn_rate = st["turn"] * (1.0 + G.tech_bonus(team_, "ship_turn"))
	max_hull *= 1.0 + G.tech_bonus(team_, "ship_hull")
	hull = max_hull
	troops = st["troops"]
	max_missiles = MISSILE_LOAD.get(cls, 4)
	missiles = max_missiles
	# troop berths: three bunks a stack in every berthing room the layout gave this ship
	berth_cap = max(4, marks_like("Bunk_Berthing_*").size() * 3)
	troops = berth_cap if troops == 0 and cls.begins_with("SMALL") else mini(troops, berth_cap)
	supply_cap = {"XL": 600.0, "LARGE": 420.0, "MEDIUM": 260.0, "SMALL_SUPPORT": 1600.0}.get(cls, 160.0)
	supplies = supply_cap * 0.8
	is_supply_ship = cls == "SMALL_SUPPORT"
	for sd in ["Port", "Starboard"]:
		for i in range(1, 20):
			var pr: Array = find_children("*_PodRack_%s_%d" % [sd, i], "MeshInstance3D", true, false)
			if pr.is_empty():
				break
			var hp: Array = find_children("*_PodTube_%s_%d_Hatch" % [sd, i], "MeshInstance3D", true, false)
			pod_racks.append({"name": "PodTube_%s_%d" % [sd, i], "rack": pr[0], "hatch": hp[0] if not hp.is_empty() else null})
	# two fewer boarding pods than the hull has tubes for (the last tube on each side is
	# sealed and its pod removed)
	if pod_racks.size() > 2:
		for side in ["Starboard", "Port"]:
			var last: Dictionary = {}
			for t in pod_racks:
				if String(t["name"]).begins_with("PodTube_%s_" % side):
					last = t
			if not last.is_empty() and pod_racks.size() > 2:
				last["rack"].visible = false
				if last["hatch"]:
					last["hatch"].visible = true
				pod_racks.erase(last)
	for i in range(1, 40):
		var rack: Array = find_children("*_DropPod_%d" % i, "MeshInstance3D", true, false)
		if rack.is_empty():
			break
		drop_racks.append(rack[0])
	if cls == "SMALL_DROP_FRIGATE":
		# the dropship: no boarding pods, sixteen ODST drop pods instead
		for t in pod_racks:
			(t["rack"] as Node3D).visible = false
		pod_racks.clear()
		var n0 := drop_racks.size()
		for i in maxi(0, 16 - n0):
			var extra := Node3D.new()                   # (stowed below the modelled racks)
			add_child(extra)
			drop_racks.append(extra)
		berth_cap = maxi(berth_cap, 32)                # 32 drop troops
		troops = maxi(troops, 32)
	if is_supply_ship:
		berth_cap = max(berth_cap, 24)
		troops = berth_cap
		_park_darter()
	park_shuttle()
	for k in marks:
		var s := String(k)
		if s.begins_with("Hangar_LandingPad_") and s.count("_") == 2:
			pads.append({"name": s, "local": local_of(marks[k]), "parked": null})
	var bridge: Node3D = mark("Bridge_CaptainChair")
	if bridge == null:
		bridge = mark("Bridge_PilotSeat")
	if bridge:
		add_capture_point("Bridge", local_of(bridge), 6.0)
	_make_selection_ring()


func _make_selection_ring() -> void:
	_sel = MeshInstance3D.new()
	var t := TorusMesh.new()
	var r := maxf(aabb.size.x, aabb.size.z) * 0.6
	t.inner_radius = r
	t.outer_radius = r + 2.0
	t.rings = 48
	_sel.mesh = t
	_sel.material_override = G._mat(G.team_color(team), 1.5)
	_sel.position = Vector3(aabb.get_center().x, aabb.position.y - 1.0, aabb.get_center().z)
	_sel.visible = false
	add_child(_sel)


func set_selected(on: bool) -> void:
	selected = on and not destroyed
	_sel.visible = selected
	_sel.material_override = G._mat(G.team_color(team), 1.5)


func park_fighter(idx: int, model: String = "FIGHTER") -> void:
	if idx >= pads.size():
		return
	var folder := "ships_P" if faction == 3 else "ships_F%d" % faction
	var path := "res://models/%s/ship_XS_%s.glb" % [folder, model]
	if not ResourceLoader.exists(path):
		path = "res://models/%s/ship_XS_FIGHTER.glb" % folder
	var f: Node3D = load(path).instantiate()
	add_child(f)
	f.position = pads[idx]["local"] + Vector3(0, 1.0, 0)
	for sb in f.find_children("*", "StaticBody3D", true, false):
		(sb as StaticBody3D).collision_layer = 0          # pilots walk up to it, not into it
	pads[idx]["parked"] = f
	pads[idx]["model"] = model


func parked_count() -> int:
	var n := 0
	for p in pads:
		if p["parked"] != null:
			n += 1
	return n


# ------------------------------------------------------------------ per frame

func _physics_process(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	vessel_process(dt)
	G.stat("us_vessel_common", Time.get_ticks_usec() - t0)
	_update_bolts(dt)
	if destroyed:
		return
	since_hit += dt
	if since_hit > 6.0 and shields < max_shields:
		shields = min(max_shields, shields + max_shields * 0.025 * dt * (1.25 if G.has_tech(team, "f1") else 1.0))
	if G.is_client():
		if net_pos != Vector3.INF:                   # (at our helm too: the host flies it from our input)
			global_position = global_position.lerp(net_pos, clampf(dt * 5.0, 0.0, 1.0))
			rotation.y = lerp_angle(rotation.y, net_yaw, clampf(dt * 5.0, 0.0, 1.0))
		_turrets(dt)
		return
	if not _esc_built and team != 4 and nav_ok():
		_make_escape_pods()
	_evac_process(dt)
	if destroyed:
		return
	if dying >= 0.0:
		pass                                         # dead in space, burning
	elif helm:
		_helm(dt)
	elif not drifting:
		_fly(dt)
	else:
		rotation.y += dt * 0.004                     # a slow dead tumble
	_keep_apart(dt)
	_turrets(dt)
	_repair_tick(dt)
	_ordnance_tick(dt)
	if not boarding.is_empty():
		_boarding_tick(dt)
	if not drop_order.is_empty():
		_drop_run(dt)
	elif G.match_node and G.match_node.get("on_surface"):
		# on a world: fly low over the ground, set down on it when stopped
		var want_y: float = G.match_node.surface_alt(self)
		global_position.y = move_toward(global_position.y, want_y, dt * 12.0)
	elif absf(global_position.y) > 0.5 and not has_meta("dock_at"):
		global_position.y = move_toward(global_position.y, 0.0, dt * 15.0)     # back down to the fleet's plane


func _fly(dt: float) -> void:
	var dest := move_target
	if follow and is_instance_valid(follow) and not follow.destroyed and follow.team == team and move_target == Vector3.INF:
		dest = follow.to_global(follow_off)
		if global_position.distance_to(dest) < 40.0:
			rotation.y = lerp_angle(rotation.y, follow.rotation.y, clampf(turn_rate * dt, 0.0, 1.0))
			global_position = global_position.lerp(dest, clampf(dt * 0.3, 0.0, 1.0))
			return
	elif follow and (not is_instance_valid(follow) or follow.destroyed or follow.team != team):
		follow = null
	if attack_target and is_instance_valid(attack_target) and not attack_target.destroyed:
		var tp: Vector3 = attack_target.global_position
		var d := global_position.distance_to(tp)
		if move_target == Vector3.INF:
			dest = tp if d > 900.0 else Vector3.INF
	if dest == Vector3.INF:
		return
	var to := dest - global_position
	to.y = 0.0
	if to.length() < 25.0:
		if dest == move_target:
			move_target = Vector3.INF
		return
	rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), clampf(turn_rate * dt, 0.0, 1.0))
	var facing := -global_basis.z
	var align: float = max(0.15, facing.dot(to.normalized()))
	global_position += facing * speed * align * dt * min(1.0, to.length() / 150.0 + 0.2) * field_drag()
	if G.match_node and G.match_node.get("campaign_mode"):
		global_position = G.match_node.planet_push(global_position)


## Asteroid fields: ships pick their way through at reduced speed.
func field_drag() -> float:
	if G.match_node == null or G.match_node.get("system") == null:
		return 1.0
	for f in G.match_node.system.get("fields", []):
		var d := Vector2(global_position.x - f["center"].x, global_position.z - f["center"].z).length()
		if d < f["radius"]:
			return 0.55
	return 1.0


# ------------------------------------------------------------------ weapons

func _helm(dt: float) -> void:
	if not is_instance_valid(helm) or helm.state != "alive":
		helm = null
		return
	rotation.y += -helm_turn * turn_rate * 1.6 * dt
	global_position += -global_basis.z * speed * helm_throttle * dt * field_drag()


static func size_class(c: String) -> String:
	if c.begins_with("SMALL"):
		return "SMALL"
	return c if c in ["MEDIUM", "LARGE", "XL"] else "SMALL"


## How hard the hull is to hurt (stations count as heavy).
func armor() -> float:
	return ARMOR.get(size_class(cls), 1.0)


## A hit from a gun with penetration `pen` against something with armour `arm`.
static func pen_mult(pen: float, arm: float) -> float:
	return clampf(pow(pen / maxf(0.1, arm), 1.2), 0.2, 1.0)


func manned_guns() -> int:
	return GUNNERS.get(size_class(cls), 3) + (2 if cls == "SMALL_DROP_FRIGATE" else 0)


# ------------------------------------------------------------------ building the guns

## The guns go on once the hull is in the physics world: each is dropped onto the hull
## (top, belly or flank) by a ray, so it sits on the plating whatever the ship's shape.
func _build_guns() -> void:
	_guns_built = true
	for t in turrets:                                # the model's own placeholder guns
		(t["node"] as Node3D).visible = false
	turrets.clear()
	var bb: AABB = aabb
	var lay: Array = LAYOUTS.get(size_class(cls), LAYOUTS["SMALL"])
	if cls == "SMALL_DROP_FRIGATE":
		lay = lay + [["arty", "bottom", -0.5, 0.15], ["arty", "bottom", 0.5, 0.15]]
	for spec in lay:
		var p := _mount_point(spec[1], float(spec[2]), float(spec[3]), bb)
		if p == Vector3.INF:
			continue
		turrets.append(_make_gun(spec[0], spec[1], p))


func _mount_point(mount: String, across: float, along: float, bb: AABB) -> Vector3:
	var cx: float = bb.get_center().x
	var z: float = bb.get_center().z + along * bb.size.z
	var x: float = cx + across * (bb.size.x * 0.5 - 2.5)
	var a := Vector3.ZERO
	var b := Vector3.ZERO
	match mount:
		"top":
			a = Vector3(x, bb.end.y + 20.0, z)
			b = Vector3(x, bb.position.y - 5.0, z)
		"bottom":
			a = Vector3(x, bb.position.y - 20.0, z)
			b = Vector3(x, bb.end.y + 5.0, z)
		"port":
			var y: float = bb.position.y + bb.size.y * 0.42
			a = Vector3(bb.position.x - 20.0, y, z)
			b = Vector3(cx, y, z)
		"starboard":
			var y2: float = bb.position.y + bb.size.y * 0.42
			a = Vector3(bb.end.x + 20.0, y2, z)
			b = Vector3(cx, y2, z)
	var space := get_world_3d().direct_space_state
	var ex: Array = []
	for k in 6:
		var q := PhysicsRayQueryParameters3D.create(to_global(a), to_global(b), G.LAYER_WORLD, ex)
		var h := space.intersect_ray(q)
		if h.is_empty():
			return Vector3.INF
		if is_ancestor_of(h.collider):
			return to_local(h.position)
		ex.append(h.rid)                             # someone else's hull in the way
	return Vector3.INF


func _gun_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = 0.6
	m.roughness = 0.45
	return m


func _make_gun(kind_: String, mount: String, p: Vector3) -> Dictionary:
	var sp: Dictionary = TURRET_SPECS[kind_] if kind_ != "arty" else ARTY
	var r: float = sp["r"]
	var body_c := Color(0.32, 0.34, 0.37) if faction != 2 else Color(0.36, 0.3, 0.32)
	if faction == 3:
		body_c = Color(0.36, 0.28, 0.22)
	var root := Node3D.new()
	root.name = "Gun_%s_%d" % [kind_, turrets.size()]
	add_child(root)
	root.position = p
	match mount:
		"bottom":
			root.rotation = Vector3(0, 0, PI)
		"port":
			root.rotation = Vector3(0, 0, PI * 0.5)
		"starboard":
			root.rotation = Vector3(0, 0, -PI * 0.5)
	var base := MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.top_radius = r * 0.9
	cy.bottom_radius = r * 1.05
	cy.height = r * 0.5
	base.mesh = cy
	base.material_override = _gun_mat(body_c.darkened(0.3))
	base.position.y = r * 0.25
	root.add_child(base)
	var yaw := Node3D.new()
	yaw.position.y = r * 0.5
	root.add_child(yaw)
	var house := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(r * 1.5, r * 0.8, r * 1.8) if kind_ != "ciws" else Vector3(r * 1.2, r * 1.2, r * 1.2)
	house.mesh = bm
	house.material_override = _gun_mat(body_c)
	house.position = Vector3(0, r * 0.4, r * 0.2)
	yaw.add_child(house)
	var bar := Node3D.new()
	bar.position = Vector3(0, r * 0.45, -r * 0.5)
	yaw.add_child(bar)
	var n: int = sp["barrels"]
	var bmat := _gun_mat(body_c.darkened(0.5))
	for i in n:
		var b := MeshInstance3D.new()
		var bc := CylinderMesh.new()
		bc.top_radius = r * (0.1 if kind_ != "ciws" else 0.16)
		bc.bottom_radius = r * (0.13 if kind_ != "ciws" else 0.2)
		bc.height = sp["len"]
		b.mesh = bc
		b.material_override = bmat
		b.rotation.x = -PI * 0.5
		b.position = Vector3((i - (n - 1) * 0.5) * r * 0.42, 0, -float(sp["len"]) * 0.5)
		bar.add_child(b)
	# where a gunner sits for it (the deck right under / inside the mount)
	var seat := Vector3.INF
	if kind_ != "ciws":
		match mount:
			"top":
				seat = snap_local(p - Vector3(0, 3.2, 0))
			"bottom":
				seat = snap_local(p + Vector3(0, 2.4, 0))
			_:
				seat = snap_local(Vector3(p.x * 0.55, p.y - 1.5, p.z))
	return {"node": yaw, "root": root, "bar": bar, "kind": kind_, "mount": mount, "spec": sp, "cool": randf() * 2.0,
		"kick": 0.0, "bar_rest": bar.position, "gunner": null, "seat": seat, "player": null, "aim": Vector3.INF, "fire": false,
		"rest_yaw": 0.0, "base_pos": yaw.position, "module": ""}


# ------------------------------------------------------------------ aiming and firing

## Swing a gun toward a world point within its arc. Returns true when on target.
## Guns can't shoot through their own hull: a dorsal gun covers everything above the
## deck line, a broadside battery its own flank, straight up and down, but never across.
func aim_gun(t: Dictionary, world_target: Vector3, dt: float) -> bool:
	var root: Node3D = t["root"]
	var yaw: Node3D = t["node"]
	var bar: Node3D = t["bar"]
	var lp: Vector3 = root.to_local(world_target) - yaw.position
	var flat := Vector2(lp.x, lp.z).length()
	var want_yaw := atan2(-lp.x, -lp.z)
	var elev := atan2(lp.y, flat)
	var spec: Dictionary = t["spec"]
	var rate: float = spec["turn"]
	yaw.rotation.y = rotate_toward(yaw.rotation.y, want_yaw, dt * rate)
	bar.rotation.x = move_toward(bar.rotation.x, clampf(elev, -0.15, 1.45), dt * rate)
	t["kick"] = move_toward(t["kick"], 0.0, dt * 3.0)
	bar.position = t["bar_rest"] + Vector3(0, 0, 1) * t["kick"] * float(spec["r"]) * 0.3
	return abs(angle_difference(yaw.rotation.y, want_yaw)) < 0.1 and abs(bar.rotation.x - elev) < 0.12 and in_arc(t, world_target)


func in_arc(t: Dictionary, world_target: Vector3) -> bool:
	if t["spec"].get("arty", false):
		return true                                  # high-angle fire: it lobs over anything
	var root: Node3D = t["root"]
	var lp: Vector3 = root.to_local(world_target)
	var elev := atan2(lp.y, Vector2(lp.x, lp.z).length())
	return elev > (-0.28 if t["mount"] in ["port", "starboard"] else -0.1)


func gun_muzzle(t: Dictionary) -> Vector3:
	var bar: Node3D = t["bar"]
	return bar.global_transform * Vector3(0, 0, -float(t["spec"]["len"]))


## Is someone at this gun? Point defense runs itself; the infection's hive guns need nobody.
func gun_manned(t: Dictionary) -> bool:
	if t["kind"] == "ciws" or team == 4:
		return true
	var p = t["player"]
	if p != null and is_instance_valid(p) and p.state == "alive":
		return true
	var g = t["gunner"]
	if g == null or not is_instance_valid(g) or g.state != "alive" or g.vessel != self or g.team != team:
		t["gunner"] = null
		return false
	return Vector2(g.position.x - t["seat"].x, g.position.z - t["seat"].z).length() < 1.6 and absf(g.position.y - t["seat"].y) < 1.6


## A gun with nobody on it, for a gunner looking for a post.
func free_gun_for(c: Node) -> int:
	var best := -1
	var bd := 1.0e9
	for i in turrets.size():
		var t: Dictionary = turrets[i]
		if t["kind"] == "ciws" or t["seat"] == Vector3.INF:
			continue
		if t["gunner"] == c:
			return i
		var g = t["gunner"]
		if g != null and is_instance_valid(g) and g.state == "alive" and g.vessel == self:
			continue
		var d: float = c.position.distance_to(t["seat"])
		if d < bd:
			bd = d
			best = i
	if best >= 0:
		turrets[best]["gunner"] = c
	return best


## The gun seat nearest p (local) within r, or -1.
func gun_seat_near(p: Vector3, r: float = 1.8) -> int:
	for i in turrets.size():
		var t: Dictionary = turrets[i]
		if t["seat"] != Vector3.INF and p.distance_to(t["seat"]) < r:
			return i
	return -1


func _turret_target(t: Dictionary) -> Node:
	var from: Vector3 = (t["root"] as Node3D).global_position
	var spec: Dictionary = t["spec"]
	var rng: float = spec["range"]
	var best: Node = null
	var bd := rng
	# small craft: the CIWS's whole job; light guns take them when nothing bigger is about
	if spec.get("pd", false) or t["kind"] == "light":
		bd = minf(rng, 900.0)
		for f in G.fighters + G.pods + G.missiles:
			if is_instance_valid(f) and G.enemies(team, f.team) and in_arc(t, f.global_position):
				var d: float = from.distance_to(f.global_position)
				if d < bd:
					bd = d
					best = f
		if best or spec.get("pd", false):
			return best
	for v in [lock, attack_target]:
		if v != null and is_instance_valid(v) and not v.destroyed and G.enemies(team, v.team):
			var c: Vector3 = v.to_global(v.aabb.get_center())
			if from.distance_to(c) < rng and in_arc(t, c):
				return v
	bd = rng
	for v in G.vessels:
		if v != self and is_instance_valid(v) and not v.destroyed and G.enemies(team, v.team):
			var c2: Vector3 = v.to_global(v.aabb.get_center())
			var d2: float = from.distance_to(c2)
			if d2 < bd and in_arc(t, c2):
				bd = d2
				best = v
	return best


func _turrets(dt: float) -> void:
	if dying >= 0.0:
		return
	if team == 4 and get_meta("role", "") != "hive":
		return                                       # the derelict's guns are long dead (hive ships' aren't)
	if not _guns_built:
		_gun_frames += 1
		if _gun_frames >= 2:
			_build_guns()
		return
	for t in turrets:
		t["cool"] -= dt
		var spec: Dictionary = t["spec"]
		var mult: float = G.turret_mult(team)
		# a player in the gunner's seat
		var pl = t["player"]
		if pl != null and is_instance_valid(pl) and pl.state == "alive" and t["aim"] != Vector3.INF:
			if aim_gun(t, t["aim"], dt) and t["fire"] and t["cool"] <= 0.0:
				t["cool"] = float(spec["cd"])
				fire_bolt(t, null, t["aim"], float(spec["dmg"]) * mult, t["kind"] == "ciws")
			continue
		if not gun_manned(t):
			continue                                 # nobody on this gun
		if spec.get("arty", false):
			_artillery(t, dt)
			continue
		var tgt := _turret_target(t)
		if tgt == null and manual_aim != Vector3.INF and t["kind"] != "ciws":
			if aim_gun(t, manual_aim, dt) and manual_fire and t["cool"] <= 0.0:
				t["cool"] = float(spec["cd"]) * randf_range(1.0, 1.2)
				fire_bolt(t, null, manual_aim, float(spec["dmg"]) * mult, false)
			continue
		if tgt == null:
			aim_gun(t, (t["root"] as Node3D).to_global(Vector3(0, 6.0, -40.0)), dt)
			continue
		var aim_p: Vector3 = tgt.global_position
		if tgt.get("aabb") != null:
			aim_p = tgt.to_global(tgt.aabb.get_center())
		var small: bool = tgt in G.fighters or tgt in G.pods or tgt in G.missiles
		if manual_aim != Vector3.INF and not small and t["kind"] != "ciws":
			aim_p = manual_aim                          # the helmsman picks the target
			if not manual_fire:
				aim_gun(t, aim_p, dt)
				continue
		if aim_gun(t, aim_p, dt) and t["cool"] <= 0.0:
			t["cool"] = float(spec["cd"]) * randf_range(1.0, 1.2)
			fire_bolt(t, tgt, aim_p, float(spec["dmg"]) * mult, small)


func fire_bolt(t: Dictionary, tgt: Node, aim_p: Vector3, dmg: float, small: bool) -> void:
	var spec: Dictionary = t.get("spec", TURRET_SPECS["medium"])
	var from: Vector3 = gun_muzzle(t) if t.has("root") else turret_muzzle(t)
	# big guns are less accurate, worse still against small, fast targets
	var spread: float = (3.0 if small else 6.0) / float(spec.get("acc", 1.0))
	if tgt != null and tgt.get("cls") != null and size_class(String(tgt.cls)) == "SMALL" and t.get("kind", "") in ["large", "xl"]:
		spread *= 2.2
	var to := aim_p + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * spread
	if G.match_node and not G.match_node.rocks.is_empty():
		var rh: Vector3 = G.match_node.SYSTEM.rock_hit(G.match_node.rocks, from, to)
		if rh != Vector3.INF:                       # an asteroid in the way: it takes the hit
			to = rh
			tgt = G.match_node                      # (marker: no damage on arrival)
	if tgt != null and tgt != G.match_node and tgt.get("aabb") != null and not tgt.aabb.grow(2.0).has_point(tgt.to_local(to)):
		tgt = null                                  # a miss: whatever it hits on the way (or nothing)
	var c := bolt_color()
	var m := MeshInstance3D.new()
	m.mesh = G._box_mesh
	m.material_override = G._mat(c, 6.0)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().root.add_child(m)
	m.global_position = from
	m.look_at(to, Vector3.UP)
	var thick: float = clampf(float(spec.get("r", 2.0)) * 0.18, 0.12, 0.9)
	m.scale = Vector3(thick, thick, 3.0 + float(spec.get("r", 2.0)) * 2.5)
	bolts.append([m, from, to, 0.0, max(0.05, from.distance_to(to) / BOLT_SPEED), tgt, dmg, float(spec.get("pen", 1.0))])
	G.flash(from, c, 8.0, 8.0 + float(spec.get("r", 2.0)) * 4.0, 0.07)
	if G.sfx:
		G.sfx.play("ciws" if t.get("kind", "") == "ciws" else "cannon", from, -6.0 if t.get("kind", "") in ["ciws", "light"] else 0.0, true)
	t["kick"] = 1.0                                  # barrels recoil (eased back in aim_gun)
	G.stat("ship_shots")


func bolt_color() -> Color:
	if team == 3:
		return Color(0.55, 1.0, 0.35)
	return Color(1.0, 0.72, 0.28) if faction == 1 else Color(1.0, 0.2, 0.45)


func _update_bolts(dt: float) -> void:
	for i in range(bolts.size() - 1, -1, -1):
		var b: Array = bolts[i]
		if not is_instance_valid(b[0]):
			bolts.remove_at(i)
			continue
		b[3] += dt
		var m: MeshInstance3D = b[0]
		var k: float = b[3] / b[4]
		if k >= 1.0:
			m.queue_free()
			bolts.remove_at(i)
			var tgt: Object = b[5] if is_instance_valid(b[5]) else null
			if tgt != null and tgt == G.match_node:
				G.flash(b[2], Color(1.0, 0.7, 0.4), 4.0, 10.0, 0.08)     # rock chips, nothing else
				continue
			if tgt == null and not G.is_client():
				tgt = _vessel_at(b[2])
			if tgt != null and not G.is_client():
				var small_t: bool = tgt in G.fighters or tgt in G.pods or tgt in G.missiles
				if small_t:
					if randf() < (0.3 if tgt in G.pods else (0.4 if tgt in G.missiles else 0.45)):
						tgt.take_hit(b[6], b[2])
				elif not tgt.get("destroyed"):
					var arm: float = tgt.armor() if tgt.has_method("armor") else 3.0
					var pen: float = b[7] if b.size() > 7 else 1.0
					tgt.take_hit(b[6] * pen_mult(pen, arm), b[2], self)
		else:
			m.global_position = (b[1] as Vector3).lerp(b[2], k)


func _vessel_at(p: Vector3) -> Node:
	for v in G.vessels:
		if v != self and not v.destroyed and v.aabb.grow(4.0).has_point(v.to_local(p)):
			return v
	return null


## Hit by ship weapons. Shields first, then hull; hull hits leave damage for engineers.
func take_hit(dmg: float, at: Vector3, _by: Node = null) -> void:
	if destroyed:
		return
	if G.is_client():
		G.flash(at, Color(0.4, 0.7, 1.0) if shields > 0.0 else Color(1.0, 0.6, 0.2), 4.0, 14.0, 0.1)
		return
	since_hit = 0.0
	if _by != null and is_instance_valid(_by) and _by.get("team") != null:
		set_meta("last_hit_team", _by.team)
	if shields > 0.0:
		shields = max(0.0, shields - dmg)
		G.flash(at, Color(0.4, 0.7, 1.0), 5.0, 16.0, 0.12)
		if shields <= 0.0:
			G.say("%s: shields down!" % display_name, team)
		return
	hull -= dmg
	G.explosion(at, 2.5)
	if randf() < 0.3 and repairs.size() < 12:
		var lp := snap_local(to_local(at) * Vector3(0.7, 0.0, 0.95))
		repairs.append({"pos": lp, "amount": dmg * 2.0})
	if hull <= 0.0:
		hull = 0.0
		_begin_dying()


# ------------------------------------------------------------------ abandon ship
## A ship doesn't just pop. Below 200 hull the crew are ordered to the escape pods; at zero
## the reactor goes critical and she has 30 seconds. The pods launch 7 seconds before the
## end with whoever made it to them, and anyone still aboard dies with her. A ship the
## infection is overrunning (more of them than crew left to fight) is abandoned the same way:
## the pods go after 25 seconds and, if nobody's left aboard, she's lost to the infection.

const EVAC_HULL := 200.0
const DEATH_S := 30.0
const PODS_AT := 7.0
var dying := -1.0
var evac := false
var evac_reason := ""
var evac_t := -1.0
var _pods_away := false
var _evac_tick := 0.0
var _boom_t := 0.0


func _begin_dying() -> void:
	if dying >= 0.0 or destroyed:
		return
	dying = DEATH_S
	move_target = Vector3.INF
	attack_target = null
	G.say("%s: HULL BREACHED, REACTOR CRITICAL. 30 seconds!" % display_name, team)
	if not evac:
		start_evac("the hull is failing")
	evac_t = -1.0                                   # (the reactor sets the clock now)


## Escape pod stations: one per deck on a small ship, two on a medium, three on a large,
## along the outer walls. Each is a hatch on the deck with a glowing ring.
var escape_spots: Array = []
var _esc_built := false


func _make_escape_pods() -> void:
	_esc_built = true
	var per: int = {"SMALL": 1, "MEDIUM": 2, "LARGE": 3, "XL": 3}.get(size_class(String(cls)), 1)
	var decks: int = maxi(1, int(round(aabb.end.y / 4.0)))
	for d in decks:
		var cands: Array = []
		for i in 40:
			var p := snap_local(Vector3(randf_range(aabb.position.x, aabb.end.x) * 0.9, d * 4.0 + 0.3, randf_range(aabb.position.z, aabb.end.z) * 0.85))
			if absf(p.y - d * 4.0) > 0.8:
				continue
			if not _inside_hull(p):
				continue                                   # a ledge on the outside of the hull
			cands.append(p)
		cands.sort_custom(func(a, b): return absf(a.x) > absf(b.x))
		var picked: Array = []
		for p in cands:
			if picked.size() >= per:
				break
			var ok := true
			for q in picked + escape_spots:
				if (q as Vector3).distance_to(p) < 8.0:
					ok = false
			if ok:
				picked.append(p)
		for p in picked:
			escape_spots.append(p)
			var hatch := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.8
			cm.bottom_radius = 0.8
			cm.height = 0.06
			hatch.mesh = cm
			hatch.material_override = G._mat(Color(1.0, 0.55, 0.15), 1.5)
			hatch.position = p + Vector3(0, 0.04, 0)
			add_child(hatch)
			var lab := Label3D.new()
			lab.text = "ESCAPE POD"
			lab.font_size = 28
			lab.pixel_size = 0.006
			lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lab.modulate = Color(1.0, 0.7, 0.3)
			lab.position = p + Vector3(0, 2.2, 0)
			lab.visibility_range_end = 90.0
			add_child(lab)


## Somewhere indoors: in a compartment, with a deck or roof overhead and no open space to
## either side within a few metres.
func _inside_hull(p: Vector3) -> bool:
	if not zones.is_empty() and zone_at(p).is_empty():
		return false
	var o := to_global(p + Vector3(0, 1.2, 0))
	if G.ray(o, to_global(p + Vector3(0, 4.6, 0)), [], G.LAYER_WORLD).is_empty():
		return false
	var walls := 0
	for dir in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		if not G.ray(o, to_global(p + Vector3(0, 1.2, 0) + dir * 40.0), [], G.LAYER_WORLD).is_empty():
			walls += 1
	return walls == 4


func _evac_spots() -> Array:
	if not escape_spots.is_empty():
		return escape_spots
	var out: Array = muster_points("pods")
	if out.is_empty():
		for m in marks_like("Hangar_LandingPad_*"):
			out.append(local_of(m))
	if out.is_empty() and nav_ok():
		for i in 4:
			out.append(random_local())
	return out


func start_evac(reason: String) -> void:
	if evac or destroyed:
		return
	evac = true
	evac_reason = reason
	_pods_away = false
	G.say("%s: ABANDON SHIP (%s). All hands to the escape pods!" % [display_name, reason], team)
	red_alert("Abandon ship")
	_order_evac()


func _order_evac() -> void:
	var spots := _evac_spots()
	if spots.is_empty():
		return
	for c in occupants:
		if not is_instance_valid(c) or c.state != "alive" or c.team != team or c == G.possessed:
			continue
		var best: Vector3 = spots[0]
		for sp in spots:
			if (sp as Vector3).distance_to(c.position) < best.distance_to(c.position):
				best = sp
		if c.position.distance_to(best) < 3.0:
			continue
		c.order = {"type": "move", "pos": snap_local(best + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5))), "vessel": self}
		c.run = true
		c.set_meta("evac", true)


func _evac_process(dt: float) -> void:
	if not evac and dying < 0.0:
		if hull <= EVAC_HULL and hull < max_hull * 0.5:
			start_evac("the hull is failing")
		elif team != 4 and infected_fraction() > 0.45:
			var crew := 0
			var inf := 0
			for c in occupants:
				if is_instance_valid(c) and c.state == "alive":
					if c.team == team:
						crew += 1
					elif c.team == 4:
						inf += 1
			if inf > 0 and (crew <= 2 or float(inf) >= float(crew) * 1.5):
				start_evac("the infection is overrunning the crew")
				evac_t = 25.0
	if not evac:
		return
	# repaired back out of danger: stand down
	if dying < 0.0 and evac_t < 0.0 and hull > EVAC_HULL * 2.0 and hull > max_hull * 0.3:
		evac = false
		_pods_away = false
		G.say("%s: hull holding, belay the abandon-ship order" % display_name, team)
		return
	_evac_tick -= dt
	if _evac_tick <= 0.0 and not _pods_away:
		_evac_tick = 2.0
		_order_evac()
	if dying >= 0.0:
		dying -= dt
		_boom_t -= dt
		if _boom_t <= 0.0:
			_boom_t = randf_range(0.4, 1.2) * clampf(dying / DEATH_S + 0.3, 0.3, 1.0)
			G.explosion(to_global(aabb.get_center() + Vector3(randf_range(-0.45, 0.45) * aabb.size.x, randf_range(-0.2, 0.4) * aabb.size.y,
				randf_range(-0.45, 0.45) * aabb.size.z)), randf_range(4.0, 9.0))
		if dying <= PODS_AT and not _pods_away:
			_launch_pods()
		if dying <= 0.0:
			destroy()
	elif evac_t >= 0.0:
		evac_t -= dt
		if evac_t <= 0.0 and not _pods_away:
			_launch_pods()
			var left := 0
			for c in occupants:
				if is_instance_valid(c) and c.state == "alive" and c.team == team:
					left += 1
			if left == 0:
				G.say("%s has been LOST to the infection" % display_name, team)
				move_target = Vector3.INF
				attack_target = null
				drifting = true
				set_meta("lost_to_infection", true)
				team = 4


## The escape pods: everyone of ours at a pod station gets away; the pods fly clear.
func _launch_pods() -> void:
	_pods_away = true
	var spots := _evac_spots()
	var saved: Array = []
	for c in occupants.duplicate():
		if not is_instance_valid(c) or c.state != "alive" or c.team != team:
			continue
		for sp in spots:
			if c.position.distance_to(sp) < 4.5:
				saved.append(c)
				break
	var n_pods: int = maxi(2, ceili(saved.size() / 4.0))
	var center: Vector3 = to_global(aabb.get_center())
	var mat := G._mat(Color(0.9, 0.55, 0.2), 0.0)
	var glow := G._mat(Color(1.0, 0.6, 0.25), 4.0)
	for i in n_pods:
		var sp2: Vector3 = to_global(spots[i % spots.size()]) if not spots.is_empty() else center
		var pod := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 1.0
		cm.height = 3.2
		pod.mesh = cm
		pod.material_override = mat
		var fl := MeshInstance3D.new()
		fl.mesh = G._box_mesh
		fl.material_override = glow
		fl.scale = Vector3(0.5, 0.5, 2.0)
		fl.position = Vector3(0, -2.0, 0)
		pod.add_child(fl)
		get_tree().root.add_child(pod)
		pod.global_position = sp2
		var away: Vector3 = (sp2 - center)
		away.y = 0.0
		away = (away.normalized() if away.length() > 0.1 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized())
		var to: Vector3 = sp2 + away * 320.0 + Vector3(randf_range(-60, 60), randf_range(20, 80), randf_range(-60, 60))
		pod.look_at_from_position(sp2, to, Vector3.UP)
		pod.rotate_object_local(Vector3.RIGHT, -PI * 0.5)
		var tw := pod.create_tween()
		tw.tween_property(pod, "global_position", to, 6.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_interval(20.0)
		tw.tween_callback(pod.queue_free)
	G.flash(center, Color(1.0, 0.7, 0.3), 10.0, 40.0, 0.3)
	# the survivors: soldiers join the nearest friendly ship's berths; everyone's out of this one
	var soldiers := 0
	for c in saved:
		if c == G.possessed and G.commander:
			G.commander.release()
		if c.role in ["rifleman", "squad_leader", "medic", "breacher", "heavy", "grenadier", "drop_trooper", "security"]:
			soldiers += 1
		if G.match_node:
			G.match_node.logistics._remove_person(c)
	if soldiers > 0:
		var best: Node = null
		var bd := 1.0e9
		for v in G.vessels:
			if v != self and is_instance_valid(v) and not v.destroyed and v.team == team and v.kind == "ship" and v.get("dying") is float and v.dying < 0.0:
				var d: float = v.global_position.distance_to(global_position)
				if d < bd:
					bd = d
					best = v
		if best:
			best.troops = mini(best.berth_cap, best.troops + soldiers)
	G.say("%s: escape pods away, %d aboard%s" % [display_name, saved.size(), "" if dying < 0.0 else " (anyone left has %d s)" % ceili(dying)], team)
	G.stat("escaped", saved.size())


func destroy() -> void:
	if destroyed:
		return
	destroyed = true
	hull = 0.0
	G.say("%s has been DESTROYED" % display_name, team)
	for k in 8:
		G.explosion(to_global(aabb.get_center() + Vector3(randf_range(-0.4, 0.4) * aabb.size.x, 2.0,
			randf_range(-0.4, 0.4) * aabb.size.z)), 14.0)
	for c in occupants.duplicate():
		if is_instance_valid(c) and c.state != "dead":
			c.die(null)
	set_selected(false)
	if G.match_node:
		G.match_node.on_vessel_destroyed(self)


# ------------------------------------------------------------------ engineers

func repair_point() -> Vector3:
	return repairs[0]["pos"] if not repairs.is_empty() else Vector3.INF


func _repair_tick(dt: float) -> void:
	if repairs.is_empty():
		# out of the fight with a damaged hull: the engineers go round patching it
		if hull < max_hull - 1.0 and since_hit > 4.0 and nav_ok():
			repairs.append({"pos": random_local(), "amount": minf(max_hull - hull, 600.0)})
		return
	var job: Dictionary = repairs[0]
	for c in occupants:
		if c.repairing and c.state == "alive" and c.team == team and c.position.distance_to(job["pos"]) < 2.0 and supplies > 0.0:
			var amt: float = min(job["amount"], 60.0 * dt)
			supplies = max(0.0, supplies - amt * 0.03)          # spare parts
			job["amount"] -= amt
			hull = min(max_hull, hull + amt)
	if job["amount"] <= 0.0:
		room_repaired(repairs.pop_front())
		G.stat("repairs_done")


# ------------------------------------------------------------------ capture

func on_captured(cp: Dictionary, by: int) -> void:
	var old := team
	team = by
	attack_target = null
	move_target = Vector3.INF
	for p in capture_points:
		p["owner"] = by
	G.say("%s's bridge was CAPTURED by %s!" % [display_name, G.team_name(by)], by)
	set_selected(false)
	if G.match_node:
		G.match_node.on_ship_captured(self, old, by)


# ------------------------------------------------------------------ boarding pods and fighters

func can_board(v: Node) -> bool:
	return pods_racked() > 0 and troops >= 4 and is_instance_valid(v) and not v.destroyed and v != self \
		and global_position.distance_to(v.global_position) < POD_RANGE


## Fire boarding pods (8 aboard each) from the tubes facing the target, right now.
## riders: people who climbed in at the pod bay (players, their squads); troops fill the rest.
func launch_pods(v: Node, count: int = 2, riders: Array = []) -> int:
	if not (can_board(v) or (not riders.is_empty() and _in_range(v, POD_RANGE))):
		return 0
	# pods drop out of the troop deck's belly hatches: racked pods only, side facing the target first
	var side := "Port" if to_local(v.global_position).x < 0.0 else "Starboard"
	var tubes: Array = pod_racks.filter(func(r): return r["rack"].visible)
	tubes.sort_custom(func(a, b): return (1 if String(a["name"]).contains(side) else 0) > (1 if String(b["name"]).contains(side) else 0))
	if tubes.is_empty() and riders.is_empty():
		return 0
	var entries: Array = v.boarding_entries(global_position)
	if entries.is_empty():
		return 0
	var queue := riders.duplicate()
	count = maxi(count, ceili(queue.size() / 8.0))
	var n := 0
	for i in count:
		var aboard: Array = queue.slice(0, 8)
		queue = queue.slice(8)
		if troops < 4 and aboard.is_empty():
			break
		if i >= tubes.size():
			break                                         # out of racked pods
		var size_: int = mini(8 - aboard.size(), troops)
		troops -= size_
		var tube: Dictionary = tubes[i]
		tube["rack"].visible = false
		var from: Vector3 = tube["rack"].global_position
		var e: Array = entries[i % entries.size()]
		var pod: Node3D = POD.new()
		get_tree().root.add_child(pod)
		var roles: Array = BOARD_ROLES.slice(0, size_)
		if aboard.size() > 0 and size_ > 0:
			roles = BOARD_ROLES.slice(1, 1 + size_)          # a player leads: no extra squad leader
		pod.setup(from, team, faction, v, e[0], e[1], e[2], e[3], roles)
		pod.launch_dir = -global_basis.y                    # out through the belly first
		pod.vel = -global_basis.y * 25.0
		pod._face(pod.vel)
		_open_hatch(tube)
		pod.riders = aboard
		for r in aboard:
			r.embark(pod)
		n += 1
	if n > 0:
		G.say("%s launched %d boarding pod%s at %s" % [display_name, n, "s" if n > 1 else "", v.display_name], team)
		G.stat("pods_launched", n)
		v.red_alert("Boarding pods inbound")
	return n


## A pod of six aimed at the breach point nearest a player who called for help; they join that player's squad.
func reinforcement_pod(v: Node, near_world: Vector3, sq) -> bool:
	var entries: Array = v.boarding_entries(near_world)
	if entries.is_empty() or troops < 4:
		return false
	var size_: int = mini(6, troops)
	troops -= size_
	var e: Array = entries[0]
	var pod: Node3D = POD.new()
	get_tree().root.add_child(pod)
	var from: Vector3 = to_global(aabb.get_center()) + Vector3.UP * 8.0
	pod.setup(from, team, faction, v, e[0], e[1], e[2], e[3], BOARD_ROLES.slice(1, 1 + size_))
	pod.join = sq
	G.stat("pods_launched")
	return true


func _in_range(v: Node, r: float) -> bool:
	return is_instance_valid(v) and not v.destroyed and v != self and global_position.distance_to(v.global_position) < r


# ------------------------------------------------------------------ boarding shuttle

func can_shuttle(v: Node) -> bool:
	return has_shuttle and shuttle_out == null and shuttle_cd <= 0.0 and troops >= 4 and _in_range(v, SHUTTLE_RANGE)


## Where the boarding shuttle sits (vessel space): the hangar's shuttle pad, or on SMALL
## ships docked against the first airlock's collar. {local, yaw, docked}
func shuttle_spot() -> Dictionary:
	var m: Node3D = mark("Hangar_ShuttlePad")
	if m:
		return {"local": local_of(m), "yaw": 0.0, "docked": false}
	var dock: Node3D = mark("Airlock_1_DropshipDock")
	if dock:
		var lp := local_of(dock)
		var side := 1.0 if lp.x >= 0.0 else -1.0
		# nose pointing away from the hull, the rear ramp against the collar
		return {"local": lp + Vector3(side * 7.6, -0.6, 0), "yaw": side * PI / 2, "docked": true}
	return {}


## The parked shuttle model (visual only, no collision), shown while the shuttle is home.
func park_shuttle() -> void:
	var sp := shuttle_spot()
	if sp.is_empty():
		has_shuttle = false
		return
	has_shuttle = true
	if _parked_shuttle == null:
		var folder := "ships_P" if faction == 3 else ("ships_F%d" % faction if faction in [1, 2] else "ships_F1")
		_parked_shuttle = load("res://models/%s/ship_XS_DROPSHIP.glb" % folder).instantiate()
		for sb in _parked_shuttle.find_children("*", "StaticBody3D", true, false):
			(sb as StaticBody3D).collision_layer = 0
		add_child(_parked_shuttle)
	_parked_shuttle.position = sp["local"] + Vector3(0, 1.0 if not sp["docked"] else 0.0, 0)
	_parked_shuttle.rotation = Vector3(0, sp["yaw"], 0)
	_parked_shuttle.visible = true


## The supply ship's Darter sits on its cargo-bay pad while it's home.
var _parked_darter: Node3D


func darter_away(away: bool) -> void:
	if _parked_darter:
		_parked_darter.visible = not away


func _park_darter() -> void:
	var folder := "ships_F%d" % faction if faction in [1, 2] else "ships_F1"
	_parked_darter = load("res://models/%s/ship_XS_DARTER.glb" % folder).instantiate()
	for sb in _parked_darter.find_children("*", "StaticBody3D", true, false):
		(sb as StaticBody3D).collision_layer = 0
	add_child(_parked_darter)
	_parked_darter.position = arrival_point() + Vector3(0, 0.4, 0)


## The shuttle came home: back on its pad.
func shuttle_home() -> void:
	shuttle_out = null
	park_shuttle()


## The shuttle was shot down: no boarding shuttle until logistics brings a new one.
func shuttle_lost() -> void:
	shuttle_out = null
	has_shuttle = false
	if _parked_shuttle:
		_parked_shuttle.visible = false
	G.say("%s has lost its boarding shuttle" % display_name, team)


func shuttle_pad() -> Dictionary:
	var sp := shuttle_spot()
	return {"local": sp.get("local", Vector3.ZERO)} if not sp.is_empty() else {}


## The boarding shuttle lifts off its pad (or undocks) with up to 12 aboard.
func launch_shuttle(v: Node, riders: Array = []) -> Node:
	if not has_shuttle or shuttle_out != null or not _in_range(v, SHUTTLE_RANGE) or (troops < 4 and riders.is_empty()):
		return null
	var sp := shuttle_spot()
	var aboard: Array = riders.slice(0, 12)
	var size_: int = mini(12 - aboard.size(), troops)
	troops -= size_
	var roles: Array = BOARD_ROLES.slice(1 if not aboard.is_empty() else 0, (1 if not aboard.is_empty() else 0) + size_)
	var sh: Node3D = SHUTTLE.new()
	get_tree().root.add_child(sh)
	var start := Transform3D(global_basis * Basis(Vector3.UP, sp["yaw"]), to_global(sp["local"] + Vector3(0, 1.0, 0)))
	sh.setup(self, start, team, faction, v, roles, aboard)
	if _parked_shuttle:
		_parked_shuttle.visible = false
	shuttle_out = sh
	for r in aboard:
		r.embark(sh)
	shuttle_cd = 45.0 * (1.0 - G.tech_bonus(team, "shuttle_cd"))
	G.say("%s launched a boarding shuttle at %s" % [display_name, v.display_name], team)
	v.red_alert("Boarding shuttle inbound")
	return sh


# ------------------------------------------------------------------ ODST drop pods (drop frigate)

## A surface installation (a base on a moon or an asteroid) can take drop pods; a station can't.
func is_surface(v: Node) -> bool:
	return v != null and ((v.kind == "station" and String(v.cls).begins_with("GROUND_")) or v.kind == "outpost")


func drop_pods_loaded() -> int:
	return drop_racks.filter(func(r): return r.visible).size()


func can_drop(v: Node) -> bool:
	return drop_pods_loaded() > 0 and troops > 0 and is_surface(v) and G.enemies(team, v.team)


const DROP_ALT := 170.0            # hover this high over the drop spot

var drop_order := {}               # {target, spot (world), n}: fly over the spot, then drop


## Order a drop: the frigate flies until it's right over `spot` (a point on or by a surface
## installation), climbs to drop height and only then fires the pods, straight down.
func order_drop(v: Node, spot: Vector3 = Vector3.INF, n: int = 6) -> bool:
	if not is_surface(v):
		if v != null and v.kind == "station":
			G.say("%s: drop pods need a surface below: designate a ground base, not a station" % display_name, team)
		return false
	if not can_drop(v):
		return false
	if spot == Vector3.INF:
		spot = v.to_global(v.aabb.get_center())
	drop_order = {"target": v, "spot": spot, "n": n}
	attack_target = null
	follow = null
	G.say("%s: moving over the drop zone at %s" % [display_name, v.display_name], team)
	return true


## On a world: fly over a point on the ground and drop pods straight down onto it.
func order_ground_drop(spot: Vector3, n: int = 8) -> bool:
	if drop_racks.is_empty() or drop_pods_loaded() == 0 or troops <= 0:
		return false
	drop_order = {"target": null, "spot": spot, "n": n, "ground": true}
	attack_target = null
	follow = null
	G.say("%s: moving over the drop zone" % display_name, team)
	return true


func _drop_run(dt: float) -> void:
	var v: Node = drop_order["target"]
	var on_ground: bool = drop_order.get("ground", false)
	if (not on_ground and (not is_instance_valid(v) or v.destroyed or not G.enemies(team, v.team))) or drop_pods_loaded() == 0 or troops <= 0:
		drop_order = {}
		return
	var spot: Vector3 = drop_order["spot"]
	var flat := Vector2(global_position.x - spot.x, global_position.z - spot.z).length()
	if flat > 40.0:
		move_target = Vector3(spot.x, 0, spot.z)
	else:
		move_target = Vector3.INF
	var want_y: float = spot.y + DROP_ALT if flat < 400.0 else 0.0
	global_position.y = move_toward(global_position.y, want_y, dt * 25.0)
	if flat < 60.0 and absf(global_position.y - want_y) < 8.0:
		if on_ground or (v != null and v.kind == "outpost"):
			_ground_drop(spot, int(drop_order["n"]))
		else:
			launch_drop_pods(v, drop_order["n"], spot)
		drop_order = {}


## Fire up to n drop pods straight down at the surface below. Only from over the spot.
func launch_drop_pods(v: Node, n: int = 6, spot: Vector3 = Vector3.INF) -> int:
	if not is_surface(v):
		if v != null and v.kind == "station":
			G.say("%s: drop pods need a surface below: target a ground base, not a station" % display_name, team)
		return 0
	if not can_drop(v):
		return 0
	if spot == Vector3.INF:
		spot = v.to_global(v.aabb.get_center())
	if Vector2(global_position.x - spot.x, global_position.z - spot.z).length() > 120.0 or global_position.y < spot.y + 40.0:
		return 0                                      # not over the drop zone: pods only go straight down
	var entries: Array = v.boarding_entries(spot)
	if entries.is_empty():
		return 0
	var fired := 0
	var roles := ["squad_leader", "drop_trooper", "drop_trooper", "medic", "drop_trooper", "breacher", "drop_trooper",
		"heavy", "drop_trooper", "grenadier", "drop_trooper", "drop_trooper"]
	for rack in drop_racks:
		if fired >= n or troops <= 0:
			break
		if not rack.visible:
			continue
		rack.visible = false
		troops -= 1
		var p: Node3D = DROPPOD.new()
		get_tree().root.add_child(p)
		var from := Transform3D(Basis(), (rack as Node3D).global_position - global_basis.y * 3.0)
		p.setup(from, team, faction, v, entries[0], roles[fired % roles.size()], fired, spot)
		fired += 1
	if fired > 0:
		G.say("%s: %d drop pods away over %s" % [display_name, fired, v.display_name], team)
		G.stat("odst_launched", fired)
		v.red_alert("Drop pods inbound")
	return fired


## ODST onto open ground: every loaded rack fires its pod straight down from under the
## hull. Each burns in, slams into the ground below and its trooper climbs out; the stick
## forms up as a squad where they landed.
func _ground_drop(spot: Vector3, n: int) -> int:
	var m: Node = G.match_node
	if m == null or m.ground == null:
		return 0
	var gnd: Node3D = m.ground
	var roles := ["squad_leader", "drop_trooper", "drop_trooper", "medic", "drop_trooper", "breacher", "drop_trooper",
		"heavy", "drop_trooper", "grenadier", "drop_trooper", "drop_trooper"]
	var sq: RefCounted = m.new_squad(team, gnd)
	var sid := randi() % 100000
	var fired := 0
	var pm := G._mat(Color(0.2, 0.21, 0.22))
	var glow := G._mat(Color(1.0, 0.55, 0.2), 4.0)
	for rack in drop_racks:
		if fired >= n or troops <= 0:
			break
		if not rack.visible:
			continue
		rack.visible = false
		troops -= 1
		var from: Vector3 = (rack as Node3D).global_position - global_basis.y * 3.0
		var land := Vector3(from.x, 0, from.z) + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4))
		land.y = m.ground_y(land.x, land.z)
		var pod := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.9
		cm.height = 3.4
		pod.mesh = cm
		pod.material_override = pm
		var flame := MeshInstance3D.new()
		flame.mesh = G._box_mesh
		flame.material_override = glow
		flame.scale = Vector3(0.6, 3.0, 0.6)
		flame.position = Vector3(0, 3.0, 0)
		pod.add_child(flame)
		get_tree().root.add_child(pod)
		pod.global_position = from
		var role: String = roles[fired % roles.size()]
		var fall: float = clampf((from.y - land.y) / 90.0, 1.2, 3.5)
		var tw := pod.create_tween()
		tw.tween_interval(fired * 0.18)
		tw.tween_property(pod, "global_position", land + Vector3.UP * 1.2, fall).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.tween_callback(func():
			if not is_instance_valid(pod):
				return
			flame.queue_free()
			pod.rotation.z = randf_range(-0.25, 0.25)
			G.explosion(land, 4.0, Color(1.0, 0.6, 0.3))
			if G.sfx:
				G.sfx.play("cannon", land, -2.0)
			if is_instance_valid(gnd):
				var c: Node = m.spawn_character(gnd, gnd.snap_local(gnd.to_local(land) + Vector3(1.6, 0, 0)), team, faction, role)
				c.squad_id = sid
				if sq:
					sq.add(c)
			pod.get_tree().create_timer(60.0).timeout.connect(func():
				if is_instance_valid(pod):
					pod.queue_free()))
		fired += 1
	if fired > 0:
		G.say("%s: %d drop pods away" % [display_name, fired], team)
		G.stat("odst_launched", fired)
	return fired


## Logistics reloads the racks (a pod costs supplies): drop pods and boarding pods.
func reload_drop_pods(budget: float) -> float:
	var spent := 0.0
	for rack in drop_racks:
		if not rack.visible and budget - spent >= 20.0:
			rack.visible = true
			spent += 20.0
	for t in pod_racks:
		if not t["rack"].visible and budget - spent >= 30.0:
			t["rack"].visible = true
			if t["hatch"]:
				t["hatch"].visible = true
			spent += 30.0
	return spent


func pods_racked() -> int:
	return pod_racks.filter(func(t): return t["rack"].visible).size()


## The belly hatch under a cradle swings open for the drop (hidden: the hole is open).
func _open_hatch(tube: Dictionary) -> void:
	if tube["hatch"]:
		tube["hatch"].visible = false
		get_tree().create_timer(4.0).timeout.connect(func():
			if is_instance_valid(tube["hatch"]):
				tube["hatch"].visible = true)


# ------------------------------------------------------------------ boarding operations (muster countdown)

## Order a boarding op: the bay klaxon sounds and anyone who wants to go has a short
## while to get to the pod bay (pods) or the hangar (shuttle) before launch.
func start_boarding(v: Node, kind_: String = "pods", count: int = 2) -> bool:
	if not boarding.is_empty() or destroyed:
		return false
	if kind_ == "shuttle" and not can_shuttle(v):
		return false
	if kind_ == "pods" and not can_board(v):
		return false
	var humans: bool = G.match_node != null and G.match_node.humans_on(team)
	var t := MUSTER_HUMAN if humans else MUSTER_AI
	boarding = {"target": v, "kind": kind_, "count": count, "t": t, "total": t}
	if humans:
		G.say("%s: BOARDING PARTY to the %s! Launch in %d s" % [display_name, "pod bays" if kind_ == "pods" else "hangar",
			int(t)], team)
	return true


func cancel_boarding() -> void:
	for c in occupants:
		if c.mustered == self:
			c.mustered = null
	boarding = {}


## Where riders gather (local): the pod bays, or the shuttle's pad in the hangar.
func muster_points(kind_: String = "") -> Array:
	if kind_ == "":
		kind_ = boarding.get("kind", "pods")
	var out: Array = []
	if kind_ == "shuttle":
		var p := shuttle_pad()
		if not p.is_empty():
			out.append(snap_local(p["local"] + Vector3(4.0, 0, 0)))
		return out
	for m in marks_like("PodBay_*_Muster"):
		out.append(local_of(m))
	if out.is_empty():
		for m in marks_like("PodTube_*"):
			if not String(m.name).ends_with("Hatch") and not String(m.name).ends_with("Muzzle"):
				out.append(snap_local(local_of(m)))
				break
	return out


func near_muster(c: Node, r: float = 5.0) -> bool:
	for p in muster_points():
		var d: Vector3 = c.position - p
		if Vector2(d.x, d.z).length() < r and absf(d.y) < 2.0:
			return true
	return false


## A player presses E at the bay: they're going.
func join_boarding(c: Node) -> bool:
	if boarding.is_empty() or c.team != team or c.vessel != self or not near_muster(c):
		return false
	c.mustered = self
	return true


func _boarding_tick(dt: float) -> void:
	var v: Node = boarding["target"]
	if not is_instance_valid(v) or v.destroyed or not G.enemies(team, v.team):
		cancel_boarding()
		return
	boarding["t"] -= dt
	if boarding["t"] > 0.0:
		return
	# launch: everyone who joined, plus players and their squadmates standing at the bay
	var riders: Array = []
	for c in occupants:
		if not is_instance_valid(c) or c.state != "alive" or c.team != team or c.piloting:
			continue
		var player: bool = c == G.possessed or c.owner_peer != 0
		if c.mustered == self or (player and near_muster(c)):
			riders.append(c)
	for c in riders.duplicate():                          # a player's squad goes with them
		if c.squad and c.squad.leader == c:
			for m in c.squad.alive():
				if not riders.has(m) and near_muster(m, 9.0):
					riders.append(m)
	var kind_: String = boarding["kind"]
	var count: int = boarding["count"]
	cancel_boarding()
	if kind_ == "shuttle":
		launch_shuttle(v, riders)
	else:
		launch_pods(v, count, riders)


# ------------------------------------------------------------------ missiles

## A missile salvo at a vessel. Returns how many flew.
func fire_missiles(v: Node, n: int = 4) -> int:
	if missiles <= 0 or missile_cd > 0.0 or not _in_range(v, MISSILE_RANGE) or not G.enemies(team, v.team):
		return 0
	n = mini(n, missiles)
	var to_t: Vector3 = (v.global_position - global_position).normalized()
	for i in n:
		var m: Node3D = MISSILE.new()
		get_tree().root.add_child(m)
		var along: float = (float(i) / maxf(1.0, n - 1.0) - 0.5) * aabb.size.z * 0.6
		var from: Vector3 = to_global(Vector3(aabb.get_center().x, aabb.end.y + 1.5, aabb.get_center().z + along))
		m.launch(from, (Vector3.UP * 0.8 + to_t).normalized(), v, team, faction)
		m.speed = 60.0 + i * 6.0
	missiles -= n
	missile_cd = 5.0
	G.say("%s: missiles away (%d) at %s" % [display_name, n, v.display_name], team)
	return n


func _ordnance_tick(dt: float) -> void:
	missile_cd = max(0.0, missile_cd - dt)
	shuttle_cd = max(0.0, shuttle_cd - dt)
	if missiles < max_missiles:
		_restock_t += dt
		if _restock_t >= 25.0:
			_restock_t = 0.0
			missiles += 1
	if lock and (not is_instance_valid(lock) or lock.destroyed):
		lock = null
	# ships nobody's flying use their missiles on what they're told to attack
	if helm == null and team != 4:
		_ai_missile_t -= dt
		if _ai_missile_t <= 0.0:
			_ai_missile_t = randf_range(18.0, 30.0)
			var tgt: Node = attack_target if attack_target else lock
			if tgt and is_instance_valid(tgt) and tgt.get("shields") != null:
				fire_missiles(tgt, 2 if tgt.kind == "ship" and tgt.cls.begins_with("SMALL") else 4)


## [approach marker, impact marker, interior marker, panel name] for each breach zone, nearest first.
func boarding_entries(from: Vector3) -> Array:
	var out: Array = []
	for i in range(1, 40):
		var tgt: Node3D = mark("BreachZone_%d_PodTarget" % i)
		if tgt == null:
			break
		var app: Node3D = mark("BreachZone_%d_PodApproach" % i)
		var ins: Node3D = mark("BreachZone_%d_Interior" % i)
		if app and ins:
			out.append([app, tgt, ins, "*_BreachPanel_%d" % i])
	# airlocks (SMALL ships have no breach zones): pods and shuttles cut in through the outer door
	for i in range(1, 5):
		var dock: Node3D = mark("Airlock_%d_DropshipDock" % i)
		if dock == null:
			break
		var app2: Node3D = mark("Airlock_%d_EVAEntry" % i)
		var ins2: Node3D = mark("Airlock_%d_Interior" % i)
		if app2 and ins2:
			out.append([app2, dock, ins2, "*Airlock_%d_OuterDoor*" % i])
	out.sort_custom(func(a, b): return a[1].global_position.distance_to(from) < b[1].global_position.distance_to(from))
	# entry points a boarding shuttle is docked over go to the back of the list (pods would
	# fly straight through it); still usable if every one is covered
	var free: Array = []
	var covered: Array = []
	for e in out:
		var blocked := false
		for sh in G.pods:
			if is_instance_valid(sh) and sh.has_method("_unload") and sh.get("target") == self and int(sh.get("stage")) >= 3 \
					and sh.global_position.distance_to((e[1] as Node3D).global_position) < 14.0:
				blocked = true
				break
		if blocked:
			covered.append(e)
		else:
			free.append(e)
	return free + covered


func request_fighters() -> void:
	launch_wanted = parked_count()
	if launch_wanted == 0:
		return
	G.say("%s: pilots, scramble!" % display_name, team)
	var free_pads: Array = pads.filter(func(p): return p["parked"] != null)
	var pilots: Array = occupants.filter(func(c): return c.role == "pilot" and c.state == "alive" and c.team == team)
	for i in min(free_pads.size(), pilots.size()):
		pilots[i].scramble_pad = free_pads[i]["name"]
		pilots[i].elev = {}
		pilots[i].working = false
		pilots[i].task_pos = Vector3.INF
	# no pilots left aboard: crew launch them the slow way
	if pilots.is_empty():
		for p in free_pads:
			_launch_from(p, null)


## A pilot reached their pad: the fighter lifts off with them aboard.
func pilot_arrived(pilot: Node, pad_name: String) -> void:
	for p in pads:
		if p["name"] == pad_name and p["parked"] != null:
			_launch_from(p, pilot)
			return
	pilot.scramble_pad = ""


## The player at a hangar pad climbs in and flies it. Returns the fighter or null.
func player_launch(pilot: Node) -> Node:
	for p in pads:
		if p["parked"] != null and Vector2(pilot.position.x - p["local"].x, pilot.position.z - p["local"].z).length() < 5.0:
			var f := _launch_from(p, null)
			f.player = true
			f.pilot_name = pilot.display
			f.pilot_role = pilot.role
			return f
	return null


## A player's fighter comes home: it parks on a free pad and the pilot climbs out.
func player_dock(f: Node) -> Vector3:
	for p in pads:
		if p["parked"] == null:
			var folder := "ships_P" if faction == 3 else "ships_F%d" % faction
			var parked: Node3D = load("res://models/%s/ship_XS_FIGHTER.glb" % folder).instantiate()
			add_child(parked)
			parked.position = p["local"] + Vector3(0, 1.0, 0)
			for sb in parked.find_children("*", "StaticBody3D", true, false):
				(sb as StaticBody3D).collision_layer = 0
			p["parked"] = parked
			G.fighters.erase(f)
			f.queue_free()
			return snap_local(p["local"] + Vector3(3.5, 0, 0))
	return Vector3.INF


func _launch_from(p: Dictionary, pilot: Node) -> Node:
	var parked: Node3D = p["parked"]
	p["parked"] = null
	var f: Node3D = FIGHTER.new()
	get_tree().root.add_child(f)
	f.setup(self, parked.global_transform, team, faction)
	if pilot:
		f.pilot_name = pilot.display
		leave(pilot)
		G.characters.erase(pilot)
		pilot.queue_free()
	parked.queue_free()
	launch_wanted = max(0, launch_wanted - 1)
	G.stat("fighters_launched")
	if G.match_node:
		G.match_node.on_spawned_fighter(f, self)
	return f


## Hulls don't pass through each other: ships too close ease apart (stations push harder).
func _keep_apart(dt: float) -> void:
	var r: float = maxf(aabb.size.x, aabb.size.z) * 0.5
	for o in G.vessels:
		if o == self or not is_instance_valid(o) or o.destroyed or absf(global_position.y - o.global_position.y) > 40.0:
			continue                                 # (a drop frigate hovering over a base is fine)
		var ro: float = maxf(o.aabb.size.x, o.aabb.size.z) * 0.5
		var d: Vector3 = global_position - o.global_position
		d.y = 0.0
		var need: float = (r + ro) * (0.55 if o.kind == "ship" else 0.75)
		var l := d.length()
		if l < need and l > 0.01:
			global_position += d / l * minf(need - l, (40.0 if o.kind == "ship" else 120.0) * dt)


# ------------------------------------------------------------------ artillery

## The nearest enemy ground target in range: a surface base (ground fort, mine, outpost).
func _arty_target(from: Vector3) -> Node:
	var best: Node = null
	var bd: float = ARTY["range"]
	for v in [attack_target, lock]:
		if v != null and is_instance_valid(v) and not v.destroyed and is_surface(v) and G.enemies(team, v.team) \
				and from.distance_to(v.global_position) < bd:
			return v
	for v in G.vessels:
		if is_instance_valid(v) and not v.destroyed and is_surface(v) and G.enemies(team, v.team):
			var d: float = from.distance_to(v.global_position)
			if d < bd:
				bd = d
				best = v
	if G.match_node and G.match_node.get("outposts") != null:
		for o in G.match_node.outposts:
			if is_instance_valid(o) and not o.destroyed and G.enemies(team, o.team):
				var d2: float = from.distance_to(o.global_position)
				if d2 < bd:
					bd = d2
					best = o
	return best


func _artillery(t: Dictionary, dt: float) -> void:
	var root: Node3D = t["root"]
	var tgt := _arty_target(root.global_position)
	if tgt == null:
		return
	# lob it: aim high over the target, the shell falls somewhere in a wide circle round it
	var c: Vector3 = tgt.to_global(tgt.aabb.get_center())
	if aim_gun(t, c + Vector3.UP * 60.0, dt) and t["cool"] <= 0.0:
		t["cool"] = float(ARTY["cd"]) * randf_range(1.0, 1.3)
		var land: Vector3 = c + Vector3(randfn(0.0, 1.0), 0, randfn(0.0, 1.0)) * maxf(25.0, tgt.aabb.size.length() * 0.35)
		land.y = tgt.global_position.y + tgt.aabb.position.y + tgt.aabb.size.y * 0.6
		var shell := MeshInstance3D.new()
		shell.mesh = G._box_mesh
		shell.material_override = G._mat(Color(1.0, 0.55, 0.2) if napalm else Color(1.0, 0.85, 0.5), 5.0)
		shell.scale = Vector3(0.5, 0.5, 3.0)
		get_tree().root.add_child(shell)
		var from := gun_muzzle(t)
		shell.global_position = from
		G.flash(from, Color(1.0, 0.7, 0.3), 10.0, 20.0, 0.1)
		t["kick"] = 1.0
		G.stat("arty_shots")
		var tw := create_tween()
		var mid: Vector3 = from.lerp(land, 0.5) + Vector3.UP * 120.0
		var flight: float = clampf(from.distance_to(land) / 260.0, 1.5, 6.0)
		tw.tween_method(func(k: float):
			if is_instance_valid(shell):
				shell.global_position = from.lerp(mid, k).lerp(mid.lerp(land, k), k), 0.0, 1.0, flight)
		tw.tween_callback(func(): _shell_lands(shell, land, tgt, napalm))


func _shell_lands(shell: Node, at: Vector3, tgt: Node, burn: bool) -> void:
	if is_instance_valid(shell):
		shell.queue_free()
	G.explosion(at, 14.0, Color(1.0, 0.45, 0.15) if burn else Color(1.0, 0.6, 0.25))
	var dmg: float = ARTY["dmg"]
	if is_instance_valid(tgt) and not tgt.destroyed and tgt.aabb.grow(30.0).has_point(tgt.to_local(at)):
		tgt.take_hit(dmg * (2.0 if burn and tgt.team == 4 else 1.0), at, self)
	G.blast(at, 18.0, 70.0 if not burn else 45.0, self)          # troops caught in it
	if burn:
		# napalm: the ground keeps burning for a while; hits the infected hardest
		for i in 6:
			await get_tree().create_timer(1.0).timeout
			G.explosion(at + Vector3(randf_range(-8, 8), 0, randf_range(-8, 8)), 6.0, Color(1.0, 0.4, 0.1))
			for c in G.characters:
				if is_instance_valid(c) and c.state != "dead" and c.global_position.distance_to(at) < 16.0 and G.enemies(team, c.team):
					c.take_damage(18.0 * (2.5 if c.team == 4 else 1.0), self, at)
