extends Node
## Automatic match check:  godot --headless --path . --fixed-fps 30 -- --selftest
## Plays the match fast-forwarded, forces the big moments (ship battle, boarding,
## fighters, a spore pod, direct control) and reports what happened.

var t := 0.0
var step := 0
var report := {}
var _start_pos := {}
var _elev_frames := 0
var _phys: Array = []


func _ready() -> void:
	Engine.time_scale = 4.0
	for c in G.characters:
		_start_pos[c] = c.global_position


func _ship(team: int, cls: String) -> Node:
	for v in G.vessels:
		if v.team == team and v.cls == cls and v.kind == "ship":
			return v
	return null


func _physics_process(dt: float) -> void:
	t += dt
	_phys.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	for v in G.vessels:
		for e in v.elevators:
			if e["target"] != e["deck"]:
				_elev_frames += 1
	var cmd: Node = G.commander
	var me: Node = _ship(1, "LARGE")
	var them: Node = _ship(2, "LARGE")
	if step == 0 and t > 1.0:
		step = 1
		report["rts"] = _rts_check(cmd, me)
		report["doors"] = _door_check(them)
		# send a crewman up to the bridge: he should take the lift
		var bridge: Node3D = me.mark("Bridge_CaptainChair")
		for o in me.occupants:
			if o.team == 1 and o.state == "alive" and o.is_crew() and o.position.y < 1.0 and o.role not in ["pilot", "cargo_handler"] and bridge:
				o.task_pos = me.snap_local(me.local_of(bridge) + Vector3(0, 0, 1.5))
				o.task_t = 90.0
				o.travel(o.task_pos)
				o.set_meta("test_lift", true)
				break
	if step == 1 and t > 3.0:
		step = 2
		print("TEST t=%.0f: fleets engage, fighters scramble" % G.time)
		me.attack_target = them
		them.attack_target = me
		me.move_target = Vector3(-300, 0, 0)
		them.move_target = Vector3(300, 0, 0)
		me.request_fighters()
		them.request_fighters()
	if step == 2 and me.global_position.distance_to(them.global_position) < 1300.0:
		step = 3
		print("TEST t=%.0f: in range; shields down, both sides board" % G.time)
		them.shields = 0.0
		me.shields = 0.0
		report["pods_player"] = me.launch_pods(them, 2)
		report["pods_rival"] = them.launch_pods(me, 2)
	if step == 3 and t > 70.0:
		step = 4
		print("TEST t=%.0f: spore pod; direct control" % G.time)
		G.match_node.ai.spore_t = 0.0
		for c in G.match_node.homes[1].occupants:
			if c.team == 1 and c.armed and c.state == "alive" and c.spare.size() >= 2:
				cmd.possess(c)
				var before: int = c.mag
				for i in 5:
					c.fire_t = 0.0
					c.fire(c.eye(), -c.global_basis.z)
				report["fps_fired"] = before - c.mag
				c.reload_t = 0.5
				break
	if step == 4 and t > 75.0:
		step = 5
		var c: Node = G.possessed
		report["fps_reloaded"] = c != null and c.mag == int(c.wstats.get("ammo_per_load", 30))
		if c:
			print("TEST reload check: ", c.display, " mag ", c.mag, " spare ", c.spare, " reload_t ", c.reload_t, " state ", c.state)
		else:
			print("TEST reload check: nobody possessed")
		cmd.release()
	if step == 5 and t > 160.0:
		step = 6
		_report()


var _door_test := {}


## Doors on an enemy ship: an ordinary door kicks in, a secure door shrugs off bullets
## and grenades but a charge blows it, a blast door can be shot down.
func _door_check(v: Node) -> String:
	var kinds := {}
	for d in v.doors:
		kinds[d["kind"]] = kinds.get(d["kind"], 0) + 1
	var plain: Dictionary = {}
	var secure: Dictionary = {}
	var heavy: Dictionary = {}
	for d in v.doors:
		if d["kind"] == "door" and plain.is_empty() and String(d["name"]).contains("RoomDoor"):
			plain = d
		elif d["kind"] == "secure" and secure.is_empty() and String(d["name"]).contains("SecureDoor"):
			secure = d
		elif d["kind"] == "heavy" and heavy.is_empty():
			heavy = d
	var kicks := 0
	while not plain.is_empty() and not plain["breached"] and kicks < 10:
		v.damage_door(plain, 90.0, plain["n"], true)
		kicks += 1
	var secure_held := true
	if not secure.is_empty():
		for i in 50:
			v.damage_door(secure, 100.0, secure["n"])
		v.blast_doors(v.to_global(secure["center"]), 4.0, 200.0)
		secure_held = not secure["breached"]
		v.plant_charge(secure, null)
		_door_test["secure"] = secure
	var shots := 0
	while not heavy.is_empty() and not heavy["breached"] and shots < 200:
		v.damage_door(heavy, 25.0, heavy["n"])
		shots += 1
	v.alarm = 0.0                     # a test, not a real boarding: don't put the crew on alert
	return "kinds=%s kicks_to_break=%d fallen=%s secure_held=%s heavy_shots=%d" % [kinds, kicks,
		plain.get("fallen", false), secure_held, shots]


