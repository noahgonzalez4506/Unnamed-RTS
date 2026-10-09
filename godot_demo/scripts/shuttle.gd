extends Node3D
## A boarding shuttle (the dropship): lifts off its carrier's hangar pad with a squad
## aboard, flies out, and either lands in the target's hangar (ships) or docks at an
## airlock (stations). The ramp drops and the squad charges out. Then it flies home.
## Point defense can shoot it down with everyone aboard.

var team := 1
var faction := 1
var carrier: Node3D
var target: Node3D
var roles: Array = []              # AI troops to spawn on arrival
var riders: Array = []             # characters riding (players and soldiers who embarked)
var hp := 650.0
const DOCK_HALF := 7.5                # rear ramp to centre: how far out the shuttle sits when docked
var stage := 0                     # 0 lift, 1 leave hangar, 2 approach, 3 land, 4 unload, 5 leave
var stage_t := 0.0
var path: Array = []               # global waypoints for the current stage
var model: Node3D
var land_at: Node3D                # marker on the target where the ramp opens
var inside: Node3D                 # where the troops come out (marker)
var door := ""                     # an airlock door to blow (stations)
var vel := Vector3.ZERO
var net_pos := Vector3.INF
var net_rot := Vector3.ZERO


func setup(carrier_: Node3D, pad_world: Transform3D, team_: int, faction_: int, tgt: Node3D, roles_: Array, riders_: Array) -> void:
	hp *= 1.0 + G.tech_bonus(team_, "shuttle_hp")
	carrier = carrier_
	team = team_
	faction = faction_
	target = tgt
	roles = roles_
	riders = riders_
	var folder := "ships_P" if faction == 3 else "ships_F%d" % faction
	model = load("res://models/%s/ship_XS_DROPSHIP.glb" % folder).instantiate()
	add_child(model)
	for sb in model.find_children("*", "StaticBody3D", true, false):
		(sb as StaticBody3D).collision_layer = 0
	global_transform = pad_world
	var pk := Area3D.new()
	pk.collision_layer = G.LAYER_PICK
	pk.monitoring = false
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 8.0
	cs.shape = sp
	pk.add_child(cs)
	pk.set_meta("unit", self)
	add_child(pk)
	G.pods.append(self)                        # point defense treats it like a pod
	G.register(self)
	_pick_landing()
	G.stat("shuttles_launched")


func _pick_landing() -> void:
	# a hangar pad on a ship, else an airlock on a station
	if target.kind == "ship":
		# a clear pad in their hangar: an empty fighter pad, else their shuttle pad if it's away
		for p in target.pads:
			if p["parked"] == null:
				land_at = target.mark(p["name"])
				break
		if land_at == null and not target.has_shuttle and target.mark("Hangar_ShuttlePad"):
			land_at = target.mark("Hangar_ShuttlePad")
		if land_at == null and not target.pads.is_empty():
			land_at = target.mark(target.pads[randi() % target.pads.size()]["name"])
		if land_at:
			inside = land_at
			return
	var e: Array = target.boarding_entries(global_position)
	if not e.is_empty():
		land_at = e[0][1]
		inside = e[0][2]
		door = e[0][3]


func take_hit(d: float, _from: Vector3 = Vector3.ZERO, _by: Node = null) -> void:
	if G.is_client():
		return
	hp -= d
	if hp <= 0.0:
		G.explosion(global_position, 10.0)
		G.say("A boarding shuttle was shot down with %d aboard" % (roles.size() + riders.size()), team)
		for r in riders:
			if is_instance_valid(r) and r.state != "dead":
				r.riding = null
				r.visible = true
				r.collision_layer = G.LAYER_CHAR
				r.die(null)
		if carrier and is_instance_valid(carrier) and carrier.has_method("shuttle_lost"):
			carrier.shuttle_lost()
		G.pods.erase(self)
		queue_free()


func _fly_to(p: Vector3, spd: float, dt: float) -> bool:
	var to := p - global_position
	var step := spd * dt
	if to.length() <= step:
		global_position = p
		return true
	vel = vel.lerp(to.normalized() * spd, clampf(dt * 2.0, 0.0, 1.0))
	global_position += vel * dt
	var flat := Vector3(vel.x, 0, vel.z)
	if flat.length() > 1.0:
		look_at(global_position + flat, Vector3.UP)
	return false


