extends Node
## Logistics:  godot --headless --path . res://match.tscn -- --logtest [folder]
## A flagship out in the field, short of boarders, supplies and crew, gets a supply
## shuttle from home; a frigate parked by the station is topped up directly; an empty
## armory turns soldiers away; the station turns out new robots.

var out := ""
var t := 0.0
var step := 0
var _w := 0.0
var report := {}
var me: Node
var frig: Node
var home: Node
var _reserve0 := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and not String(args[-1]).begins_with("--"):
		out = args[-1]
		DirAccess.make_dir_recursive_absolute(out)
	Engine.time_scale = 1.0 if out != "" else 4.0
	for v in G.vessels:
		if v.get_meta("slot", "") == "flag1":
			me = v
		elif v.get_meta("slot", "") == "frigate1":
			frig = v
	home = G.match_node.homes[1]


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
			if t > 1.5:
				step = 1
				G.match_node.ai.attack_after = 99999.0          # keep the rival home: this is about supply
				me.global_position = home.global_position + (Vector3.ZERO - home.global_position).normalized() * 1900.0
				me.move_target = Vector3.INF
				me.attack_target = null
				me.troops = 2
				me.supplies = 20.0
				var killed := 0
				for c in me.occupants.duplicate():
					if c.team == 1 and c.role in ["engineer", "cargo_handler"] and killed < 3:
						c.die(null)
						killed += 1
				report["crew_killed"] = killed
				report["berth_cap"] = me.berth_cap
				report["supply_cap"] = me.supply_cap
				frig.global_position = home.global_position + Vector3(0, 0, 350)
				frig.move_target = Vector3.INF
				frig.supplies = 10.0
				frig.troops = 0
				_reserve0 = home.reserve
				G.resources[1]["alloys"] += 2000.0
				G.resources[1]["cores"] += 20.0
				_w = t
				# the armory check: empty stores turn a soldier away
				var sold: Node = null
				for c in me.occupants:
					if c.team == 1 and c.state == "alive" and c.role in c.COMBAT_ROLES:
						sold = c
						break
				var arm: Array = me.marks_like("Armory_*_Resupply")
				if sold and not arm.is_empty():
					var keep: float = me.supplies
					me.supplies = 0.0
					sold.position = me.snap_local(me.local_of(arm[0]))
					report["empty_armory"] = String(sold.player_use({}))
					me.supplies = keep
		1:
			if not report.has("run_launched") and G.stats.get("supply_runs", 0) > 0:
				report["run_launched"] = t - _w
				if out != "":
					for f in G.pods:
						if is_instance_valid(f) and f.has_method("_deliver"):
							G.commander.pivot = f.global_position
							G.commander.zoom = 140.0
							break
			if report.has("run_launched") and not report.has("shot") and t - _w > report["run_launched"] + 6.0:
				report["shot"] = true
				for f in G.pods:
					if is_instance_valid(f) and f.has_method("_deliver"):
						G.commander.pivot = f.global_position
						G.commander.zoom = 90.0
				_shot("supply_shuttle")
			if G.stats.get("supply_runs_delivered", 0) > 0 or t - _w > 150.0:
				step = 2
				report["delivered_after_s"] = int(t - _w)
				report["troops_now"] = me.troops
				report["supplies_now"] = int(me.supplies)
				report["crew_replaced"] = G.stats.get("crew_replaced", 0)
				report["frigate_supplies"] = int(frig.supplies)
				report["frigate_troops"] = frig.troops
				report["dock_transfers"] = G.stats.get("dock_transfers", 0)
				_w = t
		2:
			if t - _w > 30.0:
				report["reserve_grew"] = home.reserve - _reserve0
				_report()
				step = 3


func _report() -> void:
	print("LOGTEST ", report)
	var fails: Array = []
	if not report.has("run_launched"):
		fails.append("no supply run was sent")
	if report.get("troops_now", 0) <= 2 or report.get("supplies_now", 0) <= 20:
		fails.append("the supply run delivered nothing")
	if report.get("crew_replaced", 0) < 1:
		fails.append("no replacement crew")
	if report.get("frigate_supplies", 0) <= 10 or report.get("dock_transfers", 0) == 0:
		fails.append("docked frigate wasn't topped up")
	if not String(report.get("empty_armory", "")).contains("bare"):
		fails.append("empty armory still handed out ammo")
	for f in fails:
		print("LOGTEST FAIL: ", f)
	print("LOGTEST RESULT: %s (%d problems)" % ["PASS" if fails.is_empty() else "FAIL", fails.size()])
	G.quit(0 if fails.is_empty() else 1)
