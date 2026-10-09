extends Node
## Crew check:  godot --headless --path . --fixed-fps 30 -- --crewtest
## No battle: watches the crews work for two minutes (one spore pod arrives) and
## reports what everyone was doing.
var t := 0.0
var done := false
var seen := {}          # activity -> count of samples
var elev := 0


func _ready() -> void:
	Engine.time_scale = 4.0
	G.match_node.ai.t = -100000.0                    # the rival waits
	G.match_node.ai.spore_t = 20.0


func _physics_process(dt: float) -> void:
	t += dt
	for v in G.vessels:
		for e in v.elevators:
			if e["target"] != e["deck"]:
				elev += 1
	if int(t * 2.0) != int((t - dt) * 2.0):
		for c in G.characters:
			if is_instance_valid(c) and c.state == "alive" and c.team != 4:
				var a: String = G.commander.hud._activity(c)
				seen[c.role + ":" + a] = seen.get(c.role + ":" + a, 0) + 1
	if t > 120.0 and not done:
		done = true
		var keys := seen.keys()
		keys.sort()
		for k in keys:
			print("CREWTEST %-36s %d" % [k, seen[k]])
		print("CREWTEST elevator frames moving: %d" % elev)
		for k in G.stats:
			print("CREWTEST stat %s %d" % [k, G.stats[k]])
		for v in G.vessels:
			print("CREWTEST %-20s supplies %.0f  infected %.2f" % [v.display_name, v.supplies, v.infected_fraction()])
		G.quit()
