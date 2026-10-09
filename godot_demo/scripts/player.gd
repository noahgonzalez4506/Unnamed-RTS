extends CharacterBody3D
## UNUSED: nothing loads this script. It is the original first-person test player, kept as a
## reference for zero-g / EVA movement (still to build into character.gd). The game's first
## person is character.gd _player_physics with commander.gd.
## Walks with gravity inside ships and stations; press V for EVA mode (no gravity, fly in the
## direction you look).

const WALK := 4.5
const RUN := 8.0
const JUMP := 4.2
const EVA_SPEED := 12.0
const EVA_BOOST := 60.0
const GRAVITY := 9.8

var cam: Camera3D
var lamp: SpotLight3D
var eva := false
var yaw := 0.0
var pitch := 0.0


func _ready() -> void:
	_make_inputs()
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	col.shape = cap
	col.position.y = 0.9
	add_child(col)
	cam = Camera3D.new()
	cam.position.y = 1.65
	cam.near = 0.05
	cam.far = 9000.0
	cam.fov = 80.0
	add_child(cam)
	lamp = SpotLight3D.new()
	lamp.spot_range = 25.0
	lamp.spot_angle = 40.0
	lamp.spot_attenuation = 1.5
	lamp.light_energy = 0.8
	lamp.shadow_enabled = true
	cam.add_child(lamp)
	floor_max_angle = deg_to_rad(46.0)
	floor_snap_length = 0.4
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _make_inputs() -> void:
	var keys := {
		"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D,
		"jump": KEY_SPACE, "move_down": KEY_CTRL, "sprint": KEY_SHIFT,
		"use": KEY_E, "charge": KEY_G, "eva": KEY_V, "lamp": KEY_F,
	}
	for action in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var ev := InputEventKey.new()
		ev.physical_keycode = keys[action]
		InputMap.action_add_event(action, ev)


## Put the player somewhere, looking along `look_yaw` (0 = Godot -Z).
func teleport(pos: Vector3, look_yaw: float, eva_mode: bool) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	yaw = look_yaw
	pitch = 0.0
	eva = eva_mode
	rotation = Vector3(0, yaw, 0)
	cam.rotation = Vector3.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * 0.0025
		pitch = clamp(pitch - event.relative.y * 0.0025, -1.5, 1.5)
		rotation.y = yaw
		cam.rotation.x = pitch
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed("eva"):
		eva = not eva
	elif event.is_action_pressed("lamp"):
		lamp.visible = not lamp.visible


func _physics_process(dt: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if eva:
		var dir := cam.global_transform.basis * Vector3(input.x, 0, input.y)
		dir += Vector3.UP * Input.get_axis("move_down", "jump")
		var speed := EVA_BOOST if Input.is_action_pressed("sprint") else EVA_SPEED
		var want := dir.normalized() * speed if dir.length() > 0.01 else Vector3.ZERO
		velocity = velocity.lerp(want, clamp(dt * 2.5, 0.0, 1.0))
	else:
		if not is_on_floor():
			velocity.y -= GRAVITY * dt
		elif Input.is_action_just_pressed("jump"):
			velocity.y = JUMP
		var dir := global_transform.basis * Vector3(input.x, 0, input.y)
		var speed := RUN if Input.is_action_pressed("sprint") else WALK
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
	move_and_slide()


## What the player is looking at within `reach` meters (empty if nothing).
func look_hit(reach: float = 4.0) -> Dictionary:
	var from := cam.global_position
	var to := from - cam.global_transform.basis.z * reach
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q)
