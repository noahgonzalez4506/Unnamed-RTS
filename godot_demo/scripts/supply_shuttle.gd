extends Node3D
## A supply shuttle (Darter): carries replacement crew, boarders and supplies from a
## station to a ship out in the field. Lifts off, flies over, lines up with the ship's
## cargo bay (or hangar), sets down, unloads and flies home. Point defense can kill it.

var home: Node3D
var target: Node3D
var team := 1
var faction := 1
var crew: Array = []               # roles of replacement crew aboard
var troops := 0                    # boarders for the berths
var supplies := 0.0
var hp := 400.0
var stage := 0                     # 0 lift, 1 cruise, 2 line up, 3 land, 4 unload, 5 home
var stage_t := 0.0
var land_local := Vector3.ZERO     # on the ship, in its space
var vel := Vector3.ZERO
var model: Node3D
var net_pos := Vector3.INF
var net_rot := Vector3.ZERO
var _home_pad := Vector3.INF       # the station pad it flies from and back to


func setup(home_: Node3D, tgt: Node3D, crew_: Array, troops_: int, supplies_: float) -> void:
	home = home_
	target = tgt
	team = tgt.team
	faction = home.faction if home.faction in [1, 2, 3] else 1
	crew = crew_
	troops = troops_
	supplies = supplies_
	var folder: String = {1: "ships_F1", 2: "ships_F2", 3: "ships_P"}.get(faction, "ships_F1")
	var path := "res://models/%s/ship_XS_DARTER.glb" % folder
	if not ResourceLoader.exists(path):
		path = "res://models/ships_F1/ship_XS_DARTER.glb"
	model = load(path).instantiate()
	add_child(model)
	for sb in model.find_children("*", "StaticBody3D", true, false):
		(sb as StaticBody3D).collision_layer = 0
	global_position = _home_point()
	if home.kind == "ship" and home.has_method("darter_away"):
		home.darter_away(true)
	land_local = target.arrival_point() + Vector3(0, 0.4, 0)
	var pk := Area3D.new()
	pk.collision_layer = G.LAYER_PICK
	pk.monitoring = false
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 7.0
	cs.shape = sp
	pk.add_child(cs)
	pk.set_meta("unit", self)
	add_child(pk)
	G.pods.append(self)                      # point defense treats it like any small craft
	G.register(self)


## Network kind marker (network.gd sends kind 5 for these).
func _deliver() -> void:
	pass


## Where it leaves from and comes back to: a supply ship's cargo bay, or above a station.
func _home_point() -> Vector3:
	if home.kind == "ship":
		return home.to_global(home.arrival_point() + Vector3(0, 3.0, 0))
	if _home_pad == Vector3.INF:
		_home_pad = home.craft_pad() if home.has_method("craft_pad") else home.aabb.get_center()
	return home.to_global(_home_pad + Vector3(0, 2.0, 0))


func take_hit(d: float, _from: Vector3 = Vector3.ZERO, _by: Node = null) -> void:
	if G.is_client() or stage >= 4:
		return
	hp -= d
	if hp <= 0.0:
		G.explosion(global_position, 8.0)
		G.say("A supply shuttle bound for %s was shot down: %d crew, %d boarders and %d supplies lost" % [
			target.display_name if is_instance_valid(target) else "the fleet", crew.size(), troops, int(supplies)], team)
		G.stat("supply_runs_lost")
		if is_instance_valid(home) and home.kind == "ship" and home.has_method("darter_away"):
			home.darter_away(false)                   # (a spare comes out of the hold)
		G.pods.erase(self)
		queue_free()


func _fly_to(p: Vector3, spd: float, dt: float, turn: float = 2.0) -> bool:
	var to := p - global_position
	if to.length() <= spd * dt:
		global_position = p
		return true
	vel = vel.lerp(to.normalized() * spd, clampf(dt * turn, 0.0, 1.0))
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
	if stage < 4 and (target == null or not is_instance_valid(target) or target.destroyed or target.team != team):
		stage = 5                                   # nothing to deliver to: take it home
		if get_parent() != get_tree().root:
			reparent(get_tree().root, true)
	stage_t += dt
	match stage:
		0:
			global_position += Vector3.UP * 6.0 * dt
			if stage_t > 1.5:
				stage = 1
				stage_t = 0.0
		1:
			# cruise to a point off the ship's cargo-bay side, level with the bay
			var side := 1.0 if land_local.x >= 0.0 else -1.0
			var app: Vector3 = target.to_global(land_local + Vector3(side * 60.0, 6.0, 0))
			if _fly_to(app, 160.0 * (1.0 + G.tech_bonus(team, "darter_speed")), dt) or stage_t > 90.0:
				stage = 2
				stage_t = 0.0
		2:
			var side2 := 1.0 if land_local.x >= 0.0 else -1.0
			var near: Vector3 = target.to_global(land_local + Vector3(side2 * 14.0, 2.0, 0))
			if _fly_to(near, 30.0, dt, 4.0) or stage_t > 20.0:
				stage = 3
				stage_t = 0.0
		3:
			if _fly_to(target.to_global(land_local), 9.0, dt, 6.0) or stage_t > 12.0:
				stage = 4
				stage_t = 0.0
				reparent(target, true)               # down on the deck: ride along with the ship
		4:
			if stage_t > 1.5 and (troops > 0 or supplies > 0.0 or not crew.is_empty()):
				_unload()
			if stage_t > 5.0:
				stage = 5
				stage_t = 0.0
				reparent(get_tree().root, true)
		5:
			if home == null or not is_instance_valid(home) or home.destroyed:
				_gone()
				return
			if _fly_to(_home_point() + Vector3.UP * 4.0, 170.0 * (1.0 + G.tech_bonus(team, "darter_speed")), dt):
				if home.kind == "ship" and home.has_method("darter_away"):
					home.darter_away(false)
				_return_cargo()
				_gone()


func _unload() -> void:
	if target.kind == "station":
		target.reserve += troops                   # into the station's barracks
	else:
		target.troops = mini(target.berth_cap, target.troops + troops)
	target.supplies = minf(target.supply_cap, target.supplies + supplies)
	if not crew.is_empty() and G.match_node and G.match_node.logistics:
		G.match_node.logistics.replace_crew(target, crew, target.arrival_point())
	G.stat("supply_runs_delivered")
	if team == G.player_team:
		G.say("Supply shuttle unloaded aboard %s: %d crew, %d boarders, %d supplies" % [target.display_name,
			crew.size(), troops, int(supplies)], team)
	crew = []
	troops = 0
	supplies = 0.0


## Came home still loaded (the ship it was flying to was lost or changed sides): everyone and
## everything aboard goes back where it came from.
func _return_cargo() -> void:
	var people: int = troops + crew.size()
	if people <= 0 and supplies <= 0.0:
		return
	if home.kind == "station":
		home.reserve = mini(home.reserve_cap, home.reserve + people)
	else:
		home.troops = mini(home.berth_cap, home.troops + people)
	home.supplies = minf(home.supply_cap, home.supplies + supplies)
	if team == G.player_team:
		G.say("Supply shuttle back at %s with its load: %d people, %d supplies" % [home.display_name, people, int(supplies)], team)
	crew = []
	troops = 0
	supplies = 0.0


func _gone() -> void:
	G.pods.erase(self)
	queue_free()
