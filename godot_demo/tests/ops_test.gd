extends Node
## Boarding operations, end to end:
##   godot --headless --path . res://match.tscn -- --opstest            (checks only)
##   godot --path . res://match.tscn -- --opstest <folder>              (checks + pictures)
## Deploys the player as a squad leader with a fireteam, brings the fleets together,
## orders a pod boarding op (30 s muster), the player and fireteam join at the pod bay
## and ride in, then: red alert, helm lock + missile salvo, a boarding shuttle, a
## reinforcement pod called from first person, fleet "form on me", squad hold order.

var out := ""
var t := 0.0
var step := 0
var wait_t := 0.0
var report := {}
var me: Node
var them: Node
var player: Node
var cmd: Node
var _shots_due: Array = []
var _hull0 := 0.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and not String(args[-1]).begins_with("--"):
		out = args[-1]
		DirAccess.make_dir_recursive_absolute(out)
	Engine.time_scale = 1.0 if out != "" else 3.0
	cmd = G.commander
	cmd._help = false
	cmd.hud.show_help(false)
	for v in G.vessels:
		if v.get_meta("slot", "") == "flag1":
			me = v
		elif v.get_meta("slot", "") == "flag2":
			them = v


func _shot(name_: String) -> void:
	if out == "":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name_])
	print("SHOT ", name_)


func _physics_process(dt: float) -> void:
	t += dt
	match step:
		0:
			if t > 1.0:
				step = 1
				cmd.deploy("squad_leader", me)
				player = G.possessed
				report["fireteam"] = player.squad.members.size() if player.squad else 0
				report["leads"] = player.squad != null and player.squad.leader == player
				# the fleets meet: park the enemy flagship 900 m off our beam, shields down
				them.global_position = me.global_position + me.global_basis.x * 900.0
				them.rotation.y = me.rotation.y
				them.move_target = Vector3.INF
				them.attack_target = null
				me.move_target = Vector3.INF
				me.attack_target = null
				them.shields = 0.0
				me.shields = me.max_shields
		1:
			if t > 2.5:
				step = 2
				report["op_started"] = me.start_boarding(them, "pods")
				report["muster_s"] = me.boarding.get("t", 0)
				# walk (teleport) the player and the fireteam to the pod bay
				var m: Array = me.muster_points("pods")
				var bay: Vector3 = m[0] if not m.is_empty() else player.position
				player.position = me.snap_local(bay)
				var i := 0
				for c in player.squad.members:
					if c != player:
						c.position = me.snap_local(bay + Vector3((i % 3) - 1.0, 0, 1.5 + int(i / 3)))
						i += 1
				player.look_yaw = player.rotation.y
		2:
			if t > 4.0:
				step = 3
				cmd.interact()                                 # E at the bay: join
				report["joined"] = player.mustered == me
				_shot("01_muster_countdown")
		3:
			if me.boarding.is_empty():
				step = 4
				report["riding"] = player.riding != null
				wait_t = t
		4:
			if out != "" and t - wait_t > 1.5 and not _shots_due.has("pod"):
				_shots_due.append("pod")
				_shot("02_riding_pod")
			if player.riding == null and player.vessel == them:
				step = 5
				wait_t = t
				var with_me := 0
				for c in player.squad.members:
					if is_instance_valid(c) and c.vessel == them and c.state == "alive":
						with_me += 1
				report["landed_with_squad"] = with_me
				report["red_alert"] = them.alarm > 0.0 and them._red_on
			elif t - wait_t > 40.0:
				step = 5
				wait_t = t
				report["landed_with_squad"] = -1
		5:
			if t - wait_t > 2.0:
				step = 6
				player.look_pitch = -0.05
				_shot("03_aboard_red_alert")
				cmd.squad_order("hold")
				report["squad_hold"] = player.squad.order.get("type", "") == "hold"
				G.resources[1]["alloys"] += 1000.0
				G.resources[1]["cores"] += 20.0
				var before: int = G.stats.get("pods_launched", 0)
				cmd.requisition()
				report["requisition_pod"] = G.stats.get("pods_launched", 0) > before
				wait_t = t
		6:
			if t - wait_t > 3.0:
				step = 7
				# back home and to the helm: lock, missiles, shuttle, fleet orders
				cmd.release()
				var p2: Node = G.match_node.spawn_player("rifleman", me, 1)
				cmd.possess(p2)
				player = p2
				var seat: Node3D = me.mark("Bridge_PilotSeat")
				player.position = me.snap_local(me.local_of(seat) + Vector3(0, 0, 1.0))
				cmd.take_helm(me)
				cmd.chase_yaw = 1.2
				cmd.chase_pitch = 0.25
				me.manual_aim = them.to_global(them.aabb.get_center())
				cmd.helm_lock()
				report["locked"] = me.lock == them
				_hull0 = them.hull + them.shields
				report["missiles_fired"] = me.missiles
				cmd._helm_op("missiles")
				report["missiles_fired"] = report["missiles_fired"] - me.missiles
				report["missiles_in_flight"] = G.missiles.size()
				wait_t = t
		7:
			if t - wait_t > 1.2 and not _shots_due.has("missiles"):
				_shots_due.append("missiles")
				_shot("04_helm_lock_missiles")
			if t - wait_t > 12.0:
				step = 8
				report["missile_damage"] = int(_hull0 - (them.hull + them.shields))
				me.troops = max(me.troops, 12)
				me.shuttle_cd = 0.0
				var sh: Node = me.launch_shuttle(them, [])
				report["shuttle"] = sh != null
				G.match_node.fleet_order(me, "form")
				var forming := 0
				for v in G.vessels:
					if v.get("follow") == me:
						forming += 1
				report["fleet_forming"] = forming
				wait_t = t
		8:
			if t - wait_t > 5.0 and not _shots_due.has("shuttle"):
				_shots_due.append("shuttle")
				for f in G.pods:
					if is_instance_valid(f) and f.has_method("_unload"):
						cmd.leave_vehicle()
						cmd.release()
						cmd.pivot = f.global_position
						cmd.zoom = 120.0
						break
				_shot("05_shuttle")
			if G.stats.get("shuttle_landed", 0) > 0 or t - wait_t > 60.0:
				step = 9
				report["shuttle_landed"] = G.stats.get("shuttle_landed", 0)
				_report()


