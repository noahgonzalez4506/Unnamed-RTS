extends Node
## Computer opponents: the rival faction's commander (team 2), the pirates (team 3)
## and the infection (team 4). They use the same orders as the player.

const POD := preload("res://scripts/pod.gd")

var t := 0.0
var _tick := 0.0
var spore_t := 120.0
var pirate_home := Vector3.ZERO
var pirate_radius := 1100.0
var rival_teams: Array = [2]      # sides without a human commander
var attack_after := 70.0          # seconds of build-up before the AI goes on the attack


func _physics_process(dt: float) -> void:
	if G.game_over:
		return
	t += dt
	spore_t -= dt
	_tick -= dt
	if _tick > 0.0:
		return
	_tick = 1.5
	for team in rival_teams:
		_rival(team)
	_pirates()
	_infection()


func _ships(team: int) -> Array:
	return G.vessels.filter(func(v): return is_instance_valid(v) and v.kind == "ship" and v.team == team and not v.destroyed)


func _station(team: int) -> Node:
	for v in G.vessels:
		if is_instance_valid(v) and v.kind == "station" and v.team == team and not v.destroyed and v.cls.begins_with("STATION"):
			return v
	return null


## Whether side `team` has found `n` (sensors, radar, or a station seen before): fog.gd.
static func sees(team: int, n: Node) -> bool:
	var f = G.match_node.get("fog") if G.match_node else null
	return f == null or f.sees(team, n)


func _nearest_enemy_vessel(from: Node, team: int, max_d: float, ships_only: bool) -> Node:
	var best: Node = null
	var bd := max_d
	for v in G.vessels:
		if not is_instance_valid(v) or v.destroyed or not G.enemies(team, v.team) or v == from:
			continue
		if not sees(team, v):
			continue                                  # (in the fog: it hasn't been found)
		if ships_only and v.kind != "ship":
			continue
		if v.team == 4 and team != 4:
			continue                                  # nobody sane boards the infected derelict
		if v.team == 3 and v.global_position.distance_to(pirate_home) < pirate_radius and team != 3:
			continue                                  # and nobody goes poking the pirates' nest
		var d: float = from.global_position.distance_to(v.global_position)
		if d < bd:
			bd = d
			best = v
	return best


# ------------------------------------------------------------------ the rival commander

func _rival(team: int) -> void:
	var home := _station(team)
	if home and home.can_train() and G.resources[team]["alloys"] > 900.0 and _soldiers(team) < 40:
		home.train_squad()
	for s in _ships(team):
		if s.is_supply_ship:
			continue                                   # the logistics fly the supply ship
		var big: bool = s.cls in ["LARGE", "XL", "MEDIUM"]
		if s.hull < s.max_hull * 0.25 and home:
			s.attack_target = null
			s.move_target = home.global_position + Vector3(-300, 0, randf_range(-200, 200))
			continue
		if t < attack_after:
			continue                                   # build up for the first minute
		var tgt := _nearest_enemy_vessel(s, team, 6000.0, true)
		if tgt == null:
			tgt = _nearest_enemy_vessel(s, team, 8000.0, false)
		if tgt == null:
			continue
		# out of boarders and nearly out of supplies: go home, top up, come back
		if s.troops < 4 and s.supplies < s.supply_cap * 0.25 and G.match_node.homes.has(team):
			var h: Node = G.match_node.homes[team]
			if h and not h.destroyed:
				if not s.has_meta("dock_at"):
					G.match_node.logistics.send_to_dock(s, h)
				continue
		if s.has_meta("dock_at"):
			continue                                   # tied up at a berth until topped up
		# drop frigates go after surface installations (mines, the pirate fort) with ODST pods
		if not s.drop_racks.is_empty():
			var gb: Node = null
			var gd := 9000.0
			for v in G.vessels:
				if s.is_surface(v) and not v.destroyed and G.enemies(team, v.team) and sees(team, v):
					var dd: float = s.global_position.distance_to(v.global_position)
					if dd < gd:
						gd = dd
						gb = v
			if gb:
				s.attack_target = gb
				if gd > 1800.0:
					s.move_target = gb.global_position + (s.global_position - gb.global_position).normalized() * 1200.0
				elif s.can_drop(gb) and s.drop_order.is_empty() and randf() < 0.5:
					s.order_drop(gb)
				continue
		s.attack_target = tgt
		var d: float = s.global_position.distance_to(tgt.global_position)
		if d > 1100.0:
			s.move_target = tgt.global_position + (s.global_position - tgt.global_position).normalized() * (800.0 if big else 600.0)
		if big and d < 2600.0 and s.launch_wanted == 0 and s.parked_count() > 0 and randf() < 0.3:
			s.request_fighters()
		var shields_down: bool = tgt.get("shields") != null and tgt.shields <= tgt.max_shields * 0.15
		if big and s.troops >= 8 and d < 1400.0 and shields_down and randf() < 0.4:
			s.start_boarding(tgt, "shuttle" if s.can_shuttle(tgt) and randf() < 0.4 else "pods")
		elif s.troops >= 6 and s.can_eva(tgt) and s.boarding.is_empty() and randf() < 0.3:
			s.start_boarding(tgt, "eva")             # close enough to cross on thruster packs


