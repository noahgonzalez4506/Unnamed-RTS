extends Node3D
## A mini dropship: flies from its dropship to a landing point on the ground, sets down, drops
## its ramp and unloads, then flies home and docks again.
##   one load: a tank and 8 troops, OR an IFV and 6, OR 2 MRAPs and 8, OR up to 4 mechs and 8
## Vanguard: a boxy Pelican-style hauler with tail ramp and twin engine pods.
## Ascendancy: a sleek wedge on ducted fans with red strips.

const BAYS := preload("res://scripts/campaign/bays.gd")
const VEHICLE := preload("res://scripts/campaign/vehicle.gd")

var home: Node3D
var team := 1
var faction := 1
var hp := 700.0
var dest := Vector3.ZERO
var stage := 0                       # 0 out, 1 descend, 2 unload, 3 climb, 4 home
var stage_t := 0.0
var vel := Vector3.ZERO
var cargo: Array = []               # vehicle kinds
var troops := 0
var _camp = null                     # the campaign it was sent from, and its ship record
var _fleet_id := -1
var _back := false                   # docked home again, or lost: nothing left to hand back


func setup(home_: Node3D, dest_: Vector3) -> void:
	home = home_
	_camp = G.campaign
	_fleet_id = int(home.get_meta("fleet_id", -1))
	team = home.team
	faction = home.faction if home.faction in [1, 2] else 1
	dest = dest_
	_load()
	_model()
	global_position = home.global_position + Vector3.UP * (home.aabb.end.y + 8.0)
	G.pods.append(self)
	var m: Node = G.match_node
	if m.ground != null and home.move_target == Vector3.INF and (cargo.size() > 0 or troops > 0):
		_start_loading()


# ------------------------------------------------------------------ loading on the ground
## With the dropship set down, the mini dropship lands beside its ramp: troops (and mechs)
## walk over and file in up the tail ramp; armour, IFVs and MRAPs ride an elevator up out
## of the dropship's bay right behind the tail ramp and drive in.
var _boarding: Array = []          # people and vehicles still on their way in
var _elev: Node3D


func _start_loading() -> void:
	var m: Node = G.match_node
	var foot: Vector3 = BAYS.ramp_foot(home)
	BAYS.ramp_down(home)
	var side: Vector3 = home.global_basis.x
	var pad: Vector3 = foot + side * 34.0
	pad.y = m.ground_y(pad.x, pad.z) + 2.4
	global_position = pad
	var away: Vector3 = (pad - foot)
	away.y = 0.0
	look_at(pad + away.normalized() * 10.0, Vector3.UP)                 # nose away: the tail ramp faces the dropship
	rotation.x = 0.0
	stage = -1
	stage_t = 0.0
	var tail: Vector3 = global_position + global_basis.z * 7.0
	# the elevator platform, sunk flush with the ground behind the tail ramp
	_elev = Node3D.new()
	m.add_child(_elev)
	var plat := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(7.0, 0.5, 9.0)
	plat.mesh = bm
	plat.material_override = G._mat(Color(0.9, 0.75, 0.2), 0.4)
	_elev.add_child(plat)
	var up_at: Vector3 = tail + global_basis.z * 9.0
	up_at.y = m.ground_y(up_at.x, up_at.z)
	_elev.global_position = up_at
	# people: out of the dropship's ramp, on foot
	var roles: Array = ["squad_leader", "rifleman", "rifleman", "medic", "breacher", "heavy", "grenadier", "rifleman"]
	for i in troops:
		var c: Node = m.spawn_character(m.ground, m.ground.snap_local(m.ground.to_local(foot + side * (i % 3 - 1) * 1.5)), team, G.team_fac(team), roles[i % roles.size()])
		c.order = {"type": "move", "pos": m.ground.snap_local(m.ground.to_local(tail)), "vessel": m.ground}
		c.run = true
		_boarding.append(c)
	troops_loading = troops
	troops = 0
	# vehicles: mechs walk over; the rest come up the elevator one by one
	var k := 0
	for kind_ in cargo:
		var v: Node3D = VEHICLE.new()
		if kind_ == "mech":
			v.setup(kind_, team, faction, m.ground, m.ground.snap_local(m.ground.to_local(foot - side * 6.0)))
			v.order_move(tail)
		else:
			v.setup(kind_, team, faction, m.ground, m.ground.to_local(up_at))
			v.set_physics_process(false)
			v.global_position = up_at + Vector3.DOWN * 7.0      # waiting down in the bay
			var tw := create_tween()
			tw.tween_interval(1.0 + k * 4.0)
			tw.tween_property(v, "global_position", up_at + Vector3.UP * 0.3, 2.5)
			tw.parallel().tween_property(_elev, "global_position", up_at + Vector3.UP * 0.3, 2.5)
			tw.tween_callback(func():
				if is_instance_valid(v):
					v.set_physics_process(true)
					v.order_move(global_position))
			tw.tween_property(_elev, "global_position", up_at, 1.5)
			k += 1
		_boarding.append(v)
	cargo_loading = cargo.duplicate()
	cargo = []


