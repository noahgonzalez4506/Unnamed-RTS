extends Control
## Overview map of the system: ships, stations, fighters, pods and where you're looking.
## Click it to move the camera there.

const HALF := 3300.0


func _to_map(p: Vector3) -> Vector2:
	return Vector2((p.x / HALF * 0.5 + 0.5) * size.x, (p.z / HALF * 0.5 + 0.5) * size.y)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var m: Vector2 = event.position / size
		G.commander.pivot = Vector3((m.x - 0.5) * 2.0 * HALF, 0, (m.y - 0.5) * 2.0 * HALF)
		accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.02, 0.04, 0.6))
	for i in range(1, 4):                                   # faint grid
		var x := size.x * i / 4.0
		var y := size.y * i / 4.0
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(1, 1, 1, 0.04))
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(1, 1, 1, 0.04))
	if G.match_node and G.match_node.get("system") != null:
		for fl in G.match_node.system.get("fields", []):           # asteroid fields
			var fc := _to_map(fl["center"])
			var fr: float = fl["radius"] / HALF * 0.5 * size.x
			draw_circle(fc, fr, Color(0.55, 0.5, 0.45, 0.12))
			draw_arc(fc, fr, 0, TAU, 24, Color(0.6, 0.55, 0.5, 0.35), 1.0)
			draw_string(get_theme_default_font(), fc + Vector2(-12, 3), String(fl.get("ore", "")).to_upper(),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 0.9, 0.7, 0.4))
		if G.match_node.system.has("name"):
			draw_string(get_theme_default_font(), Vector2(4, size.y - 4), String(G.match_node.system["name"]).to_upper(),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.35))
	var fog: Node = G.match_node.get("fog") if G.match_node else null
	for v in G.vessels:
		if not is_instance_valid(v):
			continue
		if fog and fog.enabled() and v.team != G.player_team:
			var fs: String = fog.state_of(v)
			if fs == "radar" and not fog.known.has(v):
				var rp := _to_map(v.global_position)
				draw_arc(rp, 4.0, 0, TAU, 12, Color(0.7, 0.75, 0.8, 0.7), 1.2)
				draw_string(get_theme_default_font(), rp + Vector2(5, 4), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.75, 0.8, 0.85, 0.8))
				continue
			if fs != "vis" and not fog.known.has(v):
				continue
		var c := G.team_color(v.team) if v.team != 4 else Color(0.8, 0.45, 1.0)
		if v.destroyed:
			c = Color(0.35, 0.35, 0.35)
		var p := _to_map(v.to_global(v.aabb.get_center()))
		if v.kind == "station":
			draw_rect(Rect2(p - Vector2(5, 5), Vector2(10, 10)), c)
		else:
			var f: Vector3 = -v.global_basis.z
			var d := Vector2(f.x, f.z).normalized() * 6.0
			draw_colored_polygon(PackedVector2Array([p + d, p - d + d.orthogonal() * 0.6, p - d - d.orthogonal() * 0.6]), c)
		if v.alarm > 0.0 and v.team == G.player_team:
			draw_arc(p, 10.0, 0, TAU, 20, Color(1, 0.3, 0.25), 1.5)
		if v.infected_fraction() > 0.0 and not v.destroyed:
			draw_arc(p, 13.0, 0, TAU, 20, Color(0.8, 0.4, 1.0, 0.8), 1.5)
	for f in G.fighters:
		if is_instance_valid(f) and f.visible:
			draw_circle(_to_map(f.global_position), 1.6, G.team_color(f.team))
	for p in G.pods:
		if is_instance_valid(p) and p.visible:
			draw_circle(_to_map(p.global_position), 1.6, Color(1, 1, 1))
	for m in G.missiles:
		if is_instance_valid(m) and m.visible:
			draw_circle(_to_map(m.global_position), 1.2, Color(1, 0.8, 0.3))
	if G.commander:
		var cp := _to_map(G.commander.pivot)
		var r := clampf(G.commander.zoom / HALF * size.x * 0.25, 4.0, 60.0)
		draw_rect(Rect2(cp - Vector2(r, r * 0.7), Vector2(r, r * 0.7) * 2.0), Color(1, 1, 0.5, 0.6), false, 1.0)
