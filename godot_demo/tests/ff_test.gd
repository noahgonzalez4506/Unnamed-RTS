extends Node
## Friendly-fire safety:  godot --headless --path . res://match.tscn -- --fftest
## In the team 1 flagship's hangar: a friend standing where a frag lands gets out of the blast,
## one walking toward it holds short until it has gone off, nobody friendly is hurt; throws
## are refused with a friend in the blast; an AI holds fire with a friend in its line and fires
## once the line is clear; a squadmate on the move goes round behind a shooter; squad slots
## see a shooter's line of fire. Prints PASS/FAIL lines and "FF TEST DONE <fails>".

var t := 0.0
var step := 0
var fails := 0
var _wait := 0.0
var v: Node
var base := Vector3.ZERO
var a: Node                       # stands where the frag lands
var b: Node                       # throws it
var w: Node                       # walking toward it
var gren: Node3D
var w_goal := Vector3.ZERO


func _check(ok: bool, what: String) -> void:
	print("PASS " if ok else "FAIL ", what)
	if not ok:
		fails += 1


func _spawn(team: int, at: Vector3, role: String = "rifleman") -> Node:
	var c: Node = G.match_node.spawn_character(v, v.snap_local(base + at), team, G.team_fac(team), role)
	c.rotation.y = 0.0
	c.order = {"type": "hold", "pos": c.position, "vessel": v}
	return c


func _physics_process(dt: float) -> void:
	t += dt
	if t < 2.0:
		return
	if _wait > 0.0:
		_wait -= dt
		return
	match step:
		0:
			for vv in G.vessels:
				if vv.get_meta("slot", "") == "flag1":
					v = vv
			var pads: Array = v.marks_like("Hangar_ShuttlePad") if v else []
			_check(not pads.is_empty(), "the flagship has a hangar")
			if pads.is_empty():
				_done()
				return
			base = v.local_of(pads[0])
			G.match_node.ai.attack_after = 99999.0
			a = _spawn(v.team, Vector3(0, 0, 9))
			b = _spawn(v.team, Vector3(0, 0, 17))
			w = _spawn(v.team, Vector3(0, 0, 1))
			w_goal = v.snap_local(base + Vector3(0, 0, 16))
			_check(b._friend_in_blast(a.global_position, 6.0), "a throw at a friend's feet is refused")
			_check(not b._friend_in_blast(v.to_global(base + Vector3(0, 400, 0)), 6.0), "a throw with nobody near is allowed")
			b.grenades = ["test_frag"]
			b._throw_grenade(a.global_position)
			for gn in get_tree().root.get_children():
				if gn.get_script() == preload("res://scripts/grenade.gd"):
					gren = gn
			_check(gren != null and gren in G.dangers, "the live frag is registered as a danger")
			w.order = {"type": "move", "pos": w_goal, "vessel": v}
			step = 1
			_wait = 1.6
		1:
			# 1.6 s into a 2.6 s fuse (2.0 for faction 2): the friend has left, the walker held
			var gp: Vector3 = gren.danger_point() if is_instance_valid(gren) else Vector3.INF
			_check(gp != Vector3.INF and a.global_position.distance_to(gp) > 5.0,
				"the friend got out of the blast (%.1f m from the frag)" % (a.global_position.distance_to(gp) if gp != Vector3.INF else -1.0))
			_check(gp != Vector3.INF and w.global_position.distance_to(gp) > 5.0,
				"the walker held short of it (%.1f m)" % (w.global_position.distance_to(gp) if gp != Vector3.INF else -1.0))
			step = 2
			_wait = 1.6
		2:
			_check(not is_instance_valid(gren), "the frag has gone off")
			_check(a.hp >= a.max_hp - 0.1 and w.hp >= w.max_hp - 0.1 and b.hp >= b.max_hp - 0.1, "no friend was hurt")
			_check(G.dangers.is_empty(), "nothing is left in the danger list")
			step = 3
			_wait = 3.5
		3:
			_check(w.position.distance_to(w_goal) < w.position.distance_to(v.snap_local(base + Vector3(0, 0, 1))),
				"the walker carried on once it had gone off")
			# line of fire: a shooter, a hostile 10 m off, a friend half way between them
			for c in [a, b, w]:
				c.order = {"type": "hold", "pos": c.position, "vessel": v}
			var s: Node = _spawn(v.team, Vector3(4, 0, 2))
			var e: Node = _spawn(2 if v.team != 2 else 1, Vector3(4, 0, 12))
			e.max_hp = 99999.0
			e.hp = 99999.0
			var f: Node = _spawn(v.team, Vector3(4, 0, 7))
			f.position = v.snap_local(s.position.lerp(e.position, 0.5))
			_check(s._friend_in_line(s.eye(), e.chest()), "a friend between the shooter and the target blocks the line")
			s.target = e
			s.los = true
			s.fire_t = 0.0
			s.reload_t = -1.0
			s.crouch = false
			var m0: int = s.mag
			s._ai_fire(0.016)
			_check(s.mag == m0, "the AI held fire with a friend in the way")
			# a squadmate on the move across that line goes round behind the shooter
			var mover: Node = _spawn(v.team, Vector3(1, 0, 7))
			mover.go(v.snap_local(base + Vector3(7, 0, 7)), false)
			var fd: Vector3 = e.position - s.position
			fd.y = 0.0
			var behind: Vector3 = v.snap_local(s.position - fd.normalized() * 1.3)
			mover._pass_behind_shooters()
			var detoured := false
			for k in range(mover.path_i, mover.path.size()):
				detoured = detoured or (mover.path[k] as Vector3).distance_to(behind) < 0.8
			_check(detoured,
				"a squadmate crossing the shooter's line detours behind them")
			var sq: RefCounted = G.match_node.new_squad(v.team, v)
			sq.add(s)
			sq.add(mover)
			_check(sq.in_fire_line(s.position.lerp(e.position, 0.3), mover), "squad slots see the shooter's line of fire")
			_check(not sq.in_fire_line(s.position + Vector3(0, 0, -3), mover), "...and nothing behind the shooter")
			# with the friend out of the line, the shot goes
			f.position = v.snap_local(f.position + Vector3(3, 0, 0))
			s.fire_t = 0.0
			s.los = true
			s.target = e
			s._ai_fire(0.016)
			_check(s.mag < m0 or s._friend_in_line(s.eye(), e.chest()), "with the line clear, the AI fires")
			_done()


func _done() -> void:
	print("FF TEST DONE %d" % fails)
	set_physics_process(false)
	G.quit()
