extends Node
## Pictures of the ship doors:  godot --path . res://match.tscn -- --doorshots <folder>
## A closed room door, a boarder kicking it in, the door flat on the deck, a secure
## (bridge) door, a breaching charge on it, and the doorway after it blows.
var out := ""
var steps: Array = []
var i := 0
var wait := 0.0
var cam: Camera3D
var lamp: OmniLight3D
var ship: Node
var plain: Dictionary
var secure: Dictionary
var boarder: Node


func _ready() -> void:
	out = OS.get_cmdline_user_args()[-1]
	DirAccess.make_dir_recursive_absolute(out)
	G.commander.hud.visible = false
	for v in G.vessels:
		if v.get_meta("slot", "") == "flag2":
			ship = v
	for d in ship.doors:
		if plain.is_empty() and d["kind"] == "door" and String(d["name"]).contains("RoomDoor_") and _quiet(d):
			plain = d
		if secure.is_empty() and String(d["name"]).contains("SecureDoor_Bridge"):
			secure = d
	if secure.is_empty():
		for d in ship.doors:
			if d["kind"] == "secure" and String(d["name"]).contains("SecureDoor"):
				secure = d
				break
	cam = Camera3D.new()
	cam.fov = 70.0
	add_child(cam)
	lamp = OmniLight3D.new()
	lamp.omni_range = 9.0
	lamp.light_energy = 0.7
	add_child(lamp)
	steps = [
		[2.0, "room_door_closed", func(): _frame(plain, 3.2, 0.6)],
		[0.5, "boarder_at_door", func(): _spawn_boarder(plain)],
		[0.12, "boarder_kicks", func(): boarder.kick_door(plain)],
		[1.0, "kick_two", func(): boarder.kick_door(plain); boarder.kick_door(plain)],
		[1.5, "door_kicked_flat", func(): _frame(plain, 3.4, 1.5, -1.0)],
		[1.0, "secure_door", func(): _frame(secure, 3.6, 0.4)],
		[0.6, "secure_charge_set", func(): ship.plant_charge(secure, null)],
		[3.0, "secure_blown", func(): pass],
		[1.0, "own_door_opening", func(): _open_own()],
	]


func _quiet(d: Dictionary) -> bool:
	for c in ship.occupants:
		if (c.position - d["center"]).length() < 7.0:
			return false
	return true


func _side(d: Dictionary, dist: float, lat: float, which: float = 1.0) -> Vector3:
	return ship.snap_local(d["center"] - d["n"] * dist * which + d["wa"] * lat)


func _frame(d: Dictionary, dist: float, lat: float, which: float = 1.0) -> void:
	var p: Vector3 = d["center"] - d["n"] * dist * which + d["wa"] * lat + Vector3(0, 0.35, 0)
	cam.global_position = ship.to_global(p)
	cam.look_at(ship.to_global(d["center"] + Vector3(0, -0.3, 0)), ship.global_basis.y)
	lamp.global_position = cam.global_position + ship.global_basis.y * 0.9 - (cam.global_basis.z * -1.0) * 0.8


func _spawn_boarder(d: Dictionary) -> void:
	var p := _side(d, 1.0, 0.0)
	boarder = G.match_node.spawn_character(ship, p, 1, 1, "breacher")
	boarder.set_physics_process(false)                 # hold still for the camera
	var to: Vector3 = d["center"] - boarder.position
	boarder.rotation.y = atan2(-to.x, -to.z)
	# camera off to the side so we see the soldier and the door
	var cp: Vector3 = d["center"] - d["n"] * 2.6 + d["wa"] * 2.2 + Vector3(0, 0.3, 0)
	cam.global_position = ship.to_global(cp)
	cam.look_at(ship.to_global(d["center"] - d["n"] * 0.6 + Vector3(0, -0.4, 0)), ship.global_basis.y)
	lamp.global_position = cam.global_position + ship.global_basis.y * 0.9 - (cam.global_basis.z * -1.0) * 0.8


func _open_own() -> void:
	for d in ship.doors:
		if d["kind"] == "door" and not d["breached"] and d != plain:
			_frame(d, 3.2, 0.8)
			ship._set_door(d, true)
			d["amt"] = 0.55
			ship._door_moving.erase(d)
			var t: Transform3D = d["rest"]
			d["node"].transform = Transform3D(t.basis, t.origin + d["slide"] * 0.5)
			return


func _process(dt: float) -> void:
	if boarder and is_instance_valid(boarder):
		boarder.rig.animate(dt)                         # the kick plays even with physics paused
	cam.make_current()
	if wait > 0.0:
		wait -= dt
		if wait <= 0.0:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [out, i, steps[i][1]])
			print("SHOT ", steps[i][1])
			i += 1
		return
	if i >= steps.size():
		G.quit()
		return
	steps[i][2].call()
	wait = steps[i][0]