func _report() -> void:
	print("OPSTEST report: ", report)
	var fails: Array = []
	if report.get("fireteam", 0) < 6 or not report.get("leads", false):
		fails.append("squad leader deploy with fireteam")
	if not report.get("op_started", false) or report.get("muster_s", 0) < 24:
		fails.append("boarding op countdown")
	if not report.get("joined", false) or not report.get("riding", false):
		fails.append("player could not join / ride the pod")
	if report.get("landed_with_squad", 0) < 4:
		fails.append("player and squad did not land aboard the target")
	if not report.get("red_alert", false):
		fails.append("no red alert aboard the boarded ship")
	if not report.get("squad_hold", false):
		fails.append("squad order")
	if not report.get("requisition_pod", false):
		fails.append("requisition pod")
	if not report.get("locked", false) or report.get("missiles_fired", 0) < 1:
		fails.append("helm lock / missiles")
	if report.get("missile_damage", 0) <= 0:
		fails.append("missiles did no damage")
	if not report.get("shuttle", false) or report.get("shuttle_landed", 0) == 0:
		fails.append("boarding shuttle")
	if report.get("fleet_forming", 0) == 0:
		fails.append("fleet form-on-me")
	for f in fails:
		print("OPSTEST FAIL: ", f)
	print("OPSTEST RESULT: %s (%d problems)" % ["PASS" if fails.is_empty() else "FAIL", fails.size()])
	G.quit(0 if fails.is_empty() else 1)
