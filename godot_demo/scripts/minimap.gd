extends Control
## Overview map: of the system in space, of the landing zone on a world. Ships, stations,
## fighters, pods and missiles; on a world also outposts, vehicles and troops. With fog of war,
## what no eye of yours covers is shaded, radar contacts are grey "?" blips, and stations and
## installations you've seen show as they were last seen (dimmed outline, last-known colours).
## Click it to move the camera there.

const HALF_SPACE := 3300.0
const HALF_GROUND := 4700.0
const UNKNOWN := Color(0.72, 0.77, 0.82, 0.8)


func _half() -> float:
	return HALF_GROUND if G.match_node and G.match_node.get("on_surface") == true else HALF_SPACE


func _to_map(p: Vector3) -> Vector2:
	var h := _half()
	return Vector2((p.x / h * 0.5 + 0.5) * size.x, (p.z / h * 0.5 + 0.5) * size.y)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var m: Vector2 = event.position / size
		var h := _half()
		G.commander.pivot = Vector3((m.x - 0.5) * 2.0 * h, 0, (m.y - 0.5) * 2.0 * h)
		accept_event()


func _blip(p: Vector2) -> void:
	draw_arc(p, 4.0, 0, TAU, 12, UNKNOWN, 1.2)
	draw_string(get_theme_default_font(), p + Vector2(5, 4), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, UNKNOWN)


