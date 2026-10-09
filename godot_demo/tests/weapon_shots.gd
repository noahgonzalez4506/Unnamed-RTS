extends Node
## First-person weapon pictures:  godot --path . res://match.tscn -- --weaponshots [--only <text>] <folder>
## --only keeps the shots whose gun or pose name contains <text> (e.g. --only BattleRifle, --only kit).
## Each gun type: at the hip looking level, up and down; aimed down the sights.
## "tp_*" shots look at the soldier from outside (third person) to check the hands and stock.

var out := ""
var t := 0.0
var c: Node
var shots: Array = []
var i := 0
var wait := 0.0


func _ready() -> void:
	out = OS.get_cmdline_user_args()[-1]
	DirAccess.make_dir_recursive_absolute(out)
	for m in ["F1_AssaultRifle", "F1_Magnum", "F1_BattleRifle", "F1_Sniper", "F2_PlasmaRifle", "F1_Shotgun"]:
		for pose in ["hip", "up", "down", "ads"]:
			shots.append([m, pose])
	shots.append(["F1_AssaultRifle", "reload"])
	shots.append(["F1_AssaultRifle", "sprint"])
	shots.append(["F1_BattleRifle", "reload"])
	for pose in ["tp_side", "tp_left", "tp_front", "tp_top", "tp_ads", "tp_reload"]:
		shots.append(["F1_BattleRifle", pose])
	shots.append(["F1_AssaultRifle", "tp_side"])
	for pose in ["hip", "ads", "reload", "tp_side", "tp_left", "tp_front"]:
		shots.append(["F1_BullpupGL", pose])
	for pose in ["tp_kit_front", "tp_kit_right", "tp_kit_back"]:   # the grenadier's belt
		shots.append(["F1_BullpupGL", pose])
	shots.append(["F2_BullpupGL", "hip"])
	shots.append(["F2_BullpupGL", "tp_side"])
	for pose in ["tp_kit_front", "tp_kit_right", "tp_kit_back"]:   # a real faction 2 grenadier (full kit)
		shots.append(["F2_BullpupGL", pose])
	var args := OS.get_cmdline_user_args()
	var only := args.find("--only")
	if only >= 0 and only + 1 < args.size() - 1:
		var key: String = args[only + 1]
		shots = shots.filter(func(s: Array) -> bool: return String(s[0]).contains(key) or String(s[1]).contains(key))
	process_priority = 1000                 # after the commander has placed its camera


func _physics_process(dt: float) -> void:
	t += dt
	if t < 3.0:
		return
	if c == null:
		for v in G.vessels:
			if v.get_meta("slot", "") == "flag1":
				for o in v.occupants:
					if o.role == "rifleman" and o.state == "alive":
						c = o
						break
		G.match_node.ai.attack_after = 99999.0
		G.commander.possess(c)
		G.commander._help = false
		G.commander.hud.show_help(false)
		# stand them in a hangar looking down its length (room to see)
		var pads: Array = c.vessel.marks_like("Hangar_ShuttlePad")
		if not pads.is_empty():
			c.position = c.vessel.snap_local(c.vessel.local_of(pads[0]) + Vector3(0, 0, 9))
		c.look_yaw = 0.0
		return
	if busy:
		return
	if wait > 0.0:
		wait -= dt
		# hold the pose every frame (the player code would otherwise reset it)
		_pose()
		if wait <= 0.0:
			busy = true
			_snap()
		return
	if i >= shots.size():
		G.quit()
		return
	if shots[i][1].begins_with("tp_kit") and String(shots[i][0]).begins_with("F2") and c.faction != 2:
		_swap_in_f2_grenadier()
	if c.weapon_model != shots[i][0]:
		c.give_weapon(shots[i][0])
	_pose()
	wait = 1.4


var busy := false


## Faction 2's kit is built for its own body, so look at a real F2 grenadier: spawned where the
## rifleman stood, taken over, and the rifleman hidden.
func _swap_in_f2_grenadier() -> void:
	var g: Node = G.match_node.spawn_character(c.vessel, c.position, c.team, 2, "grenadier")
	g.rotation.y = c.rotation.y
	g.look_yaw = c.look_yaw
	G.commander.release()
	c.visible = false
	c.order = {"type": "hold", "pos": c.position, "vessel": c.vessel}
	G.commander.possess(g)
	c = g


func _pose() -> void:
	var s: Array = shots[i]
	if s[1].begins_with("tp_kit") and c.gl_rounds.is_empty():
		c._grenadier_kit()                       # same armour as the rifleman we're looking at
		c.gl_ammo = 4                            # two shells fired, one breaching round used
		c.breach_ammo = 1
		c.kit_refresh()
	var tp: bool = s[1].begins_with("tp_")
	c.rig.set_first_person(not tp)
	c.set_meta("force_ads", s[1] in ["ads", "tp_ads"])
	c.look_pitch = {"up": 0.95, "down": -0.95}.get(s[1], 0.0)
	if s[1] in ["reload", "tp_reload"] and c.reload_t < 0.5:
		c.reload_t = 1.2


## Third-person shots: move the commander's camera off the soldier once it has been placed.
func _process(_dt: float) -> void:
	if c == null or i >= shots.size() or not shots[i][1].begins_with("tp_"):
		return
	G.commander.viewmodel.visible = false
	var cam: Camera3D = G.commander.fps_cam
	var yb := Basis(Vector3.UP, c.global_rotation.y)
	var fwd := -yb.z
	var right := yb.x
	var at: Vector3 = c.global_position + Vector3.UP * 1.3 + fwd * 0.25
	if shots[i][1].begins_with("tp_kit"):
		at = c.global_position + Vector3.UP * 0.98                  # the belt
	var from: Vector3 = {
		"tp_side": at + right * 1.3,
		"tp_left": at - right * 1.3,
		"tp_front": at + fwd * 1.4 + right * 0.5,
		"tp_top": at + Vector3.UP * 1.0 + right * 0.4 - fwd * 0.3,
		"tp_ads": at + right * 1.1 + fwd * 0.3,
		"tp_reload": at + right * 0.9 + fwd * 0.7 - Vector3.UP * 0.2,
		"tp_kit_front": at + fwd * 1.6 + right * 0.45 - Vector3.UP * 0.1,      # under the gun
		"tp_kit_right": at + right * 1.0 + fwd * 0.2 + Vector3.UP * 0.15,
		"tp_kit_back": at - fwd * 1.0 + right * 0.4 + Vector3.UP * 0.3,
	}[shots[i][1]]
	cam.fov = 50.0
	cam.look_at_from_position(from, at)


func _snap() -> void:
	await RenderingServer.frame_post_draw
	if i >= shots.size():
		return
	var s: Array = shots[i]
	get_viewport().get_texture().get_image().save_png("%s/%02d_%s_%s.png" % [out, i, s[0], s[1]])
	print("SHOT ", s[0], " ", s[1])
	i += 1
	busy = false
