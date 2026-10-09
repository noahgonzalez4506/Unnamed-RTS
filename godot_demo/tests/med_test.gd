extends Node
## Medical:  godot --path . res://match.tscn -- --medtest [folder]
##   * soldiers carry 4 revive pens, medics 8 and a revive gun with 8 shots
##   * with no pens anywhere aboard, a friend carries a downed soldier to a medbay bed,
##     and the bed brings them back
##   * a medic revives a downed soldier from range with the revive gun

var out := ""
var t := 0.0
var step := 0
var _w := 0.0
var report := {}
var ship: Node
var patient: Node
var carrier: Node
var medic: Node
var patient2: Node
var cam: Camera3D
var _cam_on := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and not String(args[-1]).begins_with("--"):
		out = args[-1]
		DirAccess.make_dir_recursive_absolute(out)
	Engine.time_scale = 1.0 if out != "" else 3.0
	for v in G.vessels:
		if v.get_meta("slot", "") == "flag1":
			ship = v
	cam = Camera3D.new()
	cam.far = 9000.0
	add_child(cam)


func _process(_dt: float) -> void:
	if _cam_on:
		cam.make_current()


func _shot(n: String, who: Node) -> void:
	if out == "" or who == null or not is_instance_valid(who):
		return
	_cam_on = true
	G.commander._help = false
	G.commander.hud.show_help(false)
	G.commander.interior_forced = 1
	G.commander.deck = int(round(who.position.y / 4.0))
	var p: Vector3 = who.global_position
	cam.global_position = p + ship.global_basis * Vector3(3.5, 7.0, 3.5)
	cam.look_at(p, Vector3.UP)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, n])
	print("SHOT ", n)


func _spot(name_: String, off: Vector3) -> Vector3:
	var m: Array = ship.marks_like(name_)
	var base: Vector3 = ship.local_of(m[0]) if not m.is_empty() else Vector3.ZERO
	return ship.snap_local(base + off)


func _physics_process(dt: float) -> void:
	t += dt
	match step:
		0:
			if t > 2.0:
				step = 1
				G.match_node.ai.attack_after = 99999.0
				# kit check
				var pens_ok := true
				var medic_ok := true
				for c in G.characters:
					if c.team != 1 or c.state != "alive":
						continue
					if c.role == "rifleman" and c.medpens.size() < 4:
						pens_ok = false
					if c.role == "medic" and (c.medpens.size() < 8 or c.revive_gun != 8):
						medic_ok = false
				report["soldiers_4_pens"] = pens_ok
				report["medics_8_pens_gun"] = medic_ok
				# nobody aboard has anything to revive with: the medbay is the only way
				for c in ship.occupants:
					if c.team == 1:
						c.medpens.clear()
						c.revive_kit = 0
						c.revive_gun = 0
				var p0 := _spot("Hangar_ShuttlePad", Vector3(4, 0, 0))
				patient = G.match_node.spawn_character(ship, p0, 1, 1, "rifleman")
				carrier = G.match_node.spawn_character(ship, ship.snap_local(p0 + Vector3(1.2, 0, 0)), 1, 1, "rifleman")
				patient.medpens.clear()
				carrier.medpens.clear()
				patient.go_down(null)
				report["beds"] = ship.marks_like("Medbay_*_Bed_*").size()
				_w = t
		1:
			if not report.has("hauled") and patient.carried_by != null:
				report["hauled"] = true
				report["hauled_after_s"] = snappedf(t - _w, 0.1)
			if report.has("hauled") and not report.has("s1") and t - _w > report["hauled_after_s"] + 2.0:
				report["s1"] = true
				_shot("01_carried_to_medbay", patient)
			if patient.on_bed and not report.has("s2"):
				report["s2"] = true
				report["on_bed"] = true
				_shot("02_on_the_medbay_bed", patient)
			if patient.state != "downed" or t - _w > 150.0:
				report["bed_revived"] = patient.state == "alive" and G.stats.get("revives_bed", 0) > 0
				report["bed_time_s"] = int(t - _w)
				step = 2
				# the revive gun: a medic 8 m from a downed soldier with a clear line
				var p1 := _spot("Hangar_ShuttlePad", Vector3(-4, 0, 0))
				patient2 = G.match_node.spawn_character(ship, p1, 1, 1, "rifleman")
				medic = G.match_node.spawn_character(ship, ship.snap_local(p1 + Vector3(0, 0, 8.0)), 1, 1, "medic")
				medic.medpens.clear()
				patient2.go_down(null)
				_w = t
		2:
			if medic.revive_t >= 0.0 and not report.has("s3"):
				report["s3"] = true
				report["gun_range_m"] = snappedf(medic.position.distance_to(patient2.position), 0.1)
				_shot("03_revive_gun", medic)
			if patient2.state != "downed" or t - _w > 30.0:
				report["gun_revived"] = patient2.state == "alive" and G.stats.get("revives_gun", 0) > 0
				report["gun_shots_left"] = medic.revive_gun
				_report()
				step = 3


func _report() -> void:
	print("MEDTEST ", report)
	var fails: Array = []
	if not report.get("soldiers_4_pens", false):
		fails.append("soldiers don't carry 4 pens")
	if not report.get("medics_8_pens_gun", false):
		fails.append("medics don't carry 8 pens and a revive gun")
	if not report.get("hauled", false):
		fails.append("nobody picked up the downed soldier")
	if not report.get("bed_revived", false):
		fails.append("the medbay bed didn't revive them")
	if not report.get("gun_revived", false) or report.get("gun_range_m", 0.0) < 3.0:
		fails.append("the medic didn't use the revive gun from range")
	for f in fails:
		print("MEDTEST FAIL: ", f)
	print("MEDTEST RESULT: %s (%d problems)" % ["PASS" if fails.is_empty() else "FAIL", fails.size()])
	G.quit(0 if fails.is_empty() else 1)
