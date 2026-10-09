extends Node3D
## Renders every model from outside and (for ships/stations) every deck from above,
## to spot missing or broken pieces:  godot --path . res://tests/model_shots.tscn -- <folder>
const VESSEL := preload("res://scripts/vessel.gd")
var out := ""
var cam: Camera3D


func _ready() -> void:
	G.reset()
	out = OS.get_cmdline_user_args()[-1]
	DirAccess.make_dir_recursive_absolute(out)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.06, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.65, 0.75)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 35, 0)
	add_child(sun)
	cam = Camera3D.new()
	cam.fov = 40.0
	cam.far = 5000.0
	add_child(cam)
	var vessels: Array = []
	for d in ["ships_F1", "ships_F2", "ships_P", "ships_X", "stations_F1", "stations_F2", "stations_P"]:
		for f in DirAccess.get_files_at("res://models/" + d):
			if f.ends_with(".glb"):
				vessels.append("res://models/%s/%s" % [d, f])
	for p in vessels:
		await _shoot_vessel(p)
	for fac in ["F1", "F2", "P"]:
		await _shoot_lineup("res://models/characters", "char_%s_" % fac, "chars_%s" % fac, 2.2)
	await _shoot_lineup("res://models/weapons", "weapon_", "weapons", 1.2)
	G.quit()


func _snap(name_: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name_])


func _look(from: Vector3, at: Vector3) -> void:
	cam.global_position = from
	cam.look_at(at, Vector3.UP if abs((at - from).normalized().y) < 0.98 else Vector3.FORWARD)


func _shoot_vessel(path: String) -> void:
	var n: Node3D = load(path).instantiate()
	n.set_script(VESSEL)
	add_child(n)
	var tag := path.get_base_dir().get_file() + "_" + path.get_file().get_basename()
	n.setup_vessel(path.get_file().get_basename().trim_prefix("ship_"), 1, 1, tag)
	var bb: AABB = n.aabb
	var c := bb.get_center()
	var r := bb.size.length() * 0.62
	G.set_cut(10000.0)
	_look(c + Vector3(1.0, 0.55, 1.0).normalized() * r * 1.7, c)
	await _snap(tag + "_a_front_quarter")
	_look(c + Vector3(-1.0, 0.35, -1.0).normalized() * r * 1.7, c)
	await _snap(tag + "_b_rear_quarter")
	_look(c + Vector3(0.0, -0.6, 1.0).normalized() * r * 1.7, c)
	await _snap(tag + "_c_below")
	if not tag.contains("XS_"):
		var decks := int(round(bb.end.y / 4.0))
		for k in clampi(decks, 1, 4):
			G.set_cut(k * 4.0 + 2.7)
			var top := Vector3(c.x, k * 4.0 + max(bb.size.x, bb.size.z) * 1.25, c.z + 0.01)
			_look(top, Vector3(c.x, k * 4.0, c.z))
			await _snap(tag + "_d_deck%d" % k)
	n.queue_free()
	await get_tree().process_frame


func _shoot_lineup(dir: String, prefix: String, name_: String, spacing: float) -> void:
	var nodes: Array = []
	var files: Array = []
	for f in DirAccess.get_files_at(dir):
		if f.begins_with(prefix) and f.ends_with(".glb"):
			files.append(f)
	files.sort()
	for i in files.size():
		var m: Node3D = load(dir + "/" + files[i]).instantiate()
		add_child(m)
		m.position = Vector3((i - files.size() / 2.0) * spacing, 0, 0)
		if name_ == "weapons":
			m.rotation.y = PI / 2
			m.scale = Vector3.ONE * 1.4
		nodes.append(m)
	var w := files.size() * spacing
	G.set_cut(10000.0)
	_look(Vector3(0, 1.2 if name_ != "weapons" else 0.3, w * 0.75 + 2.0), Vector3(0, 0.9 if name_ != "weapons" else 0.0, 0))
	await _snap(name_ + "_front")
	_look(Vector3(0, 1.4 if name_ != "weapons" else 0.3, -(w * 0.75 + 2.0)), Vector3(0, 0.9 if name_ != "weapons" else 0.0, 0))
	await _snap(name_ + "_back")
	for m in nodes:
		m.queue_free()
	await get_tree().process_frame