func _rts_check(cmd: Node, me: Node) -> String:
	var c: Node = null
	for o in me.occupants:
		if o.team == 1 and o.state == "alive" and o.position.y < 2.0:
			c = o
			break
	cmd.pivot = c.global_position
	cmd.zoom = 25.0
	cmd.interior_forced = 1
	cmd._rts_frame(0.016)
	var picked: Node = cmd.pick(cmd.cam.unproject_position(c.global_position + Vector3.UP))
	cmd.clear_selection()
	if picked:
		cmd.select(picked)
	cmd.order_at(cmd.cam.unproject_position(c.global_position + Vector3(2.0, 0.05, 0.0)), false)
	var ordered: bool = picked != null and not picked.order.is_empty()
	cmd.possess_selected()
	var possessed_ok: bool = G.possessed == picked
	cmd.release()
	cmd.clear_selection()
	cmd.select(me)
	cmd.zoom = 400.0
	cmd._rts_frame(0.016)
	cmd.order_at(cmd.cam.unproject_position(me.global_position + Vector3(0, 0, -200)), false)
	var ship_ok: bool = me.move_target != Vector3.INF
	me.move_target = Vector3.INF
	cmd.clear_selection()
	G.resources[1]["alloys"] += 500.0
	cmd.select(G.match_node.homes[1])
	cmd.cmd_train()
	var train_ok: bool = G.match_node.homes[1].training.size() > 0
	cmd.clear_selection()
	cmd.interior_forced = -1
	return "picked=%s ordered=%s possess=%s ship_move=%s train=%s" % [picked != null, ordered, possessed_ok, ship_ok, train_ok]


func _report() -> void:
	var by_team := {}
	var moved := 0
	for c in G.characters:
		if not is_instance_valid(c):
			continue
		var k := "%d_%s" % [c.team, c.state]
		by_team[k] = by_team.get(k, 0) + 1
		if _start_pos.has(c) and c.global_position.distance_to(_start_pos[c]) > 3.0:
			moved += 1
	print("SELFTEST characters by team_state: ", by_team)
	print("SELFTEST characters that moved: %d of %d" % [moved, _start_pos.size()])
	print("SELFTEST elevator frames moving: %d" % _elev_frames)
	for v in G.vessels:
		var st := ""
		if v.kind == "ship":
			st = "hull %d shields %d destroyed %s" % [v.hull, v.shields, v.destroyed]
		else:
			var states := {}
			for code in v.modules:
				states[v.modules[code]["state"]] = states.get(v.modules[code]["state"], 0) + 1
			st = str(states)
		print("SELFTEST %-20s team %d  %s  aboard %d  infected %.2f" % [v.display_name, v.team, st, v.occupants.size(), v.infected_fraction()])
	var ks := G.stats.keys()
	ks.sort()
	for k in ks:
		if not String(k).begins_with("us_"):
			print("SELFTEST stat %-24s %d" % [k, G.stats[k]])
	report["secure_charge_blew"] = _door_test.has("secure") and _door_test["secure"]["breached"]
	print("SELFTEST report: ", report)
	_phys.sort()
	print("SELFTEST physics ms per step: median %.1f  95th %.1f  (%d characters)" % [_phys[_phys.size() / 2],
		_phys[int(_phys.size() * 0.95)], G.characters.size()])
	var fails: Array = []
	if moved < _start_pos.size() * 0.5:
		fails.append("too few characters moved")
	if report.get("pods_player", 0) == 0 or report.get("pods_rival", 0) == 0:
		fails.append("boarding pods did not launch")
	if String(report.get("rts", "")).contains("false"):
		fails.append("commander controls: " + report.get("rts", ""))
	if G.stats.get("fighters_launched", 0) == 0:
		fails.append("no fighters launched")
	if G.stats.get("ship_shots", 0) == 0:
		fails.append("ship turrets never fired")
	if report.get("fps_fired", 0) < 5 or not report.get("fps_reloaded", false):
		fails.append("direct control firing/reloading")
	if G.stats.get("elevator_rides", 0) == 0 and _elev_frames == 0:      # (crewtest checks full rides in peacetime)
		fails.append("nobody rode an elevator")
	if G.stats.get("squads_spawned", 0) == 0:
		fails.append("no boarders came out of the pods")
	var dr: String = report.get("doors", "")
	if not dr.contains("fallen=true") or not dr.contains("secure_held=true") or not report.get("secure_charge_blew", false):
		fails.append("doors: " + dr)
	if G.stats.get("door_openings", 0) == 0:
		fails.append("crew never opened a door")
	G.match_node.on_station_lost(G.match_node.homes[2], 1)
	if not G.game_over:
		fails.append("capturing the rival command core did not end the match")
	for f in fails:
		print("SELFTEST FAIL: ", f)
	print("SELFTEST RESULT: %s (%d problems)" % ["PASS" if fails.is_empty() else "FAIL", fails.size()])
	G.quit(1 if not fails.is_empty() else 0)
