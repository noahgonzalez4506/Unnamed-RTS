extends Node3D
## The first-person weapon: a copy of the soldier's gun with gloved forearms, hung off the
## camera so it always sits low and to the right whatever way you look (it never swings
## up into view). Everything is procedural:
##   sway against the mouse, bob while walking, kick on every shot, a dip-and-roll reload,
##   lowered while sprinting, raised when drawn, and aim-down-sights onto the sight line.
## Sights by weapon type:
##   iron sights (pistols, shotguns): a rear notch and a front post
##   holo / red dot (rifles, SMGs, LMGs): an open frame with a glowing dot
##   scope (sniper and beam rifles, the PulseCarbine): a tube whose rear lens shows a live zoomed view
##   (picture-in-picture from a second camera) with a reticle
## Lives on render layer 2, so the scope camera never sees it.

const LAYER := 2
const HIP := Vector3(0.17, -0.19, -0.36)
const SCOPE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D view : source_color, filter_linear;
uniform vec4 ret : source_color = vec4(0.05, 0.05, 0.05, 1.0);
void fragment() {
	vec2 uv = UV - 0.5;
	float r = length(uv);
	if (r > 0.5) discard;
	vec3 c = texture(view, vec2(UV.x, UV.y)).rgb;
	float line = (abs(uv.x) < 0.004 || abs(uv.y) < 0.004) ? 1.0 : 0.0;
	line *= step(0.02, r);                         // a gap at the centre
	float post = (abs(uv.x) < 0.012 && uv.y > 0.12) ? 1.0 : 0.0;
	c = mix(c, ret.rgb, max(line, post));
	c = mix(c, vec3(1.0, 0.2, 0.15), step(r, 0.006));   // the centre dot
	c *= smoothstep(0.5, 0.40, r);                  // dark edge of the eyepiece
	ALBEDO = c;
}
"""

var who: Node = null
var model_path := ""
var gun: Node3D
var kind := "holo"                 # iron, holo, scope
var zoom := 4.0                    # scope magnification
var sight_local := Vector3(0, 0.08, 0.05)   # the gun's Sight marker, in its own space
var aim_local := Vector3(0, 0.08, 0.05)     # the point the eye lines up on (dot, post tip, lens centre)
var grip_local := Vector3.ZERO
var support_local := Vector3(0, 0, 0.25)
var muzzle_local := Vector3(0, 0, 0.6)
var arm_r: MeshInstance3D
var arm_l: MeshInstance3D
var glove_r: MeshInstance3D
var glove_l: MeshInstance3D
var sight_parts: Array = []
var pip: SubViewport
var pip_cam: Camera3D
var lens: MeshInstance3D
var _ads := 0.0
var _sprint := 0.0
var _draw := 1.0                   # 1 = still coming up after a weapon change
var _bob := 0.0
var _sway := Vector2.ZERO
var _last_look := Vector2.ZERO
var _kick := 0.0
var _kick_side := 0.0
var _last_recoil := 0.0


var _upd_frame := 0


func _process(_dt: float) -> void:
	if Engine.get_process_frames() - _upd_frame > 1 and visible:
		visible = false                                   # not in first person any more (chase cam, commander)
		if pip:
			pip.render_target_update_mode = SubViewport.UPDATE_DISABLED


## Each frame from the commander while the player is in first person.
func update(c: Node, cam: Camera3D, dt: float) -> void:
	_upd_frame = Engine.get_process_frames()
	visible = c != null and c.armed and c.state == "alive" and c.piloting == null and c.riding == null
	if not visible:
		if pip:
			pip.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	if c != who or c.rig.weapon == null or c.rig.weapon.scene_file_path != model_path:
		_build(c)
	if gun == null:
		return
	# ---- states
	var moving: float = Vector2(c.velocity.x, c.velocity.z).length()
	var sprinting: bool = Input.is_action_pressed("sprint") and moving > 4.5 and not c.ads and c.reload_t < 0.0
	_ads = move_toward(_ads, 1.0 if c.ads and c.reload_t < 0.0 and _draw < 0.3 else 0.0, dt * 6.5)
	_sprint = move_toward(_sprint, 1.0 if sprinting else 0.0, dt * 5.0)
	_draw = move_toward(_draw, 0.0, dt * 2.4)
	# ---- sway: the gun lags behind the look, then springs back
	var look := Vector2(c.look_yaw, c.look_pitch)
	var dl := look - _last_look
	_last_look = look
	if dl.length() > 1.0:
		dl = Vector2.ZERO                          # a teleport / respawn, not a flick
	var sway_k := lerpf(1.0, 0.25, _ads)
	_sway = _sway.lerp(Vector2(clampf(dl.x * 2.2, -0.08, 0.08), clampf(-dl.y * 2.2, -0.08, 0.08)) * sway_k, clampf(dt * 9.0, 0.0, 1.0))
	# ---- bob
	if c.is_on_floor() and moving > 0.5:
		_bob += dt * (6.0 + moving * 1.4)
	var bob_amt := clampf(moving / 6.0, 0.0, 1.0) * lerpf(1.0, 0.15, _ads)
	var bob := Vector3(sin(_bob) * 0.012, -absf(cos(_bob)) * 0.014, 0.0) * bob_amt
	# ---- recoil kick (the rig's recoil jumps to 1 on every shot)
	var rc: float = c.rig.recoil
	if rc > _last_recoil + 0.5:
		_kick = minf(1.6, _kick + 1.0)
		_kick_side = randf_range(-1.0, 1.0)
	_last_recoil = rc
	_kick = move_toward(_kick, 0.0, dt * 9.0)
	# ---- reload: dip and roll the gun, the left hand goes for a fresh mag
	var rl := -1.0
	if c.reload_t >= 0.0:
		rl = 1.0 - c.reload_t / maxf(0.1, float(c.wstats.get("reload_s", 2.0)))
	var rl_amt := sin(clampf(rl, 0.0, 1.0) * PI) if rl >= 0.0 else 0.0
	# ---- the pose
	var hip := HIP + Vector3(0, -0.02, 0) * (1.0 if c.crouch else 0.0)
	var pos := hip.lerp(_ads_target(), _ads)
	pos += bob + Vector3(-_sway.x, _sway.y, 0) * 0.6
	pos += Vector3(0.0, 0.004, 0.05) * _kick * lerpf(1.0, 0.6, _ads)
	pos += Vector3(-0.05, -0.12, 0.04) * _sprint + Vector3(0, -0.07, 0.03) * rl_amt + Vector3(0.02, -0.35, 0.05) * _draw
	if c.revive_t >= 0.0 or c.hauling != null:
		pos += Vector3(0.05, -0.3, 0.05)
	var rot := Vector3(0.0, PI, 0.0)
	rot.x += _kick * 0.05 * lerpf(1.0, 0.5, _ads) + _sway.y * 0.6 - _sprint * 0.35 + rl_amt * 0.35 - _draw * 0.8
	rot.y += _sway.x * 0.8 + _kick * _kick_side * 0.012 + _sprint * 0.55
	rot.z += -rl_amt * 0.6 + _sprint * 0.25
	gun.position = pos
	gun.rotation = rot
	_arms(rl)
	_scope(c, cam)


func _ads_target() -> Vector3:
	# put the sight line on the camera's centre line, a hand's breadth in front of the eye
	var s: Vector3 = Basis(Vector3.UP, PI) * aim_local
	var eye_dist := 0.11 if kind == "scope" else 0.24
	return Vector3(-s.x, -s.y, -eye_dist - s.z)


# ------------------------------------------------------------------ building

func _build(c: Node) -> void:
	who = c
	for ch in get_children():
		if ch != pip:
			ch.queue_free()
	sight_parts.clear()
	gun = null
	lens = null
	_draw = 1.0
	if c.rig.weapon == null:
		model_path = ""
		return
	model_path = c.rig.weapon.scene_file_path
	gun = load(model_path).instantiate()
	add_child(gun)
	for sb in gun.find_children("*", "StaticBody3D", true, false):
		(sb as StaticBody3D).collision_layer = 0
	for m in gun.find_children("*", "GeometryInstance3D", true, false):
		(m as GeometryInstance3D).layers = 1 << (LAYER - 1)
		(m as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var marks := {}
	for k in ["Grip", "SupportHand", "Muzzle", "Sight"]:
		var n: Node3D = gun.find_child(k, true, false)
		if n:
			marks[k] = _local_in(gun, n)
	grip_local = marks.get("Grip", Vector3.ZERO)
	support_local = marks.get("SupportHand", grip_local + Vector3(0, 0, 0.25))
	muzzle_local = marks.get("Muzzle", grip_local + Vector3(0, 0.05, 0.6))
	sight_local = marks.get("Sight", Vector3(0, grip_local.y + 0.12, grip_local.z + 0.05))
	# which sight this gun gets
	var mdl: String = c.weapon_model
	kind = "holo"
	zoom = 1.0
	if mdl.contains("Magnum") or mdl.contains("Pistol") or mdl.contains("Shotgun") or mdl.contains("ScatterGun"):
		kind = "iron"
	elif mdl.contains("Sniper") or mdl.contains("BeamRifle"):
		kind = "scope"
		zoom = 6.0
	elif mdl.contains("PulseCarbine"):
		kind = "scope"
		zoom = 3.0
	_make_sight(c)
	# gloved forearms
	var fac_col: Color = Color(0.22, 0.25, 0.3) if c.faction != 2 else Color(0.3, 0.2, 0.22)
	arm_r = _limb(0.045, fac_col)
	arm_l = _limb(0.045, fac_col)
	glove_r = _glove(fac_col.darkened(0.4))
	glove_l = _glove(fac_col.darkened(0.4))


## A marker's position in the gun's own space.
func _local_in(root: Node3D, n: Node3D) -> Vector3:
	var p := Vector3.ZERO
	var node: Node = n
	var xf := Transform3D.IDENTITY
	while node != null and node != root:
		if node is Node3D:
			xf = (node as Node3D).transform * xf
		node = node.get_parent()
	p = xf.origin
	return p


func _mat(col: Color, emit: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.6
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = emit
	return m


func _part(mesh: Mesh, mat: Material, parent: Node3D, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.layers = 1 << (LAYER - 1)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _make_sight(c: Node) -> void:
	var dark := _mat(Color(0.08, 0.09, 0.1))
	# sights ride on a riser above the gun's own sight block, so the eye looks over the receiver
	var s := sight_local + Vector3(0, 0.03 if kind != "scope" else 0.024, 0)
	aim_local = s + Vector3(0, 0.004, 0)
	if kind != "iron":
		var riser := BoxMesh.new()
		riser.size = Vector3(0.022, 0.03, 0.05)
		_part(riser, dark, gun, sight_local + Vector3(0, 0.012, 0.03 if kind == "holo" else 0.1))
	match kind:
		"iron":
			# rear notch: two little blades either side of the sight line; front post near the muzzle
			var blade := BoxMesh.new()
			blade.size = Vector3(0.006, 0.018, 0.008)
			_part(blade, dark, gun, s + Vector3(0.007, -0.004, 0))
			_part(blade, dark, gun, s + Vector3(-0.007, -0.004, 0))
			var post := BoxMesh.new()
			post.size = Vector3(0.0035, 0.016, 0.006)
			var front := Vector3(s.x, s.y - 0.005, maxf(muzzle_local.z - 0.04, s.z + 0.15))
			_part(post, dark, gun, front)
			var tip := SphereMesh.new()
			tip.radius = 0.0025
			tip.height = 0.005
			_part(tip, _mat(Color(0.3, 1.0, 0.4), 3.0), gun, front + Vector3(0, 0.009, 0))
		"holo":
			# an open frame on a little base, and a red dot that floats on the sight line
			var frame := TorusMesh.new()
			frame.inner_radius = 0.016
			frame.outer_radius = 0.02
			frame.rings = 24
			frame.ring_segments = 6
			_part(frame, dark, gun, s + Vector3(0, 0.004, 0.02), Vector3(PI * 0.5, 0, 0))
			var base := BoxMesh.new()
			base.size = Vector3(0.026, 0.01, 0.04)
			_part(base, dark, gun, s + Vector3(0, -0.02, 0.02))
			var glass := QuadMesh.new()
			glass.size = Vector2(0.03, 0.03)
			var gm := StandardMaterial3D.new()
			gm.albedo_color = Color(0.4, 0.8, 1.0, 0.08)
			gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			gm.cull_mode = BaseMaterial3D.CULL_DISABLED
			_part(glass, gm, gun, s + Vector3(0, 0.004, 0.02))
			var dot := SphereMesh.new()
			dot.radius = 0.0016
			dot.height = 0.0032
			var dm := _mat(Color(1.0, 0.15, 0.1), 6.0)
			dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_part(dot, dm, gun, s + Vector3(0, 0.004, 0.021))
		"scope":
			# a tube with a live picture-in-picture rear lens
			var tube := CylinderMesh.new()
			tube.top_radius = 0.025
			tube.bottom_radius = 0.025
			tube.height = 0.2
			_part(tube, dark, gun, s + Vector3(0, 0.016, 0.1), Vector3(PI * 0.5, 0, 0))
			var bell := CylinderMesh.new()
			bell.top_radius = 0.033
			bell.bottom_radius = 0.025
			bell.height = 0.05
			_part(bell, dark, gun, s + Vector3(0, 0.016, 0.21), Vector3(PI * 0.5, 0, 0))
			var ring := BoxMesh.new()
			ring.size = Vector3(0.012, 0.02, 0.012)
			_part(ring, dark, gun, s + Vector3(0, -0.006, 0.05))
			_part(ring, dark, gun, s + Vector3(0, -0.006, 0.15))
			if pip == null:
				pip = SubViewport.new()
				pip.size = Vector2i(384, 384)
				pip.render_target_update_mode = SubViewport.UPDATE_DISABLED
				add_child(pip)
				pip_cam = Camera3D.new()
				pip_cam.cull_mask = 0xFFFFF & ~(1 << (LAYER - 1))
				pip_cam.near = 0.3
				pip_cam.far = 9000.0
				pip.add_child(pip_cam)
			var lm := ShaderMaterial.new()
			var sh := Shader.new()
			sh.code = SCOPE_SHADER
			lm.shader = sh
			lm.set_shader_parameter("view", pip.get_texture())
			var disc := QuadMesh.new()
			disc.size = Vector2(0.048, 0.048)
			lens = _part(disc, lm, gun, s + Vector3(0, 0.016, -0.002), Vector3(0, PI, 0))
			aim_local = s + Vector3(0, 0.016, 0)


func _limb(r: float, col: Color) -> MeshInstance3D:
	var cm := CapsuleMesh.new()
	cm.radius = r
	cm.height = 0.42
	return _part(cm, _mat(col), self, Vector3.ZERO)


func _glove(col: Color) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = Vector3(0.06, 0.05, 0.09)
	return _part(bm, _mat(col), self, Vector3.ZERO)


## Forearms from below the frame to the grip and the support hand (the left one goes
## down for a fresh magazine mid-reload).
func _arms(rl: float) -> void:
	var g: Vector3 = gun.transform * grip_local
	var sp: Vector3 = gun.transform * support_local
	if rl >= 0.0:
		var mag_out := sin(clampf(rl, 0.0, 1.0) * PI)
		sp = sp.lerp(gun.transform * (grip_local + Vector3(0, -0.12, 0.08)), 0.5 * mag_out) + Vector3(0, -0.12, 0.05) * mag_out
	_limb_between(arm_r, glove_r, Vector3(0.3, -0.42, 0.12), g)
	_limb_between(arm_l, glove_l, Vector3(-0.22, -0.45, 0.0), sp)


func _limb_between(arm: MeshInstance3D, glove: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var d := to - from
	var l := d.length()
	arm.position = from + d * 0.5
	var up := d.normalized()
	var side := up.cross(Vector3.FORWARD)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	arm.basis = Basis(side, up, side.cross(up)).scaled(Vector3(1.0, l / 0.42, 1.0))
	glove.position = to
	glove.basis = gun.basis


## The scope's picture: a second camera looking down the sight line, narrow field of view.
func _scope(c: Node, cam: Camera3D) -> void:
	if kind != "scope" or pip == null:
		return
	pip.render_target_update_mode = SubViewport.UPDATE_ALWAYS if _ads > 0.05 else SubViewport.UPDATE_DISABLED
	if _ads <= 0.05:
		return
	pip_cam.global_transform = cam.global_transform
	pip_cam.fov = cam.fov / zoom


## Where shots should appear to come from in first person.
func muzzle_world() -> Vector3:
	if gun == null:
		return Vector3.INF
	return gun.global_transform * muzzle_local
