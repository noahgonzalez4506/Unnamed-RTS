extends Node
## The grenadier:  godot --headless --path . res://match.tscn -- --grenadiertest
## With a folder after the flag (rendering, not --headless) it also saves a picture of the
## breaching round drilling into the wall.
## Kit and gun, a launcher shell into a target 15 m off, a dud at point-blank range, the AI's
## choice to fire (a group, yes; a friend near the target, no), a breaching round through a weak
## wall, a miss that hands the target back, and who a squad picks to breach. Prints PASS/FAIL
## lines and "GRENADIER TEST DONE <fails>".

var t := 0.0
var step := 0
var fails := 0
var c: Node
var foe: Node
var foe2: Node
var shell: Node3D
var _wait := 0.0
var _hp0 := 0.0
var wall := {}
var fake := {}
var out := ""
var _view := {}                   # {from, at}: where the drill picture's camera goes (see _process)
var _g2: Node = null
var _floor_round: Node3D = null
var _floor_t := 0.0


func _ready() -> void:
	process_priority = 1000                      # after the commander has placed its camera
	var args := OS.get_cmdline_user_args()
	if args.size() > 1 and not String(args[-1]).begins_with("--"):
		out = args[-1]
		DirAccess.make_dir_recursive_absolute(out)


func _check(ok: bool, what: String) -> void:
	print("PASS " if ok else "FAIL ", what)
	if not ok:
		fails += 1


