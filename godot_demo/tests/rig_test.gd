extends Node3D
## Lines up characters in every animation mode and saves a picture (used to check the rig).
const RIG := preload("res://scripts/rig.gd")

func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.09, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.65, 0.75)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	add_child(sun)
	var floor_ := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 20)
	floor_.mesh = pm
	add_child(floor_)
	var setups := [["F1", "rifleman", "normal", 0.0, false, false, "weapon_F1_AssaultRifle"],
		["F1", "squad_leader", "normal", 0.0, true, false, "weapon_F1_BattleRifle"],
		["F2", "rifleman", "normal", 5.0, false, false, "weapon_F2_PlasmaRifle"],
		["F2", "heavy", "normal", 0.0, true, true, "weapon_F2_ArcCannon"],
		["F1", "engineer", "work", 0.0, false, false, ""],
		["F1", "cargo_handler", "carry", 0.0, false, false, ""],
		["F2", "medic", "kneel", 0.0, false, false, "weapon_F2_EnergySMG"],
		["P", "rifleman", "normal", 2.0, false, false, "weapon_P_AssaultRifle"],
		["F1", "medic", "downed", 0.0, false, false, "weapon_F1_SMG"],
		["F2", "breacher", "normal", 0.0, true, false, "weapon_F2_ScatterGun"]]
	var rigs := []
	for i in setups.size():
		var s: Array = setups[i]
		var holder := Node3D.new()
		add_child(holder)
		holder.position = Vector3(-9.0 + i * 2.0, 0, 0)
		holder.rotation.y = PI
		var r := RIG.new()
		holder.add_child(r)
		r.setup("res://models/characters/char_%s_%s.glb" % [s[0], s[1]], 2 if s[0] == "F2" else 1)
		if s[6] != "":
			r.set_weapon("res://models/weapons/%s.glb" % s[6])
		r.mode = s[2]
		r.speed = s[3]
		r.aiming = s[4]
		r.crouch = s[5]
		if s[2] == "carry":
			var crate := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.5, 0.35, 0.4)
			crate.mesh = bm
			r.set_held(crate)
		rigs.append(r)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 1.6, 9.0)
	cam.look_at(Vector3(0, 0.9, 0))
	cam.fov = 70
	for f in 50:
		for r in rigs:
			r.animate(1.0 / 60.0)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[-1])
	G.quit()
