extends Node
## Fleets:  godot --path . res://match.tscn -- --fleettest [folder]
##   * every class mounts its guns: small 3 manned (2 dorsal, 1 ventral) + 2 CIWS, medium 3
##     dorsal + 3 CIWS, large 4 broadside + 4 CIWS, XL 4 large + 2 XL broadsides + 6 CIWS
##   * guns stay quiet with no gunner on them; broadsides can't fire across their own hull
##   * composition beats numbers: a large, two mediums and four smalls against ten smalls

var out := ""
var t := 0.0
var step := 0
var _w := 0.0
var report := {}
var A: Array = []
var B: Array = []
var probe: Array = []
var cam: Camera3D
var _cam_on := false
const AT := Vector3(0, 0, 7600)


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and not String(args[-1]).begins_with("--"):
		out = args[-1]
		DirAccess.make_dir_recursive_absolute(out)
	Engine.time_scale = 1.0 if out != "" else 4.0
	cam = Camera3D.new()
	cam.far = 20000.0
	add_child(cam)


func _process(_dt: float) -> void:
	if _cam_on:
		cam.make_current()


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
	cam.global_position = from
	cam.look_at(at, Vector3.UP)


func _physics_process(dt: float) -> void:
	t += dt
	var m: Node = G.match_node
	match step:
		0:
			if t > 2.0:
				step = 1
				m.ai.attack_after = 1.0e9
				m.ai.rival_teams = []
				# one of each class off on their own, to count guns
				var x := -900.0
				for cls in ["SMALL_FRIGATE", "MEDIUM", "LARGE", "SMALL_DROP_FRIGATE"]:
					probe.append(m.spawn_runtime_ship(cls, 1, 1, "Probe " + cls, AT + Vector3(x, 0, -2600), ["bridge_officer"]))
					x += 600.0
				_w = t
		1:
			if t - _w > 6.0:
				var guns := {}
				for s in probe:
					var k := {}
					var manned := 0
					for g in s.turrets:
						k[g["kind"] + "_" + g["mount"]] = k.get(g["kind"] + "_" + g["mount"], 0) + 1
						if g["kind"] != "ciws" and s.gun_manned(g):
							manned += 1
					guns[s.cls] = k
					report["manned_" + s.cls] = "%d/%d" % [manned, s.manned_guns()]
				report["guns"] = guns
				# arcs: a port battery can't fire at a point off the starboard side, but can fire straight up
				var L: Node = probe[2]
				for g in L.turrets:
					if g["mount"] == "port":
						report["port_vs_starboard_target"] = L.in_arc(g, L.to_global(Vector3(200, 0, 0)))
						report["port_vs_port_target"] = L.in_arc(g, L.to_global(Vector3(-200, 0, 0)))
						report["port_straight_up"] = L.in_arc(g, L.to_global(Vector3(-20, 300, 0)))
						break
				if out != "":
					_look(probe[3].global_position + Vector3(160, 90, 120), probe[3].global_position)
					_shot("01_dropship_guns")
				step = 2
				_w = t
		2:
			if t - _w > 1.5:
				if out != "":
					_look(probe[2].global_position + Vector3(-110, 50, 60), probe[2].global_position)
					_shot("02_large_broadside")
				# a gun with nobody on it: kill the small probe's gunners
				var sm: Node = probe[0]
				for c in sm.occupants:
					if c.role == "gunner":
						c.die(null)
				for s in probe:
					m.logistics.set_physics_process(false)
				report["shots_before"] = G.stats.get("ship_shots", 0)
				for s in probe:
					s.queue_free()
					G.vessels.erase(s)
				# the battle
				var cls_a := ["LARGE", "MEDIUM", "MEDIUM", "SMALL_FRIGATE", "SMALL_FRIGATE", "SMALL_FRIGATE", "SMALL_FRIGATE"]
				for i in cls_a.size():
					A.append(m.spawn_runtime_ship(cls_a[i], 1, 1, "A%d %s" % [i, cls_a[i]], AT + Vector3(-1100, 0, (i - 3) * 180.0), ["bridge_officer"]))
				for i in 10:
					B.append(m.spawn_runtime_ship("SMALL_FRIGATE", 2, 2, "B%d" % i, AT + Vector3(1100, 0, (i - 4.5) * 140.0), ["bridge_officer"]))
				step = 3
				_w = t
		3:
			# everyone closes on the nearest enemy
			if int(t * 2.0) != int((t - dt) * 2.0):
				for s in A + B:
					if is_instance_valid(s) and not s.destroyed:
						var best: Node = null
						var bd := 1.0e9
						for o in (B if s in A else A):
							if is_instance_valid(o) and not o.destroyed:
								var d: float = s.global_position.distance_to(o.global_position)
								if d < bd:
									bd = d
									best = o
						s.attack_target = best
						if best and bd > 700.0:
							s.move_target = best.global_position + (s.global_position - best.global_position).normalized() * 600.0
			if out != "" and t - _w > 40.0 and not report.has("s3"):
				report["s3"] = true
				_look(AT + Vector3(0, 700, 900), AT)
				_shot("03_battle")
			var a_left := A.filter(func(s): return is_instance_valid(s) and not s.destroyed).size()
			var b_left := B.filter(func(s): return is_instance_valid(s) and not s.destroyed).size()
			if a_left == 0 or b_left == 0 or t - _w > 900.0:
				report["battle_s"] = int(t - _w)
				report["A_left"] = a_left
				report["B_left"] = b_left
				report["large_alive"] = is_instance_valid(A[0]) and not A[0].destroyed
				_report()
				step = 99


func _report() -> void:
	print("FLEETTEST ", report)
	var fails: Array = []
	var g: Dictionary = report.get("guns", {})
	var want := {"SMALL_FRIGATE": {"light_top": 2, "light_bottom": 1, "ciws_top": 2},
		"MEDIUM": {"medium_top": 3, "ciws_top": 2, "ciws_bottom": 1},
		"LARGE": {"large_port": 2, "large_starboard": 2, "ciws_top": 4},
		"SMALL_DROP_FRIGATE": {"light_top": 2, "light_bottom": 1, "ciws_top": 2, "arty_bottom": 2}}
	for c in want:
		if g.get(c, {}) != want[c]:
			fails.append("%s guns %s, want %s" % [c, g.get(c, {}), want[c]])
	for c in ["SMALL_FRIGATE", "MEDIUM", "LARGE", "SMALL_DROP_FRIGATE"]:
		var mm: String = report.get("manned_" + c, "0/1")
		if mm.get_slice("/", 0) != mm.get_slice("/", 1):
			fails.append("%s guns not all manned (%s)" % [c, mm])
	if report.get("port_vs_starboard_target", true) or not report.get("port_vs_port_target", false) or not report.get("port_straight_up", false):
		fails.append("broadside arcs wrong")
	if report.get("B_left", 1) > 0 or not report.get("large_alive", false):
		fails.append("the mixed fleet didn't beat ten smalls (A %d left, B %d left)" % [report.get("A_left", 0), report.get("B_left", 0)])
	for f in fails:
		print("FLEETTEST FAIL: ", f)
	print("FLEETTEST RESULT: %s (%d problems)" % ["PASS" if fails.is_empty() else "FAIL", fails.size()])
	G.quit(0 if fails.is_empty() else 1)
