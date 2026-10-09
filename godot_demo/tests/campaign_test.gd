extends Node
## Campaign:  godot --path . res://match.tscn -- --camptest [folder]
##   home system: the frigate, the starter station, two miners that bring ore home,
##   planets and jump gates, a trade post; buying and selling; taking a job; the galaxy
##   map and station screens; then a jump to the next system, a save and a load.

var out := ""
var t := 0.0
var step := 0
var _w := 0.0
var report := {}
var me: Node
var post: Node
var cam: Camera3D
var _cam_on := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and not String(args[-1]).begins_with("--"):
		out = args[-1]
		DirAccess.make_dir_recursive_absolute(out)
	Engine.time_scale = 1.0 if out != "" else 3.0
	report = G.get_meta("camptest", {})
	if report.has("landed_on"):
		step = 30 if not report.has("took_off") else 40
	elif report.has("jumped_to"):
		step = 10
	cam = Camera3D.new()
	cam.far = 30000.0
	add_child(cam)


func _process(_dt: float) -> void:
	if _cam_on:
		cam.make_current()


func _shot(n: String) -> void:
	if out == "":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, n])
	print("SHOT ", n)


func _look(from: Vector3, at: Vector3) -> void:
	_cam_on = true
	G.commander._help = false
	G.commander.hud.show_help(false)
	cam.global_position = from
	cam.look_at(at, Vector3.UP)


func _rts() -> void:
	_cam_on = false
	G.commander._help = false
	G.commander.hud.show_help(false)
	G.commander.cam.make_current()


