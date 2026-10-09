extends Node
## Riding in a boarding pod:  godot --headless --path . res://match.tscn -- --ridetest
## Two soldiers ride a pod from the team 1 flagship to the rival flagship: in flight they're
## shown, seated in the pod's seats and riding along with it; after the breach they're out on
## their feet inside the target. Prints PASS/FAIL lines and "RIDE TEST DONE <fails>".

var t := 0.0
var step := 0
var fails := 0
var _wait := 0.0
var home: Node
var target: Node
var riders: Array = []
var pod: Node3D
var _flight := 0.0


func _check(ok: bool, what: String) -> void:
	print("PASS " if ok else "FAIL ", what)
	if not ok:
		fails += 1


func _physics_process(dt: float) -> void:
	t += dt
	if t < 2.5:
		return
	if _wait > 0.0:
		_wait -= dt
		return
	match step:
		0:
			for v in G.vessels:
				if v.get_meta("slot", "") == "flag1":
					home = v
				elif v.get_meta("slot", "") == "flag2":
					target = v
			_check(home != null and target != null, "both flagships are here")
			if home == null or target == null:
				_done()
				return
			G.match_node.ai.attack_after = 99999.0
			target.global_position = home.global_position + Vector3(600, 0, 0)    # in pod range
			for k in 2:
				var c: Node = G.match_node.spawn_character(home, home.random_local(), home.team, G.team_fac(home.team), "rifleman")
				riders.append(c)
			step = 1
			_wait = 0.5
		1:
			var n: int = home.launch_pods(target, 1, riders)
			_check(n == 1, "a pod launched with the two riders")
			for p in G.pods:
				if is_instance_valid(p) and p.get("riders") != null and riders[0] in p.riders:
					pod = p
			_check(pod != null and riders.all(func(r): return r.riding == pod), "both riders are aboard it")
			step = 2
			_wait = 1.5
		2:
			if not is_instance_valid(pod) or pod.stage >= 2:
				_check(false, "caught the pod in flight")
				step = 3
				return
			var seated := 0
			for r in riders:
				var seat: Node3D = r.ride_seat
				if seat != null and is_instance_valid(seat) and r.visible and r.rig.visible \
						and r.global_position.distance_to(seat.global_position) < 0.7:
					seated += 1
			_check(seated == 2, "in flight both are shown, seated in their seats (%d)" % seated)
			_check(riders[0].ride_seat != riders[1].ride_seat, "...in different seats")
			_check(riders[0].rig.mode == "seated", "...in the seated pose")
			_check(riders[0].global_position.distance_to(pod.global_position) < 5.0, "...riding along with the pod")
			step = 3
		3:
			_flight += dt
			if _flight < 40.0 and riders.any(func(r): return is_instance_valid(r) and r.riding != null):
				return
			var out := 0
			for r in riders:
				if is_instance_valid(r) and r.state != "dead" and r.riding == null and r.vessel == target and r.ride_seat == null:
					out += 1
			_check(out == 2, "after the breach both are out, aboard the target (%d)" % out)
			_check(riders.all(func(r): return absf(r.rotation.x) < 0.01 and absf(r.rotation.z) < 0.01), "...standing upright")
			_done()


func _done() -> void:
	print("RIDE TEST DONE %d" % fails)
	set_physics_process(false)
	G.quit()
