extends Node3D
## An EVA boarding team crossing open space from its ship's airlock to an adjacent hull, no
## pods: troopers in vacuum suits on thruster packs, in a loose wedge. They're real people the
## whole way across (point defense and anyone with a gun can pick them off), breathing from
## their suits. At the far hull they stop on the breach panel or airlock door, cut it (a few
## seconds; the compartment behind vents) and go in. If the target is lost on the way, they
## fly back to their ship.

var eva := true                    # (riders float in formation, not seated)
var team := 1
var faction := 1
var target: Node3D
var home: Node3D
var approach_m: Node3D             # outside the target's hull, lined up with the way in
var impact_m: Node3D               # on the hull
var inside_m: Node3D               # where they come out
var panel := ""                    # what they cut open
var riders: Array = []
var stage := 0                     # 0 out to the approach, 1 in to the hull, 2 cutting, 3 going home
var speed := 16.0
var cut_t := 3.0
var vel := Vector3.ZERO
var _slots: Array = []
var _home_at := Vector3.ZERO       # (local to home) the airlock they left by, for the way back
var _home_in := Vector3.ZERO
var _spark_t := 0.0


## from: just outside our airlock (world). entry: the target's [approach, impact, interior, panel].
## mine: our own airlock's entry (for the way home).
func setup(from: Vector3, team_: int, faction_: int, tgt: Node3D, entry: Array, home_: Node3D, mine: Array) -> void:
	team = team_
	faction = faction_
	target = tgt
	home = home_
	approach_m = entry[0]
	impact_m = entry[1]
	inside_m = entry[2]
	panel = entry[3]
	_home_at = home.to_local(from)
	_home_in = home.to_local((mine[2] as Node3D).global_position)
	global_position = from
	G.pods.append(self)                            # point defense treats them like any small craft
	G.register(self)


## Each rider gets a place in the wedge: the leader at the point, the rest in pairs behind.
func seat_for(c: Node) -> Node3D:
	var i: int = riders.find(c)
	if i < 0:
		i = riders.size()
	while _slots.size() <= i:
		var k := _slots.size()
		var row := int((k + 1) / 2.0)
		var side := -1.0 if k % 2 == 1 else 1.0
		var s := Node3D.new()
		s.position = Vector3(side * 1.8 * row if k > 0 else 0.0, -0.9, 2.2 * row)
		add_child(s)
		_slots.append(s)
	return _slots[i]


## Point defense or a gunner hit the team: one of them takes it.
func take_hit(dmg: float, from: Vector3 = Vector3.ZERO, by: Node = null) -> void:
	var alive: Array = riders.filter(func(r): return is_instance_valid(r) and r.state == "alive")
	if alive.is_empty():
		return
	alive.pick_random().take_damage(dmg * 0.5, by, from)


func _process(dt: float) -> void:
	# anyone hit hard out here drifts off and is lost
	for r in riders.duplicate():
		if not is_instance_valid(r) or r.riding != self:
			riders.erase(r)
		elif r.state != "alive":
			riders.erase(r)
			r.riding = null
			r.ride_seat = null
			if r.state == "downed":
				r.die(null)
		else:
			r.breathe_vacuum(dt)
	if riders.is_empty():
		_gone()
		return
	var lost: bool = target == null or not is_instance_valid(target) or target.destroyed
	if lost and stage < 3:
		stage = 3
	if stage == 3:
		_go_home(dt)
		return
	if stage == 2:
		cut_t -= dt
		_spark_t -= dt
		if _spark_t <= 0.0:
			_spark_t = 0.12
			G.flash(impact_m.global_position, Color(1.0, 0.75, 0.35), 1.5, 2.5, 0.06)
		if cut_t <= 0.0:
			_cut_through()
		return
	var goal: Vector3
	if stage == 0:
		goal = approach_m.global_position
	else:
		var axis: Vector3 = (impact_m.global_position - approach_m.global_position).normalized()
		goal = impact_m.global_position - axis * 2.5     # (the point man's hands on the hull)
	if _fly_to(goal, dt):
		stage += 1
		if stage == 2:
			target.red_alert("EVA boarders on the hull")


## Thrusters toward goal; true on arrival.
func _fly_to(goal: Vector3, dt: float) -> bool:
	var to := goal - global_position
	var step := speed * dt
	if to.length() <= step:
		global_position = goal
		vel = Vector3.ZERO
		return true
	vel = vel.lerp(to.normalized() * speed, clampf(dt * 1.5, 0.0, 1.0))
	global_position += vel * dt
	if vel.length() > 0.5:
		var up := Vector3.UP if absf(vel.normalized().dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
		global_basis = Basis.looking_at(vel.normalized(), up)
	return false


func _cut_through() -> void:
	G.pods.erase(self)
	var at: Vector3 = impact_m.global_position
	G.explosion(at, 2.5)
	if panel != "":
		target.breach(panel)                         # (the compartment behind vents)
	var inside: Vector3 = target.to_local(inside_m.global_position)
	target.raise_alarm(inside)
	G.say("%s EVA team cut into %s" % [G.team_name(team), target.display_name], target.team)
	G.stat("eva_boardings")
	if G.match_node:
		G.match_node.disembark(target, inside, team, faction, [], riders)
	riders = []
	queue_free()


func _go_home(dt: float) -> void:
	if home == null or not is_instance_valid(home) or home.destroyed:
		for r in riders:
			if is_instance_valid(r):
				r.riding = null
				r.ride_seat = null
				r.die(null)
		_gone()
		return
	if _fly_to(home.to_global(_home_at), dt):
		G.pods.erase(self)
		if G.match_node:
			G.match_node.disembark(home, home.snap_local(_home_in), team, faction, [], riders)
		riders = []
		queue_free()


func _gone() -> void:
	G.pods.erase(self)
	queue_free()
