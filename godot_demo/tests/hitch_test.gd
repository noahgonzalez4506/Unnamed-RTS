extends Node
## Recovery after a long frame (what alt-tabbing back in looks like to the engine):
##   godot --headless --path . res://match.tscn -- --hitchtest
## Measures frames and physics steps per second for 4 s, stalls one frame for 4 s, lets a
## second pass, then measures again. Passes when the frame rate comes back to at least 60 %
## of what it was and physics isn't stuck running the maximum steps every frame.
## Prints "HITCH TEST DONE <fails>".

var t := 0.0
var phase := 0
var fails := 0
var us0 := 0
var f0 := 0
var p0 := 0
var fps_a := 0.0


func _check(ok: bool, what: String) -> void:
	print("PASS " if ok else "FAIL ", what)
	if not ok:
		fails += 1


func _measure_start() -> void:
	us0 = Time.get_ticks_usec()
	f0 = Engine.get_process_frames()
	p0 = Engine.get_physics_frames()


func _measure() -> Array:
	var s: float = (Time.get_ticks_usec() - us0) / 1e6
	var frames: int = Engine.get_process_frames() - f0
	var steps: int = Engine.get_physics_frames() - p0
	return [frames / s, steps / maxf(1.0, float(frames)), s]


func _process(dt: float) -> void:
	t += dt
	match phase:
		0:
			if t > 6.0:
				_measure_start()
				phase = 1
		1:
			if (Time.get_ticks_usec() - us0) > 4_000_000:
				var m := _measure()
				fps_a = m[0]
				print("HITCH before: %.1f fps, %.2f physics steps a frame" % [m[0], m[1]])
				print("HITCH stalling 4 s ...")
				OS.delay_msec(4000)
				phase = 2
				t = 0.0
		2:
			if t > 1.0:
				_measure_start()
				phase = 3
		3:
			if (Time.get_ticks_usec() - us0) > 4_000_000:
				var m2 := _measure()
				print("HITCH after:  %.1f fps, %.2f physics steps a frame (max %d)" % [m2[0], m2[1], Engine.max_physics_steps_per_frame])
				_check(m2[0] >= fps_a * 0.6, "the frame rate recovered (%.1f of %.1f fps)" % [m2[0], fps_a])
				_check(m2[1] < float(Engine.max_physics_steps_per_frame) * 0.9, "physics isn't stuck at the step cap")
				_check(Engine.max_physics_steps_per_frame <= 3, "physics catch-up is capped (%d steps a frame)" % Engine.max_physics_steps_per_frame)
				print("HITCH TEST DONE %d" % fails)
				set_process(false)
				G.quit()
