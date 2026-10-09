extends Node
## Two-process multiplayer check (see tests/run_net_test.sh). The client spawns as a
## soldier on side 2, walks and shoots; both sides report what they see.
var t := 0.0
var step := 0
var me: Node = null
var start_pos := Vector3.ZERO


func _physics_process(dt: float) -> void:
	t += dt
	var client := G.is_client()
	if client and step == 0 and t > 4.0:
		step = 1
		print("NET client: characters received %d, vessels %d" % [G.characters.size(), G.vessels.size()])
		G.commander.deploy("rifleman", G.match_node.homes[2])
	if client and step == 1 and G.possessed:
		step = 2
		me = G.possessed
		start_pos = me.global_position
		Input.action_press("move_forward")
		print("NET client: spawned as %s (net id %d)" % [me.display, me.get_meta("net_id", 0)])
	if client and step == 2 and t > 9.0:
		step = 3
		Input.action_release("move_forward")
		var before: int = me.mag
		for i in 4:
			me.fire_t = 0.0
			G.network.send_fire(me, me.eye(), -me.global_basis.z)
			me.fire(me.eye(), -me.global_basis.z)
		print("NET client: walked %.1f m, fired %d" % [me.global_position.distance_to(start_pos), before - me.mag])
	if t > 16.0 and step < 9:
		step = 9
		if client:
			var moving := 0
			for c in G.characters:
				if c != me and is_instance_valid(c) and c.net_pos != Vector3.INF:
					moving += 1
			var hull: float = G.vessels[2].hull
			print("NET client: puppets with host positions %d of %d, rival flagship hull %.0f, my hp %.0f" % [moving, G.characters.size(), hull, me.hp if me else -1.0])
			print("NET RESULT client: %s" % ("PASS" if moving >= G.characters.size() * 0.9 - 2 and me != null else "FAIL"))
		else:
			var remote: Node = null
			for c in G.characters:
				if is_instance_valid(c) and c.owner_peer != 0:
					remote = c
			print("NET host: characters %d, remote player's soldier %s at %s, mag %s" % [G.characters.size(),
				remote.display if remote else "MISSING", remote.global_position if remote else "-", remote.mag if remote else "-"])
			print("NET RESULT host: %s" % ("PASS" if remote != null else "FAIL"))
		await get_tree().create_timer(1.0).timeout
		G.quit()