func _process(dt: float) -> void:
	if G.is_client():
		if net_pos != Vector3.INF:
			global_position = global_position.lerp(net_pos, clampf(dt * 10.0, 0.0, 1.0))
			global_rotation = net_rot
		return
	if target == null or not is_instance_valid(target) or target.destroyed or land_at == null:
		_go_home(dt)
		return
	stage_t += dt
	match stage:
		0:                                      # lift off the pad
			global_position += Vector3.UP * 3.0 * dt
			if stage_t > 1.6:
				stage = 1
				stage_t = 0.0
		1:                                      # out of the hangar, sideways through the shield
			var side := 1.0 if carrier and carrier.to_local(global_position).x >= 0.0 else -1.0
			var out: Vector3 = carrier.to_global(carrier.to_local(global_position) + Vector3(side * 45.0, 4.0, 0)) if carrier else global_position + Vector3.UP * 40.0
			if _fly_to(out, 30.0, dt) or stage_t > 6.0:
				stage = 2
				stage_t = 0.0
		2:                                      # cross to the target, lined up with the landing spot
			var lp: Vector3 = target.to_local(land_at.global_position)
			var side2 := 1.0 if lp.x >= 0.0 else -1.0
			var app: Vector3 = target.to_global(lp + Vector3(side2 * 50.0, 6.0, 0))
			if _fly_to(app, 140.0 * (1.0 + G.tech_bonus(team, "shuttle_speed")), dt):
				stage = 3
				stage_t = 0.0
		3:                                      # in through the hangar shield (or onto the airlock) and down
			if door != "":
				# docking at a hull airlock: swing round and back the rear ramp onto it
				var out_dir: Vector3 = (global_position - land_at.global_position)
				out_dir.y = 0.0
				out_dir = out_dir.normalized() if out_dir.length() > 0.5 else Vector3.FORWARD
				var dock_p: Vector3 = land_at.global_position + out_dir * DOCK_HALF
				var to := dock_p - global_position
				var stp := 16.0 * dt
				global_basis = global_basis.slerp(Basis.looking_at(out_dir, Vector3.UP), clampf(dt * 3.0, 0.0, 1.0)).orthonormalized()
				if to.length() <= stp:
					global_position = dock_p
					global_basis = Basis.looking_at(out_dir, Vector3.UP)
					stage = 4
					stage_t = 0.0
					reparent(target, true)
					target.breach(door)
				else:
					global_position += to.normalized() * stp
			else:
				# into a hangar: turn the nose back out the way we came and reverse in, so the
				# rear ramp drops toward the inside of the ship
				var lp3: Vector3 = target.to_local(land_at.global_position)
				var out3: Vector3 = target.global_basis * Vector3(1.0 if lp3.x >= 0.0 else -1.0, 0, 0)
				out3.y = 0.0
				out3 = out3.normalized()
				var want: Basis = Basis.looking_at(out3, Vector3.UP)
				global_basis = global_basis.slerp(want, clampf(dt * 3.0, 0.0, 1.0)).orthonormalized()
				var spot: Vector3 = land_at.global_position + Vector3.UP * (0.6 if target.kind == "ship" else 1.5)
				var to3 := spot - global_position
				var stp3 := 18.0 * dt * clampf(1.2 - global_basis.z.angle_to(want.z) / PI, 0.25, 1.0)
				if to3.length() <= stp3:
					global_position = spot
					global_basis = want
					stage = 4
					stage_t = 0.0
					reparent(target, true)
				else:
					global_position += to3.normalized() * stp3
		4:                                      # ramp down, troops out
			if stage_t > 1.0 and (not roles.is_empty() or not riders.is_empty()):
				_unload()
			if stage_t > 6.0:
				stage = 5
				stage_t = 0.0
				reparent(get_tree().root, true)
		5:
			_go_home(dt)


func _unload() -> void:
	var lp: Vector3 = target.snap_local(target.to_local(inside.global_position) + (Vector3(3.0, 0, 0) if target.kind == "ship" else Vector3.ZERO))
	# out down the ramp: the foot of it, if that's on the deck
	var ramp: Node3D = model.find_child("*_RampExit", true, false) as Node3D if model else null
	if ramp:
		var rl: Vector3 = target.snap_local(target.to_local(ramp.global_position))
		if rl.distance_to(target.to_local(ramp.global_position)) < 4.0:
			lp = rl
	target.raise_alarm(lp)
	G.say("%s boarding shuttle landed aboard %s" % [G.team_name(team), target.display_name], target.team)
	G.stat("shuttle_landed")
	if G.match_node:
		G.match_node.disembark(target, lp, team, faction, roles, riders)
	roles = []
	riders = []


## Seats in the model (its *_Seat_n markers, in order); each rider gets the next free one.
var _seats: Array = []


func seat_for(c: Node) -> Node3D:
	if _seats.is_empty() and model:
		for n in model.find_children("*_Seat_*", "Node3D", true, false):
			_seats.append(n)
		_seats.sort_custom(func(a, b): return int(String(a.name).get_slice("_Seat_", 1)) < int(String(b.name).get_slice("_Seat_", 1)))
	var i: int = riders.find(c)
	if i < 0:
		i = riders.size()
	return _seats[i] if i < _seats.size() else null


func _go_home(dt: float) -> void:
	if carrier and is_instance_valid(carrier) and not carrier.destroyed:
		var sp: Dictionary = carrier.shuttle_spot() if carrier.has_method("shuttle_spot") else {}
		var home_p: Vector3 = carrier.to_global(sp.get("local", Vector3.ZERO) + Vector3(0, 30.0, 0))
		if _fly_to(home_p, 150.0, dt):
			_return_riders()
			_docked_home()
			G.pods.erase(self)
			queue_free()
	else:
		_return_riders()
		G.pods.erase(self)
		queue_free()


## Back aboard the carrier, or lost with it.
func _docked_home() -> void:
	if carrier and is_instance_valid(carrier) and not carrier.destroyed and carrier.has_method("shuttle_home"):
		carrier.shuttle_home()


## The op was called off (target gone): whoever is still aboard gets off back home.
func _return_riders() -> void:
	if riders.is_empty() and roles.is_empty():
		return
	if carrier and is_instance_valid(carrier) and not carrier.destroyed:
		carrier.troops += roles.size()
		var p: Dictionary = carrier.shuttle_pad()
		for r in riders:
			if is_instance_valid(r) and r.state == "alive":
				r.disembark_to(carrier, carrier.snap_local(p["local"] + Vector3(3.0, 0, 0)))
	else:
		for r in riders:
			if is_instance_valid(r) and r.state != "dead":
				r.riding = null
				r.visible = true
				r.die(null)
	riders = []
	roles = []