func _physics_process(dt: float) -> void:
	t += dt
	if t < 2.0:
		return
	if _wait > 0.0:
		_wait -= dt
		return
	match step:
		0:
			var n := 0
			for o in G.characters:
				if is_instance_valid(o) and o.role == "grenadier":
					n += 1
			_check(n > 0, "the match spawned grenadiers (%d)" % n)
			# a fresh one in the team 1 flagship's hangar, a hostile 15 m down it
			var v: Node = null
			for vv in G.vessels:
				if vv.get_meta("slot", "") == "flag1":
					v = vv
			var pads: Array = v.marks_like("Hangar_ShuttlePad") if v else []
			_check(not pads.is_empty(), "the flagship has a hangar")
			if pads.is_empty():
				_done()
				return
			var base: Vector3 = v.local_of(pads[0])
			c = G.match_node.spawn_character(v, v.snap_local(base + Vector3(0, 0, 9)), v.team, G.team_fac(v.team), "grenadier")
			c.rotation.y = 0.0
			c.order = {"type": "hold", "pos": c.position, "vessel": v}
			G.match_node.ai.attack_after = 99999.0
			_check(c.weapon_model == ("F2_BullpupGL" if c.faction == 2 else "F1_BullpupGL"), "carries the BullpupGL (%s)" % c.weapon_model)
			_check(c.spare.size() == 4 and c.medpens.size() >= 1, "4 spare mags (%d), a medpen" % c.spare.size())
			_check(c.gl_ammo == 6 and c.gl_rounds.size() == 6, "6 shells on the belt")
			_check(c.breach_ammo == 2 and c.breach_rounds.size() == 2, "2 breaching rounds on the hips")
			_check(c.rig.weapon != null and c.rig.weapon.find_child("GLMuzzle", true, false) != null, "the gun has a GLMuzzle")
			foe = G.match_node.spawn_character(v, v.snap_local(base + Vector3(0, 0, -6)), 2, 2, "rifleman")
			foe.rotation.y = 0.0
			foe.order = {"type": "hold", "pos": foe.position, "vessel": c.vessel}
			step = 1
			_wait = 0.5
		1:
			_hp0 = foe.hp
			var from: Vector3 = c._gl_muzzle()
			var dir: Vector3 = c._lob(from, foe.global_position + Vector3.UP * 0.3, 50.0)
			_check(dir != Vector3.ZERO, "a firing solution to 15 m")
			shell = c.fire_launcher(from, dir)
			_check(shell != null and c.gl_ammo == 5, "fired: 5 shells left")
			var shown := 0
			for n in c.gl_rounds:
				shown += 1 if (n as Node3D).visible else 0
			_check(shown == 5, "the belt shows 5 shells (%d)" % shown)
			step = 2
			_wait = 1.2
		2:
			_check(not is_instance_valid(shell), "the shell burst")
			_check(foe.hp < _hp0 or foe.state != "alive", "the target was hurt (%.0f -> %.0f, %s)" % [_hp0, foe.hp, foe.state])
			# point-blank: into the floor a metre ahead, before it arms
			var from2: Vector3 = c.eye()
			var fwd: Vector3 = -c.global_transform.basis.z
			shell = c.fire_launcher(from2, (fwd + Vector3.DOWN * 1.2).normalized())
			step = 3
			_wait = 0.3
		3:
			_check(is_instance_valid(shell) and shell.dud, "a shell that hits within 4 m is a dud")
			# AI: two hostiles together 18 m off -> fires
			for o in [foe]:
				if is_instance_valid(o) and o.state == "alive":
					o.hp = o.max_hp
			if not is_instance_valid(foe) or foe.state != "alive":
				var base: Vector3 = c.vessel.local_of(c.vessel.marks_like("Hangar_ShuttlePad")[0])
				foe = G.match_node.spawn_character(c.vessel, c.vessel.snap_local(base + Vector3(0, 0, -9)), 2, 2, "rifleman")
			foe2 = G.match_node.spawn_character(c.vessel, foe.position + Vector3(1.5, 0, 0), 2, 2, "rifleman")
			for o in [foe, foe2]:
				o.order = {"type": "hold", "pos": o.position, "vessel": c.vessel}
			# square up to them and let the pose settle (the grenadier's own brain may have shuffled it)
			c.position = c.order["pos"]
			c.crouch = false
			c.target = foe
			var to_f: Vector3 = foe.position - c.position
			c.rotation.y = atan2(-to_f.x, -to_f.z)
			step = 31
			_wait = 0.4
		31:
			c._gl_cd = 0.0
			c.target = foe
			var n0: int = c.gl_ammo
			var fired: bool = c._ai_launcher() and c.gl_ammo == n0 - 1
			_check(fired, "AI fires into a group of two (%.1f m)" % c.global_position.distance_to(foe.global_position))
			if not fired:
				for o in G.characters:
					if is_instance_valid(o) and o.state == "alive" and o.global_position.distance_to(foe.global_position) < 4.5:
						print("   near the target: %s team %d %.1f m" % [o.display, o.team, o.global_position.distance_to(foe.global_position)])
				print("   cd %.1f ammo %d target %s %s" % [c._gl_cd, c.gl_ammo, foe.state, foe.get("in_cover")])
				var fr: Vector3 = c._gl_muzzle()
				var dr: Vector3 = c._lob(fr, foe.global_position + Vector3.UP * 0.3, 50.0)
				var h: Dictionary = G.ray(fr, fr + dr * 3.0, [c.get_rid()], G.LAYER_WORLD | G.LAYER_DOOR)
				print("   muzzle %s (eye %s) dir %s blocked by %s at %s; me at %s crouch %s" % [fr, c.eye(), dr,
					(h["collider"] as Node).name if not h.is_empty() else "-", h.get("position", "-"), c.position, c.crouch])
			# a friend beside the target -> holds
			var pal: Node = G.match_node.spawn_character(c.vessel, foe.position + Vector3(-1.5, 0, 0), 1, c.faction, "rifleman")
			c._gl_cd = 0.0
			_check(not c._ai_launcher(), "AI holds fire with a friend near the target")
			pal.state = "dead"
			# too close -> holds
			c._gl_cd = 0.0
			foe2.state = "dead"
			c.target = foe
			var save: Vector3 = c.position
			c.position = foe.position + Vector3(0, 0, 4)
			_check(not c._ai_launcher(), "AI holds fire under 8 m")
			c.position = save
			step = 4
		4:
			# a breaching round through a weak (hazard-striped) wall, fired the way the AI does
			var g2: Node = null
			for v in G.vessels:
				if not is_instance_valid(v) or not v.get("breach_walls") is Array:
					continue
				for d in v.breach_walls:
					if d["breached"] or d.get("charged", false):
						continue
					var sides: Array = v.wall_sides(d, (d["center"] as Vector3) + (d["n"] as Vector3))
					for sd in sides:
						var away: Vector3 = (sd as Vector3) - (d["center"] as Vector3)
						away.y = 0.0
						away = away.normalized()
						for k in [5.0, 3.5, 2.0]:
							var p: Vector3 = v.snap_local((sd as Vector3) + away * k)
							if g2 == null:
								g2 = G.match_node.spawn_character(v, p, 1, 1, "grenadier")
							elif g2.vessel != v:
								continue
							g2.position = p
							g2.order = {"type": "hold", "pos": p, "vessel": v}
							if g2._breach_shot(d):
								wall = d
								break
						if not wall.is_empty():
							break
					if not wall.is_empty():
						break
				if not wall.is_empty() or g2 != null:
					break                                 # g2 lives on the first ship with weak walls
			if wall.is_empty():
				print("SKIP no weak wall with a clear shot from 2-5 m")
				step = 7
			else:
				_check(wall.get("charged", false) and g2.breach_ammo == 1, "AI fired a breaching round at a weak wall (1 left)")
				var shown := 0
				for n in g2.breach_rounds:
					shown += 1 if (n as Node3D).visible else 0
				_check(shown == 1, "one round left on the hips (%d)" % shown)
				# a player's round goes for what's in the crosshair: aimed at this wall, that's its target
				var gm: Vector3 = g2._gl_muzzle()
				var wc: Vector3 = wall_vessel().to_global(wall["center"])
				_check(is_same(g2._breach_target_along(gm, (wc - gm).normalized()), wall), "a player's round targets the wall in the crosshair")
				step = 5
				_wait = 0.55
				_g2 = g2
				if out != "":
					G.commander.possess(g2)          # first person: no interior cutaway, a camera we can move
		5:
			# mid-drill: the round stuck in the wall, crown spinning
			var rnd: Node3D = null
			for n in wall_vessel().get_children():
				if n.get_script() == c.BREACH_ROUND:
					rnd = n
			_check(rnd != null and rnd.stuck, "the round stuck in the wall and rides with the ship")
			step = 6                                      # before the awaits below, so this runs once
			_wait = 1.3
			if rnd != null and out != "":
				var n_: Vector3 = wall_vessel().global_basis * (wall["n"] as Vector3)
				var back: Vector3 = -rnd.model.global_basis.z         # toward whoever fired it
				_view = {"from": rnd.global_position + back * 0.55 + n_.cross(Vector3.UP).normalized() * 0.3 + Vector3.UP * 0.12,
					"at": rnd.global_position}
				G.commander.hud.visible = false
				for k in 3:
					await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(out + "/breach_round_drilling.png")
				print("SHOT breach_round_drilling")
		6:
			_check(wall["breached"], "the wall was breached")
			if out != "":
				_view = {}
				G.commander.hud.visible = true
				G.commander.release()
			step = 7
		7:
			# a round into the bare hangar floor: no door or wall in reach -> small blast, target freed
			fake = {"breached": false, "charged": true, "center": Vector3(0, -999, 0), "kind": "door", "n": Vector3.FORWARD}
			c.breach_ammo = 2
			var r: Node3D = c.fire_breach_round(c.eye(), (-c.global_transform.basis.z + Vector3.DOWN * 0.5).normalized(), fake)
			_check(r != null and c.breach_ammo == 1, "fired a breaching round at the floor")
			_floor_round = r
			_floor_t = 0.0
			step = 8
			_wait = 1.8
		8:
			# (it fails when it goes off on the floor, or after 3 s in the air if it missed)
			_floor_t += dt
			if is_instance_valid(_floor_round) and _floor_t < 4.0:
				return
			_check(fake["charged"] == false, "a round that breaches nothing hands its target back")
			# who breaches a heavy door: a charge carrier, else the grenadier, else nobody
			var v2: Node = c.vessel
			var sq: RefCounted = G.match_node.new_squad(1, v2)
			var mk := func(role: String) -> Node:
				var m: Node = G.match_node.spawn_character(v2, c.position + Vector3(randf_range(-2, 2), 0, 2), 1, c.faction, role)
				sq.add(m)
				return m
			var _sl: Node = mk.call("squad_leader")
			var br: Node = mk.call("breacher")
			var gr: Node = mk.call("grenadier")
			sq.stack_door = {"kind": "heavy", "center": c.position + Vector3(0, 1.3, -5), "breached": false, "n": Vector3.BACK}
			_check(sq.stack_breacher() == br, "a breacher with charges breaches a heavy door")
			br.charges.clear()
			sq.stack_door.erase("breacher")
			_check(sq.stack_breacher() == gr, "without charges, the grenadier does (breaching round)")
			gr.breach_ammo = 0
			sq.stack_door.erase("breacher")
			_check(sq.stack_breacher() == null, "with neither, nobody")
			G.match_node.squads.erase(sq)
			_done()


func _process(_dt: float) -> void:
	if _view.is_empty():
		return
	var cam_: Camera3D = G.commander.fps_cam
	G.commander.viewmodel.visible = false
	cam_.fov = 45.0
	cam_.look_at_from_position(_view["from"], _view["at"])


func wall_vessel() -> Node:
	for v in G.vessels:
		if is_instance_valid(v) and v.get("breach_walls") is Array and (v.breach_walls as Array).has(wall):
			return v
	return null


func _done() -> void:
	print("GRENADIER TEST DONE %d" % fails)
	set_physics_process(false)
	G.quit()