func _team_col(team: int) -> Color:
	return G.team_color(team) if team != 4 else Color(0.8, 0.45, 1.0)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.02, 0.04, 0.6))
	var m: Node = G.match_node
	var fog: Node = m.get("fog") if m else null
	var fogged: bool = fog != null and fog.enabled()
	var px_per_m: float = size.x / (_half() * 2.0)
	var ground: bool = m != null and m.get("on_surface") == true
	if ground and m.has_meta("ground_map"):
		# the terrain from above (baked when we landed: surface.gd _minimap_image)
		var gh: float = m.get_meta("ground_map_half", HALF_GROUND)
		var a := _to_map(Vector3(-gh, 0, -gh))
		var b := _to_map(Vector3(gh, 0, gh))
		draw_texture_rect(m.get_meta("ground_map"), Rect2(a, b - a), false, Color(1.15, 1.15, 1.15, 1.0))
		if m.get("city") != null and not (m.city as Dictionary).is_empty():
			draw_arc(_to_map(m.city["center"]), float(m.city["radius"]) * px_per_m, 0, TAU, 28, Color(0.85, 0.85, 0.8, 0.55), 1.2)
	if fogged:
		# shade everything, then lift what our eyes cover; radar reach as a faint ring
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.38 if ground else 0.35))
		for e in fog.eyes:
			var ep := _to_map(e[0])
			var er: float = float(e[1]) * px_per_m
			draw_circle(ep, er, Color(1.0, 1.0, 0.95, 0.16) if ground else Color(0.3, 0.45, 0.6, 0.09))
			if ground:
				draw_arc(ep, er, 0, TAU, 24, Color(0.9, 0.95, 1.0, 0.35), 1.0)
		for e in fog.eyes:
			if float(e[2]) > 900.0 or (ground and float(e[2]) > 0.0):     # (on a world: vehicle and outpost radar too)
				draw_arc(_to_map(e[0]), float(e[2]) * px_per_m, 0, TAU, 32, Color(0.6, 0.7, 0.8, 0.1), 1.0)
	for i in range(1, 4):                                   # faint grid
		var x := size.x * i / 4.0
		var y := size.y * i / 4.0
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(1, 1, 1, 0.04))
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(1, 1, 1, 0.04))
	if m and m.get("system") != null and m.get("on_surface") != true:
		for fl in m.system.get("fields", []):           # asteroid fields
			var fc := _to_map(fl["center"])
			var fr: float = fl["radius"] * px_per_m
			draw_circle(fc, fr, Color(0.55, 0.5, 0.45, 0.12))
			draw_arc(fc, fr, 0, TAU, 24, Color(0.6, 0.55, 0.5, 0.35), 1.0)
			draw_string(get_theme_default_font(), fc + Vector2(-12, 3), String(fl.get("ore", "")).to_upper(),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 0.9, 0.7, 0.4))
	if m and m.get("system") != null and m.system.has("name"):
		draw_string(get_theme_default_font(), Vector2(4, size.y - 4), String(m.system["name"]).to_upper(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.35))
	# vessels
	for v in G.vessels:
		if not is_instance_valid(v) or v.get("kind") == "ground":
			continue
		var gh: Dictionary = {}
		if fogged and v.team != G.player_team:
			var fs: String = fog.state_of(v)
			if fs == "radar" and not fog.known.has(v):
				_blip(_to_map(v.global_position))
				continue
			if fs != "vis" and not fog.known.has(v):
				continue
			gh = fog.ghost_of(v)
		var tm: int = int(gh.get("team", v.team))
		var c := _team_col(tm)
		if gh.get("destroyed", v.destroyed):
			c = Color(0.35, 0.35, 0.35)
		var p := _to_map(v.to_global(v.aabb.get_center()))
		if v.kind == "station":
			if gh.is_empty():
				draw_rect(Rect2(p - Vector2(5, 5), Vector2(10, 10)), c)
			else:
				draw_rect(Rect2(p - Vector2(5, 5), Vector2(10, 10)), Color(c, 0.6), false, 1.5)   # as last seen
		else:
			var f: Vector3 = -v.global_basis.z
			var d := Vector2(f.x, f.z).normalized() * 6.0
			draw_colored_polygon(PackedVector2Array([p + d, p - d + d.orthogonal() * 0.6, p - d - d.orthogonal() * 0.6]), c)
		if v.alarm > 0.0 and v.team == G.player_team:
			draw_arc(p, 10.0, 0, TAU, 20, Color(1, 0.3, 0.25), 1.5)
		if gh.is_empty() and v.infected_fraction() > 0.0 and not v.destroyed:
			draw_arc(p, 13.0, 0, TAU, 20, Color(0.8, 0.4, 1.0, 0.8), 1.5)
	# down on a world: installations, vehicles and troops
	if m and m.get("on_surface") == true:
		if m.get("outposts") != null:
			for o in m.outposts:
				if not is_instance_valid(o):
					continue
				var op := _to_map(o.global_position)
				var gh2: Dictionary = {}
				if fogged and o.team != G.player_team:
					var fs2: String = fog.state_of(o)
					if fs2 == "radar" and not fog.known.has(o):
						_blip(op)
						continue
					if fs2 != "vis" and not fog.known.has(o):
						continue
					gh2 = fog.ghost_of(o)
				var oc := _team_col(int(gh2.get("team", o.team)))
				if gh2.get("destroyed", o.destroyed):
					oc = Color(0.35, 0.35, 0.35)
				var big: float = 4.0 if o.get("part") in ["core", "hq", "gravemind"] else 2.0
				if gh2.is_empty():
					draw_rect(Rect2(op - Vector2(big, big), Vector2(big, big) * 2.0), oc)
				else:
					draw_rect(Rect2(op - Vector2(big, big), Vector2(big, big) * 2.0), Color(oc, 0.6), false, 1.2)
		for veh in G.vehicles:
			if not is_instance_valid(veh) or veh.get("destroyed") == true:
				continue
			var vp := _to_map(veh.global_position)
			if fogged and veh.team != G.player_team and not veh.visible:
				if fog.state_of(veh) == "radar":
					draw_circle(vp, 1.6, UNKNOWN)
				continue
			var vc := _team_col(veh.team)
			draw_colored_polygon(PackedVector2Array([vp + Vector2(0, -3), vp + Vector2(3, 0), vp + Vector2(0, 3), vp + Vector2(-3, 0)]), vc)
		for ch in G.characters:
			if not is_instance_valid(ch) or ch.state != "alive" or ch.vessel == null or ch.vessel.get("kind") != "ground":
				continue
			var cp := _to_map(ch.global_position)
			if ch.fog_hidden:
				if fogged and fog.state_of(ch) == "radar":
					draw_rect(Rect2(cp - Vector2(0.75, 0.75), Vector2(1.5, 1.5)), Color(UNKNOWN, 0.5))
				continue
			draw_rect(Rect2(cp - Vector2(0.9, 0.9), Vector2(1.8, 1.8)), _team_col(ch.team))
	for f in G.fighters:
		if is_instance_valid(f) and f.visible:
			draw_circle(_to_map(f.global_position), 1.6, G.team_color(f.team))
	for p in G.pods:
		if is_instance_valid(p) and p.visible:
			draw_circle(_to_map(p.global_position), 1.6, Color(1, 1, 1))
	for mi in G.missiles:
		if is_instance_valid(mi) and mi.visible:
			draw_circle(_to_map(mi.global_position), 1.2, Color(1, 0.8, 0.3))
	if G.commander:
		var cp2 := _to_map(G.commander.pivot)
		var r := clampf(G.commander.zoom / _half() * size.x * 0.25, 4.0, 60.0)
		draw_rect(Rect2(cp2 - Vector2(r, r * 0.7), Vector2(r, r * 0.7) * 2.0), Color(1, 1, 0.5, 0.6), false, 1.0)
