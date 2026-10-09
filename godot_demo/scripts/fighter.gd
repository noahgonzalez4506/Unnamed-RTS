extends Node3D
## A fighter: launches from its carrier's hangar pad, then makes strafing runs on its
## target. Point defense shoots it down.

var team := 1
var faction := 1
var carrier: Node3D
var target: Node3D = null
var hp := 160.0
var speed := 140.0
var vel := Vector3.ZERO
var stage := 0                     # 0 lifting off the pad, 1 leaving the hangar, 2 fighting
var stage_t := 0.0
var gun_t := 0.0
var orbit := 0.0
var pilot_name := ""
var model: Node3D
var display_name := "Fighter"
var player := false                # flown by the player (commander.gd drives it)
var throttle := 0.6
var pilot_role := "pilot"
var net_pos := Vector3.INF         # client side: where the host says it is
var net_rot := Vector3.ZERO


func setup(carrier_: Node3D, pad_world: Transform3D, team_: int, faction_: int) -> void:
	carrier = carrier_
	team = team_
	faction = faction_
	var folder := "ships_P" if faction == 3 else "ships_F%d" % faction
	model = load("res://models/%s/ship_XS_FIGHTER.glb" % folder).instantiate()
	add_child(model)
	global_transform = pad_world
	orbit = randf() * TAU
	G.fighters.append(self)
	var pk := Area3D.new()
	pk.collision_layer = G.LAYER_PICK
	pk.monitoring = false
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 6.0
	cs.shape = sp
	pk.add_child(cs)
	pk.set_meta("unit", self)
	add_child(pk)


func take_hit(dmg: float, _from: Vector3 = Vector3.ZERO, _by: Node = null) -> void:
	if G.is_client():
		return
	hp -= dmg
	if hp <= 0.0:
		if player and G.commander:
			G.commander.on_vehicle_lost(self)
		G.explosion(global_position, 8.0)
		G.fighters.erase(self)
		G.say("%s fighter destroyed" % G.team_name(team), team)
		queue_free()


func _process(dt: float) -> void:
	if G.is_client() and not player:
		if net_pos != Vector3.INF:
			global_position = global_position.lerp(net_pos, clampf(dt * 10.0, 0.0, 1.0))
			global_rotation = net_rot
		return
	stage_t += dt
	if player and stage >= 2:
		return                                       # the commander flies it (player_fly)
	if stage == 0:                                   # lift off the pad
		global_position += global_transform.basis.y * 3.0 * dt
		if stage_t > 1.5:
			stage = 1
			stage_t = 0.0
			var side := 1.0 if carrier and carrier.to_local(global_position).x >= 0.0 else -1.0
			vel = carrier.global_transform.basis.x * side * 40.0 if carrier else Vector3.FORWARD * 40.0
		return
	if stage == 1:                                   # out through the hangar shield
		global_position += vel * dt
		if vel.length() > 0.1:
			look_at(global_position + vel, Vector3.UP)
		if stage_t > 2.0:
			stage = 2
		return
	if target == null or not is_instance_valid(target) or target.get("destroyed"):
		target = G.match_node.pick_fighter_target(self) if G.match_node else null
		if target == null:
			if carrier and is_instance_valid(carrier):
				_fly_toward(carrier.global_position + Vector3(0, 60, 0), dt)
			return
	orbit += dt * 0.45
	var c: Vector3 = target.global_position
	var r := 140.0
	var aim_pt := c + Vector3(cos(orbit) * r, 25.0 + sin(orbit * 2.0) * 20.0, sin(orbit) * r)
	_fly_toward(aim_pt, dt)
	gun_t -= dt
	var to_t := c - global_position
	if gun_t <= 0.0 and to_t.length() < 450.0 and (-global_transform.basis.z).dot(to_t.normalized()) > 0.2:
		gun_t = 0.12
		var col := Color(1.0, 0.8, 0.3) if faction != 2 else Color(1.0, 0.3, 0.5)
		var hit_pt := c + Vector3(randfn(0, 6), randfn(0, 3), randfn(0, 10))
		G.tracer(global_position, hit_pt, col, 0.25, 0.08)
		if target.has_method("take_hit"):
			target.take_hit(1.6, global_position)


func _fly_toward(p: Vector3, dt: float) -> void:
	var want := (p - global_position).normalized() * speed
	vel = vel.lerp(want, clamp(dt * 1.5, 0.0, 1.0))
	global_position += vel * dt
	if vel.length() > 1.0:
		look_at(global_position + vel, Vector3.UP)


## The player's flight model: mouse steers, A/D roll, W/S throttle, Shift boost.
func player_fly(dt: float, steer: Vector2, roll: float, throttle_in: float, boost: bool, firing: bool) -> void:
	if stage < 2:
		stage = 2
	throttle = clampf(throttle + throttle_in * dt * 0.8, 0.15, 1.0)
	rotate_object_local(Vector3.RIGHT, -steer.y)
	rotate_object_local(Vector3.UP, -steer.x)
	rotate_object_local(Vector3.FORWARD, -roll * dt * 2.2)
	var spd := speed * (0.35 + throttle * 0.9) * (1.6 if boost else 1.0)
	vel = vel.lerp(-global_basis.z * spd, clampf(dt * 2.0, 0.0, 1.0))
	global_position += vel * dt
	gun_t -= dt
	if firing and gun_t <= 0.0:
		gun_t = 0.09
		var col := Color(1.0, 0.8, 0.3) if faction != 2 else Color(1.0, 0.3, 0.5)
		for side in [-1.5, 1.5]:
			var from: Vector3 = global_position + global_basis.x * side - global_basis.z * 3.0
			var to: Vector3 = from - global_basis.z * 900.0
			var space := get_world_3d().direct_space_state
			var q := PhysicsRayQueryParameters3D.create(from, to, G.LAYER_PICK | G.LAYER_WORLD)
			q.collide_with_areas = true
			var h := space.intersect_ray(q)
			var end: Vector3 = h.position if not h.is_empty() else to
			G.tracer(from, end, col, 0.2, 0.06)
			if h.is_empty():
				continue
			var who: Node = h.collider.get_meta("unit") if h.collider.has_meta("unit") else null
			if who == null:
				var n: Node = h.collider
				while n and not n.has_method("take_hit"):
					n = n.get_parent()
				who = n
			if who and who != self and who.has_method("take_hit") and G.enemies(team, who.team):
				if G.is_client():
					# the host finds the target by its vessel index, or by network id (craft)
					G.network.send_action(G.possessed, "fighter_hit", [G.vessels.find(who), end, int(who.get_meta("net_id", 0))])
				else:
					who.take_hit(3.0, end)
				if G.commander:
					G.commander.hit_marker(false)
