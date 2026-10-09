extends Node
## Pictures of the player-facing features:  godot --path . res://match.tscn -- --features <folder>
var out := ""
var steps: Array = []
var i := 0
var wait := 0.0


func _ready() -> void:
	out = OS.get_cmdline_user_args()[-1]
	DirAccess.make_dir_recursive_absolute(out)
	var cmd: Node = G.commander
	cmd._help = false
	cmd.hud.show_help(false)
	var home: Node = G.match_node.homes[1]
	var ship: Node = _v("UNV Resolute")
	steps = [
		[1.0, "rts_hud", func(): cmd.pivot = ship.global_position; cmd.zoom = 420.0; cmd.select(ship)],
		[2.0, "research", func(): cmd.clear_selection(); cmd.hud.toggle_research()],
		[3.0, "deploy", func(): cmd.hud.close_panels(); cmd.open_deploy()],
		[4.0, "first_person", func(): cmd.deploy("rifleman", ship); G.possessed.look_pitch = -0.05],
		[5.5, "first_person_ads", func(): Input.action_press("aim")],
		[6.5, "helm_walk", func(): Input.action_release("aim"); _to_seat(ship)],
		[7.0, "helm", func(): cmd.take_helm(ship); cmd.chase_yaw = 0.6; cmd.chase_pitch = 0.3],
		[9.0, "helm_firing", func(): ship.manual_fire = true],
		[11.0, "fighter", func(): cmd.leave_vehicle(); _to_pad(ship)],
		[11.5, "fighter_launch", func(): var f: Node = ship.player_launch(G.possessed); if f: cmd.fly_fighter(f)],
		[15.0, "fighter_flight", func(): pass],
	]


func _v(n: String) -> Node:
	for v in G.vessels:
		if v.display_name == n or v.get_meta("slot", "") == {"UNV Resolute": "flag1", "ASC Verdict": "flag2", "UNV Lance": "frigate1",
				"UNV Hammerfall": "dropfrig1", "UNV Provision": "support1", "Pirate Marauder": "pirate_ship"}.get(n, "-"):
			return v
	return null


func _to_seat(ship: Node) -> void:
	var m: Node3D = ship.mark("Bridge_PilotSeat")
	G.possessed.position = ship.snap_local(ship.local_of(m) + Vector3(0, 0, 1.0))


func _to_pad(ship: Node) -> void:
	for p in ship.pads:
		if p["parked"] != null:
			G.possessed.position = ship.snap_local(p["local"] + Vector3(3.0, 0, 0))
			return


func _process(dt: float) -> void:
	if G.possessed and G.possessed.piloting and G.possessed.piloting in G.fighters:
		G.commander._steer += Vector2(1.5, -0.6)          # a gentle banking turn for the camera
	if wait > 0.0:
		wait -= dt
		if wait <= 0.0:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [out, i, steps[i][1]])
			print("SHOT ", steps[i][1])
			i += 1
			if i >= steps.size():
				G.quit()
		return
	if i < steps.size() and G.time >= steps[i][0]:
		steps[i][2].call()
		wait = 0.8
