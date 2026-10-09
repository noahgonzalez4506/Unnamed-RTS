extends Node
## The player's squad commands:  godot --headless --path . res://match.tscn -- --squadtest [folder]
## Puts the player (a squad leader with a fireteam) aboard an emptied enemy ship and
## runs every order: breach & clear, suppress, formation, fireteam B, frag, weapons tight, regroup.

var out := ""
var t := 0.0
var step := 0
var _w := 0.0
var report := {}
var me: Node
var them: Node
var player: Node
var cmd: Node
var door: Dictionary


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and not String(args[-1]).begins_with("--"):
		out = args[-1]
		DirAccess.make_dir_recursive_absolute(out)
	Engine.time_scale = 1.0 if out != "" else 2.0
	cmd = G.commander
	for v in G.vessels:
		if v.get_meta("slot", "") == "flag1":
			me = v
		elif v.get_meta("slot", "") == "flag2":
			them = v


func _shot(n: String) -> void:
	if out == "":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, n])
	print("SHOT ", n)


func _physics_process(dt: float) -> void:
	t += dt
	match step:
		0:
			if t > 1.0:
				step = 1
				cmd.deploy("squad_leader", me)
				player = G.possessed
				for c in them.occupants.duplicate():
					if c.team != 1:
						c.die(null)                         # an empty ship: test the drills, not a firefight
				# find an ordinary closed room door on deck 0, then put the squad in the corridor outside it
				for d in them.doors:
					if d["kind"] == "door" and String(d["name"]).contains("RoomDoor_0_"):
						door = d
						break
				var outside: Vector3 = them.snap_local(door["center"] - door["n"] * 2.5 * _corridor_side(door) - Vector3(0, 1.3, 0))
				G.match_node.disembark(them, outside, 1, 1, [], player.squad.members.duplicate())
				player.look_yaw = player.rotation.y
				_w = t
		1:
			if t - _w > 2.0:
				step = 2
				G.match_node.squad_command(player, "breach", door["center"])
				report["stacked"] = not player.squad.stack_door.is_empty() or not player.squad.clear.is_empty()
				_w = t
		2:
			if t - _w > 4.0 and not report.has("shot_stack"):
				report["shot_stack"] = true
				_overhead("01_stack_on_door")
			if not player.squad.clear.is_empty() and not report.has("clear_started"):
				report["clear_started"] = t - _w
			if t - _w > 22.0 or (report.has("clear_started") and t - _w > report["clear_started"] + 6.0):
				step = 3
				report["door_down"] = door["breached"]
				var inside := 0
				if not player.squad.clear.is_empty():
					for m in player.squad.alive():
						if m != player and (m.position - (player.squad.clear["door"] - Vector3(0, 1.3, 0))).dot(player.squad.clear["dir"]) > 0.5:
							inside += 1
				report["in_room"] = inside
				_overhead("02_room_cleared")
				_w = t
		3:
			player.squad.clear = {}
			step = 4
			var aim: Vector3 = player.position - player.global_basis.z * 0.0 + them.to_local(them.global_position)
			aim = them.snap_local(player.position + Vector3(0, 0, 8.0))
			G.match_node.squad_command(player, "suppress", aim + Vector3(0, 1.0, 0))
			G.match_node.squad_command(player, "formation", Vector3.ZERO)
			report["formation"] = player.squad.formation
			G.match_node.squad_command(player, "split", them.snap_local(player.position + Vector3(4.0, 0, 3.0)))
			report["grenades_before"] = _grenades()
			G.match_node.squad_command(player, "grenade", aim)
			G.match_node.squad_command(player, "fire", Vector3.ZERO)
			report["weapons_tight"] = player.squad.hold_fire
			_w = t
		4:
			if t - _w > 6.0:
				step = 5
				report["suppress_shots"] = G.stats.get("suppress_shots", 0)
				report["grenade_thrown"] = _grenades() < report["grenades_before"]
				var b_near := 0
				for m in player.squad.alive():
					if m.fireteam == 1 and m != player and m.position.distance_to(player.squad.split["pos"]) < 4.0:
						b_near += 1
				report["team_b_at_split"] = b_near
				_overhead("03_split_suppress")
				G.match_node.squad_command(player, "regroup", Vector3.ZERO)
				_w = t
		5:
			if t - _w > 8.0:
				step = 6
				var close := 0
				for m in player.squad.alive():
					if m != player and m.position.distance_to(player.position) < 5.0:
						close += 1
				report["regrouped"] = close
				report["squad_alive"] = player.squad.alive().size() - 1
				_report()


func _corridor_side(d: Dictionary) -> float:
	# room doors sit in the corridor wall: the corridor is toward the ship's centreline (x = 0)
	return 1.0 if (d["center"] as Vector3).dot(d["n"]) > 0.0 else -1.0


func _grenades() -> int:
	var n := 0
	for m in player.squad.alive():
		n += m.grenades.size()
	return n


func _overhead(n: String) -> void:
	if out == "":
		return
	var cam: Camera3D = cmd.cam
	cmd.release()
	cmd.interior_forced = 1
	cmd.deck = 0
	cmd.pivot = them.to_global(door["center"])
	cmd.zoom = 28.0
	cmd.pitch = 1.2
	_shot(n)
	cmd.possess(player)


func _report() -> void:
	print("SQUADTEST ", report)
	var fails: Array = []
	if not report.get("stacked", false):
		fails.append("did not stack on the door")
	if not report.get("door_down", false) or not report.has("clear_started"):
		fails.append("door was not breached / room clear did not start")
	if report.get("in_room", 0) < 2:
		fails.append("nobody went into the room")
	if report.get("suppress_shots", 0) == 0:
		fails.append("no suppressing fire")
	if report.get("formation", "") != "file":
		fails.append("formation change")
	if report.get("team_b_at_split", 0) < 1:
		fails.append("fireteam B didn't move")
	if not report.get("grenade_thrown", false):
		fails.append("no frag thrown")
	if report.get("regrouped", 0) < max(1, int(report.get("squad_alive", 0) * 0.5)):
		fails.append("regroup")
	for f in fails:
		print("SQUADTEST FAIL: ", f)
	print("SQUADTEST RESULT: %s (%d problems)" % ["PASS" if fails.is_empty() else "FAIL", fails.size()])
	G.quit(0 if fails.is_empty() else 1)