func _physics_process(dt: float) -> void:
	t += dt
	var c = G.campaign
	match step:
		0:
			if t > 2.0:
				step = 1
				for v in G.vessels:
					if v.team == 1 and v.kind == "ship":
						me = v
					if v.kind == "station" and v.team == 6:
						post = v
				report["frigate"] = me != null and me.cls == "SMALL_FRIGATE"
				report["home_station"] = G.match_node.homes.has(1) and G.match_node.homes[1].cls == "STATION_STARTER"
				report["miners"] = G.match_node.miner_crafts.size()
				report["planets"] = G.match_node.planets.size()
				report["gates"] = G.match_node.gates.size()
				report["trade_post"] = post != null
				report["system"] = c.system()["name"]
				report["vessels"] = G.vessels.size()
				_w = t
				if out != "":
					var pl: Dictionary = G.match_node.planets[0]
					var hp: Vector3 = G.match_node.homes[1].global_position
					_look(hp + (hp - (pl["pos"] as Vector3)).normalized() * 700.0 + Vector3.UP * 320.0, (pl["pos"] as Vector3).lerp(hp, 0.4))
					_shot("01_home_system")
		1:
			if out != "" and t - _w > 1.0 and not report.has("s_mine"):
				for mc in G.match_node.miner_crafts:
					if is_instance_valid(mc) and mc.stage == 2:
						report["s_mine"] = true
						_look(mc.global_position + Vector3(60, 35, 60), mc.global_position)
						_shot("02_miner_cutting")
						break
			if G.stats.get("ore_delivered", 0) > 0 or t - _w > 150.0:
				report["ore_delivered"] = G.stats.get("ore_delivered", 0)
				report["ore_in_stores"] = int(c.stores.get("ore", 0.0) + c.stores.get("fuel", 0.0) - 200.0)
				step = 2
				_w = t
				# alongside the trade post
				if post:
					me.global_position = post.global_position + (me.global_position - post.global_position).normalized() * 450.0
					me.move_target = Vector3.INF
				G.commander.selection = [me]
		2:
			if t - _w > 1.0:
				step = 3
				var key: String = post.get_meta("key")
				var e: Dictionary = c.fleet_entry(int(me.get_meta("fleet_id")))
				var cr0: int = c.credits
				report["buy"] = c.buy(key, e, "food", 10)
				report["credits_spent"] = cr0 - c.credits
				var cr1: int = c.credits
				report["sell"] = c.sell(key, e, "food", 4)
				report["credits_back"] = c.credits - cr1
				report["cargo"] = e.get("cargo", {}).duplicate()
				var offers: Array = c.offers_at(key)
				report["offers"] = offers.size()
				if not offers.is_empty():
					report["accepted"] = c.accept(offers[0])
				# building: a mining craft in the queue, a refinery segment snapped onto the station
				var B = load("res://scripts/campaign/builder.gd")
				var he: Dictionary = c.stations[0]
				c.stores["alloys"] = 9000.0
				c.stores["circuitry"] = 3000.0
				report["order"] = B.order(he, "MINER")
				he["queue"][0]["left"] = 2.0
				var hn: Node = G.match_node.homes[1]
				var spot := Vector3.INF
				for gx in range(-8, 9):
					for gz in range(-8, 9):
						var p := Vector3(gx * B.GRID, 0, gz * B.GRID)
						if spot == Vector3.INF and B.spot_ok(hn, he, p):
							spot = p
				report["segment"] = B.place(hn, he, "defense", spot) if spot != Vector3.INF else "no spot"
				G.commander.camp_ui.toggle_build()
				report["build_open"] = G.commander.camp_ui.build_panel.visible
				G.commander.camp_ui.build_panel.visible = false
				G.commander.camp_ui.toggle_services()
				report["services_open"] = G.commander.camp_ui.svc_panel.visible
				_rts()
				G.commander.pivot = me.global_position
				G.commander.zoom = 700.0
				_w = t
		3:
			if t - _w > 1.0 and step == 3:
				step = 4
				_shot("03_station_services")
				_w = t
		4:
			if t - _w > 1.0:
				G.commander.camp_ui.svc_panel.visible = false
				G.commander.camp_ui.toggle_map()
				report["map_open"] = G.commander.camp_ui.map_panel.visible
				report["miners_after_build"] = c.miners.size()
				step = 5
				_w = t
		5:
			if t - _w > 1.0:
				step = 55
				await _shot("04_galaxy_map")
				G.commander.camp_ui.map_panel.visible = false
				# jump to the first neighbour: fly to the gate (helped along for the test)
				var to: int = int(c.neighbours()[0])
				report["jumped_to"] = to
				report["fleet_before"] = c.fleet.size()
				report["credits_before_jump"] = c.credits
				G.set_meta("camptest", report)
				G.match_node.order_jump([me], to)
				report["from"] = c.current
				var gp: Vector3 = G.match_node._gate_pos(to)
				me.global_position = gp + (me.global_position - gp).normalized() * 500.0
				step = 6
				_w = t
		6:
			if t - _w > 90.0:
				report["jump_timeout"] = true
				_report()
				step = 99
		10:
			# after the jump: a new system
			if t > 3.0:
				step = 11
				report["arrived_in"] = c.current
				var mine: Array = G.vessels.filter(func(v): return v.team == 1 and v.kind == "ship")
				report["ships_here"] = mine.size()
				report["npc_vessels"] = G.vessels.filter(func(v): return v.team != 1).size()
				var gp: Vector3 = G.match_node._gate_pos(int(report.get("from", c.arrive_from)))
				report["near_gate"] = not mine.is_empty() and gp != Vector3.INF and mine[0].global_position.distance_to(gp) < 900.0
				if out != "" and not mine.is_empty():
					_look(mine[0].global_position + Vector3(250, 160, 250), mine[0].global_position)
					_shot("05_arrived_" + c.system()["name"].replace(" ", "_"))
				# save, load and compare
				c.snapshot()
				report["saved"] = c.save()
				var c2 = load("res://scripts/campaign/campaign.gd").load_game()
				report["loaded_same"] = c2 != null and c2.current == c.current and c2.credits == c.credits and c2.fleet.size() == c.fleet.size() \
					and c2.jobs.size() == c.jobs.size() and c2.galaxy["systems"].size() == c.galaxy["systems"].size()
				_w = t
		11:
			if t - _w > 1.0 and out != "":
				# a look at the planets of this system
				var pl: Dictionary = G.match_node.planets[0]
				var pp: Vector3 = pl["pos"]
				_look(pp + (Vector3.ZERO - pp).normalized() * (float(pl["radius"]) * 2.6) + Vector3.UP * float(pl["radius"]) * 0.8, pp)
				_shot("06_planet_" + String(pl["def"]["biome"]))
				step = 12
				_w = t
			elif out == "":
				step = 12
		12:
			if t - _w > 1.0:
				# land on a world with landing zones (helped close for the test)
				var sys: Dictionary = c.system()
				var me2: Node = null
				for v in G.vessels:
					if v.team == 1 and v.kind == "ship":
						me2 = v
				for i in sys["planets"].size():
					var pl: Dictionary = sys["planets"][i]
					if not pl["sites"].is_empty() and me2:
						var pp: Vector3 = pl["pos"]
						me2.global_position = Vector3(pp.x, 0, pp.z) + (Vector3.ZERO - Vector3(pp.x, 0, pp.z)).normalized() * (float(pl["radius"]) + 600.0)
						report["landed_on"] = pl["name"]
						G.set_meta("camptest", report)
						report["land_msg"] = G.match_node.land([me2])
						break
				if not report.has("landed_on"):
					_report()
				step = 13
		30:
			if "--perf" in OS.get_cmdline_user_args() and t > 3.0:
				_perf(t)
				return
			if t > 3.0:
				report["on_surface"] = G.match_node.on_surface
				report["surface_ships"] = G.vessels.filter(func(v): return v.team == 1 and v.kind == "ship").size()
				report["surface_bases"] = G.vessels.filter(func(v): return v.kind == "station").size()
				# (exercise the city builder even when this zone has no city)
				var rr := RandomNumberGenerator.new()
				rr.seed = 99
				var cov0: int = G.match_node.ground_cover.size()
				var Lc: Dictionary = G.match_node.system.duplicate()
				if not Lc.has("city_site"):
					Lc["city_site"] = {"center": Vector3(900, 0, 900), "radius": 330.0}
				load("res://scripts/campaign/ruins.gd")._city(G.match_node, Lc,
					load("res://scripts/campaign/surface.gd")._terrain_params(G.match_node.system), rr)
				report["city_cover_points"] = G.match_node.ground_cover.size() - cov0
				var gnd: Node3D = G.match_node.ground
				report["ground_nav"] = gnd != null and gnd.nav_ok()
				report["city"] = not G.match_node.city.is_empty()
				var sh0: Array = G.vessels.filter(func(v): return v.team == 1 and v.kind == "ship")
				if gnd and not sh0.is_empty():
					sh0[0].troops = maxi(sh0[0].troops, 8)
					report["deployed"] = G.match_node.deploy_troops(sh0[0])
					report["vehicles_deployed"] = G.match_node.deploy_vehicles(sh0[0])
					# a line-up of every vehicle for both sides (for the picture)
					var VEH = load("res://scripts/campaign/vehicle.gd")
					var base: Vector3 = gnd.snap_local(gnd.to_local(sh0[0].global_position)) + Vector3(0, 0, 60)
					var kinds: Array = ["tank", "ifv", "mrap_ai", "mrap_aa", "mrap_av", "mech", "mortar"]
					for fi in 2:
						for ki in kinds.size():
							var vv: Node3D = VEH.new()
							vv.setup(kinds[ki], 6, fi + 1, gnd, gnd.snap_local(base + Vector3(ki * 14.0 - 42.0, 0, fi * 18.0)))
					report["vehicles_total"] = G.vehicles.size()
					# a mini dropship loading beside a landed ship: troops on foot, vehicles by elevator
					var fe: Dictionary = c.fleet_entry(int(sh0[0].get_meta("fleet_id")))
					fe["minidrops"] = 1
					fe["vehicles"] = ["mrap_ai", "mech"]
					sh0[0].troops = 8
					sh0[0].move_target = Vector3.INF
					report["minidrop"] = G.match_node.send_minidrop(sh0[0], sh0[0].global_position + Vector3(500, 0, 300))
					var mds: Array = G.pods.filter(func(p): return p.get_script() == load("res://scripts/campaign/minidrop.gd"))
					report["minidrop_boarding"] = mds[0]._boarding.size() if not mds.is_empty() else -1
					var mv: Node = G.vehicles[0]
					mv.order_move(mv.global_position + Vector3(80, 0, 40))
					report["vehicle_path"] = mv.path.size()
					# ground cargo: a depot down the front ramp, then hauled back up
					var cls0: String = sh0[0].cls
					sh0[0].cls = "SMALL_SUPPORT"
					c.stores["alloys"] = maxf(float(c.stores.get("alloys", 0.0)), 500.0)
					report["depot_unload"] = G.match_node.DEPOT.unload(G.match_node, sh0[0])
					report["depot_crates"] = (G.match_node.get_meta("depot_crates", []) as Array).size()
					G.match_node.DEPOT.tick(G.match_node)
					report["depot_load"] = G.match_node.DEPOT.load_cargo(G.match_node, sh0[0])
					sh0[0].cls = "SMALL_DROP_FRIGATE"
					G.match_node.post_perimeter_guards()
					report["perimeter_guards"] = G.match_node.ground.occupants.filter(func(o): return is_instance_valid(o) and o.has_meta("perimeter")).size()
					sh0[0].cls = cls0
					# driving: the player's controls move a vehicle and fire its gun
					var dv: Node = G.vehicles[G.vehicles.size() - 1]
					var dp0: Vector3 = dv.global_position
					for k in 40:
						dv.player_drive(0.05, 1.0, 0.2, false, dv.global_position + Vector3(50, 0, 0), true, false)
					report["drive_moved"] = snappedf(dv.global_position.distance_to(dp0), 0.1)
					# ground installations: an outlaw camp and a hive built onto the ground, then the camp's core destroyed
					var CAMPS = load("res://scripts/campaign/camps.gd")
					var op0: int = G.match_node.outposts.size()
					var cp0: Vector3 = gnd.to_global(base) + Vector3(400, 0, 0)
					CAMPS.outlaw_camp(G.match_node, cp0, "test_camp", G.match_node.system, G.match_node.terrain_P)
					CAMPS.hive(G.match_node, cp0 + Vector3(0, 0, 400), "test_hive", G.match_node.system, G.match_node.terrain_P)
					report["outpost_parts"] = G.match_node.outposts.size() - op0
					if out != "":
						_look(cp0 + Vector3(70, 45, 70), cp0)
						await _shot("09_outlaw_camp")
						_look(cp0 + Vector3(45, 30, 445), cp0 + Vector3(0, 2, 400))
						await _shot("10_hive")
					# the infection: brood sacs, a wave, a gravemind once fed, a spreader born and moving on
					report["brood_sacs"] = G.match_node.outposts.filter(func(o): return o.part == "brood").size()
					var INF = load("res://scripts/campaign/infection.gd")
					c.world["test_hive"] = {"team": 4, "biomass": 700.0}
					for o in G.match_node.outposts:
						if o.part == "core" and o.base_key == "test_hive":
							o.set_meta("wave_t", 1.0)
					INF.surface_tick(G.match_node)
					report["gravemind"] = G.match_node.outposts.filter(func(o): return o.part == "gravemind").size()
					report["wave_members"] = G.match_node.ground.occupants.filter(func(o): return is_instance_valid(o) and o.has_meta("wave")).size()
					c.world["test_hive"]["gm_t"] = 9999.0
					var key_sys := "%d_9_9_9" % c.current
					c.world[key_sys] = {"team": 4, "gravemind": true, "gm_t": 9999.0}
					INF.galaxy_tick(G.match_node)
					report["spreaders"] = (c.world.get("infestation", {}).get("ships", []) as Array).size()
					c.world.erase(key_sys)
					c.world.erase("test_hive")
					c.world.erase("infestation")
					report["outlaw_convoys"] = G.pods.filter(func(p): return p.get("pace") != null and p.pace < 5.0).size()
					var cores: Array = G.match_node.outposts.filter(func(o): return o.part == "core" and o.base_key == "test_camp")
					if not cores.is_empty():
						cores[0].take_hit(99999.0, cores[0].global_position, null, 5.0)
					report["camp_fallen"] = c.world.get("test_camp", {}).get("destroyed", false)
					# zones: this landing zone is listed, and our units here are written down
					G.match_node.save_ground_units()
					report["zones"] = c.zones().size()
					var uk: String = c.units_key(c.current, int(c.surface["planet"]), int(c.surface["site"]))
					report["saved_ground_units"] = (c.world.get(uk, {}).get("troops", []) as Array).size() + (c.world.get(uk, {}).get("vehicles", []) as Array).size()
					c.world.erase(uk)
					# an ODST drop straight down onto open ground
					var ds: Node = sh0[0]
					var racks0: int = ds.drop_racks.size()
					report["odst_ground"] = ds._ground_drop(ds.global_position, 4) if racks0 > 0 else -1
					if out != "":
						_look(gnd.to_global(base) + Vector3(10, 30, 75), gnd.to_global(base) + Vector3(0, 2, 8))
						_shot("08_vehicles")
					var occ: Array = gnd.occupants.filter(func(c): return c.team == 1)
					if not occ.is_empty():
						var a: Vector3 = occ[0].position
						report["ground_path_pts"] = gnd.path_local(a, gnd.near_local(a, 60.0)).size()
				if out != "":
					var sh: Array = G.vessels.filter(func(v): return v.team == 1 and v.kind == "ship")
					if not sh.is_empty():
						_look(sh[0].global_position + Vector3(300, 120, 300), sh[0].global_position + Vector3(0, -60, 0))
						_shot("07_surface")
				report["took_off"] = true
				G.set_meta("camptest", report)
				step = 31
				_w = t
		31:
			# convoy range: a path from the landing zone right across to the farthest walkable area
			var gnd2: Node3D = G.match_node.ground
			if gnd2 and gnd2.areas.size() > 1 and not report.has("cross_path_gap"):
				var a0: Vector3 = gnd2.snap_local(gnd2.areas[0][0])
				var a1: Vector3 = gnd2.areas[-1][0]
				var pth: PackedVector3Array = gnd2.path_local(a0, gnd2.snap_local(a1))
				var gap: float = Vector2(pth[-1].x - a1.x, pth[-1].z - a1.z).length() if pth.size() > 0 else 9999.0
				if gap < 60.0 or t - _w > 60.0:
					report["cross_path_gap"] = int(gap)
					report["cross_path_len"] = int(pth.size())
					report["baked"] = snappedf(gnd2.baked_fraction(), 0.01)
			if (report.has("cross_path_gap") or gnd2 == null or gnd2.areas.size() <= 1) and t - _w > 1.5:
				step = 32
				G.match_node.take_off()
		40:
			if t > 3.0:
				report["back_in_orbit"] = not G.match_node.on_surface and G.vessels.filter(func(v): return v.team == 1 and v.kind == "ship").size() > 0
				_report()
				step = 99


