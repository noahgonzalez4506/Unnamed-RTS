extends Node
## Pods and breaching:  godot --path . res://match.tscn -- --breachtest [folder]
## Fires two pods at the enemy flagship, checks they fly nose-first, then measures how
## spread out the boarders are once they're aboard (no lumps of robots in one spot).

var out := ""
var t := 0.0
var step := 0
var me: Node
var them: Node
var pod: Node3D
var cam: Camera3D
var report := {"nose_err_deg": 0.0, "samples": 0}
var _wait := 0.0
var _crowd: Array = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and not String(args[-1]).begins_with("--"):
		out = args[-1]
		DirAccess.make_dir_recursive_absolute(out)
	for v in G.vessels:
		if v.get_meta("slot", "") == "flag1":
			me = v
		elif v.get_meta("slot", "") == "flag2":
			them = v
	cam = Camera3D.new()
	add_child(cam)
	G.commander.hud.visible = out == ""


func _shot(n: String) -> void:
	if out == "":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, n])
	print("SHOT ", n)


func _process(dt: float) -> void:
	t += dt
	if step >= 1:
		cam.make_current()
	if pod and is_instance_valid(pod) and pod.stage < 2:
		# nose (-Z) vs flight direction
		if pod.vel.length() > 1.0:
			var nose: Vector3 = -pod.global_basis.z
			var err := rad_to_deg(nose.angle_to(pod.vel.normalized()))
			if err > 20.0 and not report.has("bad_sample"):
				report["bad_sample"] = "stage %d age %.2f vel %s nose %s" % [pod.stage, pod._age, pod.vel, nose]
			report["nose_err_deg"] = max(report["nose_err_deg"], err)
			report["samples"] += 1
		cam.current = true
		var back: Vector3 = pod.global_basis.z * 16.0 + pod.global_basis.x * 7.0 + Vector3.UP * 4.0
		cam.global_position = pod.global_position + back
		cam.look_at(pod.global_position - pod.global_basis.z * 6.0, Vector3.UP)
	match step:
		0:
			if t > 1.5:
				step = 1
				them.global_position = me.global_position + me.global_basis.x * 700.0
				them.rotation.y = me.rotation.y + 0.4
				them.move_target = Vector3.INF
				me.move_target = Vector3.INF
				them.attack_target = null
				me.attack_target = null
				them.shields = 0.0
				me.troops = 24
				var n0 := G.pods.size()
				report["launched"] = me.launch_pods(them, 2)
				if G.pods.size() > n0:
					pod = G.pods[-1]
				_wait = t
		1:
			if t - _wait > 2.0 and not report.has("shot1"):
				report["shot1"] = true
				_shot("pod_flight")
			if pod == null or not is_instance_valid(pod) or pod.stage >= 2:
				step = 2
				_wait = t
				if pod and is_instance_valid(pod):
					var cp: Vector3 = pod.global_position + pod.global_basis.z * 14.0 + Vector3.UP * 5.0
					cam.global_position = cp
					cam.look_at(pod.global_position, Vector3.UP)
					_shot("pod_impact")
		2:
			if t - _wait > 2.5 and not report.has("shot3"):
				report["shot3"] = true
				var sq: Array = them.occupants.filter(func(c): return c.team == 1 and c.state == "alive")
				if not sq.is_empty():
					var c0: Node = sq[0]
					G.set_cut(c0.global_position.y + 2.6)
					cam.global_position = c0.global_position + Vector3.UP * 14.0 + them.global_basis.z * 6.0
					cam.look_at(c0.global_position, Vector3.UP)
					_shot("boarders_out")
			if t - _wait > 2.0 and t - _wait < 14.0:
				_crowd.append(_min_spacing())
				if _crowd[-1][1] >= 3 and not report.has("dumped"):
					report["dumped"] = t - _wait
					_dump()
			if t - _wait > 14.0:
				_report()


## The closest any two boarders stand to each other right now, and how many pairs are under 0.6 m.
func _min_spacing() -> Array:
	var b: Array = them.occupants.filter(func(c): return c.team == 1 and c.state == "alive")
	var tight := 0
	var mn := 99.0
	for i in b.size():
		for j in range(i + 1, b.size()):
			var d: Vector3 = b[i].position - b[j].position
			if absf(d.y) > 1.5:
				continue
			d.y = 0.0
			mn = min(mn, d.length())
			# a clump: two robots standing still (not filing past each other) within 0.6 m
			if d.length() < 0.6 and b[i].velocity.length() < 0.6 and b[j].velocity.length() < 0.6:
				tight += 1
	return [mn, tight, b.size()]


func _dump() -> void:
	var b: Array = them.occupants.filter(func(c): return c.team == 1 and c.state == "alive")
	for c in b:
		var near := 0
		for o in b:
			if o != c and absf(o.position.y - c.position.y) < 1.5 and Vector2(o.position.x - c.position.x, o.position.z - c.position.z).length() < 0.6:
				near += 1
		var dd: Dictionary = c.vessel.door_blocking(c.position, Vector3.ZERO, 2.5)
		print("BREACHDBG door=%s %s %s pos=%s goal=%s path=%d/%d sep=%s near=%d stack=%s order=%s leader=%s" % [dd.get("name", "-") + "/" + str(dd.get("kind", "")), c.display, c.role, c.position, c.goal, c.path_i, c.path.size(), c._sep, near,
			not c.squad.stack_door.is_empty() if c.squad else false, c.order, c.squad.leader == c if c.squad else false])


func _report() -> void:
	var worst := 0
	var avg_tight := 0.0
	for c in _crowd:
		worst = max(worst, c[1])
		avg_tight += c[1]
	avg_tight /= max(1, _crowd.size())
	report["boarders"] = _crowd[-1][2] if not _crowd.is_empty() else 0
	report["pairs_under_0.6m_avg"] = snappedf(avg_tight, 0.01)
	report["pairs_under_0.6m_worst"] = worst
	print("BREACHTEST ", report)
	var ok: bool = report.get("launched", 0) > 0 and report["nose_err_deg"] < 20.0 and avg_tight < 1.0 and report["boarders"] > 0
	print("BREACHTEST RESULT: ", "PASS" if ok else "FAIL")
	G.quit(0 if ok else 1)
