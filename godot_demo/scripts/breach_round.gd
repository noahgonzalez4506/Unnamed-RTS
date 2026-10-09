extends Node3D
## A breaching round for the grenadier's launcher (like Ash's in Siege): a finned dark-grey
## cylinder with a red band and a hole-saw crown on the nose. Four curved fins lie folded along
## the body and flip out when it's fired.
## The model is built here so the belt sleeves (character.gd) and the projectile share it.
## Its axis is +z, nose forward; it is about 0.14 m long.

const BODY_R := 0.02

var by: Node = null               # who fired it
var aim := {}                     # the door or wall it was fired at: it opens that one only
var claim := true                 # an AI breacher's round: the target's "charged" flag is ours
var vel := Vector3.ZERO
var model: Node3D
var stuck := false
var vessel: Node = null           # the ship it stuck to (it rides along)
var _st := {}
var _t := 0.0
var _spin := 1.0
var _spark := 0.0
var _life := 3.0
var team := 0                     # while it drills, the firer's friends keep clear of the far side's blast


## Fire from `from` along `dir` (stats: the "BreachRound" item). `aim_at` is the door/wall dict
## it's meant for, if any: it gets its "charged" flag back if the round fails.
func fire(from: Vector3, dir: Vector3, who: Node, st: Dictionary, aim_at: Dictionary = {}) -> void:
	by = who
	aim = aim_at
	_st = st
	global_position = from
	vel = dir.normalized() * float(st.get("speed_m_s", 40.0))
	_spin = float(st.get("spin_s", 1.0))
	model = build_model()
	add_child(model)
	model.basis = Basis.looking_at(-vel.normalized(), Vector3.UP if absf(vel.normalized().y) < 0.99 else Vector3.BACK)


func _physics_process(dt: float) -> void:
	_t += dt
	if not stuck:
		set_fins(model, _t / 0.12)
		var nxt := global_position + vel * dt               # flies straight: no drop over breaching ranges
		var hit := G.ray(global_position, nxt, [], G.LAYER_WORLD | G.LAYER_DOOR)
		if hit.is_empty():
			global_position = nxt
			_life -= dt
			if _life <= 0.0:
				_fail()
			return
		# bite in: nose on the surface, then ride with the ship
		stuck = true
		team = int(by.get("team")) if by and is_instance_valid(by) and by.get("team") != null else 0
		G.dangers.append(self)
		global_position = (hit.position as Vector3) - vel.normalized() * 0.065
		vessel = _vessel_of(hit.collider)
		if vessel:
			reparent(vessel, true)
		return
	# the hole saw spins up and throws sparks, then the round goes off
	var crown: Node3D = model.get_meta("crown")
	crown.rotate_object_local(Vector3.BACK, dt * minf(_t * 60.0, 45.0))
	_spark -= dt
	if _spark <= 0.0:
		_spark = 0.07
		var nose: Vector3 = model.global_transform * Vector3(0, 0, 0.07)
		G.flash(nose, Color(1.0, 0.62, 0.2), 1.6, 1.8, 0.05)
		if G.sfx and randf() < 0.3:
			G.sfx.play("ciws", nose, -16.0)
	_spin -= dt
	if _spin <= 0.0:
		_go_off()


func _go_off() -> void:
	if G.is_client():
		queue_free()                                     # (only a picture here: the host's round opens it)
		return
	var nose: Vector3 = model.global_transform * Vector3(0, 0, 0.07)
	var d := {}
	if vessel and is_instance_valid(vessel):
		var reach: float = float(_st.get("reach_m", 1.5))
		var p: Vector3 = vessel.to_local(nose)
		var at_floor := p - Vector3(0, 1.2, 0)            # door_near / wall_near take a standing position
		if not aim.is_empty():
			# aimed at something: open that, or nothing (never a different door it happened to land by)
			if not aim["breached"] and (aim["center"] as Vector3).distance_to(p) < reach + 1.0:
				d = aim
		elif vessel.has_method("wall_near"):
			d = vessel.wall_near(at_floor, reach)
		if d.is_empty() and vessel.has_method("door_near"):
			d = vessel.door_near(at_floor, reach)
			if not d.is_empty() and d["breached"]:
				d = {}
	if d.is_empty():
		_fail()
		return
	# blow it inward, away from whoever fired
	var nrm: Vector3 = d["n"]
	var from_side: Vector3 = vessel.to_local(by.global_position) if by and is_instance_valid(by) else vessel.to_local(global_position - vel)
	var push := nrm * (1.0 if ((d["center"] as Vector3) - from_side).dot(nrm) >= 0.0 else -1.0)
	push.y = 0.0
	vessel.breach_door(d, by if by and is_instance_valid(by) else null, push)
	G.say("Breaching round: %s opened" % ("wall" if d["kind"] == "wall" else "door"), by.team if by and is_instance_valid(by) else 1)
	queue_free()