func _report() -> void:
	G.remove_meta("camptest")
	print("CAMPTEST ", report)
	var fails: Array = []
	if not report.get("frigate", false) or not report.get("home_station", false) or report.get("miners", 0) != 2:
		fails.append("the start: a frigate, a starter station and 2 miners")
	if report.get("planets", 0) < 1 or report.get("gates", 0) < 1 or not report.get("trade_post", false):
		fails.append("home system missing planets, gates or the trade post")
	if report.get("ore_delivered", 0) <= 0:
		fails.append("miners didn't bring ore home")
	if report.get("credits_spent", 0) <= 0 or report.get("credits_back", 0) <= 0:
		fails.append("trading didn't move credits")
	if report.get("offers", 0) < 1 or not String(report.get("accepted", "")).begins_with("Job taken"):
		fails.append("no job could be taken")
	if not report.get("services_open", false) or not report.get("map_open", false):
		fails.append("the station screen or the galaxy map didn't open")
	if report.get("jump_timeout", false) or report.get("arrived_in", -1) != report.get("jumped_to", -2):
		fails.append("the jump didn't happen")
	if report.get("ships_here", 0) < 1 or not report.get("near_gate", false):
		fails.append("the fleet didn't arrive at the gate")
	if report.get("miners_after_build", 0) < 3 or not String(report.get("segment", "")).ends_with("built") or not report.get("build_open", false):
		fails.append("building: queue %s, segment %s" % [report.get("order", ""), report.get("segment", "")])
	if not report.get("saved", false) or not report.get("loaded_same", false):
		fails.append("save / load")
	if report.has("landed_on") and (not report.get("on_surface", false) or report.get("surface_ships", 0) < 1 or not report.get("back_in_orbit", false)):
		fails.append("landing / take-off (%s)" % report.get("land_msg", ""))
	if report.has("landed_on") and (report.get("vehicles_deployed", 0) < 1 or report.get("vehicle_path", 0) < 2):
		fails.append("vehicles (deployed %s, path %s)" % [report.get("vehicles_deployed"), report.get("vehicle_path")])
	if report.has("landed_on") and report.get("minidrop_boarding", 0) < 2:
		fails.append("mini dropship loading (%s, %s boarding)" % [report.get("minidrop"), report.get("minidrop_boarding")])
	if report.has("landed_on") and (report.get("depot_crates", 0) < 6 or not "loading" in String(report.get("depot_load", ""))):
		fails.append("ground cargo (%s / %s)" % [report.get("depot_unload"), report.get("depot_load")])
	if report.has("landed_on") and report.get("drive_moved", 0.0) < 2.0:
		fails.append("driving a vehicle (moved %s m)" % report.get("drive_moved"))
	if report.has("landed_on") and report.get("perimeter_guards", 0) < 4:
		fails.append("dropship perimeter guards (%s)" % report.get("perimeter_guards"))
	if report.has("landed_on") and (report.get("outpost_parts", 0) < 8 or not report.get("camp_fallen", false)):
		fails.append("ground installations (parts %s, fallen %s)" % [report.get("outpost_parts"), report.get("camp_fallen")])
	if report.has("landed_on") and (report.get("zones", 0) < 2 or report.get("saved_ground_units", 0) < 1):
		fails.append("zones (%s zones, %s units saved)" % [report.get("zones"), report.get("saved_ground_units")])
	if report.has("landed_on") and (report.get("brood_sacs", 0) < 2 or report.get("gravemind", 0) < 1 or report.get("spreaders", 0) < 1 or report.get("outlaw_convoys", 0) < 1):
		fails.append("infection / convoys (brood %s, gravemind %s, wave %s, spreaders %s, convoys %s)" % [report.get("brood_sacs"), report.get("gravemind"), report.get("wave_members"), report.get("spreaders"), report.get("outlaw_convoys")])
	if report.get("cross_path_gap", 0) > 60:
		fails.append("can't walk from the landing zone across the zone (gap %d m)" % report.get("cross_path_gap", 0))
	if report.has("landed_on") and (not report.get("ground_nav", false) or report.get("deployed", 0) < 1 or report.get("ground_path_pts", 0) < 2):
		fails.append("troops on the open ground (nav %s, deployed %s, path %s)" % [report.get("ground_nav"), report.get("deployed"), report.get("ground_path_pts")])
	for f in fails:
		print("CAMPTEST FAIL: ", f)
	print("CAMPTEST RESULT: %s (%d problems)" % ["PASS" if fails.is_empty() else "FAIL", fails.size()])
	get_tree().quit(0 if fails.is_empty() else 1)


