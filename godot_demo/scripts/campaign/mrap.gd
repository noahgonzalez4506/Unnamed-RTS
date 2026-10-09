extends Node3D
## An outlaw MRAP: a wheeled armoured truck with a roof gun, driving the streets of a ruin
## and shooting at anything of ours that comes low and close. Ship guns and point defence
## treat it like any small target (it's in G.pods), so it can be shot up.

const SURFACE := preload("res://scripts/campaign/surface.gd")
var team := 3
var hp := 900.0
var home := Vector3.ZERO
var radius := 150.0
var L := {}
var P := {}
var goal := Vector3.ZERO
var gun_t := 0.0
var _model: Node3D
var pace := 9.0                    # convoys slow to a walk so their escort keeps up
var _wait := false
var _esc_t := 0.0


func setup(team_: int, center: Vector3, r: float, L_: Dictionary, P_: Dictionary) -> void:
	team = team_
	home = center
	radius = r
	L = L_
	P = P_
	_model = Node3D.new()
	add_child(_model)
	var body := StandardMaterial3D.new()
	body.albedo_color = Color(0.4, 0.33, 0.24)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.12, 0.12)
	_box(Vector3(3.0, 2.2, 6.5), Vector3(0, 1.9, 0), body)
	_box(Vector3(2.8, 1.2, 2.2), Vector3(0, 1.6, -3.6), body)
	_box(Vector3(0.8, 0.6, 1.8), Vector3(0, 3.4, 0.4), dark)
	_box(Vector3(0.18, 0.18, 2.0), Vector3(0, 3.5, -1.0), dark)
	for k in 6:
		var w := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.6
		cm.bottom_radius = 0.6
		cm.height = 0.5
		w.mesh = cm
		w.material_override = dark
		w.rotation.z = PI * 0.5
		w.position = Vector3((1 if k % 2 == 0 else -1) * 1.6, 0.6, -2.5 + (k / 2) * 2.4)
		_model.add_child(w)
	position = center + Vector3(randf_range(-r, r), 0, randf_range(-r, r)) * 0.5
	_ground_y()
	goal = position
	G.pods.append(self)


func _box(s: Vector3, p: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = s
	mi.mesh = bm
	mi.material_override = mat
	mi.position = p
	_model.add_child(mi)


func _ground_y() -> void:
	position.y = SURFACE.GROUND_Y - 2.0 + SURFACE.height(P, L, position.x, position.z)


func take_hit(d: float, _from: Vector3 = Vector3.ZERO, _by: Node = null) -> void:
	hp -= d
	if hp <= 0.0:
		G.explosion(global_position, 9.0)
		G.stat("mraps_destroyed")
		G.pods.erase(self)
		queue_free()


func _process(dt: float) -> void:
	# a convoy waits for its escort to catch up
	_esc_t -= dt
	if _esc_t <= 0.0:
		_esc_t = 2.0
		_wait = false
		var g0: Node = G.match_node.ground if G.match_node else null
		if g0:
			var near := 1.0e9
			var any := false
			for c in g0.occupants:
				if is_instance_valid(c) and c.state == "alive" and c.has_meta("escort") and c.get_meta("escort") == self:
					any = true
					near = minf(near, c.global_position.distance_to(global_position))
			_wait = any and near > 40.0
	# drive the streets
	var to := goal - position
	to.y = 0.0
	if _wait:
		pass
	elif to.length() < 8.0:
		goal = home + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * radius * 0.8
	else:
		var dir := to.normalized()
		position += dir * pace * dt
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), clampf(dt * 2.0, 0.0, 1.0))
		_ground_y()
	# the roof gun: at our ships and craft passing low overhead
	gun_t -= dt
	if gun_t > 0.0:
		return
	gun_t = 0.35
	for veh in G.vehicles:
		if is_instance_valid(veh) and G.enemies(team, veh.team) and veh.global_position.distance_to(global_position) < 300.0:
			G.tracer(global_position + Vector3.UP * 3.5, veh.global_position + Vector3.UP * 2.0, Color(0.6, 1.0, 0.4), 0.06, 0.06)
			veh.take_hit(9.0, veh.global_position, null, 1.0)
			return
	var g: Node = G.match_node.ground if G.match_node else null
	if g:
		for c in g.occupants:
			if is_instance_valid(c) and c.state == "alive" and G.enemies(team, c.team) and c.global_position.distance_to(global_position) < 250.0:
				G.tracer(global_position + Vector3.UP * 3.5, c.global_position + Vector3.UP, Color(0.6, 1.0, 0.4), 0.05, 0.05)
				c.take_damage(7.0, null, global_position)
				return
	for v in G.vessels:
		if is_instance_valid(v) and not v.destroyed and G.enemies(team, v.team) and v.kind == "ship" \
				and v.global_position.distance_to(global_position) < 450.0:
			var at: Vector3 = v.to_global(v.aabb.get_center()) + Vector3(randf_range(-6, 6), randf_range(-3, 3), randf_range(-6, 6))
			G.tracer(global_position + Vector3.UP * 3.5, at, Color(0.6, 1.0, 0.4), 0.06, 0.06)
			v.take_hit(4.0, at, null)
			if G.sfx:
				G.sfx.play("heavy", global_position, -4.0)
			return
