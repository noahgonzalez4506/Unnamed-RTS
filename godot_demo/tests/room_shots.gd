extends Node
## Pictures of a flagship's rooms (cutaway from above) and of the whole system:
##   godot --path . res://match.tscn -- --roomshots <folder>
var out := ""
var shots: Array = []
var i := 0
var wait := 0.0
var cmd: Node
var ship: Node


func _ready() -> void:
	out = OS.get_cmdline_user_args()[-1]
	DirAccess.make_dir_recursive_absolute(out)
	cmd = G.commander
	cmd._help = false
	cmd.hud.show_help(false)
	for v in G.vessels:
		if v.get_meta("slot", "") == "flag1":
			ship = v
	for pat in ["Armory_1_Resupply", "Berthing_1_Deck*", "Quarters_1_Cabin1_Deck*", "Mess_1_Deck*", "Workshop_1_Deck*",
			"Medbay_1_MedpenResupply", "Storage_1_Stores_Deck*", "Comms_1_Deck*",
			"PodBay_Port_Muster", "DropBay_Muster", "Bunk_Berthing_T*", "Medbay_T*", "ReadyRoom_T*", "BayAccess_1_Bottom",
			"Hangar_ShuttlePad"]:
		var m: Array = ship.marks_like(pat)
		if not m.is_empty():
			shots.append([pat.replace("*", "").to_lower(), m[0]])
	shots.append(["system", null])
	for v in G.vessels:
		if v.kind == "ship" and v.get_meta("slot", "") in ["flag1", "flag2", "pirate_ship", "derelict", "support1", "dropfrig1", "frigate1"]:
			shots.append(["ship_" + v.display_name.replace(" ", "_"), v])


func _process(dt: float) -> void:
	if wait > 0.0:
		wait -= dt
		if wait <= 0.0:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [out, i, shots[i][0]])
			print("SHOT ", shots[i][0])
			i += 1
		return
	if i >= shots.size():
		G.quit()
		return
	if G.time < 3.0:
		return
	var s: Array = shots[i]
	cmd.clear_selection()
	if s[0] == "system":
		cmd.interior_forced = 0
		cmd.pivot = Vector3.ZERO
		cmd.zoom = 3400.0
		cmd.pitch = 1.2
	elif s[0].begins_with("ship_"):
		cmd.interior_forced = 0
		var v: Node = s[1]
		cmd.pivot = v.to_global(v.aabb.get_center())
		cmd.zoom = v.aabb.size.length() * 0.9
		cmd.pitch = 0.55
		cmd.yaw = v.rotation.y + 0.9
	else:
		var m: Node3D = s[1]
		cmd.interior_forced = 1
		cmd.deck = int(round(ship.local_of(m).y / 4.0))
		cmd.pivot = m.global_position
		cmd.zoom = 24.0
		cmd.pitch = 1.05
		cmd.yaw = ship.rotation.y + 0.3
	wait = 1.2
