extends Node3D
## Side-by-side exterior pictures of each faction's warships:
##   godot --path . res://tests/faction_shots.tscn -- <folder>
var out := ""
var cam: Camera3D


func _ready() -> void:
	out = OS.get_cmdline_user_args()[-1]
	DirAccess.make_dir_recursive_absolute(out)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.05, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.7)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 140, 0)
	sun.light_energy = 1.3
	add_child(sun)
	cam = Camera3D.new()
	cam.fov = 35.0
	cam.far = 5000.0
	add_child(cam)
	for cls in ["LARGE", "MEDIUM", "SMALL_FRIGATE", "XL"]:
		for d in ["ships_F1", "ships_F2", "ships_P", "ships_X"]:
			var p := "res://models/%s/ship_%s.glb" % [d, cls]
			if ResourceLoader.exists(p):
				for view in [0, 1]:
					await _shoot(p, "%s_%s_%d" % [cls, d.substr(6), view], view)
	G.quit()


func _shoot(path: String, name_: String, view: int) -> void:
	var n: Node3D = load(path).instantiate()
	add_child(n)
	var bb := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		bb = b if first else bb.merge(b)
		first = false
	var c := bb.get_center()
	var r := bb.size.length() * 0.62
	var dir := Vector3(0.75, 0.42, -0.55).normalized() if view == 0 else Vector3(-0.7, 0.3, 0.65).normalized()
	cam.global_position = c + dir * r * 1.7
	cam.look_at(c, Vector3.UP)
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name_])
	n.queue_free()
	await get_tree().process_frame
