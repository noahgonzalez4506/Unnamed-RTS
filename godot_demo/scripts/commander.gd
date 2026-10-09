extends Node3D
## The player: RTS commander camera and orders, plus direct control of any of your
## soldiers or crew in first person. The HUD lives in hud.gd.

var TEAM := 1                  # the side this player commands (G.player_team)
const CUT_DECK_OFFSET := 2.7
const HUD := preload("res://scripts/hud.gd")

var cam: Camera3D
var fps_cam: Camera3D
var hud: Control
var pivot := Vector3(-1500, 0, 120)
var yaw := 0.6
var pitch := 0.95
var zoom := 520.0
var selection: Array = []
var interior := false          # cutaway view
var interior_forced := -1      # -1 auto, 0 off, 1 on
var deck := 0
var _drag_from := Vector2.INF
var _drag_rect: Panel
var _mid_drag := false
var _back_t := -1.0
var _labels := {}
var _ui_t := 0.0
var _look_t := 0.0
var _look_text := ""
var _help := true
var _pending := ""             # "board": the next right click picks a pod target
var chase_yaw := 0.0           # piloting: the chase camera
var chase_pitch := 0.25
var chase_dist := 0.0
var _steer := Vector2.ZERO
var soldier_mode := false      # started as a soldier: no fleet orders, respawn through the deploy screen
var _respawn_t := -1.0
var camp_ui: Control = null    # campaign screens (galaxy map, station services)
var viewmodel: Node3D             # the first-person gun (viewmodel.gd)
var _roof_lvl := -1
var _emp_rect: ColorRect          # EMP static over the first-person view (emp_static)
var _emp_t := 0.0
var _emp_len := 0.0

