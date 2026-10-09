extends Node
## Fog of war:  godot --headless --path . res://match.tscn -- --fogtest
## An enemy ship sent far off goes dark for the player; the AI doesn't find (or target) a
## player ship outside its sensors and radar, and does once it's close; an enemy station the
## player saw keeps its last-seen side while out of sight; enemy crew aboard their own ship are
## hidden until one of ours aboard can see them, and a "?" marks where they were when they drop
## out of sight. Prints PASS/FAIL lines and "FOG TEST DONE <fails>".

var t := 0.0
var step := 0
var fails := 0
var _wait := 0.0
var fog: Node
var far_enemy: Node
var my_ship: Node
var ai_ship: Node
var st2: Node
var foe: Node
var mine: Node
var marks0 := 0


func _check(ok: bool, what: String) -> void:
	print("PASS " if ok else "FAIL ", what)
	if not ok:
		fails += 1


func _physics_process(dt: float) -> void:
	t += dt
	if t < 2.5:
		return
	if _wait > 0.0:
		_wait -= dt
		return
	match step:
		0:
			fog = G.match_node.fog
			_check(fog != null and fog.enabled(), "fog of war is on")
			G.match_node.ai.attack_after = 99999.0
			var me: int = G.player_team
			var foes: Array = G.vessels.filter(func(v): return v.kind == "ship" and v.team == 2 and not v.destroyed)
			var mines: Array = G.vessels.filter(func(v): return v.kind == "ship" and v.team == me and not v.destroyed)
			_check(foes.size() >= 2 and mines.size() >= 2, "both sides have ships (%d, %d)" % [foes.size(), mines.size()])
			far_enemy = foes[0]
			ai_ship = foes[1]
			my_ship = mines[-1]
			far_enemy.global_position = Vector3(30000, 0, 30000)         # far beyond anyone's radar
			my_ship.global_position = Vector3(-30000, 0, -30000)
			st2 = G.match_node.homes.get(2)
			step = 1
			_wait = 1.2
		1:
			_check(fog.state_of(far_enemy) == "" and not far_enemy.visible, "an enemy ship far off is hidden from the player")
			_check(not fog.sees(2, my_ship), "the AI hasn't found a player ship far off")
			var tgt: Node = G.match_node.ai._nearest_enemy_vessel(ai_ship, 2, 99999.0, true)
			_check(tgt != my_ship, "...and doesn't pick it as a target")
			my_ship.global_position = ai_ship.global_position + Vector3(900, 0, 0)
			step = 2
			_wait = 1.2
		2:
			_check(fog.sees(2, my_ship), "once close, the AI has found it")
			# the rival station: seen at the start (in the player's sensors?) - make sure it's known,
			# then take it out of sight and change its side: the player still sees the old side
			if st2 == null:
				_check(false, "the rival has a home station")
				_done()
				return
			var near_me: Node = G.vessels.filter(func(v): return v.kind == "ship" and v.team == G.player_team and not v.destroyed and v != my_ship)[0]
			near_me.global_position = st2.global_position + Vector3(800, 0, 0)
			step = 3
			_wait = 1.0
		3:
			_check(fog.known.has(st2) and fog.state_of(st2) == "vis", "the player has seen the rival station")
			for v in G.vessels:
				if v.team == G.player_team and v.global_position.distance_to(st2.global_position) < 9000.0:
					v.global_position = v.global_position + (v.global_position - st2.global_position).normalized() * 12000.0
			step = 4
			_wait = 1.0
		4:
			var gh: Dictionary = fog.ghost_of(st2)
			_check(not gh.is_empty() and st2.visible, "out of sight, it stays on the map as last seen")
			var real_team: int = st2.team
			st2.team = 3                                         # taken by someone while no one was looking
			_check(int(gh.get("team", -1)) == real_team, "the last-seen copy keeps its old side")
			st2.team = real_team
			# crew aboard an enemy ship: hidden from the player unless one of ours aboard sees them
			ai_ship.global_position = my_ship.global_position + Vector3(400, 0, 0)
			var spot: Vector3 = ai_ship.random_local()
			foe = G.match_node.spawn_character(ai_ship, spot, 2, 2, "rifleman")
			foe.order = {"type": "hold", "pos": foe.position, "vessel": ai_ship}
			step = 5
			_wait = 0.8
		5:
			_check(fog.state_of(ai_ship) == "vis" and foe.fog_hidden, "enemy crew aboard their own ship are hidden")
			mine = G.match_node.spawn_character(ai_ship, ai_ship.snap_local(foe.position + Vector3(1.0, 0, 0)), G.player_team, G.team_fac(G.player_team), "rifleman")
			mine.order = {"type": "hold", "pos": mine.position, "vessel": ai_ship}
			foe.max_hp = 99999.0
			foe.hp = 99999.0
			mine.max_hp = 99999.0
			mine.hp = 99999.0
			step = 6
			_wait = 0.6
		6:
			_check(not foe.fog_hidden, "...and show once one of ours aboard can see them")
			marks0 = int(G.stats.get("fog_last_seen_marks", 0))
			mine.vessel.leave(mine)
			G.characters.erase(mine)
			mine.queue_free()
			step = 7
			_wait = 0.6
		7:
			_check(foe.fog_hidden, "out of sight again, they're hidden")
			_check(int(G.stats.get("fog_last_seen_marks", 0)) > marks0, "a '?' marks where they were last seen")
			_done()


func _done() -> void:
	print("FOG TEST DONE %d" % fails)
	set_physics_process(false)
	G.quit()