var troops_loading := 0
var cargo_loading: Array = []


func _loading_tick() -> void:
	var c0 := global_position
	var m: Node = G.match_node
	for b in _boarding.duplicate():
		if not is_instance_valid(b) or (b.get("state") != null and b.state != "alive") or b.get("destroyed") == true:
			_boarding.erase(b)
			continue
		if Vector2(b.global_position.x - c0.x, b.global_position.z - c0.z).length() < 9.0:
			_boarding.erase(b)
			if b.get("is_vehicle") == true:
				cargo.append(b.kind)
				G.vehicles.erase(b)
				b.queue_free()
			else:
				troops += 1
				m.logistics._remove_person(b)
	if _boarding.is_empty() or stage_t > 60.0:
		for b in _boarding:                           # stragglers stay on the ground
			if is_instance_valid(b) and b.get("rig") != null:
				b.order = {}
		_boarding.clear()
		if is_instance_valid(_elev):
			_elev.queue_free()
		if is_instance_valid(home):
			BAYS.ramp_up(home)
		stage = 0
		stage_t = 0.0


## Take the best load the dropship's bay allows.
func _load() -> void:
	var bay: Array = G.match_node.ship_vehicles(home)
	if bay.has("tank"):
		bay.erase("tank")
		cargo = ["tank"]
		troops = 8
	elif bay.has("ifv"):
		bay.erase("ifv")
		cargo = ["ifv"]
		troops = 6
	elif bay.count("mech") > 0:
		for i in mini(4, bay.count("mech")):
			bay.erase("mech")
			cargo.append("mech")
		troops = 8
	else:
		for k in ["mrap_ai", "mrap_av", "mrap_aa", "mortar"]:
			while bay.has(k) and cargo.size() < 2:
				bay.erase(k)
				cargo.append(k)
		troops = 8
	troops = mini(troops, home.troops)
	home.troops -= troops


func _box(s: Vector3, p: Vector3, m: Material, rot: Vector3 = Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = s
	mi.mesh = bm
	mi.material_override = m
	mi.position = p
	mi.rotation = rot
	add_child(mi)


func _model() -> void:
	var asc := faction == 2
	var body := StandardMaterial3D.new()
	body.albedo_color = Color(0.36, 0.4, 0.33) if not asc else Color(0.8, 0.82, 0.86)
	body.metallic = 0.4
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.13, 0.13, 0.15)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.25, 0.4, 0.55)
	if asc:
		_box(Vector3(5.5, 2.6, 13.0), Vector3(0, 0, 0), body)
		_box(Vector3(4.2, 1.2, 4.0), Vector3(0, 0.9, -7.0), body, Vector3(0.35, 0, 0))
		_box(Vector3(3.2, 0.6, 2.0), Vector3(0, 1.5, -5.2), glass)
		for sx in [-1, 1]:
			var fan := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 1.8
			cm.bottom_radius = 1.8
			cm.height = 1.0
			fan.mesh = cm
			fan.material_override = dark
			fan.position = Vector3(sx * 4.6, 0.2, 1.0)
			add_child(fan)
			_box(Vector3(0.12, 0.12, 11.0), Vector3(sx * 2.8, 1.3, 0), G._mat(Color(1.0, 0.2, 0.25), 2.5))
	else:
		_box(Vector3(5.0, 3.6, 12.0), Vector3(0, 0, 0), body)                 # troop bay
		_box(Vector3(4.0, 2.4, 3.6), Vector3(0, 0.3, -7.6), body)             # nose
		_box(Vector3(3.2, 0.9, 1.8), Vector3(0, 1.2, -8.2), glass)
		_box(Vector3(4.6, 0.4, 3.0), Vector3(0, -1.4, 6.8), body, Vector3(-0.5, 0, 0))   # tail ramp
		for sx in [-1, 1]:
			_box(Vector3(1.6, 1.6, 5.0), Vector3(sx * 3.6, 1.0, 1.0), dark)      # engine pods
			_box(Vector3(2.6, 0.4, 1.8), Vector3(sx * 2.6, 1.2, 1.0), body)     # pylons
		_box(Vector3(0.4, 2.4, 2.4), Vector3(0, 2.6, 5.0), body)              # tail fin