## Nothing to breach: a small blast where it is, and the target is free to try again.
func _fail() -> void:
	G.blast(model.global_transform * Vector3(0, 0, 0.07), float(_st.get("radius_m", 1.5)), float(_st.get("damage", 40.0)), by)
	if claim and not aim.is_empty() and not aim["breached"]:
		aim["charged"] = false
	queue_free()


func danger_point() -> Vector3:
	return global_position


func danger_radius() -> float:
	return 3.5


func _exit_tree() -> void:
	G.dangers.erase(self)


static func _vessel_of(n: Object) -> Node:
	var x: Node = n as Node
	while x != null:
		if x in G.vessels:
			return x
		x = x.get_parent()
	return null


## The round's model. Its meta "fins" holds the four fin hinges (see set_fins) and "crown"
## the hole-saw node, which spins about +z.
static func build_model() -> Node3D:
	var root := Node3D.new()
	root.name = "BreachRound"
	var grey := _mat(Color(0.2, 0.21, 0.23), 0.5, 0.55)
	var steel := _mat(Color(0.62, 0.64, 0.67), 0.85, 0.3)
	var red := _mat(Color(0.75, 0.08, 0.06), 0.0, 0.6)
	var dark := _mat(Color(0.05, 0.05, 0.06), 0.0, 0.9)
	# body and its red band
	_cyl(root, BODY_R, 0.1, Vector3(0, 0, -0.02), grey)
	_cyl(root, BODY_R + 0.0008, 0.012, Vector3(0, 0, 0.0), red)
	_cyl(root, BODY_R * 0.75, 0.012, Vector3(0, 0, -0.074), dark)          # tail nozzle
	# the hole-saw crown: a collar, a ring rim with a dark cup inside, and ten teeth
	var crown := Node3D.new()
	crown.name = "Crown"
	crown.position.z = 0.03
	root.add_child(crown)
	_cyl(crown, BODY_R + 0.002, 0.018, Vector3(0, 0, 0.009), steel)
	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.016
	tm.outer_radius = 0.0235
	tm.rings = 20
	tm.ring_segments = 6
	rim.mesh = tm
	rim.material_override = steel
	rim.rotation.x = PI * 0.5
	rim.position.z = 0.019
	crown.add_child(rim)
	_cyl(crown, 0.016, 0.002, Vector3(0, 0, 0.0185), dark)                 # inside the cup
	var tooth := BoxMesh.new()
	tooth.size = Vector3(0.006, 0.004, 0.011)
	for i in 10:
		var a := TAU * i / 10.0
		var t := MeshInstance3D.new()
		t.mesh = tooth
		t.material_override = steel
		t.position = Vector3(cos(a), sin(a), 0) * 0.0198 + Vector3(0, 0, 0.026)
		t.rotation = Vector3(0, 0, a + PI * 0.5)
		t.rotate_object_local(Vector3.RIGHT, 0.35)                      # raked, like saw teeth
		crown.add_child(t)
	root.set_meta("crown", crown)
	# fins: each hinges at the tail and lies forward along the body until it flips out
	var fin := BoxMesh.new()
	fin.size = Vector3(0.003, 0.022, 0.058)
	var fins: Array = []
	for i in 4:
		var spoke := Node3D.new()
		spoke.position.z = -0.066
		spoke.rotation.z = TAU * i / 4.0 + PI * 0.25
		root.add_child(spoke)
		var hinge := Node3D.new()
		hinge.position.x = BODY_R
		spoke.add_child(hinge)
		var f := MeshInstance3D.new()
		f.mesh = fin
		f.material_override = grey
		f.position = Vector3(0.0018, 0, 0.029)
		f.rotation.y = -0.05                                             # curved toward the body
		hinge.add_child(f)
		fins.append(hinge)
	root.set_meta("fins", fins)
	return root


## Fins from folded (0) to fully out (1): they swing back past square, like a dart's.
static func set_fins(model: Node3D, t: float) -> void:
	for h in model.get_meta("fins", []):
		(h as Node3D).rotation.y = lerpf(0.0, deg_to_rad(125.0), clampf(t, 0.0, 1.0))


static func _cyl(parent: Node3D, r: float, h: float, at: Vector3, m: Material) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 14
	cm.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = m
	mi.rotation.x = PI * 0.5                                             # the mesh's axis is y; ours is z
	mi.position = at
	parent.add_child(mi)


static func _mat(c: Color, metal: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	return m
