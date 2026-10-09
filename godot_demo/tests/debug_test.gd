extends Node
var t := 0.0
var step := 0
var me: Node
var them: Node
func _ready() -> void:
	Engine.time_scale = 4.0
	for v in G.vessels:
		if v.cls == "LARGE" and v.team == 1: me = v
		if v.cls == "LARGE" and v.team == 2: them = v
	G.match_node.ai.t = -100000.0
func _physics_process(dt: float) -> void:
	t += dt
	if step == 0 and t > 1.0:
		var br: Vector3 = them.capture_points[0]["pos"]
		print("DBG bridge cp ", br, " snapped ", them.snap_local(br), " zones ", them.zones.size())
		var ins: Vector3 = them.local_of(them.mark("BreachZone_1_Interior"))
		var pth: PackedVector3Array = them.path_local(them.snap_local(ins), them.snap_local(br))
		print("DBG path from breach ", ins, " len ", pth.size(), " end ", pth[pth.size()-1] if pth.size() else "-")
		for y in [0.0, 4.0]:
			for z in [-20.0, -40.0, -55.0, -60.0]:
				print("DBG snap (0,%s,%s) -> %s" % [y, z, them.snap_local(Vector3(0, y, z))])
		step = 1
		them.global_position = me.global_position + Vector3(600, 0, 0)
		them.shields = 0.0
		print("DBG launched ", me.launch_pods(them, 2), " entries ", them.boarding_entries(me.global_position).size())
	if step >= 1 and int(t) != int(t - dt):
		var b := 0
		var alive := 0
		for c in them.occupants:
			if c.team == 1:
				b += 1
				if c.state == "alive": alive += 1
		var ds := {}
		for c in them.occupants:
			ds[c.state + str(c.team)] = ds.get(c.state + str(c.team), 0) + 1
		print("DBG t=%d pods %d boarders aboard %d alive %d  states %s" % [t, G.pods.size(), b, alive, ds])
		var shown := 0
		for c in them.occupants:
			if shown < 6 and (c.team == 1 or c.role in ["security", "rifleman"]):
				shown += 1
				print("      vel %s floor %s working %s revive %.1f gear %.1f elev %s purging %s run %s p1 %s" % [c.velocity.snapped(Vector3(0.1,0.1,0.1)), c.is_on_floor(), c.working, c.revive_t, c.gear_t, c.elev, c.purging, c.run, c.path[c.path_i] if c.path_i < c.path.size() else "-"])
				if c.path_i < c.path.size():
					var wp: Vector3 = them.to_global(c.path[c.path_i])
					var h: Dictionary = G.ray(c.global_position + Vector3.UP * 0.9, wp + Vector3.UP * 0.6, [c.get_rid()], 1 | 4 | 2)
					if not h.is_empty():
						print("      BLOCKED BY ", h.collider.name, " / ", h.collider.get_parent().name, " layer ", h.collider.collision_layer, " at ", them.to_local(h.position).snapped(Vector3(0.1,0.1,0.1)))
				for k in c.get_slide_collision_count():
					var col: KinematicCollision3D = c.get_slide_collision(k)
					var o: Object = col.get_collider()
					print("      HIT ", o.name if o else "-", " / ", o.get_parent().name if o and o.get_parent() else "-", " layer ", o.get("collision_layer"), " normal ", col.get_normal().snapped(Vector3(0.01,0.01,0.01)))
				print("   %s %s pos %s path %d/%d goal %s tgt %s los %s mag %d alarm %.0f order %s" % [c.team, c.role, c.position.snapped(Vector3(0.1,0.1,0.1)), c.path_i, c.path.size(), c.goal.snapped(Vector3(0.1,0.1,0.1)) if c.goal != Vector3.INF else "-", c.target.role if c.target else "-", c.los, c.mag, them.alarm, c.order])
		for p in G.pods:
			print("   pod stage ", p.stage, " at ", p.global_position, " goal ", p.approach_m.global_position if p.stage == 0 else p.impact_m.global_position)
	if t > 40.0:
		G.quit()
