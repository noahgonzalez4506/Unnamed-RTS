extends Node
## Renders a tour of the match into a folder:  godot --path . -- --shots <folder>
var out := ""
var shots: Array = []
var i := 0
var wait := 0.0


func _ready() -> void:
	out = OS.get_cmdline_user_args()[-1]
	DirAccess.make_dir_recursive_absolute(out)
	Engine.time_scale = 3.0
	G.commander._help = false
	G.commander.hud.show_help(false)
	shots = [
		[1.5, "overview_help", func(): G.commander.hud.show_help(true); _cam(Vector3(0, 0, 0), 3300.0, 0.3, 1.0, -1)],
		[3.0, "home_fleet", func(): G.commander.hud.show_help(false); _cam(_v("UNV Resolute").global_position, 380.0, 0.9, 0.75, -1); _sel(_v("UNV Resolute"))],
		[4.5, "our_ship_deck0", func(): _cam(_v("UNV Resolute").to_global(Vector3(0, 0, 10)), 34.0, 0.5, 1.0, 0); _sel_crew(_v("UNV Resolute"))],
		[6.0, "crew_at_work", func(): _cam(_v("UNV Resolute").to_global(_crew_spot(_v("UNV Resolute"))), 11.0, 0.8, 0.7, 0)],
		[7.5, "station_interior", func(): _cam(_v("Vanguard Bastion").to_global(_v("Vanguard Bastion").aabb.get_center()), 120.0, 0.4, 1.15, 0); _sel(_v("Vanguard Bastion"))],
		[8.5, "engage", func(): _engage()],
		[30.0, "battle", func(): _cam(_v("UNV Resolute").global_position, 330.0, 2.2, 0.45, -1); _sel(_v("UNV Resolute"))],
		[32.0, "turrets_close", func(): _cam(_v("UNV Resolute").to_global(Vector3(0, 8, -20)), 60.0, 2.6, 0.3, -1)],
		[40.0, "board", func(): _board()],
		[48.0, "boarding_pods", func(): _cam(_v("ASC Verdict").global_position, 240.0, 0.7, 0.7, -1)],
		[60.0, "firefight_inside", func(): _cam(_v("ASC Verdict").to_global(_fight_spot(_v("ASC Verdict"))), 22.0, 0.6, 0.9, _fight_deck(_v("ASC Verdict")))],
		[66.0, "direct_control", func(): _possess()],
		[68.0, "direct_control_2", func(): pass],
		[70.0, "derelict", func(): G.commander.release(); _cam(_v("Derelict Calypso").global_position, 420.0, 0.9, 0.6, -1)],
		[71.5, "derelict_inside", func(): _cam(_v("Derelict Calypso").to_global(_infected_spot(_v("Derelict Calypso"))), 26.0, 0.5, 0.95, 0)],
		[73.0, "pirate_haven", func(): _cam(_v("Pirate Haven").to_global(_v("Pirate Haven").aabb.get_center()), 300.0, 0.6, 0.75, -1)],
		[74.5, "pirates_inside", func(): _cam(_v("Pirate Haven").to_global(_crew_spot(_v("Pirate Haven"))), 16.0, 0.9, 0.85, 0)],
	]


func _v(n: String) -> Node:
	for v in G.vessels:
		if v.display_name == n or v.get_meta("slot", "") == {"UNV Resolute": "flag1", "ASC Verdict": "flag2", "UNV Lance": "frigate1",
				"UNV Hammerfall": "dropfrig1", "UNV Provision": "support1", "Pirate Marauder": "pirate_ship"}.get(n, "-"):
			return v
	return null


func _cam(p: Vector3, z: float, yaw: float, pitch: float, deck: int) -> void:
	var cmd: Node = G.commander
	cmd.pivot = p
	cmd.zoom = z
	cmd.yaw = yaw
	cmd.pitch = pitch
	cmd.interior_forced = 1 if deck >= 0 else 0
	cmd.deck = max(deck, 0)


func _sel(u: Node) -> void:
	G.commander.clear_selection()
	G.commander.select(u)


func _sel_crew(v: Node) -> void:
	G.commander.clear_selection()
	var n := 0
	for c in v.occupants:
		if c.team == 1 and c.state == "alive" and c.position.y < 2.0 and n < 4:
			G.commander.select(c)
			n += 1


func _engage() -> void:
	var a: Node = _v("UNV Resolute")
	var b: Node = _v("ASC Verdict")
	a.attack_target = b
	b.attack_target = a
	a.move_target = Vector3(-450, 0, 0)
	b.move_target = Vector3(450, 0, 0)
	a.request_fighters()
	b.request_fighters()


func _board() -> void:
	var a: Node = _v("UNV Resolute")
	var b: Node = _v("ASC Verdict")
	b.shields = 0.0
	a.launch_pods(b, 2)


func _crew_spot(v: Node) -> Vector3:
	for c in v.occupants:
		if is_instance_valid(c) and c.state == "alive" and c.position.y < 2.0 and (c.working or c.carrying):
			return c.position
	for c in v.occupants:
		if is_instance_valid(c) and c.state == "alive" and c.position.y < 2.0:
			return c.position
	return Vector3.ZERO


func _infected_spot(v: Node) -> Vector3:
	for c in v.occupants:
		if is_instance_valid(c) and c.state == "alive" and c.team == 4 and c.position.y < 2.0:
			return c.position
	return Vector3.ZERO


func _fight_spot(v: Node) -> Vector3:
	for c in v.occupants:
		if is_instance_valid(c) and c.state == "alive" and c.team == 1:
			return c.position
	return _crew_spot(v)


func _fight_deck(v: Node) -> int:
	return int(_fight_spot(v).y / 4.0 + 0.3)


func _possess() -> void:
	var b: Node = _v("ASC Verdict")
	for c in b.occupants + _v("UNV Resolute").occupants:
		if is_instance_valid(c) and c.state == "alive" and c.team == 1 and c.armed:
			G.commander.possess(c)
			c.look_pitch = -0.05
			return


func _process(dt: float) -> void:
	if wait > 0.0:
		wait -= dt
		if wait <= 0.0:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [out, i, shots[i][1]])
			print("SHOT ", shots[i][1], " at ", G.time)
			i += 1
			if i >= shots.size():
				G.quit()
		return
	if i < shots.size() and G.time >= shots[i][0]:
		shots[i][2].call()
		wait = 0.7
