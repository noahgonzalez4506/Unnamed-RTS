extends Node
## Frame-time check in real time (no fast-forward):  godot --path . res://match.tscn -- --perf
## Forces a ship battle and a boarding fight, then reports CPU time per frame.
var t := 0.0
var proc: Array = []
var phys: Array = []
var started := false


func _ready() -> void:
	G.profiling = true
	var a: Node = null
	var b: Node = null
	for v in G.vessels:
		if v.cls == "LARGE":
			if v.team == 1: a = v
			else: b = v
	b.global_position = a.global_position + Vector3(700, 0, 0)
	a.attack_target = b
	b.attack_target = a
	a.shields = 0.0
	b.shields = 0.0
	a.request_fighters()
	b.request_fighters()
	await get_tree().create_timer(3.0).timeout
	a.launch_pods(b, 2)
	b.launch_pods(a, 2)
	started = true


func _process(dt: float) -> void:
	t += dt
	if started and t > 8.0:
		proc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		phys.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	if t > 48.0:
		proc.sort()
		phys.sort()
		var n := proc.size()
		print("PERF frames %d  process ms median %.1f p95 %.1f  |  physics ms median %.1f p95 %.1f  |  characters %d" % [n,
			proc[n / 2], proc[int(n * 0.95)], phys[n / 2], phys[int(n * 0.95)], G.characters.size()])
		var ks := G.stats.keys()
		ks.sort()
		for k in ks:
			if String(k).begins_with("us_"):
				print("PERF %-20s %.2f ms per frame" % [k, G.stats[k] / 1000.0 / float(Engine.get_physics_frames())])
		G.quit()
