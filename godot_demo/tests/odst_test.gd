extends Node
## Drop frigate, docks and asteroids:  godot --path . res://match.tscn -- --odsttest [folder]
##   * the drop frigate refuses to fire pods at a station, and fires them at the pirates'
##     ground fort; the troopers land beside it and cut in through its airlocks
##   * a flagship ordered home ties up at a docking arm berth
##   * gunfire through a big asteroid is stopped by the rock

var out := ""
var t := 0.0
var step := 0
var _w := 0.0
var report := {}
var df: Node
var me: Node
var fort: Node
var home: Node
var cam: Camera3D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and not String(args[-1]).begins_with("--"):
		out = args[-1]
		DirAccess.make_dir_recursive_absolute(out)
	Engine.time_scale = 1.0 if out != "" else 3.0
	for v in G.vessels:
		if v.get_meta("slot", "") == "dropfrig1":
			df = v
		elif v.get_meta("slot", "") == "flag1":
			me = v
	fort = G.match_node.pirate_fort
	home = G.match_node.homes[1]
	cam = Camera3D.new()
	cam.far = 9000.0
	add_child(cam)


func _shot(n: String) -> void:
	if out == "":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, n])
	print("SHOT ", n)


func _look(from: Vector3, at: Vector3) -> void:
	_cam_on = true
	G.commander._help = false
	G.commander.hud.show_help(false)
	cam.make_current()
	cam.global_position = from
	cam.look_at(at, Vector3.UP)


var _cam_on := false


func _process(_dt: float) -> void:
	if _cam_on:
		cam.make_current()


func _physics_process(dt: float) -> void:
	t += dt
	match step:
		0:
			if t > 1.5:
				step = 1
				G.match_node.ai.attack_after = 99999.0
				report["station_refused"] = df.launch_drop_pods(G.match_node.homes[2], 6) == 0
				df.global_position = fort.global_position + (df.global_position - fort.global_position).normalized() * 900.0
				df.move_target = Vector3.INF
				df.attack_target = null
				report["pods_loaded"] = df.drop_pods_loaded()
				report["fired_from_afar"] = df.launch_drop_pods(fort, 6)        # not over the zone: must refuse
				report["ordered"] = df.order_drop(fort, fort.to_global(fort.aabb.get_center()), 6)
				_w = t
				# a flagship ordered home to dock
				me.global_position = home.global_position + (me.global_position - home.global_position).normalized() * 700.0
				me.troops = 4
				me.supplies = 50.0
				G.match_node.run_command(1, "resupply", [G.vessels.find(me)])
		1:
			if out != "" and t - _w > 2.5 and not report.has("s1"):
				report["s1"] = true
				for p in G.pods:
					if is_instance_valid(p) and p.get_script() == preload("res://scripts/drop_pod.gd"):
						_look(p.global_position + Vector3(40, 25, 40), p.global_position)
						break
				_shot("01_odst_falling")
			if not report.has("fired") and G.stats.get("odst_launched", 0) > 0:
				report["fired"] = G.stats["odst_launched"]
				report["altitude_at_drop"] = int(df.global_position.y - fort.global_position.y)
			if t - _w > 60.0 or (report.has("fired") and G.stats.get("odst_landed", 0) >= report["fired"]):
				step = 2
				report["landed"] = G.stats.get("odst_landed", 0)
				var inside := 0
				for c in fort.occupants:
					if c.team == 1 and c.state != "dead":
						inside += 1
				report["troopers_in_fort"] = inside
				if out != "":
					_look(fort.global_position + Vector3(90, 60, 90), fort.global_position)
					_shot("02_pods_planted_at_fort")
				_w = t
		2:
			if (G.stats.get("ships_docked", 0) > 0 and t - _w > 20.0) or t - _w > 90.0:
				step = 3
				report["docked"] = G.stats.get("ships_docked", 0) > 0
				report["arty_shots"] = G.stats.get("arty_shots", 0)
				report["dock_time_s"] = int(t - _w)
				if out != "":
					_look(me.global_position + Vector3(0, 180, 0) + (me.global_position - home.global_position).normalized() * 160.0,
						(me.global_position + home.global_position) * 0.5)
					_shot("03_docked_at_arm")
				_w = t
		3:
			step = 4
			# gunfire through a rock: the rock takes it
			var rocks: Array = G.match_node.rocks
			report["rocks"] = rocks.size()
			if not rocks.is_empty():
				var rk: Array = rocks[0]
				var a: Vector3 = rk[0] + Vector3(rk[1] * 3.0, 0, 0)
				var b: Vector3 = rk[0] - Vector3(rk[1] * 3.0, 0, 0)
				report["rock_blocks_fire"] = G.match_node.SYSTEM.rock_hit(rocks, a, b) != Vector3.INF
				if out != "":
					_look(rk[0] + Vector3(rk[1] * 2.2, rk[1] * 0.8, rk[1] * 2.2), rk[0])
					_shot("04_asteroid")
			_report()


func _report() -> void:
	print("ODSTTEST ", report)
	var fails: Array = []
	if not report.get("station_refused", false):
		fails.append("drop pods fired at a station")
	if report.get("fired", 0) < 4 or report.get("fired_from_afar", 1) != 0:
		fails.append("drop pods didn't fire from over the drop zone (or fired from afar)")
	if report.get("landed", 0) < 3 or report.get("troopers_in_fort", 0) < 2:
		fails.append("troopers didn't land and get inside")
	if not report.get("docked", false):
		fails.append("ship didn't dock at a berth")
	if report.get("rocks", 0) > 0 and not report.get("rock_blocks_fire", false):
		fails.append("rocks don't stop gunfire")
	for f in fails:
		print("ODSTTEST FAIL: ", f)
	print("ODSTTEST RESULT: %s (%d problems)" % ["PASS" if fails.is_empty() else "FAIL", fails.size()])
	G.quit(0 if fails.is_empty() else 1)
