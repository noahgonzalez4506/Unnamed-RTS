extends Node
## Vacuum, airlocks and EVA:  godot --headless --path . res://match.tscn -- --evatest
##  A  a hull breach vents the compartment behind it: air drains, loose people are pulled toward
##     the hole, suit air runs down and then it's suffocation; the engineers get a job to patch
##     it, and once patched the compartment repressurises.
##  B  the player cycles out of an airlock onto the hull, thrusts around in zero g (no gravity),
##     then cuts in through an enemy hull and is aboard.
##  C  a ship sends an EVA team across to an adjacent hull: real troopers, out in the open in
##     formation, who cut in and board.
## Prints PASS/FAIL lines and "EVA TEST DONE <fails>".

var t := 0.0
var step := 0
var fails := 0
var _wait := 0.0
var home: Node
var target: Node
var entry: Array = []
var zi := -1
var crew: Node
var soldier: Node
var hp0 := 0.0
var job: Dictionary = {}
var air_low := 0.0
var player: Node
var y0 := 0.0
var team_node: Node3D
var riders: Array = []
var open0 := 0
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
			# hulls 120 m apart: in EVA range
			target.global_position = home.global_position + Vector3(2000, 0, 0)
			target.global_position.x -= home.hull_gap(target) - 120.0
			_check(absf(home.hull_gap(target) - 120.0) < 30.0, "hulls placed about 120 m apart (%d m)" % int(home.hull_gap(target)))
			entry = target.boarding_entries(home.global_position)[0]
			var inside: Vector3 = target.snap_local(target.to_local((entry[2] as Node3D).global_position))
			zi = target.zone_index_near(inside)
			_check(zi >= 0, "the way in has a compartment behind it")
			crew = G.match_node.spawn_character(target, inside, target.team, G.team_fac(target.team), "cargo_handler")
			soldier = G.match_node.spawn_character(target, inside + Vector3(1.0, 0, 0), target.team, G.team_fac(target.team), "rifleman")
			_check(not crew.suited() and crew.suit_air > 40.0, "crew aren't in vacuum suits (%d s of air)" % int(crew.suit_air))
			step = 1
			_wait = 0.5
		1:
			# ---- A: a hole in the hull
			target.breach(entry[3])
			_check(target.openings.size() == 1 and int(target.openings[0]["zone"]) == zi, "the breach opened the hull into that compartment")
			step = 2
			_wait = 0.7
		2:
			var air: float = float(target.zones[zi].get("air", 1.0))
			_check(air < 0.9, "...it's venting (air %.2f)" % air)
			var pulled := 0
			for c in target.occupants:
				if is_instance_valid(c) and c.vent_push != Vector3.ZERO:
					pulled += 1
			_check(pulled > 0, "...and pulling loose people toward the hole (%d)" % pulled)
			for j in target.repairs:
				if j.has("seal"):
					job = j
			_check(not job.is_empty(), "...and the engineers have a job to patch it")
			step = 3
			_wait = 0.6
		3:
			soldier.suit_air = 0.4
			soldier._vac_at = G.time
			hp0 = soldier.hp
			step = 4
			_wait = 2.0
		4:
			_check(float(target.zones[zi].get("air", 1.0)) < 0.2, "the compartment is down to vacuum")
			_check(crew.suit_air < 44.0, "the crew are breathing from their suits (%.1f s left)" % crew.suit_air)
			_check(soldier.hp < hp0 or soldier.state != "alive", "with the suit empty, it's suffocation (hp %d -> %d)" % [int(hp0), int(soldier.hp)])
			_check(target.air_at(crew.position) > 0.6 or (crew.goal != Vector3.INF and target.air_at(crew.goal) > 0.9),
				"unsuited crew get out to good air (air %.2f here, goal %s)" % [target.air_at(crew.position), crew.goal])
			air_low = float(target.zones[zi].get("air", 1.0))
			if not job.is_empty():
				target.repairs.erase(job)                  # (as if the engineers finished it)
				target.room_repaired(job)
			_check(not target._opening_open(target.openings[0]), "patched, the hole is sealed")
			step = 5
			_wait = 3.0
		5:
			_check(float(target.zones[zi].get("air", 1.0)) > air_low + 0.1, "...and the compartment repressurises (%.2f)" % float(target.zones[zi].get("air", 1.0)))
			# ---- B: the player goes out an airlock
			var ex: Array = home._eva_exit(target)
			_check(not ex.is_empty(), "the home ship has an airlock facing the target")
			if ex.is_empty():
				_done()
				return
			player = G.match_node.spawn_character(home, home.snap_local(home.to_local((ex[2] as Node3D).global_position)), home.team, G.team_fac(home.team), "rifleman")
			G.commander.possess(player)
			step = 6
			_wait = 0.5
		6:
			_check(not player.eva_exit_entry().is_empty(), "inside the airlock, the player can cycle out")
			_check(G.commander._look_prompt().contains("go out"), "...and is told so (%s)" % G.commander._look_prompt())
			G.commander.interact()
			_check(not player.eva_cycle.is_empty(), "E starts the airlock cycle")
			step = 7
			_wait = 3.0
		7:
			_check(player.eva_out, "the cycle put the player outside")
			_check(not home.aabb.grow(-1.0).has_point(player.position), "...out on the hull")
			_check(player.zero_g(), "...in zero g")
			y0 = player.global_position.y
			player.velocity = Vector3.ZERO
			Input.action_press("move_forward")
			step = 8
			_wait = 1.5
		8:
			Input.action_release("move_forward")
			_check(player.velocity.length() > 2.0, "thrusters push you where you look (%.1f m/s)" % player.velocity.length())
			_check(player.global_position.y > y0 - 1.0, "...and nothing pulls you down (%.1f m)" % (player.global_position.y - y0))
			_check(player.suit_air < 45.0, "...breathing from the suit (%.1f s)" % player.suit_air)
			# over to the target's hull
			open0 = target.openings.size()
			var es: Array = target.boarding_entries(player.global_position)
			var e2: Array = es[0]
			var hull: Vector3 = (e2[1] as Node3D).global_position
			player.global_position = hull + ((e2[0] as Node3D).global_position - hull).normalized() * 3.0
			player.velocity = Vector3.ZERO
			player._near_at = -10.0
			step = 9
			_wait = 0.3
		9:
			var ne: Array = player.eva_entry_near()
			_check(not ne.is_empty() and ne[0] == target, "at the enemy hull there's a way in")
			_check(G.commander._look_prompt().contains("cut in"), "...cut in, says the prompt")
			G.commander.interact()
			_check(not player.eva_cycle.is_empty() and player.eva_cycle["kind"] == "cut", "E starts cutting")
			step = 10
			_wait = 5.0
		10:
			_check(player.vessel == target and not player.eva_out, "the player cut through and is aboard the target")
			_check(target.openings.any(func(o): return target._opening_open(o)), "...and the cut vents the compartment behind it (%d openings, %d before)" % [target.openings.size(), open0])
			# ---- C: an EVA team crosses
			home.troops = 10
			var ok: bool = home.launch_eva(target)
			_check(ok, "the ship sends an EVA team across")
			for p in G.pods:
				if is_instance_valid(p) and p.get("eva") == true:
					team_node = p
			_check(team_node != null and team_node.riders.size() == 8, "...eight troopers")
			if team_node == null:
				_done()
				return
			riders = team_node.riders.duplicate()
			step = 11
			_wait = 1.0
		11:
			var shown := 0
			for r in riders:
				if is_instance_valid(r) and r.visible and r.collision_layer == G.LAYER_CHAR and r.ride_seat != null \
						and r.global_position.distance_to(r.ride_seat.global_position) < 0.5 and r.rig.mode != "seated":
					shown += 1
			_check(shown == riders.size(), "in the open, in formation, solid enough to shoot (%d/%d)" % [shown, riders.size()])
			_check(riders.all(func(r): return r.suited()), "...in vacuum suits")
			_check(team_node.global_position.distance_to(home.global_position) > 10.0, "...flying across")
			step = 12
		12:
			_flight += dt
			if _flight < 60.0 and is_instance_valid(team_node):
				return
			var aboard := 0
			for r in riders:
				if is_instance_valid(r) and r.state != "dead" and r.vessel == target and r.riding == null:
					aboard += 1
			_check(not is_instance_valid(team_node), "the team reached the hull and cut in (%.0f s)" % _flight)
			_check(aboard > 0, "...and the survivors are aboard the target (%d of %d)" % [aboard, riders.size()])
			_done()


func _done() -> void:
	print("EVA TEST DONE %d" % fails)
	set_physics_process(false)
	G.quit()