# ------------------------------------------------------------------ frame-rate probe (--perf)
var _pf := {}
func _perf(tt: float) -> void:
	var gnd: Node3D = G.match_node.ground
	var sh: Array = G.vessels.filter(func(v): return v.team == 1 and v.kind == "ship")
	if _pf.is_empty():
		_pf = {"phase": 0, "t0": tt, "frames": 0, "us": Time.get_ticks_usec()}
		G.profiling = true
		if not sh.is_empty():
			sh[0].troops = maxi(sh[0].troops, 8)
			G.match_node.deploy_troops(sh[0])
		return
	_pf["frames"] = int(_pf["frames"]) + 1
	var el: float = tt - float(_pf["t0"])
	if int(_pf["phase"]) == 0 and el > 8.0:
		var us: int = Time.get_ticks_usec() - int(_pf["us"])
		print("PERF baseline: %d frames in %.1f s real -> %.1f fps" % [_pf["frames"], us / 1e6, _pf["frames"] / (us / 1e6)])
		G.stats.clear()
		var VEH = load("res://scripts/campaign/vehicle.gd")
		var base: Vector3 = sh[0].global_position + Vector3(120, 0, 80)
		for kk in ["tank", "mech"]:
			var vv: Node3D = VEH.new()
			vv.setup(kk, 4, 1, gnd, gnd.snap_local(gnd.to_local(base + Vector3(randf_range(-20, 20), 0, randf_range(-20, 20)))))
			print("PERF spawned %s at y %.1f (ground %.1f)" % [kk, vv.global_position.y, G.match_node.ground_y(vv.global_position.x, vv.global_position.z)])
		for k2 in 6:
			G.match_node.spawn_squad(gnd, gnd.snap_local(gnd.to_local(base + Vector3(k2 * 6.0, 0, -30))), 4, 3, ["x", "x", "x", "x", "x", "x", "x", "x", "x", "x"], false)
		for k3 in 3:
			G.match_node.spawn_squad(gnd, gnd.snap_local(gnd.to_local(sh[0].global_position + Vector3(60 + k3 * 8, 0, 0))), 1, 1, ["squad_leader", "rifleman", "rifleman", "heavy", "rifleman", "medic", "breacher", "rifleman"], false)
		print("PERF characters on the ground: ", gnd.occupants.size())
		_pf["phase"] = 1
		_pf["t0"] = tt
		_pf["frames"] = 0
		_pf["us"] = Time.get_ticks_usec()
	elif int(_pf["phase"]) == 1 and el > 10.0:
		var us2: int = Time.get_ticks_usec() - int(_pf["us"])
		print("PERF with infected vehicles: %d frames in %.1f s real -> %.1f fps" % [_pf["frames"], us2 / 1e6, _pf["frames"] / (us2 / 1e6)])
		var ks: Array = G.stats.keys()
		ks.sort_custom(func(a, b): return int(G.stats[a]) > int(G.stats[b]))
		for k in ks.slice(0, 25):
			print("PERF stat ", k, " = ", G.stats[k])
		for v in G.vehicles:
			if is_instance_valid(v) and v.team == 4:
				print("PERF %s y %.1f ground %.1f path %d/%d" % [v.kind, v.global_position.y, G.match_node.ground_y(v.global_position.x, v.global_position.z), v.path_i, v.path.size()])
		get_tree().quit()
