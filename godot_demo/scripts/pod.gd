extends Node3D
## A boarding pod (or an infection spore pod) flying from its launcher to a breach
## point on the target. On impact it blows the hull panel or airlock door and the
## squad inside steps out into the target's interior.

var team := 1
var faction := 1
var target: Node3D                 # the vessel being boarded
var approach_m: Node3D             # outside the hull, lined up with the breach
var impact_m: Node3D               # on the hull
var inside_m: Node3D               # where the squad comes out
var panel := ""                    # the node to blow open
var squad: Array = []              # roles to spawn
var riders: Array = []             # people riding in it (players, their squadmates)
var join = null                    # a squad the troops join on landing (reinforcements)
var hp := 200.0
var stage := 0
var speed := 140.0
var spore := false
var model: Node3D
var trail_t := 0.0


func setup(from: Vector3, team_: int, faction_: int, tgt: Node3D, approach: Node3D, impact: Node3D, inside: Node3D,
		panel_: String, roles: Array, spore_: bool = false) -> void:
	team = team_
	faction = faction_
	target = tgt
	approach_m = approach
	impact_m = impact
	inside_m = inside
	panel = panel_
	squad = roles
	spore = spore_
	var folder := "ships_X" if spore else ("ships_P" if faction == 3 else "ships_F%d" % faction)
	model = load("res://models/%s/ship_XS_POD.glb" % folder).instantiate()
	add_child(model)
	global_position = from
	G.pods.append(self)
	G.register(self)
	var pk := Area3D.new()
	pk.collision_layer = G.LAYER_PICK
	pk.monitoring = false
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 3.0
	cs.shape = sp
	pk.add_child(cs)
	pk.set_meta("unit", self)
	add_child(pk)


func take_hit(dmg: float, _from: Vector3 = Vector3.ZERO, _by: Node = null) -> void:
	hp -= dmg
	if hp <= 0.0 and stage < 2:
		G.explosion(global_position, 4.0)
		G.say("A %s was shot down%s" % ["spore pod" if spore else "boarding pod",
			"" if riders.is_empty() else " with %d aboard" % (riders.size() + squad.size())], team)
		_lost_riders()
		G.pods.erase(self)
		queue_free()


func _lost_riders() -> void:
	for r in riders:
		if is_instance_valid(r) and r.state != "dead":
			r.riding = null
			r.visible = true
			r.collision_layer = G.LAYER_CHAR
			r.die(null)
	riders = []


var vel := Vector3.ZERO
var launch_dir := Vector3.ZERO     # set by the ship: the pod first drops out of the belly this way
const NOSE := 3.0                  # origin to the tip of the ram claws (the model's nose is -Z)


func _process(dt: float) -> void:
	if target == null or not is_instance_valid(target) or target.destroyed:
		_lost_riders()
		G.pods.erase(self)
		queue_free()
		return
	if stage >= 2:
		return
	if launch_dir != Vector3.ZERO and _age < 1.0:
		_age += dt                                    # falling clear of the belly hatch
		vel = vel.lerp(launch_dir * 35.0, clampf(dt * 3.0, 0.0, 1.0))
		global_position += vel * dt
		_face(vel)
		return
	var goal: Vector3
	var spd: float
	if stage == 0:
		goal = approach_m.global_position
		spd = min(speed, 40.0 + 120.0 * _age)          # kicked out of the tube, then the motor lights
	else:
		# the final run: straight down the approach line, ram first, claws biting into the hull
		var axis: Vector3 = (impact_m.global_position - approach_m.global_position).normalized()
		goal = impact_m.global_position - axis * NOSE
		spd = speed * 0.45
	_age += dt
	var to := goal - global_position
	var step := spd * dt
	if to.length() <= step:
		global_position = goal
		stage += 1
		if stage == 2:
			_impact()
		return
	# steer: the heading swings toward the goal at a limited rate (no instant snaps)
	var want := to.normalized()
	if vel == Vector3.ZERO:
		vel = want * spd
	var turn: float = clampf(dt * (2.5 if stage == 0 else 6.0), 0.0, 1.0)
	var dir := vel.normalized().slerp(want, turn).normalized() if vel.normalized().dot(want) > -0.99 else want
	if stage == 1 or to.length() < 60.0:
		dir = want                                    # lined up for the hit
	vel = dir * spd
	global_position += vel * dt
	_face(dir)
	trail_t -= dt
	if trail_t <= 0.0:
		trail_t = 0.05
		G.tracer(global_position + dir * 3.0, global_position + dir * 3.0 - dir * 7.0,
			Color(0.75, 0.3, 1.0) if spore else Color(1.0, 0.6, 0.3), 0.4, 0.15)
		G.tracer(global_position - dir * 4.0, global_position - dir * 10.0,
			Color(1.0, 0.75, 0.4) if not spore else Color(0.8, 0.4, 1.0), 0.6, 0.1)


var _age := 0.0


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


## Point the nose (-Z) along dir.
func _face(dir: Vector3) -> void:
	if dir.length() < 0.001:
		return
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	global_basis = Basis.looking_at(dir, up)


func _impact() -> void:
	G.pods.erase(self)
	var at := impact_m.global_position
	# square-on to the hull: line up with the surface where it hits
	var axis: Vector3 = (impact_m.global_position - approach_m.global_position).normalized()
	var hh := G.ray(at - axis * 8.0, at + axis * 4.0, [], G.LAYER_WORLD)
	var nrm: Vector3 = -axis
	if not hh.is_empty() and (hh.normal as Vector3).length() > 0.5:
		nrm = (hh.normal as Vector3).normalized()
		at = hh.position
	_face(-nrm)
	global_position = at + nrm * NOSE
	# one pod per entry point: a new one knocks the old, empty one off the hull
	for old in target.get_children():
		if old != self and old.get_script() == get_script() and old.global_position.distance_to(global_position) < 6.0:
			G.explosion(old.global_position, 2.0)
			old.queue_free()
	G.explosion(at, 3.5, Color(0.8, 0.35, 1.0) if spore else Color(1.0, 0.55, 0.15))
	if panel != "":
		target.breach(panel)
	reparent(target, true)                          # the pod stays stuck in the hull...
	for sb in find_children("*", "StaticBody3D", true, false):
		(sb as StaticBody3D).collision_layer = 0     # ...but doesn't block the breach it made
	var inside := target.to_local(inside_m.global_position)
	target.raise_alarm(inside)
	if spore:
		target.infect_zone(target.zone_at(inside))
	if G.match_node:
		if riders.is_empty() and join == null:
			G.match_node.spawn_squad(target, inside, team, faction, squad, true)
		else:
			G.match_node.disembark(target, inside, team, faction, squad, riders, join)
			riders = []
	G.say("%s %s breached %s" % [G.team_name(team) if team != 4 else "An infection", "spore pod" if spore else "boarding pod",
		target.display_name], target.team)
