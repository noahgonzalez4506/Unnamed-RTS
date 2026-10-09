extends RefCounted
## Vehicle bays: the loading ramp (supply ship: the new front cargo bay; dropship: the stern),
## the supply ship's mech room (its mechs stand in their bay like suits of power armour), and
## driving vehicles out down the ramp one after another.

const VEHICLE := preload("res://scripts/campaign/vehicle.gd")


static func ramp_at_bow(s: Node) -> bool:
	return s.cls in ["SMALL_SUPPORT", "SMALL_FRIGATE"]      # the front cargo bay (frigate: lower deck, 2 MRAPs)


## The ramp: a hinged plank at the bow or stern, folded up flush until it's lowered.
static func ensure_ramp(s: Node3D) -> Node3D:
	var r: Node3D = s.get_node_or_null("Ramp")
	if r:
		return r
	var bow := ramp_at_bow(s)
	r = Node3D.new()
	r.name = "Ramp"
	r.position = Vector3(s.aabb.get_center().x, s.aabb.position.y + 1.2, s.aabb.position.z + 1.5 if bow else s.aabb.end.z - 1.5)
	s.add_child(r)
	var plank := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(8.0, 0.4, 11.0)
	plank.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.32, 0.34)
	m.metallic = 0.5
	plank.material_override = m
	plank.position = Vector3(0, 0, -5.5 if bow else 5.5)
	r.add_child(plank)
	for k in 5:                                      # tread strips
		var st := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(7.6, 0.08, 0.3)
		st.mesh = sb
		st.material_override = G._mat(Color(0.9, 0.75, 0.2), 0.8)
		st.position = Vector3(0, 0.22, (-1.5 - k * 2.0) if bow else (1.5 + k * 2.0))
		r.add_child(st)
	r.rotation.x = (-PI * 0.5) if bow else (PI * 0.5)  # folded shut
	return r


static func ramp_down(s: Node3D) -> void:
	var r := ensure_ramp(s)
	var bow := ramp_at_bow(s)
	var tw := s.create_tween()
	tw.tween_property(r, "rotation:x", 0.32 if bow else -0.32, 1.6)


static func ramp_up(s: Node3D) -> void:
	var r := ensure_ramp(s)
	var bow := ramp_at_bow(s)
	var tw := s.create_tween()
	tw.tween_property(r, "rotation:x", (-PI * 0.5) if bow else (PI * 0.5), 1.6)


## The foot of the ramp, on the ground (world).
static func ramp_foot(s: Node3D) -> Vector3:
	var bow := ramp_at_bow(s)
	var dir: Vector3 = (-s.global_basis.z) if bow else s.global_basis.z
	var p: Vector3 = s.to_global(Vector3(s.aabb.get_center().x, 0, s.aabb.position.z if bow else s.aabb.end.z)) + dir * 14.0
	p.y = G.match_node.ground_y(p.x, p.z)
	return p


## Lower the ramp and drive the bay's vehicles out, one every second and a bit. `bay` is the
## ship record's own list: each vehicle leaves it only as it rolls out, so one still aboard
## when the ship takes off (or the scene changes) stays aboard.
static func drive_out(s: Node3D, bay: Array) -> void:
	if bay.is_empty():
		return
	ramp_down(s)
	var m: Node = G.match_node
	var foot := ramp_foot(s)
	var out: Vector3 = (foot - s.global_position)
	out.y = 0.0
	out = out.normalized()
	var tree: SceneTree = s.get_tree()
	await tree.create_timer(1.7).timeout
	var count: int = bay.size()
	for i in count:
		if not is_instance_valid(s) or m.ground == null or bay.is_empty():
			return
		var kind: String = bay.pop_front()
		var v: Node3D = VEHICLE.new()
		v.setup(kind, s.team, G.team_fac(s.team), m.ground, m.ground.snap_local(m.ground.to_local(foot)))
		v.rotation.y = atan2(-out.x, -out.z)
		if kind == "ifv" and s.troops >= 6:
			s.troops -= 6
			v.passengers = 6
		v.order_move(foot + out * (30.0 + (i / 3) * 14.0) + out.cross(Vector3.UP) * ((i % 3) * 12.0 - 12.0))
		await tree.create_timer(1.3).timeout
	await tree.create_timer(2.0).timeout
	if is_instance_valid(s):
		ramp_up(s)


## The mech room: the mechs a supply ship carries stand parked in a row in its hold.
static func refresh_mech_bay(s: Node3D, mechs: int) -> void:
	if s.get_meta("mech_bay_n", -1) == mechs:
		return
	s.set_meta("mech_bay_n", mechs)
	var old: Node = s.get_node_or_null("MechBay")
	if old:
		old.free()
	var bay := Node3D.new()
	bay.name = "MechBay"
	s.add_child(bay)
	var spots: Array = s.marks_like("CargoStorage_*")
	if spots.is_empty():
		return
	var base: Vector3 = s.local_of(spots[spots.size() - 1])
	var lab := Label3D.new()
	lab.text = "MECH BAY"
	lab.font_size = 48
	lab.pixel_size = 0.006
	lab.position = base + Vector3(0, 3.4, 0)
	bay.add_child(lab)
	for i in mechs:
		var v: Node3D = VEHICLE.new()
		v.kind = "mech"
		v.team = s.team
		v.faction = s.faction if s.faction in [1, 2] else 1
		v._build()
		v.set_physics_process(false)
		for hb in v.find_children("*", "StaticBody3D", true, false):
			(hb as StaticBody3D).collision_layer = 0
		v.scale = Vector3.ONE * 0.42                   # (parked down in its cradle)
		v.position = base + Vector3(-3.0 + (i % 3) * 1.6, 0.05, -1.6 + (i / 3) * 2.4)
		bay.add_child(v)
		# a cradle frame round each
		var fr := MeshInstance3D.new()
		var fb := BoxMesh.new()
		fb.size = Vector3(1.4, 0.15, 1.4)
		fr.mesh = fb
		fr.material_override = G._mat(Color(0.9, 0.75, 0.2), 0.6)
		fr.position = v.position + Vector3(0, 0.05, 0)
		bay.add_child(fr)