const EMP_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	float t = TIME;
	vec2 uv = SCREEN_UV;
	// tearing: random bands of rows jump sideways
	float band = floor(uv.y * 48.0) + floor(t * 18.0) * 7.0;
	float tear = (hash(vec2(band, floor(t * 24.0))) - 0.5) * step(0.82, hash(vec2(band * 1.7, floor(t * 12.0))));
	uv.x += tear * 0.06 * strength;
	// blurred, washed-out and dimmed view
	vec3 col = textureLod(screen_tex, uv, 3.5 * strength).rgb;
	float grey = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(grey) * vec3(0.75, 0.9, 1.1), 0.7 * strength) * (1.0 - 0.45 * strength);
	// snow and scanlines
	float n = hash(floor(FRAGCOORD.xy / 2.0) + fract(t * 61.0) * 113.0);
	float scan = 0.85 + 0.15 * sin(FRAGCOORD.y * 1.6 + t * 40.0);
	col = mix(col, vec3(n) * vec3(0.7, 0.85, 1.0), 0.45 * strength) * mix(1.0, scan, strength);
	COLOR = vec4(col, 1.0);
}
"""


var pause_menu: CanvasLayer


func _ready() -> void:
	G.commander = self
	TEAM = G.player_team
	_inputs()
	pause_menu = load("res://scripts/pause_menu.gd").new()
	add_child(pause_menu)
	cam = Camera3D.new()
	cam.far = 14000.0
	cam.near = 0.3
	cam.fov = 55.0
	add_child(cam)
	fps_cam = Camera3D.new()
	fps_cam.far = 9000.0
	fps_cam.near = 0.05
	fps_cam.fov = 80.0
	add_child(fps_cam)
	var lamp := SpotLight3D.new()
	lamp.spot_range = 18.0
	lamp.spot_angle = 30.0
	lamp.spot_attenuation = 1.6
	lamp.light_energy = 0.35
	lamp.light_cull_mask = 0xFFFFF & ~2           # not the first-person gun (render layer 2): it would glare
	fps_cam.add_child(lamp)
	viewmodel = load("res://scripts/viewmodel.gd").new()
	fps_cam.add_child(viewmodel)
	cam.current = true
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = HUD.new()
	hud.cmd = self
	layer.add_child(hud)
	var ab: Control = load("res://scripts/action_bar.gd").new()
	ab.cmd = self
	layer.add_child(ab)
	if G.campaign != null and G.config.get("mode", "") == "campaign":
		camp_ui = load("res://scripts/campaign/campaign_ui.gd").new()
		camp_ui.cmd = self
		layer.add_child(camp_ui)
	_drag_rect = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.4, 0.7, 1.0, 0.1)
	sb.border_color = Color(0.45, 0.8, 1.0, 0.9)
	sb.set_border_width_all(1)
	_drag_rect.add_theme_stylebox_override("panel", sb)
	_drag_rect.visible = false
	_drag_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.rts.add_child(_drag_rect)
	hud.show_help(_help)
	var emp_layer := CanvasLayer.new()
	emp_layer.layer = 10                           # over the HUD, under the pause menu
	add_child(emp_layer)
	_emp_rect = ColorRect.new()
	_emp_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_emp_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = EMP_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	_emp_rect.material = mat
	_emp_rect.visible = false
	emp_layer.add_child(_emp_rect)


## The player's body was EMP'd: static over the view for t seconds, fading out.
func emp_static(t: float) -> void:
	if t > _emp_t:
		_emp_t = t
		_emp_len = t
	_emp_rect.visible = true


func _emp_frame(dt: float) -> void:
	var c: Node = G.possessed
	if c == null or not is_instance_valid(c) or c.state != "alive":
		_emp_t = 0.0
	_emp_t -= dt
	if _emp_t <= 0.0:
		_emp_rect.visible = false
		return
	# full strength for the first part, then fade out over the last 60 %
	var k := clampf(_emp_t / maxf(_emp_len * 0.6, 0.01), 0.0, 1.0)
	(_emp_rect.material as ShaderMaterial).set_shader_parameter("strength", k)


func _inputs() -> void:
	var keys := {"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D,
		"jump": KEY_SPACE, "sprint": KEY_SHIFT, "crouch": KEY_C, "use": KEY_E, "reload": KEY_R,
		"grenade": KEY_G, "medpen": KEY_Q, "possess": KEY_TAB, "rot_left": KEY_Q, "rot_right": KEY_E,
		"interior": KEY_X, "deck_up": KEY_UP, "deck_down": KEY_DOWN, "board": KEY_B,
		"fighters": KEY_L, "train": KEY_T, "hold": KEY_H, "sabotage": KEY_K, "help": KEY_F1,
		"dash": KEY_V, "deploy": KEY_J, "research": KEY_Y, "shuttle": KEY_N, "missiles": KEY_M, "resupply": KEY_U,
		"launcher": KEY_B}
	for a in keys:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
			var ev := InputEventKey.new()
			ev.physical_keycode = keys[a]
			InputMap.action_add_event(a, ev)
	if not InputMap.has_action("aim"):
		InputMap.add_action("aim")
		var rb := InputEventMouseButton.new()
		rb.button_index = MOUSE_BUTTON_RIGHT
		InputMap.action_add_event("aim", rb)
	if not InputMap.has_action("fire"):
		InputMap.add_action("fire")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("fire", mb)


# ------------------------------------------------------------------ per frame

func _process(dt: float) -> void:
	var c: Node = G.possessed
	if c and is_instance_valid(c) and c.state == "alive" and not c.gunning.is_empty():
		_gun_frame(dt)
	elif c and is_instance_valid(c) and c.state == "alive" and c.piloting:
		_vehicle_frame(dt)
	elif c and is_instance_valid(c) and c.state == "alive" and c.riding:
		_ride_frame(dt)
	elif c and is_instance_valid(c) and c.state == "alive":
		_fps_frame(dt)
	else:
		if c and _back_t < 0.0:
			_back_t = 2.0
		if _back_t >= 0.0:
			_back_t -= dt
			if _back_t < 0.0:
				release()
				if soldier_mode:
					_respawn_t = 4.0
		if _respawn_t >= 0.0:
			_respawn_t -= dt
			if _respawn_t < 0.0:
				open_deploy()
		_rts_frame(dt)
	if _emp_rect.visible:
		_emp_frame(dt)
	_ui_t -= dt
	if _ui_t <= 0.0:
		_ui_t = 0.25
		_update_labels()
		hud.refresh()
	if G.possessed and is_instance_valid(G.possessed):
		_look_t -= dt
		if _look_t <= 0.0:
			_look_t = 0.2
			_look_text = _look_prompt()
		hud.refresh_fps(G.possessed, _look_text)


func _rts_frame(dt: float) -> void:
	cam.current = true
	var pan := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	pivot += Basis(Vector3.UP, yaw) * Vector3(pan.x, 0, pan.y) * zoom * 0.9 * dt * (2.5 if Input.is_action_pressed("sprint") else 1.0)
	if G.match_node and G.match_node.get("on_surface") and not G.match_node.terrain_P.is_empty():
		var gy: float = G.match_node.ground_y(pivot.x, pivot.z) + 1.5
		pivot.y = lerpf(pivot.y, gy, clampf(dt * 6.0, 0.0, 1.0)) if absf(pivot.y - gy) < 60.0 else gy
	if Input.is_action_pressed("rot_left"):
		yaw += dt * 1.4
	if Input.is_action_pressed("rot_right"):
		yaw -= dt * 1.4
	cam.global_position = pivot + Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -pitch) * Vector3(0, 0, zoom)
	cam.look_at(pivot, Vector3.UP)
	interior = (zoom < 180.0) if interior_forced < 0 else interior_forced == 1
	var base_y := 0.0
	if interior and G.match_node and G.match_node.get("on_surface"):
		# on a world the ships sit on the ground: slice the one we're looking at, at its own decks
		var bd := 1.0e9
		for v in G.vessels:
			if is_instance_valid(v) and not v.destroyed and v.kind == "ship":
				var dd: float = Vector2(v.global_position.x - pivot.x, v.global_position.z - pivot.z).length()
				if dd < bd:
					bd = dd
					base_y = v.global_position.y
		if bd > 400.0:
			base_y = pivot.y                         # (nothing near: slice at the ground we're looking at)
	var cut := base_y + deck * 4.0 + CUT_DECK_OFFSET if interior else 10000.0
	if G.match_node and G.match_node.get("on_surface"):
		# the cutaway on a world: see into buildings, floor by floor
		var lvl: int = (deck + 1) if interior else 99
		if lvl != _roof_lvl:
			_roof_lvl = lvl
			for rf in G.match_node.roofs:
				if is_instance_valid(rf[0]):
					rf[0].visible = int(rf[1]) <= lvl - 1 or not interior
	G.set_cut(cut)
	for c in G.characters:
		if is_instance_valid(c):
			c.ring.visible = c.state != "dead" and (c.selected or (interior and zoom < 120.0 and c.team == TEAM))
	if _drag_from != Vector2.INF:
		var r := Rect2(_drag_from, get_viewport().get_mouse_position() - _drag_from).abs()
		_drag_rect.position = r.position
		_drag_rect.size = r.size
		_drag_rect.visible = r.size.length() > 6.0


func _fps_frame(_dt: float) -> void:
	hud.set_mode_fps(true)
	var c: Node = G.possessed
	fps_cam.current = true
	G.set_cut(10000.0)
	var head: Node3D = c.rig.b.get("Head")
	var hp_: Vector3 = head.global_position if head else c.global_position + Vector3.UP * 1.6
	fps_cam.global_position = hp_ + Vector3.UP * 0.08
	fps_cam.global_rotation = Vector3(c.look_pitch + c.kick * 0.01, c.global_rotation.y, 0)
	var base_fov: float = G.settings.get("fov", 85.0)
	var zoom_ := 1.0
	if c.ads:
		zoom_ = 0.8 if viewmodel.kind == "scope" else 0.72      # scopes magnify through the lens instead
	fps_cam.fov = lerpf(fps_cam.fov, base_fov * zoom_, clampf(_dt * 14.0, 0.0, 1.0))
	viewmodel.update(c, fps_cam, _dt)
	pivot = c.global_position


## Riding a boarding pod or shuttle: a chase camera on the craft until it hits.
func _ride_frame(dt: float) -> void:
	hud.set_mode_fps(true)
	var craft: Node3D = G.possessed.riding
	if not is_instance_valid(craft):
		return
	fps_cam.current = true
	fps_cam.fov = G.settings.get("fov", 85.0)
	G.set_cut(10000.0)
	var shuttle: bool = craft.has_method("_unload")
	var dist := 26.0 if shuttle else 14.0
	var yaw_: float = craft.global_rotation.y + chase_yaw
	var want: Vector3 = craft.global_position + Basis(Vector3.UP, yaw_) * Vector3(0, 0, dist) + Vector3.UP * dist * 0.35
	fps_cam.global_position = fps_cam.global_position.lerp(want, clampf(dt * 6.0, 0.0, 1.0))
	var tgt: Node = craft.get("target")
	var look: Vector3 = craft.global_position
	if tgt and is_instance_valid(tgt):
		look = look.lerp(tgt.global_position, 0.02)
	fps_cam.look_at(look, Vector3.UP)
	pivot = craft.global_position


## Piloting: a chase camera behind the ship or fighter, and its controls.
func _vehicle_frame(dt: float) -> void:
	var c: Node = G.possessed
	var v: Node = c.piloting
	if not is_instance_valid(v) or v.get("destroyed") == true:
		leave_vehicle()
		return
	fps_cam.current = true
	fps_cam.fov = G.settings.get("fov", 85.0)
	G.set_cut(10000.0)
	if v.get("is_vehicle") == true:
		_drive_frame(dt, v)
		return
	var fighter: bool = v in G.fighters
	var center: Vector3 = v.global_position if fighter else v.to_global(v.aabb.get_center())
	if chase_dist <= 0.0:
		chase_dist = 18.0 if fighter else v.aabb.size.length() * 0.75
	if fighter:
		var sens: float = G.settings.get("sens", 1.0)
		v.player_fly(dt, _steer * 0.0022 * sens, Input.get_axis("move_left", "move_right"),
			Input.get_axis("move_back", "move_forward"), Input.is_action_pressed("sprint"), Input.is_action_pressed("fire"))
		_steer = Vector2.ZERO
		var back: Vector3 = v.global_basis.z * chase_dist + v.global_basis.y * chase_dist * 0.28
		fps_cam.global_position = fps_cam.global_position.lerp(center + back, clampf(dt * 8.0, 0.0, 1.0))
		fps_cam.look_at(center - v.global_basis.z * 40.0, v.global_basis.y)
	else:
		v.helm_throttle = Input.get_axis("move_back", "move_forward")
		v.helm_turn = Input.get_axis("move_left", "move_right")
		var rot := Basis(Vector3.UP, v.rotation.y + chase_yaw) * Basis(Vector3.RIGHT, -chase_pitch)
		fps_cam.global_position = center + rot * Vector3(0, 0, chase_dist) + Vector3.UP * v.aabb.size.y
		fps_cam.look_at(center + Vector3.UP * v.aabb.size.y * 0.5, Vector3.UP)
		var from := fps_cam.global_position
		var to := from - fps_cam.global_basis.z * 4000.0
		var q := PhysicsRayQueryParameters3D.create(from, to, G.LAYER_PICK | G.LAYER_WORLD)
		q.collide_with_areas = true
		q.exclude = [v.pick.get_rid()]
		var h := get_world_3d().direct_space_state.intersect_ray(q)
		v.manual_aim = h.position if not h.is_empty() and v.aabb.grow(10.0).has_point(v.to_local(h.position)) == false else to
		v.manual_fire = Input.is_action_pressed("fire")
		if G.is_client():
			G.network.send_helm(v)
	pivot = center


## Driving a ground vehicle: a chase camera you swing with the mouse; the turret follows
## where the camera points.
func _drive_frame(dt: float, v: Node) -> void:
	var mech: bool = v.kind == "mech"
	if chase_dist <= 0.0:
		chase_dist = 11.0 if mech else 15.0
	var center: Vector3 = v.global_position + Vector3.UP * (5.0 if mech else 3.0)
	var rot := Basis(Vector3.UP, v.rotation.y + chase_yaw) * Basis(Vector3.RIGHT, -chase_pitch)
	var want: Vector3 = center + rot * Vector3(0, 0, chase_dist) + Vector3.UP * 1.5
	fps_cam.global_position = fps_cam.global_position.lerp(want, clampf(dt * 10.0, 0.0, 1.0))
	fps_cam.look_at(center + Vector3.UP * 1.0, Vector3.UP)
	var from := fps_cam.global_position
	var to := from - fps_cam.global_basis.z * 1500.0
	var q := PhysicsRayQueryParameters3D.create(from, to, G.LAYER_WORLD | G.LAYER_CHAR)
	var ex: Array = []
	for ch in v.get_children():
		if ch is StaticBody3D:
			ex.append(ch.get_rid())
	q.exclude = ex
	var h := get_world_3d().direct_space_state.intersect_ray(q)
	var aim: Vector3 = h.position if not h.is_empty() else to
	v.player_drive(dt, Input.get_axis("move_back", "move_forward"), Input.get_axis("move_left", "move_right"),
		Input.is_action_pressed("sprint"), aim, Input.is_action_pressed("fire"), Input.is_action_pressed("aim"))
	pivot = v.global_position


## E beside one of your vehicles on a world (or Tab on a selected one): take the controls.
func drive(v: Node) -> void:
	var c: Node = G.possessed
	if v.driver != null and is_instance_valid(v.driver) and v.driver != c:
		log_event("Someone's already driving that", TEAM)
		return
	c.piloting = v
	v.driver = c
	c.visible = false
	c.collision_layer = 0
	c.stop()
	chase_dist = 0.0
	chase_yaw = 0.0
	chase_pitch = 0.25
	c.rig.set_first_person(false)
	log_event("Driving the %s. W/S drive, A/D steer, Shift boost, mouse aims, LMB/RMB fire, E get out." % v.display_name, TEAM)


func _vehicle_near(c: Node) -> Node:
	for v in G.vehicles:
		if is_instance_valid(v) and v.team == c.team and v.cargo_of == null and v.global_position.distance_to(c.global_position) < 7.0:
			return v
	return null


# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	# Esc: close whatever's open first; with nothing open (and the mouse free) it pauses
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		var busy: bool = (camp_ui != null and camp_ui.any_open()) or hud.deploy_open() or hud.research_open() or _help
		var fps_captured: bool = G.possessed != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		if not busy and not fps_captured and _pending == "":
			pause_menu.open()
			return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F7:
		G.settings["fog"] = not bool(G.settings.get("fog", true))
		log_event("Fog of war %s" % ("ON" if G.settings["fog"] else "off"), TEAM)
		return
	if camp_ui and camp_ui.placing != "" and event is InputEventMouseButton and event.pressed:
		camp_ui.place_click(event)
		return
	if camp_ui and event is InputEventKey and event.pressed and not event.echo:
		var kk: int = event.physical_keycode
		if kk == KEY_O and not G.possessed:
			camp_ui.toggle_map()
			return
		if kk == KEY_P and not G.possessed:
			camp_ui.toggle_services()
			return
		if kk == KEY_I and not G.possessed:
			camp_ui.toggle_build("ships" if event.shift_pressed else "units")
			return
		if kk == KEY_G and not G.possessed:
			camp_ui.toggle_build("station")
			return
		if kk == KEY_Z and not G.possessed:
			camp_ui.toggle_zones()
			return
		if kk == KEY_C and not G.possessed:
			camp_ui.toggle_crew()
			return
		if kk == KEY_N and not G.possessed:
			camp_ui.toggle_base()
			return
		if kk == KEY_R and camp_ui.placing.begins_with("g:"):
			camp_ui.ghost_yaw += PI * 0.25
			return
		if kk == KEY_F5:
			G.campaign.snapshot()
			log_event("Campaign saved" if G.campaign.save() else "Couldn't save", TEAM)
			return
		if kk == KEY_ESCAPE and camp_ui.any_open():
			camp_ui.close_all()
			return
	if event.is_action_pressed("help"):
		_help = not _help
		hud.show_help(_help)
		return
	if event.is_action_pressed("deploy") and not hud.deploy_open():
		open_deploy()
		return
	if event.is_action_pressed("research") and not G.possessed:
		hud.toggle_research()
		return
	if event.is_action_pressed("ui_cancel") and (hud.deploy_open() or hud.research_open()):
		hud.close_panels()
		return
	if G.possessed:
		_fps_input(event)
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if _help and mb.pressed:
			_help = false
			hud.show_help(false)
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom = max(4.0, zoom * 0.85)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom = min(5200.0, zoom * 1.18)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_mid_drag = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag_from = mb.position
			else:
				_finish_select(mb.position, mb.shift_pressed, mb.double_click)
				_drag_from = Vector2.INF
				_drag_rect.visible = false
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			order_at(mb.position, mb.shift_pressed)
	elif event is InputEventMouseMotion and _mid_drag:
		yaw -= event.relative.x * 0.006
		pitch = clampf(pitch + event.relative.y * 0.004, 0.25, 1.45)
	elif event.is_action_pressed("possess"):
		possess_selected()
	elif event.is_action_pressed("interior"):
		interior_forced = 1 if not interior else 0
	elif event.is_action_pressed("deck_up"):
		deck = min(deck + 1, 2)
		interior_forced = 1
	elif event.is_action_pressed("deck_down"):
		deck = max(deck - 1, -1)
	elif event.is_action_pressed("board"):
		cmd_board()
	elif event.is_action_pressed("fighters"):
		cmd_fighters()
	elif event.is_action_pressed("train"):
		cmd_train()
	elif event.is_action_pressed("hold"):
		var chars: Array = selection.filter(func(c): return is_instance_valid(c) and c.get("rig") != null)
		if not chars.is_empty():
			G.match_node.command("hold", [_ids(chars)])
	elif event.is_action_pressed("sabotage"):
		cmd_sabotage()
	elif event.is_action_pressed("resupply"):
		for s in selection:
			if is_instance_valid(s) and s.get("kind") == "ship" and s.team == TEAM:
				G.match_node.command("resupply", [G.vessels.find(s)])
	elif event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode
		if k >= KEY_1 and k <= KEY_4:
			_quick_select(k - KEY_1)


func _fps_input(event: InputEvent) -> void:
	var c: Node = G.possessed
	var sens: float = G.settings.get("sens", 1.0)
	if not c.gunning.is_empty():
		_gun_input(event, sens)
		return
	if c.piloting:
		_vehicle_input(event)
		return
	if c.riding:
		if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			chase_yaw -= event.relative.x * 0.004
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode
		if k >= KEY_0 and k <= KEY_9 and c.squad and c.squad.leader == c:
			squad_order(SQUAD_KEYS[(k - KEY_0 + 9) % 10])
			return
	if event.is_action_pressed("train"):
		requisition()
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var ads_scale := 0.55 if c.ads else 1.0
		c.look_yaw -= event.relative.x * 0.0025 * sens * ads_scale
		c.look_pitch = clampf(c.look_pitch - event.relative.y * 0.0025 * sens * ads_scale, -1.45, 1.45)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed("possess") and not soldier_mode:
		release()
	elif event.is_action_pressed("use"):
		interact()


func _vehicle_input(event: InputEvent) -> void:
	var c: Node = G.possessed
	var v: Node = c.piloting
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if v in G.fighters:
			_steer += event.relative
		else:
			chase_yaw -= event.relative.x * 0.004
			chase_pitch = clampf(chase_pitch + event.relative.y * 0.003, -0.2, 1.2)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			chase_dist = max(8.0, chase_dist * 0.88)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			chase_dist = min(900.0, chase_dist * 1.14)
		elif Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("use"):
		leave_vehicle()
	elif event.is_action_pressed("possess") and v.get("is_vehicle") == true:
		release()
	elif event.is_action_pressed("train") and v.has_method("fire_missiles"):
		helm_lock()
	elif event.is_action_pressed("board") and v.has_method("start_boarding"):
		_helm_op("pods")
	elif event.is_action_pressed("shuttle") and v.has_method("start_boarding"):
		_helm_op("shuttle")
	elif event.is_action_pressed("missiles") and v.has_method("fire_missiles"):
		_helm_op("missiles")
	elif event.is_action_pressed("fighters") and v.has_method("request_fighters"):
		v.request_fighters()
	elif event is InputEventKey and event.pressed and not event.echo and v.has_method("fire_missiles"):
		var k: int = event.physical_keycode
		if k >= KEY_1 and k <= KEY_4:
			var op: String = ["attack", "form", "hold", "board"][k - KEY_1]
			G.match_node.command("fleet", [G.vessels.find(v), op])
			log_event({"attack": "Fleet: attack my lock", "form": "Fleet: form on me", "hold": "Fleet: hold position",
				"board": "Fleet: board my lock"}[op], TEAM)


## T at the helm: lock what the guns are aimed at (or the nearest enemy ahead); T again clears it.
func helm_lock() -> void:
	var v: Node = G.possessed.piloting
	var t := _vessel_under(v.manual_aim)
	if t == null or t == v or not G.enemies(v.team, t.team):
		var best: Node = null
		var bd := 3000.0
		var fwd: Vector3 = -fps_cam.global_basis.z
		for o in G.vessels:
			if o != v and not o.destroyed and G.enemies(v.team, o.team):
				var to: Vector3 = o.global_position - fps_cam.global_position
				var d := to.length()
				if d < bd and fwd.dot(to.normalized()) > 0.8:
					bd = d
					best = o
		t = best
	if t == null or t == v.lock:
		G.match_node.command("lock", [G.vessels.find(v), -1])
		log_event("Target lock cleared" if t == null and v.lock else "No target: aim at an enemy ship or station, then T", TEAM)
		return
	G.match_node.command("lock", [G.vessels.find(v), G.vessels.find(t)])
	log_event("LOCKED: %s  ·  M missiles, B pods, N shuttle, 1 fleet attack, 4 fleet board" % t.display_name, TEAM)


func _helm_op(op: String) -> void:
	var v: Node = G.possessed.piloting
	if v.lock == null or not is_instance_valid(v.lock):
		log_event("Lock a target first (T)", TEAM)
		return
	G.match_node.command(op if op == "missiles" else "board", [G.vessels.find(v), G.vessels.find(v.lock)] + ([] if op == "missiles" else [op]))


const SQUAD_KEYS := ["follow", "hold", "move", "breach", "suppress", "regroup", "formation", "split", "fire", "grenade"]
const SQUAD_SAY := {"follow": "Squad: on me", "hold": "Squad: hold here", "move": "Squad: move up",
	"breach": "Squad: stack up, breach and clear", "suppress": "Squad: suppressing fire!", "regroup": "Squad: regroup on me",
	"formation": "Squad: change formation", "split": "Fireteam B: move / rejoin", "fire": "Squad: weapons free / tight",
	"grenade": "Squad: frag out"}


## FPS number keys when you lead a squad (see match.squad_command).
func squad_order(op: String) -> void:
	var c: Node = G.possessed
	var p := Vector3.INF
	if op in ["move", "breach", "suppress", "split", "grenade"]:
		var hit := G.ray(fps_cam.global_position, fps_cam.global_position - fps_cam.global_basis.z * 60.0, [c.get_rid()],
			G.LAYER_WORLD | G.LAYER_DOOR)
		if hit.is_empty():
			log_event("Aim at the deck or a door to send the squad there", TEAM)
			return
		p = c.vessel.to_local(hit.position)
	elif op == "hold":
		p = c.position
	G.match_node.command("squad", [c.get_meta("net_id", 0), op, p])
	log_event(SQUAD_SAY[op], TEAM)


## T on foot: call for reinforcements from the AI commander.
func requisition() -> void:
	var c: Node = G.possessed
	G.match_node.command("requisition", [c.get_meta("net_id", 0)])


func _vessel_under(p: Vector3) -> Node:
	if p == Vector3.INF:
		return null
	for o in G.vessels:
		if not o.destroyed and o.aabb.grow(8.0).has_point(o.to_local(p)):
			return o
	return null


func take_helm(ship: Node) -> void:
	var c: Node = G.possessed
	c.piloting = ship
	ship.helm = c
	ship.move_target = Vector3.INF
	ship.attack_target = null
	chase_dist = 0.0
	chase_yaw = 0.0
	c.rig.set_first_person(false)
	if G.is_client():
		G.network.send_action(c, "helm", [G.vessels.find(ship), true])     # the host flies it for us
	log_event("You have the helm of %s. W/S throttle, A/D turn, mouse aims, LMB fires, B boards, E leaves." % ship.display_name, TEAM)


func fly_fighter(f: Node) -> void:
	var c: Node = G.possessed
	c.piloting = f
	c.visible = false
	c.collision_layer = 0
	chase_dist = 0.0
	log_event("Launching! Mouse steers, A/D roll, W/S throttle, Shift boost, LMB guns. E near your carrier lands.", TEAM)


func leave_vehicle() -> void:
	var c: Node = G.possessed
	if c == null or not is_instance_valid(c):
		return
	var v: Node = c.piloting
	if v and is_instance_valid(v) and v in G.fighters:
		var carrier: Node = c.vessel
		if is_instance_valid(carrier) and not carrier.destroyed and v.global_position.distance_to(carrier.global_position) < 450.0:
			var p: Vector3 = carrier.player_dock(v)
			if p == Vector3.INF:
				log_event("No free pad aboard %s" % carrier.display_name, TEAM)
				return
			c.position = p
			log_event("Landed aboard %s" % carrier.display_name, TEAM)
		else:
			log_event("Fly back within 450 m of %s to land" % (carrier.display_name if is_instance_valid(carrier) else "your carrier"), TEAM)
			return
	elif v and is_instance_valid(v) and v.get("is_vehicle") == true:
		v.driver = null
		v.drive_vel = 0.0
		var out: Vector3 = v.position + v.transform.basis.x * 4.5
		c.position = c.vessel.snap_local(out) if c.vessel.has_method("snap_local") else out
		log_event("Out of the %s" % v.display_name, TEAM)
	elif v and is_instance_valid(v) and v.get("helm") == c:
		v.helm = null
		v.manual_aim = Vector3.INF
		v.manual_fire = false
		v.helm_throttle = 0.0
		if G.is_client():
			G.network.send_action(c, "helm", [G.vessels.find(v), false])
	c.piloting = null
	c.visible = true
	c.collision_layer = G.LAYER_CHAR
	c.rig.set_first_person(true)


func on_vehicle_lost(v: Node) -> void:
	var c: Node = G.possessed
	if c and is_instance_valid(c) and c.piloting == v:
		c.piloting = null
		c.visible = true
		c.die(null)
		log_event("Your %s was destroyed" % ("vehicle" if v.get("is_vehicle") == true else "fighter"), TEAM)
	elif c and is_instance_valid(c) and c.riding == v:
		log_event("Your boarding craft was destroyed", TEAM)


# ------------------------------------------------------------------ selecting

func _mine() -> Array:
	return G.characters.filter(func(c): return is_instance_valid(c) and c.team == TEAM and c.state == "alive")


func _finish_select(pos: Vector2, add: bool, dbl: bool) -> void:
	if not add:
		clear_selection()
	if _drag_from != Vector2.INF and _drag_from.distance_to(pos) > 8.0:
		var r := Rect2(_drag_from, pos - _drag_from).abs()
		var see_people := interior or zoom < 160.0
		for v in G.vehicles:
			if is_instance_valid(v) and v.team == TEAM and not cam.is_position_behind(v.global_position) \
					and r.has_point(cam.unproject_position(v.global_position + Vector3.UP * 2.0)):
				select(v)
		for c in _mine():
			if see_people and c.rig.visible and not cam.is_position_behind(c.global_position) \
					and r.has_point(cam.unproject_position(c.global_position + Vector3.UP)):
				select(c)
		if selection.is_empty():
			for v in G.vessels:
				if v.team == TEAM and v.kind == "ship" and not v.destroyed and not cam.is_position_behind(v.global_position) \
						and r.has_point(cam.unproject_position(v.global_position)):
					select(v)
		return
	var u := pick(pos)
	if u == null:
		return
	if dbl and u.get("rig") != null and u.team == TEAM:
		for c in _mine():                               # double click: everyone of that role nearby
			if c.role == u.role and c.vessel == u.vessel and c.position.distance_to(u.position) < 30.0:
				select(c)
	elif dbl and u.get("kind") == "ship" and u.team == TEAM:
		for v in G.vessels:                             # double click a ship: every ship of that class in view
			if v.kind == "ship" and v.team == TEAM and not v.destroyed and v.cls == u.cls \
					and not cam.is_position_behind(v.global_position) \
					and get_viewport().get_visible_rect().has_point(cam.unproject_position(v.global_position)):
				select(v)
	else:
		select(u)


func pick(pos: Vector2) -> Node:
	var from := cam.project_ray_origin(pos)
	var dir := cam.project_ray_normal(pos)
	var hit := G.ray(from, from + dir * 12000.0, [], G.LAYER_CHAR)
	if not hit.is_empty() and hit.collider.get("rig") != null and hit.collider.rig.visible:
		return hit.collider
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 12000.0, G.LAYER_PICK)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	var h2 := space.intersect_ray(q)
	if not h2.is_empty() and h2.collider.has_meta("unit"):
		var u: Node = h2.collider.get_meta("unit")
		if u is Node3D and not (u as Node3D).is_visible_in_tree():
			return null                                  # (in the fog)
		return u
	return null


func select(u: Node) -> void:
	if not selection.has(u):
		selection.append(u)
		if u.has_method("set_selected"):
			u.set_selected(true)


func clear_selection() -> void:
	for u in selection:
		if is_instance_valid(u) and u.has_method("set_selected"):
			u.set_selected(false)
	selection.clear()


func _quick_select(i: int) -> void:
	var mine: Array = G.vessels.filter(func(v): return v.team == TEAM and not v.destroyed)
	if i < mine.size():
		clear_selection()
		select(mine[i])
		pivot = mine[i].to_global(mine[i].aabb.get_center())
		zoom = 380.0


# ------------------------------------------------------------------ orders

func _ids(units: Array) -> Array:
	return units.map(func(u): return u.get_meta("net_id", 0))


func order_at(pos: Vector2, queue: bool) -> void:
	if soldier_mode:
		return
	var from := cam.project_ray_origin(pos)
	var dir := cam.project_ray_normal(pos)
	var picked := pick(pos)
	var chars: Array = []
	var ships: Array = []
	var fighters_: Array = []
	for u in selection:
		if not is_instance_valid(u) or u.team != TEAM:
			continue
		if u.get("rig") != null:
			if u.state == "alive":
				chars.append(u)
		elif u.get("kind") == "ship" and not u.destroyed:
			ships.append(u)
		elif u in G.fighters:
			fighters_.append(u)
	var enemy_vessel: bool = picked != null and picked.get("kind") != null and G.enemies(TEAM, picked.team)
	if camp_ui and not enemy_vessel and picked != null and picked.get("kind") != null and picked.team != TEAM \
			and Input.is_key_pressed(KEY_CTRL) and not ships.is_empty():
		G.change_standing(picked.team, -60.0, "you opened fire on %s" % picked.display_name)
		enemy_vessel = G.enemies(TEAM, picked.team)
	if _pending == "minidrop":
		_pending = ""
		var mh := G.ray(from, from + dir * 12000.0, [], G.LAYER_WORLD)
		if not mh.is_empty():
			for s in ships:
				if s.cls == "SMALL_DROP_FRIGATE":
					log_event(G.match_node.send_minidrop(s, mh.position), TEAM)
					break
		return
	if _pending == "odst":
		_pending = ""
		var oh := G.ray(from, from + dir * 12000.0, [], G.LAYER_WORLD)
		if not oh.is_empty():
			var n_ok := 0
			for s in ships:
				if s.cls == "SMALL_DROP_FRIGATE" and s.order_ground_drop(oh.position):
					n_ok += 1
			log_event("ODST: %s" % ("dropship moving over the drop zone" if n_ok > 0 else "no dropship with loaded pods and troops selected"), TEAM)
		return
	if picked != null and picked.get("kind") == "outpost":
		# a ground installation: ships engage it (or drop on it), vehicles attack, infantry walk there
		for s in ships:
			if _pending == "board" and not s.drop_racks.is_empty():
				var bh := G.ray(from, from + dir * 12000.0, [], G.LAYER_WORLD)
				if not s.order_drop(picked, bh.position if not bh.is_empty() else picked.global_position, 8):
					log_event("%s can't drop: needs loaded pods and troops aboard" % s.display_name, TEAM)
			elif enemy_vessel:
				s.attack_target = picked
				s.move_target = Vector3.INF
				log_event("%s: engaging %s" % [s.display_name, picked.display_name], TEAM)
		_pending = ""
		ships = []
		fighters_ = []
		if not enemy_vessel:
			picked = null
	if _pending == "board" and enemy_vessel:
		_pending = ""
		# the exact point clicked is the drop zone (drop frigates); boarding ships ignore it
		var hit := G.ray(from, from + dir * 12000.0, [], G.LAYER_WORLD | G.LAYER_DOOR)
		var spot: Vector3 = hit.position if not hit.is_empty() else picked.global_position
		for s in ships:
			G.match_node.command("board", [G.vessels.find(s), G.vessels.find(picked), "pods", spot])
		return
	_pending = ""
	for s in ships:
		if enemy_vessel:
			G.match_node.command("ship_attack", [G.vessels.find(s), G.vessels.find(picked)])
			log_event("%s: engaging %s" % [s.display_name, picked.display_name], TEAM)
		else:
			G.match_node.command("ship_move", [G.vessels.find(s), _plane_point(from, dir), queue])
	var vehs: Array = selection.filter(func(u): return is_instance_valid(u) and u.get("is_vehicle") == true and u.team == TEAM)
	if not vehs.is_empty():
		var tgt_any: Node = picked if picked != null and picked.get("team") != null and G.enemies(TEAM, picked.team) else null
		var gh := G.ray(from, from + dir * 12000.0, [], G.LAYER_WORLD)
		var gp: Vector3 = gh.position if not gh.is_empty() else _plane_point(from, dir)
		var haul: Node = picked if picked != null and picked.get("kind") == "ship" and picked.team == TEAM and picked.cls in G.match_node.HAULERS \
			and G.match_node.on_surface else null
		if haul:
			var foot: Vector3 = load("res://scripts/campaign/bays.gd").ramp_foot(haul)
			for vv in vehs:
				vv.set_meta("board_ship", haul)
				vv.order_move(foot)
			log_event("%d vehicle%s driving aboard %s" % [vehs.size(), "" if vehs.size() == 1 else "s", haul.display_name], TEAM)
			return
		for i in vehs.size():
			var vv: Node = vehs[i]
			if tgt_any:
				vv.order_attack(tgt_any)
			else:
				vv.order_move(gp + Vector3((i % 3) * 10.0 - 10.0, 0, (i / 3) * 12.0))
		log_event("%d vehicle%s: %s" % [vehs.size(), "" if vehs.size() == 1 else "s", "engage" if tgt_any else "move"], TEAM)
		if chars.is_empty() and ships.is_empty():
			return
	for f in fighters_:
		if enemy_vessel:
			G.match_node.command("fighter_attack", [f.get_meta("net_id", 0), G.vessels.find(picked)])
	if chars.is_empty():
		return
	# soldiers ordered onto another vessel: a boarding party at an enemy, a Darter ride to a friend
	if picked != null and picked.get("kind") != null and picked.get("kind") != "outpost" and not picked.destroyed:
		var home: Node = chars[0].vessel
		if picked != home and home != null:
			if enemy_vessel and home.kind == "ship" and home.team == TEAM:
				var kind_: String = "shuttle" if home.can_shuttle(picked) and not home.can_board(picked) else "pods"
				if home.boarding.is_empty() and not home.start_boarding(picked, kind_, maxi(2, ceili(chars.size() / 3.0))):
					log_event("%s can't board %s from here (too far, no pods or shuttle)" % [home.display_name, picked.display_name], TEAM)
					return
				var spots: Array = home.muster_points()
				for i in chars.size():
					var c: Node = chars[i]
					if c.vessel != home:
						continue
					c.mustered = home
					if not spots.is_empty():
						c.order = {"type": "move", "pos": home.snap_local(spots[i % spots.size()] + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5))), "vessel": home}
				log_event("%d soldiers to the %s: boarding %s" % [chars.size(), "hangar" if kind_ == "shuttle" else "pod bay", picked.display_name], TEAM)
				return
			if picked.team == TEAM:
				var n: int = G.match_node.logistics.ferry(chars, picked)
				log_event("%d aboard a Darter to %s" % [n, picked.display_name] if n > 0 else "Nobody could go (they must be aboard a ship or station of yours)", TEAM)
				return
	# infantry: where on which vessel did we click?
	var hit := G.ray(from, from + dir * 12000.0, [], G.LAYER_WORLD | G.LAYER_DOOR | G.LAYER_CHAR)
	if hit.is_empty():
		return
	var v: Node = hit.collider
	while v and not v.has_method("path_local"):
		v = v.get_parent()
	if v == null:
		return
	if hit.collider.get("rig") != null and G.enemies(TEAM, hit.collider.team):
		G.match_node.command("attack", [_ids(chars), hit.collider.get_meta("net_id", 0)])
		return
	var here: Array = chars.filter(func(c): return c.vessel == v)
	if here.size() < chars.size():
		log_event("Troops can only move on the vessel they're aboard: boarding pods carry them between vessels", TEAM)
	if not here.is_empty():
		G.match_node.command("move", [_ids(here), G.vessels.find(v), v.to_local(hit.position)])
		for c in here:                                 # instant feedback on our own screen
			c.order = {"type": "move", "pos": v.to_local(hit.position), "vessel": v}


func _plane_point(from: Vector3, dir: Vector3) -> Vector3:
	if G.match_node and G.match_node.get("on_surface"):
		var gh := G.ray(from, from + dir * 12000.0, [], G.LAYER_WORLD)
		if not gh.is_empty():
			var gp: Vector3 = gh.position
			return Vector3(gp.x, 0.0, gp.z)            # (ships keep their own height over the ground)
	if abs(dir.y) < 0.0001:
		return from + dir * 500.0
	var t := -from.y / dir.y
	return from + dir * (t if t > 0.0 else 500.0)


func _name(u: Node) -> String:
	return u.display_name if u.get("display_name") != null else "Fighter"


func cmd_board() -> void:
	for s in selection:
		if is_instance_valid(s) and s.has_method("launch_pods") and s.team == TEAM:
			var t: Node = s.attack_target
			if t and is_instance_valid(t) and not t.destroyed:
				G.match_node.command("board", [G.vessels.find(s), G.vessels.find(t)])
				return
			_pending = "board"
			log_event("Right-click an enemy ship or station to send boarding pods", TEAM)
			return


func cmd_fighters() -> void:
	for s in selection:
		if is_instance_valid(s) and s.has_method("request_fighters") and s.team == TEAM:
			if s.parked_count() == 0:
				log_event("%s has no fighters left on its pads" % s.display_name, TEAM)
			G.match_node.command("fighters", [G.vessels.find(s)])


func cmd_train() -> void:
	for s in selection:
		if is_instance_valid(s) and s.has_method("train_squad") and s.team == TEAM:
			G.match_node.command("train", [G.vessels.find(s)])


func cmd_sabotage() -> void:
	var chars: Array = selection.filter(func(c): return is_instance_valid(c) and c.get("rig") != null)
	if not chars.is_empty():
		G.match_node.command("sabotage", [_ids(chars)])


# ------------------------------------------------------------------ direct control

func possess_selected() -> void:
	for u in selection:
		if is_instance_valid(u) and u.get("is_vehicle") == true and u.team == TEAM and u.cargo_of == null:
			_crew_vehicle(u)
			return
	for u in selection:
		if is_instance_valid(u) and u.get("rig") != null and u.team == TEAM and u.state == "alive":
			possess(u)
			return
	log_event("Select one of your soldiers or crew first (zoom in on a ship to see inside)", TEAM)


func possess(c: Node) -> void:
	G.possessed = c
	c.order = {}
	c.stop()
	c.target = null
	c.working = false
	c.carrying = false
	if c.role != "scientist":
		c.rig.set_held(null)
	c.look_yaw = c.rotation.y
	c.look_pitch = 0.0
	c.rig.set_first_person(true)
	clear_selection()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.set_mode_fps(true)
	_back_t = -1.0
	log_event("Direct control: %s. Tab returns to command." % c.display, TEAM)


## Tab on a selected vehicle: its crew's driver is yours to control.
func _crew_vehicle(v: Node) -> void:
	var gnd: Node = v.ground
	if v.driver != null and is_instance_valid(v.driver):
		possess(v.driver)
		return
	var c: Node = G.match_node.spawn_character(gnd, v.position + v.transform.basis.x * 4.0, TEAM, G.team_fac(TEAM), "rifleman")
	c.set_meta("vehicle_crew", v)
	possess(c)
	drive(v)


func release() -> void:
	leave_gun()
	var c: Node = G.possessed
	if c and is_instance_valid(c) and c.piloting and is_instance_valid(c.piloting) and c.piloting.get("is_vehicle") == true:
		var veh: Node = c.piloting
		leave_vehicle()
		if c.has_meta("vehicle_crew"):
			# the crewman we lent you goes back inside
			G.possessed = null
			G.match_node.logistics._remove_person(c)
			c = null
			pivot = veh.global_position
	if c and is_instance_valid(c):
		c.rig.set_first_person(false)
		if c.state == "alive":
			c.order = {"type": "hold", "pos": c.position, "vessel": c.vessel}
		pivot = c.global_position
	G.possessed = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.set_mode_fps(false)
	cam.current = true
	_back_t = -1.0
	zoom = min(zoom, 60.0)


func on_possessed_died() -> void:
	log_event("Your unit is down. Returning to command...", TEAM)
	_back_t = 2.0


func hit_marker(killed: bool) -> void:
	hud.hit_t = 0.35 if killed else 0.18


## E in first person: what character.gd doesn't handle itself (sabotage, purge).
func interact() -> void:
	var c: Node = G.possessed
	var v: Node = c.vessel
	var hit := G.ray(fps_cam.global_position, fps_cam.global_position - fps_cam.global_basis.z * 3.0, [c.get_rid()])
	var nv := _vehicle_near(c)
	if nv:
		drive(nv)
		return
	if G.is_client() and v.has_method("room_near") and G.enemies(c.team, v.team) and v.room_near(c.position, 3.0) != "":
		G.network.send_action(c, "use", [])           # the host sets the demolition charges
		log_event("Charges set on the %s: get clear, 10 s" % v.room_near(c.position, 3.0), TEAM)
		return
	if not G.is_client() and v.has_method("defuse_near") and v.defuse_near(c.position, c.team):
		log_event("Charge defused", TEAM)
		return
	if not G.is_client() and v.has_method("room_near") and G.enemies(c.team, v.team):
		var room: String = v.room_near(c.position, 3.0)
		if room != "":
			v.plant_demo(c.position, room, c.team)
			log_event("Charges set on the %s: get clear, 10 s" % room, TEAM)
			return
	if v.kind == "ship" and v.team == c.team and v.has_method("gun_seat_near"):
		var gi: int = v.gun_seat_near(c.position)
		if gi >= 0:
			take_gun(v, gi)
			return
	if v.kind == "ship" and v.team == c.team:
		for seat in ["Bridge_PilotSeat", "Bridge_CaptainChair"]:
			var m: Node3D = v.mark(seat)
			if m and v.local_of(m).distance_to(c.position) < 2.6:
				take_helm(v)
				return
		if v.has_method("player_launch"):
			var f: Node = v.player_launch(c)
			if f:
				fly_fighter(f)
				return
	if v.kind == "ship" and v.team == c.team and v.get("boarding") != null and not v.boarding.is_empty() \
			and c.mustered != v and v.near_muster(c):
		G.match_node.command("join_board", [c.get_meta("net_id", 0), G.vessels.find(v)])
		log_event("You're going: stay at the %s for launch" % ("pod bay" if v.boarding["kind"] == "pods" else "hangar"), TEAM)
		return
	# on a client the host does the same for our body there (defusing, doors, charges, the
	# armory); we run it here too so our own magazines and kit match
	if G.is_client():
		G.network.send_action(c, "use", [])
	var r: String = c.player_use(hit)
	if r != "":
		log_event(r, TEAM)
		return
	if c.role == "scientist":
		c.purging = not c.purging
		if G.is_client():
			G.network.send_action(c, "purge", [c.purging])
		log_event("Purge emitter %s" % ("ON" if c.purging else "off"), TEAM)
		return
	var sp := _sabotage_spot(c)
	if sp:
		var code: String = v._module_of(String(sp.name))
		c.working = true
		log_event("Planting charges on %s..." % code, TEAM)
		get_tree().create_timer(3.0).timeout.connect(func():
			if is_instance_valid(c) and c.state == "alive":
				c.working = false
				if G.is_client():
					G.network.send_action(c, "sabotage", [code])
				else:
					v.sabotage(code, c.team))
		return
	if G.is_client():
		return                                         # (the host may still defuse something: it says so)
	log_event("Nothing to use here", TEAM)


func _sabotage_spot(c: Node) -> Node3D:
	var v: Node = c.vessel
	if not v.has_method("sabotage") or not G.enemies(c.team, v.team):
		return null
	for n in v.marks_like("*_SabotagePoint_?"):
		if v.local_of(n).distance_to(c.position) < 2.2:
			return n
	return null


func _look_prompt() -> String:
	var c: Node = G.possessed
	var v: Node = c.vessel
	if not c.gunning.is_empty():
		var gs: Node = c.gunning["ship"]
		var gt: Dictionary = gs.turrets[c.gunning["idx"]]
		return "%s GUN  ·  mouse aims  ·  LMB fires  ·  E leave the seat%s" % [String(gt["kind"]).to_upper(),
			"" if gt["cool"] <= 0.0 else "   (reloading)"]
	if c.piloting:
		var pv: Node = c.piloting
		if pv in G.fighters:
			return "Speed %d   ·   E near your carrier to land" % int(pv.vel.length())
		if pv.get("is_vehicle") == true:
			return "%s  ·  W/S drive  A/D steer  Shift boost  ·  E get out" % pv.hud_line()
		var t := _vessel_under(pv.manual_aim)
		var lk: String = ("LOCK %s  ·  " % pv.lock.display_name) if pv.get("lock") and is_instance_valid(pv.lock) else ""
		var aim: String = ("aiming at %s  ·  " % t.display_name) if t and t != pv else ""
		return lk + aim + "T lock  ·  M missiles  ·  B pods  ·  N shuttle  ·  1 attack  2 form on me  3 hold  4 board  ·  E leave"
	var nv := _vehicle_near(c)
	if nv:
		return "E  drive the %s" % nv.display_name
	for ch in v.get("demo_charges") if v.get("demo_charges") != null else []:
		if ch["team"] != c.team and (ch["local"] as Vector3).distance_to(c.position) < 2.4:
			return "E  DEFUSE the charge (%d s)" % ceili(ch["t"])
	if v.has_method("room_near") and G.enemies(c.team, v.team) and v.room_near(c.position, 3.0) != "":
		return "E  set demolition charges on the %s" % v.room_near(c.position, 3.0)
	if v.kind == "ship" and v.team == c.team and v.has_method("gun_seat_near") and v.gun_seat_near(c.position) >= 0:
		return "E  take the %s gun" % String(v.turrets[v.gun_seat_near(c.position)]["kind"])
	if v.kind == "ship" and v.team == c.team:
		if v.get("boarding") != null and not v.boarding.is_empty() and v.near_muster(c):
			return ("Boarding party: launch in %d s" % ceili(v.boarding["t"])) if c.mustered == v \
				else "E  join the boarding party (%d s)" % ceili(v.boarding["t"])
		for seat in ["Bridge_PilotSeat", "Bridge_CaptainChair"]:
			var m: Node3D = v.mark(seat)
			if m and v.local_of(m).distance_to(c.position) < 2.6:
				return "E  take the helm"
		for p in (v.get("pads") if v.get("pads") != null else []):
			if p["parked"] != null and Vector2(c.position.x - p["local"].x, c.position.z - p["local"].z).length() < 5.0:
				return "E  launch in this fighter"
	var med: String = c.medical_prompt()
	if med != "":
		return med
	if v.elevator_at(c.position) >= 0:
		return "E  elevator"
	if v.team == c.team:
		for s in v.marks_like("Armory_*_Resupply") + v.marks_like("Armory_*_Counter") + v.marks_like("ReadyLocker_*") + v.marks_like("*_ReadyLocker"):
			if c.position.distance_to(v.local_of(s)) < 3.0:
				return "E  %s" % ("resupply" if c.armed else "gear up")
	if _sabotage_spot(c):
		return "E  plant sabotage charges"
	if c.role == "scientist" and not v.zone_at(c.position).is_empty() and v.zone_at(c.position)["infected"]:
		return "E  purge emitter %s" % ("off" if c.purging else "on")
	var dd: Dictionary = v.door_blocking(c.position, -c.transform.basis.z, 1.6)
	if not dd.is_empty() and v.team != c.team:
		var hp_txt := "" if dd["kind"] == "secure" else "  [%d%%]" % int(100.0 * dd["hp"] / v.DOOR_HP[dd["kind"]])
		if dd.get("charged", false):
			return "Charge set: STAND CLEAR"
		match dd["kind"]:
			"door":
				return "E  kick the door in%s   (or shoot it down)" % hp_txt
			"heavy":
				return ("E  set a breaching charge" if not c.charges.is_empty() else "Blast door: shoot it down%s or bring a charge" % hp_txt)
			_:
				return ("E  set a breaching charge" if not c.charges.is_empty() else "SECURITY DOOR: breaching charge only")
	return ""


# ------------------------------------------------------------------ deploying as a soldier

const CLASSES := ["rifleman", "squad_leader", "breacher", "medic", "heavy", "grenadier", "eva_boarder", "pilot",
	"engineer", "scientist"]


func open_deploy() -> void:
	if G.possessed and is_instance_valid(G.possessed) and G.possessed.state == "alive":
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.open_deploy(spawn_points())


func spawn_points() -> Array:
	var out: Array = []
	for v in G.vessels:
		if v.team == G.player_team and not v.destroyed:
			out.append(v)
	return out


func deploy(role: String, v: Node) -> void:
	hud.close_panels()
	if G.is_client():
		G.network.request_spawn(role, G.vessels.find(v))
		return
	var c: Node = G.match_node.spawn_player(role, v, 1)
	if c:
		possess(c)
		if soldier_mode:
			hud.set_mode_fps(true)


func start_as_soldier() -> void:
	soldier_mode = true
	_help = false
	hud.show_help(false)
	open_deploy()


# ------------------------------------------------------------------ messages and labels

func log_event(text: String, team: int) -> void:
	var loud := text.contains("CAPTURED") or text.contains("DESTROYED") or text.contains("VICTORY") or text.contains("DEFEAT")
	if team != 0 and team != TEAM and not loud:
		return                                     # the enemy's (and pirates') internal chatter isn't ours to hear
	if hud.log_items.size() > 0 and hud.log_items[-1][0].text == text:
		return                                     # no repeats
	var col := Color(0.88, 0.92, 0.96)
	if text.contains("infection") or text.contains("spore") or text.contains("Infected"):
		col = Color(0.82, 0.55, 1.0)
	elif text.begins_with("ALERT") or text.contains("shields down") or text.contains("DESTROYED") or loud:
		col = Color(1.0, 0.55, 0.45)
	elif team == 3:
		col = Color(0.6, 1.0, 0.5)
	hud.log_event(text, col)


func banner(title: String, sub: String) -> void:
	hud.banner(title, sub)


func _update_labels() -> void:
	for v in G.vessels:
		if not is_instance_valid(v):
			continue
		if not _labels.has(v):
			var l := Label3D.new()
			l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			l.fixed_size = true
			l.pixel_size = 0.001
			l.font_size = 26
			l.outline_size = 8
			l.no_depth_test = true
			add_child(l)
			_labels[v] = l
		var lab: Label3D = _labels[v]
		lab.global_position = v.to_global(v.aabb.get_center()) + Vector3.UP * (v.aabb.size.y * 0.5 + 12.0)
		lab.modulate = G.team_color(v.team) if v.team != 4 else Color(0.8, 0.45, 1.0)
		lab.visible = G.possessed == null and zoom > 150.0
		lab.text = v.display_name + ("  (wreck)" if v.destroyed else "")
		var fs: String = G.match_node.fog.state_of(v) if G.match_node and G.match_node.fog else "vis"
		if not v.visible:
			if fs == "radar":
				lab.text = "UNKNOWN CONTACT"
				lab.modulate = Color(0.7, 0.75, 0.8)
				lab.global_position = v.global_position + Vector3.UP * 30.0
			else:
				lab.visible = false
			continue
		if v.has_meta("job") and not v.destroyed:
			lab.text = "JOB ▸ " + lab.text
			lab.modulate = Color(1.0, 0.85, 0.3)


# ------------------------------------------------------------------ manning a gun

var gun_yaw := 0.0
var gun_pitch := 0.1


func take_gun(ship: Node, idx: int) -> void:
	var c: Node = G.possessed
	var t: Dictionary = ship.turrets[idx]
	var old = t["gunner"]
	if old != null and is_instance_valid(old) and old != c:
		t["gunner"] = null                              # the crew gunner stands aside (they'll find another)
	t["player"] = c
	c.gunning = {"ship": ship, "idx": idx}
	c.stop()
	c.ads = false
	gun_yaw = (t["node"] as Node3D).rotation.y
	gun_pitch = 0.1
	log_event("On the %s gun. Mouse aims, LMB fires, E leaves the seat." % t["kind"], TEAM)


func leave_gun() -> void:
	var c: Node = G.possessed
	if c == null or c.gunning.is_empty():
		return
	var ship: Node = c.gunning["ship"]
	if is_instance_valid(ship) and c.gunning["idx"] < ship.turrets.size():
		var t: Dictionary = ship.turrets[c.gunning["idx"]]
		t["player"] = null
		t["aim"] = Vector3.INF
		t["fire"] = false
	c.gunning = {}


func _gun_input(event: InputEvent, sens: float) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		gun_yaw -= event.relative.x * 0.0022 * sens
		gun_pitch = clampf(gun_pitch - event.relative.y * 0.0022 * sens, -0.25, 1.45)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("use"):
		leave_gun()
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## The gunner's view: just behind and above the gun, looking where you aim.
func _gun_frame(_dt: float) -> void:
	var c: Node = G.possessed
	var ship: Node = c.gunning["ship"]
	if not is_instance_valid(ship) or ship.destroyed or c.vessel != ship or c.gunning["idx"] >= ship.turrets.size():
		c.gunning = {}
		return
	hud.set_mode_fps(true)
	fps_cam.current = true
	G.set_cut(10000.0)
	var t: Dictionary = ship.turrets[c.gunning["idx"]]
	var root: Node3D = t["root"]
	var r: float = t["spec"]["r"]
	var dir_l := Basis.from_euler(Vector3(gun_pitch, gun_yaw, 0)) * Vector3(0, 0, -1)
	var dir: Vector3 = (root.global_basis * dir_l).normalized()
	var up: Vector3 = root.global_basis.y
	var eye: Vector3 = root.global_position + up * (r * 2.2) - dir * (r * 3.0)
	fps_cam.global_position = eye
	fps_cam.look_at(eye + dir * 100.0, up)
	fps_cam.fov = lerpf(fps_cam.fov, G.settings.get("fov", 85.0) * (0.55 if Input.is_action_pressed("aim") else 1.0), 0.2)
	var h := G.ray(eye + dir * (r * 4.0), eye + dir * 4000.0, [], G.LAYER_WORLD)
	t["aim"] = h.position if not h.is_empty() else eye + dir * 3000.0
	t["fire"] = Input.is_action_pressed("fire")
	t["player"] = c
	pivot = c.global_position