func _soldiers(team: int) -> int:
	var n := 0
	for c in G.characters:
		if is_instance_valid(c) and c.team == team and c.state != "dead" and not c.is_crew():
			n += 1
	return n


# ------------------------------------------------------------------ pirates

func _pirates() -> void:
	for s in _ships(3):
		var intruder: Node = null
		var bd := pirate_radius + 400.0
		for v in G.vessels:
			if is_instance_valid(v) and not v.destroyed and v.kind == "ship" and G.enemies(3, v.team) and v.team != 4 and sees(3, v):
				var d: float = v.global_position.distance_to(pirate_home)
				if d < bd:
					bd = d
					intruder = v
		if intruder:
			s.attack_target = intruder
			if s.global_position.distance_to(intruder.global_position) > 700.0:
				s.move_target = intruder.global_position
			# raiders board soft targets: pirates love a prize ship
			if s.cls == "MEDIUM" and s.troops >= 8 and intruder.shields <= intruder.max_shields * 0.2 \
					and s.global_position.distance_to(intruder.global_position) < 1400.0 and randf() < 0.3:
				s.start_boarding(intruder, "pods")
		else:
			s.attack_target = null
			if s.move_target == Vector3.INF or s.global_position.distance_to(pirate_home) > pirate_radius:
				var a := randf() * TAU
				s.move_target = pirate_home + Vector3(cos(a), 0, sin(a)) * 600.0     # patrol their space


# ------------------------------------------------------------------ the infection

## Every couple of minutes an overgrown vessel fires a spore pod at the nearest clean one.
func _infection() -> void:
	if spore_t > 0.0:
		return
	spore_t = 150.0
	for v in G.vessels:
		if not is_instance_valid(v) or v.destroyed or v.infected_fraction() < 0.3:
			continue
		var tgt: Node = null
		var bd := 2600.0
		for o in G.vessels:
			if o != v and is_instance_valid(o) and not o.destroyed and o.infected_fraction() < 0.05:
				var d: float = v.global_position.distance_to(o.global_position)
				if d < bd:
					bd = d
					tgt = o
		if tgt == null:
			continue
		var entries: Array = tgt.boarding_entries(v.global_position)
		if entries.is_empty():
			continue
		var e: Array = entries[0]
		var pod: Node3D = POD.new()
		get_tree().root.add_child(pod)
		pod.setup(v.to_global(v.aabb.get_center()) + Vector3.UP * 8.0, 4, 4, tgt, e[0], e[1], e[2], e[3],
			["swarmer", "swarmer", "swarmer", "swarmer"], true)
		G.say("The infection launched a spore pod at %s!" % tgt.display_name, tgt.team)
		G.stat("spore_pods")
		return