func take_hit(d: float, _from: Vector3 = Vector3.ZERO, _by: Node = null) -> void:
	hp -= d
	if hp <= 0.0:
		G.explosion(global_position, 9.0)
		G.say("A mini dropship was shot down with %d troops and %d vehicles aboard" % [troops, cargo.size()], team)
		_back = true
		G.pods.erase(self)
		queue_free()


func _fly(p: Vector3, spd: float, dt: float) -> bool:
	var to := p - global_position
	if to.length() < maxf(3.0, spd * dt):
		global_position = p
		return true
	vel = vel.lerp(to.normalized() * spd, clampf(dt * 1.5, 0.0, 1.0))
	global_position += vel * dt
	var flat := Vector3(vel.x, 0, vel.z)
	if flat.length() > 2.0:
		look_at(global_position + flat, Vector3.UP)
	return false


func _process(dt: float) -> void:
	stage_t += dt
	var m: Node = G.match_node
	if m == null or m.ground == null:
		return
	var gy: float = m.ground_y(dest.x, dest.z)
	match stage:
		-1:
			_loading_tick()
		0:
			if _fly(Vector3(dest.x, gy + 70.0, dest.z), 70.0, dt) or stage_t > 90.0:
				stage = 1
				stage_t = 0.0
		1:
			if _fly(Vector3(dest.x, gy + 3.0, dest.z), 12.0, dt) or stage_t > 20.0:
				stage = 2
				stage_t = 0.0
				_unload()
		2:
			if stage_t > 6.0:
				stage = 3
				stage_t = 0.0
		3:
			if _fly(Vector3(dest.x, gy + 80.0, dest.z), 20.0, dt) or stage_t > 12.0:
				stage = 4
				stage_t = 0.0
		4:
			if home == null or not is_instance_valid(home) or home.destroyed:
				_back = true
				G.pods.erase(self)
				queue_free()
				return
			if _fly(home.global_position + Vector3.UP * (home.aabb.end.y + 8.0), 70.0, dt):
				var e: Dictionary = G.campaign.fleet_entry(int(home.get_meta("fleet_id", -1)))
				if not e.is_empty():
					e["minidrops"] = int(e.get("minidrops", 0)) + 1
				_back = true
				G.pods.erase(self)
				queue_free()


## Still out when the scene goes (take-off, zone switch, jump): the craft, and whatever it
## hadn't set down yet, go back aboard its ship's record rather than vanishing.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and not _back and _camp != null and G.campaign == _camp:
		_back = true
		owed_to(_camp.fleet_entry(_fleet_id))


## Add this craft and its load to a ship record `e` (the live one, or a copy being saved).
func owed_to(e: Dictionary) -> void:
	if e.is_empty():
		return
	e["minidrops"] = int(e.get("minidrops", 0)) + 1
	e["troops"] = int(e.get("troops", 0)) + troops
	var bay: Array = e.get("vehicles", [])
	bay.append_array(cargo)
	e["vehicles"] = bay


func _unload() -> void:
	var m: Node = G.match_node
	var back: Vector3 = global_basis.z
	var foot := global_position + back * 10.0
	foot.y = m.ground_y(foot.x, foot.z)
	for i in cargo.size():
		var v: Node3D = VEHICLE.new()
		v.setup(cargo[i], team, faction, m.ground, m.ground.snap_local(m.ground.to_local(foot + global_basis.x * (i * 7.0 - 3.5))))
		v.rotation.y = rotation.y + PI
		v.order_move(foot + back * 25.0 + global_basis.x * (i * 8.0))
	if troops > 0:
		var roles: Array = ["squad_leader", "rifleman", "rifleman", "medic", "breacher", "heavy", "grenadier", "rifleman"].slice(0, troops)
		m.spawn_squad(m.ground, m.ground.snap_local(m.ground.to_local(foot + back * 6.0)), team, G.team_fac(team), roles, false)
	G.say("Mini dropship down: %d troops%s" % [troops, (" and %d vehicle%s" % [cargo.size(), "" if cargo.size() == 1 else "s"]) if not cargo.is_empty() else ""], team)
	G.stat("minidrop_landings")
	cargo = []
	troops = 0
