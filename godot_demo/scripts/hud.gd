extends Control
## The heads-up display, kept to a few tidy blocks:
##   commander: thin top bar (clock, resources, objective), minimap + fleet list on the
##              right, selection card bottom-left, event log bottom-right, F1 help overlay
##   direct control: crosshair, vitals bottom-left, weapon and kit bottom-right,
##              action progress under the crosshair
## The commander script owns the camera and orders; this script only draws.

const BG := Color(0.035, 0.05, 0.075, 0.84)
const EDGE := Color(0.33, 0.52, 0.72, 0.45)
const TEXT := Color(0.88, 0.92, 0.96)
const DIM := Color(0.56, 0.63, 0.71)
const WARN := Color(1.0, 0.36, 0.3)
const PURPLE := Color(0.78, 0.42, 1.0)
const LOG_LINES := 6
const LOG_LIFE := 24.0

var cmd: Node                     # the commander
var rts: Control
var fps: Control
var top_clock: Label
var top_res: Dictionary = {}
var top_obj: Label
var fleet_box: VBoxContainer
var fleet_rows := {}              # vessel -> {row, name, info, hull, shield, tag}
var sel_panel: PanelContainer
var sel_title: Label
var sel_sub: Label
var sel_body: VBoxContainer
var sel_keys: Label
var hint: Label
var cut_chip: PanelContainer
var cut_label: Label
var log_box: VBoxContainer
var log_items: Array = []         # [label, born]
var help_panel: PanelContainer
var banner_box: VBoxContainer
var banner_title: Label
var banner_sub: Label
var minimap: Control
var cross: Control
var vit_name: Label
var vit_hp: Control
var vit_hp_text: Label
var vit_armor: Label
var wpn_name: Label
var wpn_ammo: Label
var wpn_mags: Label
var wpn_kit: Label
var act_box: VBoxContainer
var act_label: Label
var act_bar: Control
var prompt: Label
var hit_t := 0.0
var deploy_panel: PanelContainer
var deploy_role := "rifleman"
var deploy_spot: Node = null
var deploy_body: VBoxContainer
var research_panel: PanelContainer
var research_body: VBoxContainer
var exo_bar: Control
var fps_label: Label
var pop_label: Label
var alert_panel: PanelContainer   # boarding op countdown / red alert strip (both views)
var alert_label: Label
var vignette: Control             # red edges while aboard a ship at red alert
var roster_panel: PanelContainer  # the squad you lead (first person)
var roster_body: VBoxContainer
var _roster_t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fit()
	get_viewport().size_changed.connect(_fit)
	rts = _layer()
	fps = _layer()
	fps.visible = false
	_fit()
	_build_top()
	_build_right()
	_build_selection()
	_build_log()
	_build_help()
	_build_fps()
	_build_banner()
	_build_deploy()
	_build_research()
	_build_alerts()


# ------------------------------------------------------------------ building blocks

func _layer() -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	return c


func _style(bg: Color = BG, edge: Color = EDGE, pad: int = 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = edge
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = pad + 2
	sb.content_margin_right = pad + 2
	sb.content_margin_top = pad
	sb.content_margin_bottom = pad
	return sb


func _panel(parent: Control, bg: Color = BG, pad: int = 8) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _style(bg, EDGE, pad))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	return p


func _lbl(parent: Control, text: String, size: int = 13, col: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _bar(parent: Control, w: float, h: float) -> Control:
	var bg := ColorRect.new()
	bg.color = Color(1, 1, 1, 0.08)
	bg.custom_minimum_size = Vector2(w, h)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := ColorRect.new()
	fill.name = "Fill"
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.size = Vector2(w, h)
	bg.add_child(fill)
	parent.add_child(bg)
	return bg


func set_bar(bar: Control, frac: float, col: Color) -> void:
	var fill: ColorRect = bar.get_node("Fill")
	fill.size = Vector2(bar.custom_minimum_size.x * clampf(frac, 0.0, 1.0), bar.custom_minimum_size.y)
	fill.color = col


func _row(parent: Control, sep: int = 6) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", sep)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r


func _col(parent: Control, sep: int = 4) -> VBoxContainer:
	var c := VBoxContainer.new()
	c.add_theme_constant_override("separation", sep)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)
	return c


## Pin a control to a corner/edge with a margin; it grows away from that edge as its content grows.
func _place(c: Control, preset: int, offset: Vector2) -> void:
	var ax := 0.0
	var ay := 0.0
	var gx := Control.GROW_DIRECTION_END
	var gy := Control.GROW_DIRECTION_END
	match preset:
		Control.PRESET_TOP_RIGHT:
			ax = 1.0
			gx = Control.GROW_DIRECTION_BEGIN
		Control.PRESET_BOTTOM_LEFT:
			ay = 1.0
			gy = Control.GROW_DIRECTION_BEGIN
		Control.PRESET_BOTTOM_RIGHT:
			ax = 1.0
			ay = 1.0
			gx = Control.GROW_DIRECTION_BEGIN
			gy = Control.GROW_DIRECTION_BEGIN
		Control.PRESET_CENTER:
			ax = 0.5
			ay = 0.5
			gx = Control.GROW_DIRECTION_BOTH
			gy = Control.GROW_DIRECTION_BOTH
		Control.PRESET_CENTER_TOP:
			ax = 0.5
			gx = Control.GROW_DIRECTION_BOTH
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.grow_horizontal = gx
	c.grow_vertical = gy
	c.offset_left = offset.x
	c.offset_right = offset.x
	c.offset_top = offset.y
	c.offset_bottom = offset.y


# ------------------------------------------------------------------ commander view

func _build_top() -> void:
	var bar := PanelContainer.new()
	var sb := _style(Color(0.03, 0.045, 0.07, 0.88), Color(0, 0, 0, 0), 5)
	sb.border_color = EDGE
	sb.border_width_bottom = 1
	sb.border_width_top = 0
	sb.border_width_left = 0
	sb.border_width_right = 0
	sb.set_corner_radius_all(0)
	bar.add_theme_stylebox_override("panel", sb)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.custom_minimum_size.y = 32
	rts.add_child(bar)
	var row := _row(bar, 18)
	top_clock = _lbl(row, "00:00", 16)
	for k in ["alloys", "circuitry", "cores"]:
		var chip := _row(row, 5)
		_lbl(chip, k.to_upper(), 11, DIM).size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top_res[k] = _lbl(chip, "0", 15)
	pop_label = _lbl(row, "", 13, TEXT)
	top_obj = _lbl(row, "", 13, DIM)
	top_obj.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_obj.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fps_label = _lbl(row, "", 12, DIM)
	_lbl(row, "J deploy   Y research   F1 help", 12, DIM)
	cut_chip = _panel(rts, Color(0.1, 0.2, 0.3, 0.85), 4)
	_place(cut_chip, Control.PRESET_TOP_LEFT, Vector2(12, 42))
	cut_label = _lbl(cut_chip, "", 12)
	cut_chip.visible = false


func _build_right() -> void:
	var col := _col(rts, 8)
	col.custom_minimum_size.x = 270
	_place(col, Control.PRESET_TOP_RIGHT, Vector2(-12, 42))
	var mp := _panel(col, BG, 4)
	minimap = preload("res://scripts/minimap.gd").new()
	minimap.custom_minimum_size = Vector2(260, 190)
	minimap.mouse_filter = Control.MOUSE_FILTER_STOP
	mp.add_child(minimap)
	var fp := _panel(col)
	fleet_box = _col(fp, 3)


func _fleet_row(v: Node) -> Dictionary:
	var row := _col(fleet_box, 2)
	var line := _row(row, 6)
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(8, 8)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(dot)
	var nm := _lbl(line, v.display_name, 13)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.clip_text = true
	var tag := _lbl(line, "", 11, WARN)
	var info := _lbl(line, "", 11, DIM)
	var bars := _row(row, 4)
	var hull := _bar(bars, 124, 4)
	var shield := _bar(bars, 124, 4)
	return {"row": row, "dot": dot, "name": nm, "tag": tag, "info": info, "hull": hull, "shield": shield, "bars": bars}


func _build_selection() -> void:
	sel_panel = _panel(rts, BG, 10)
	sel_panel.custom_minimum_size = Vector2(440, 0)
	_place(sel_panel, Control.PRESET_BOTTOM_LEFT, Vector2(12, -12))
	var c := _col(sel_panel, 5)
	sel_title = _lbl(c, "", 16)
	sel_sub = _lbl(c, "", 12, DIM)
	sel_body = _col(c, 4)
	sel_keys = _lbl(c, "", 12, Color(0.75, 0.85, 0.95))
	sel_keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sel_keys.custom_minimum_size.x = 420
	hint = _lbl(rts, "Left-click or drag to select  ·  Right-click to order  ·  X to look inside ships", 12, DIM)
	_place(hint, Control.PRESET_BOTTOM_LEFT, Vector2(14, -14))


func _stat_line(label: String, frac: float, col: Color, text: String) -> void:
	var r := _row(sel_body, 8)
	var l := _lbl(r, label, 11, DIM)
	l.custom_minimum_size.x = 64
	var b := _bar(r, 220, 6)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	set_bar(b, frac, col)
	_lbl(r, text, 12)


func _text_line(text: String, col: Color = TEXT, size: int = 12) -> void:
	_lbl(sel_body, text, size, col)


func _build_log() -> void:
	log_box = _col(self, 2)
	log_box.custom_minimum_size.x = 520
	log_box.alignment = BoxContainer.ALIGNMENT_END
	_place(log_box, Control.PRESET_BOTTOM_RIGHT, Vector2(-14, -14))


func _build_help() -> void:
	help_panel = _panel(rts, Color(0.03, 0.045, 0.07, 0.94), 18)
	_place(help_panel, Control.PRESET_CENTER, Vector2.ZERO)
	var c := _col(help_panel, 10)
	_lbl(c, "CONTROLS", 18)
	var cols := _row(c, 36)
	var left := _col(cols, 3)
	var right := _col(cols, 3)
	var sections := [
		[left, "Commander", [["WASD · wheel · middle-drag", "pan · zoom · rotate"], ["Q / E", "turn the camera"],
			["Left click / drag", "select (double-click: same role)"], ["Right click", "move · attack · capture"],
			["X  ·  Up / Down", "look inside · change deck"], ["1 - 4", "jump to your ships and station"],
			["B", "boarding pods (ships)"], ["L", "scramble fighters"], ["T", "train a squad (station)"],
			["H · K", "hold · sabotage (soldiers)"], ["Tab", "take direct control"]]],
		[right, "Direct control", [["WASD · mouse", "move · aim"], ["Shift · C · Space", "run · crouch · jump"],
			["Left mouse", "fire"], ["R", "reload from your chest rig"], ["G", "grenade"], ["Q", "medpen"],
			["E", "use: revive, elevator, locker, sabotage, breach, purge"], ["Tab", "back to command"],
			["B", "grenadier: launcher, breaching round, rifle"], ["Goal", "capture or destroy the Ascendancy Spire's command core"]]],
	]
	for s in sections:
		_lbl(s[0], s[1].to_upper(), 12, Color(0.5, 0.8, 1.0))
		for kv in s[2]:
			var r := _row(s[0], 10)
			var k := _lbl(r, kv[0], 12, TEXT)
			k.custom_minimum_size.x = 170
			var d := _lbl(r, kv[1], 12, DIM)
			d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			d.custom_minimum_size.x = 230
	_lbl(c, "Press F1 to close", 11, DIM).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _build_banner() -> void:
	banner_box = _col(self, 2)
	_place(banner_box, Control.PRESET_CENTER_TOP, Vector2(0, 120))
	banner_title = _lbl(banner_box, "", 46)
	banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_title.add_theme_color_override("font_outline_color", Color.BLACK)
	banner_title.add_theme_constant_override("outline_size", 10)
	banner_sub = _lbl(banner_box, "", 18, TEXT)
	banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_box.visible = false


func banner(title: String, sub: String) -> void:
	banner_title.text = title
	banner_sub.text = sub
	banner_title.add_theme_color_override("font_color", Color(0.5, 0.9, 1.0) if title == "VICTORY" else WARN)
	banner_box.visible = true


func show_help(on: bool) -> void:
	help_panel.visible = on


func log_event(text: String, col: Color) -> void:
	var l := _lbl(log_box, text, 13, col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 5)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 520
	log_items.append([l, G.time])
	while log_items.size() > LOG_LINES:
		(log_items.pop_front()[0] as Node).queue_free()


## Under a CanvasLayer the root has no parent Control to fill: size it to the window ourselves.
func _fit() -> void:
	position = Vector2.ZERO
	size = get_viewport().get_visible_rect().size
	for c in [rts, fps]:
		if c:
			c.position = Vector2.ZERO
			c.size = size


func _process(dt: float) -> void:
	if size != get_viewport().get_visible_rect().size:
		_fit()
	for e in log_items.duplicate():
		var age: float = G.time - e[1]
		if age > LOG_LIFE:
			(e[0] as Node).queue_free()
			log_items.erase(e)
		else:
			(e[0] as Label).modulate.a = clampf((LOG_LIFE - age) / 6.0, 0.0, 1.0)
	hit_t = max(0.0, hit_t - dt)
	if cross:
		cross.queue_redraw()


## Called by the commander a few times a second.
func refresh() -> void:
	var r: Dictionary = G.resources.get(G.player_team, {})
	top_clock.text = "%02d:%02d" % [int(G.time) / 60, int(G.time) % 60]
	for k in top_res:
		top_res[k].text = _num(r.get(k, 0.0))
	var enemy_home := "Ascendancy Spire" if G.player_team == 1 else "Vanguard Bastion"
	var rs: Array = G.researching.get(G.player_team, [])
	var goal := "capture or destroy the %s's command core" % enemy_home
	if G.campaign != null and G.match_node and G.match_node.get("campaign_mode"):
		goal = "%s  ·  %s" % [G.campaign.system()["name"], ("next job: " + G.campaign.jobs[0]["title"]) if not G.campaign.jobs.is_empty() else "explore, trade, take jobs at stations (P)"]
	top_obj.text = "Objective  ·  %s%s" % [goal,
		("     Researching %s  %ds" % [G.TECH[rs[0]]["name"], int(rs[1])]) if not rs.is_empty() else ""]
	pop_label.text = "SOLDIERS %d" % G.soldiers_of(G.player_team)
	fps_label.text = "%d FPS" % Engine.get_frames_per_second() if G.settings.get("show_fps", true) else ""
	_refresh_fleet()
	_refresh_selection()
	refresh_alerts()
	cut_chip.visible = cmd.interior
	cut_label.text = "INTERIOR VIEW  ·  DECK %d   (PgUp / PgDn,  X to exit)" % cmd.deck
	minimap.queue_redraw()


func _num(v: float) -> String:
	var s := str(int(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


func _refresh_fleet() -> void:
	var order := G.vessels.duplicate()
	order.sort_custom(func(a, b): return [1, 2, 3, 4].find(a.team) < [1, 2, 3, 4].find(b.team))
	for v in order:
		if not is_instance_valid(v):
			continue
		if not fleet_rows.has(v):
			fleet_rows[v] = _fleet_row(v)
		var fr: Dictionary = fleet_rows[v]
		fleet_box.move_child(fr["row"], fleet_box.get_child_count() - 1)
		# your own vessels get health bars; everyone else is one compact line
		(fr["bars"] as Control).visible = v.team == G.player_team and not v.destroyed
		(fr["name"] as Label).add_theme_font_size_override("font_size", 13 if v.team == G.player_team else 11)
		var tc: Color = G.team_color(v.team) if v.team != 4 else PURPLE
		(fr["dot"] as ColorRect).color = tc if not v.destroyed else Color(0.35, 0.35, 0.35)
		(fr["name"] as Label).modulate = Color(1, 1, 1, 0.45) if v.destroyed else Color.WHITE
		var tag := ""
		if v.destroyed:
			tag = "LOST"
		elif v.get("is_supply_ship") and v.team == G.player_team:
			tag = "SUPPLY" if v.get_meta("supply_state", "fleet") == "fleet" else "RESTOCKING"
		elif v.alarm > 0.0 and v.team == G.player_team:
			tag = "BOARDED"
		var inf: float = v.infected_fraction()
		if inf > 0.0 and not v.destroyed:
			tag += ("  " if tag != "" else "") + "INFECTED %d%%" % int(inf * 100.0)
		(fr["tag"] as Label).text = tag
		(fr["tag"] as Label).add_theme_color_override("font_color", PURPLE if tag.begins_with("INFECTED") else
			(Color(0.6, 0.85, 0.5) if tag in ["SUPPLY", "RESTOCKING"] else WARN))
		if v.kind == "ship":
			(fr["info"] as Label).text = "" if v.team != G.player_team or v.destroyed else "%d/%d  ·  %d%%" % [v.troops, v.berth_cap,
				int(100.0 * v.supplies / max(1.0, v.supply_cap))]
			(fr["info"] as Label).tooltip_text = "boarders in berths / berths  ·  supplies"
			set_bar(fr["hull"], v.hull / v.max_hull, Color(0.85, 0.75, 0.45))
			set_bar(fr["shield"], v.shields / max(1.0, v.max_shields), Color(0.35, 0.7, 1.0))
		else:
			(fr["info"] as Label).text = ("%d/%d" % [v.modules_online(), v.modules.size()]) + \
				("  ·  %d in reserve" % v.reserve if v.team == G.player_team else "")
			set_bar(fr["hull"], float(v.modules_online()) / max(1, v.modules.size()), Color(0.85, 0.75, 0.45))
			set_bar(fr["shield"], v.shields / max(1.0, v.max_shields), Color(0.35, 0.7, 1.0))


func _refresh_selection() -> void:
	for c in sel_body.get_children():
		c.queue_free()
	var sel: Array = cmd.selection.filter(func(u): return is_instance_valid(u))
	sel_panel.visible = not sel.is_empty()
	hint.visible = sel.is_empty()
	if sel.is_empty():
		return
	var u: Node = sel[0]
	if u.get("kind") == "ship":
		sel_title.text = u.display_name
		sel_sub.text = "%s  ·  %s" % [u.cls.replace("_", " ").capitalize(), G.team_name(u.team)]
		_stat_line("HULL", u.hull / u.max_hull, Color(0.85, 0.75, 0.45), "%d" % u.hull)
		_stat_line("SHIELDS", u.shields / max(1.0, u.max_shields), Color(0.35, 0.7, 1.0), "%d" % u.shields)
		_stat_line("BERTHS", float(u.troops) / max(1, u.berth_cap), Color(0.6, 0.85, 0.5), "%d / %d boarders" % [u.troops, u.berth_cap])
		_stat_line("SUPPLIES", u.supplies / max(1.0, u.supply_cap), Color(0.9, 0.7, 0.35), "%d / %d" % [u.supplies, u.supply_cap])
		_text_line("Boarding shuttle: %s" % ("aboard" if u.has_shuttle and u.shuttle_out == null else ("flying" if u.shuttle_out != null else "LOST (replaced at the station or a supply ship)")),
			DIM if u.has_shuttle else WARN)
		if u.is_supply_ship:
			_text_line("Supply ship: tops up ships within 600 m, runs the Darter to ships out to 2.6 km, restocks at home when low", Color(0.6, 0.85, 0.5))
		var miss: Array = u.crew_missing()
		_text_line("Fighters on pads %d   ·   Crew aboard %d%s   ·   Missiles %d   ·   Repairs waiting %d" % [
			u.parked_count(), u.occupants.filter(func(c): return c.state == "alive" and c.team == u.team).size(),
			("  (%d posts empty)" % miss.size()) if not miss.is_empty() else "", u.missiles, u.repairs.size()], DIM)
		var run = G.match_node.logistics.runs.get(u) if G.match_node and G.match_node.logistics else null
		if run != null and is_instance_valid(run):
			_text_line("Supply shuttle on its way", Color(0.6, 0.85, 0.5))
		if u.attack_target and is_instance_valid(u.attack_target):
			_text_line("Engaging %s" % u.attack_target.display_name, WARN)
		sel_keys.text = "Right-click: move / attack    B: board    L: fighters    U: go home and resupply    X: look inside"
	elif u.get("kind") == "station":
		sel_title.text = u.display_name
		sel_sub.text = "%s  ·  %s" % [u.cls.replace("_", " ").capitalize(), G.team_name(u.team)]
		_stat_line("MODULES", float(u.modules_online()) / max(1, u.modules.size()), Color(0.85, 0.75, 0.45),
			"%d / %d online" % [u.modules_online(), u.modules.size()])
		_stat_line("SHIELDS", u.shields / max(1.0, u.max_shields), Color(0.35, 0.7, 1.0), "%d" % u.shields)
		var bad: Array = []
		for code in u.modules:
			if u.modules[code]["state"] != "online":
				bad.append("%s %s" % [code, u.modules[code]["state"]])
		if not bad.is_empty():
			_text_line(", ".join(bad.slice(0, 4)), WARN)
		_text_line("Squads training %d   ·   Robots in reserve %d / %d   ·   Supplies %d" % [u.training.size(), u.reserve,
			u.reserve_cap, u.supplies], DIM)
		var tc: Vector2 = u.train_cost() if u.has_method("train_cost") else Vector2(400, 8)
		sel_keys.text = "T: train a squad (%d alloys, %d cores)    X: look inside" % [int(tc.x), int(tc.y)]
	elif u.get("is_vehicle") == true:
		var vs: Array = sel.filter(func(x): return x.get("is_vehicle") == true)
		sel_title.text = u.display_name if vs.size() == 1 else "%d vehicles" % vs.size()
		sel_sub.text = G.team_name(u.team)
		for x in vs.slice(0, 6):
			_stat_line(x.SPECS[x.kind]["label"].to_upper(), x.hp / x.max_hp, Color(0.85, 0.75, 0.45),
				"%d%s" % [x.hp, ("  ·  %d aboard" % x.passengers) if x.kind == "ifv" else ""])
		sel_keys.text = "Right-click: move / attack    IFVs: LOAD / UNLOAD on the command card"
	elif u in G.fighters:
		sel_title.text = "Fighter"
		sel_sub.text = G.team_name(u.team)
		_stat_line("HULL", u.hp / 160.0, Color(0.85, 0.75, 0.45), "%d" % u.hp)
		sel_keys.text = "Right-click an enemy: attack it"
	else:
		var chars: Array = sel.filter(func(c): return c.get("rig") != null)
		if chars.size() == 1:
			var c: Node = chars[0]
			sel_title.text = c.display
			sel_sub.text = "Aboard %s  ·  %s" % [c.vessel.display_name, _activity(c)]
			_stat_line("HEALTH", c.hp / c.max_hp, _hp_col(c), "%d" % c.hp)
			if c.armed:
				_text_line("%s   %d rounds  ·  %d mags   ·   armor %d%%" % [c.weapon_model.substr(3).capitalize(), c.mag,
					c.spare.size(), int(c.dr * 100.0)], DIM)
			_text_line("Medpens %d   ·   Grenades %d   ·   Charges %d" % [c.medpens.size(), c.grenades.size(), c.charges.size()], DIM)
		else:
			sel_title.text = "%d selected" % chars.size()
			sel_sub.text = "Aboard %s" % chars[0].vessel.display_name
			for c in chars.slice(0, 6):
				var r := _row(sel_body, 8)
				var n := _lbl(r, c.display, 12)
				n.custom_minimum_size.x = 190
				n.clip_text = true
				var b := _bar(r, 120, 5)
				b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				set_bar(b, c.hp / c.max_hp, _hp_col(c))
				_lbl(r, _activity(c), 11, DIM)
			if chars.size() > 6:
				_text_line("+ %d more" % (chars.size() - 6), DIM)
		sel_keys.text = "Right-click their deck: move    H: hold    K: sabotage    Tab: take control"


func _hp_col(c: Node) -> Color:
	if c.state == "downed":
		return WARN
	return Color(0.4, 0.9, 0.5) if c.hp > 50 else Color(1.0, 0.75, 0.3)


func _activity(c: Node) -> String:
	if c.state == "downed":
		return "DOWNED"
	if c.state == "dead":
		return "dead"
	if c.target and is_instance_valid(c.target) and c.los:
		return "in combat"
	if c.revive_t >= 0.0:
		return "reviving"
	if c.gear_t >= 0.0:
		return "gearing up"
	if c.repairing:
		return "repairing"
	if c.carrying:
		return "hauling cargo"
	if c.purging:
		return "purging"
	if c.working:
		return "working"
	if c.path_i < c.path.size():
		return "moving"
	return "standing by"


# ------------------------------------------------------------------ direct control

func _build_fps() -> void:
	cross = Crosshair.new()
	cross.hud = self
	cross.set_anchors_preset(Control.PRESET_FULL_RECT)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fps.add_child(cross)
	var tag := _panel(fps, Color(0.1, 0.2, 0.3, 0.85), 4)
	_place(tag, Control.PRESET_TOP_LEFT, Vector2(12, 12))
	_lbl(tag, "DIRECT CONTROL  ·  Tab returns to command", 12)
	var vit := _panel(fps, BG, 10)
	_place(vit, Control.PRESET_BOTTOM_LEFT, Vector2(16, -16))
	var vc := _col(vit, 4)
	vit_name = _lbl(vc, "", 12, DIM)
	var hr := _row(vc, 8)
	vit_hp = _bar(hr, 230, 9)
	vit_hp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vit_hp_text = _lbl(hr, "", 18)
	vit_armor = _lbl(vc, "", 11, DIM)
	var er := _row(vc, 8)
	exo_bar = _bar(er, 230, 4)
	exo_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_lbl(er, "EXO", 10, DIM)
	var wp := _panel(fps, BG, 10)
	_place(wp, Control.PRESET_BOTTOM_RIGHT, Vector2(-16, -16))
	var wc := _col(wp, 2)
	wpn_name = _lbl(wc, "", 12, DIM)
	wpn_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var ar := _row(wc, 8)
	ar.alignment = BoxContainer.ALIGNMENT_END
	wpn_ammo = _lbl(ar, "", 34)
	wpn_mags = _lbl(ar, "", 13, DIM)
	wpn_mags.size_flags_vertical = Control.SIZE_SHRINK_END
	wpn_kit = _lbl(wc, "", 12, Color(0.75, 0.85, 0.95))
	wpn_kit.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	act_box = _col(fps, 3)
	act_box.custom_minimum_size.x = 200
	_place(act_box, Control.PRESET_CENTER, Vector2(0, 52))
	act_label = _lbl(act_box, "", 12, TEXT)
	act_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	act_bar = _bar(act_box, 200, 4)
	prompt = _lbl(fps, "", 13, Color(1.0, 0.85, 0.5))
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.custom_minimum_size.x = 600
	_place(prompt, Control.PRESET_CENTER, Vector2(0, 96))


func set_mode_fps(on: bool) -> void:
	fps.visible = on
	rts.visible = not on
	log_box.offset_bottom = -118.0 if on else -14.0     # sit above the weapon block in first person
	log_box.offset_top = log_box.offset_bottom


func refresh_fps(c: Node, look_text: String) -> void:
	prompt.text = look_text
	_roster_t -= get_process_delta_time()
	if _roster_t <= 0.0:
		_roster_t = 0.5
		refresh_roster(c)
		refresh_alerts()
	if c.riding and is_instance_valid(c.riding):
		var craft: Node = c.riding
		vit_name.text = "%s  ·  aboard a %s" % [c.display, "boarding shuttle" if craft.has_method("_unload") else "boarding pod"]
		set_bar(vit_hp, c.hp / c.max_hp, _hp_col(c))
		vit_hp_text.text = "%d" % c.hp
		vit_armor.text = "CRAFT HULL %d" % int(craft.get("hp") if craft.get("hp") != null else 0)
		act_box.visible = false
		prompt.text = "Mouse looks around  ·  you'll come out fighting"
		return
	if c.piloting and is_instance_valid(c.piloting):
		var v: Node = c.piloting
		if v.get("is_vehicle") == true:
			vit_name.text = "%s  ·  %s" % [v.display_name, c.display]
			set_bar(vit_hp, v.hp / v.max_hp, Color(0.85, 0.75, 0.45))
			vit_hp_text.text = "%d" % v.hp
			vit_armor.text = "ARMOR %.1f  ·  SPEED %d" % [float(v.SPECS[v.kind]["armor"]), int(absf(v.drive_vel) * 3.6)]
			set_bar(exo_bar, clampf(absf(v.drive_vel) / float(v.SPECS[v.kind]["speed"]), 0.0, 1.0), Color(0.35, 0.7, 1.0))
			wpn_name.text = String(v.SPECS[v.kind]["label"]).to_upper()
			wpn_ammo.text = ""
			wpn_mags.text = ""
			wpn_kit.text = v.hud_line()
			act_box.visible = false
			return
		var fighter: bool = v in G.fighters
		vit_name.text = ("Fighter  ·  %s" % c.display) if fighter else ("%s  ·  at the helm" % v.display_name)
		set_bar(vit_hp, (v.hp / 160.0) if fighter else (v.hull / v.max_hull), Color(0.85, 0.75, 0.45))
		vit_hp_text.text = "%d" % (v.hp if fighter else v.hull)
		vit_armor.text = ("THROTTLE %d%%" % int(v.throttle * 100.0)) if fighter else ("SHIELDS %d / %d" % [v.shields, v.max_shields])
		set_bar(exo_bar, (v.throttle if fighter else v.shields / max(1.0, v.max_shields)), Color(0.35, 0.7, 1.0))
		wpn_name.text = "GUNS" if fighter else "TURRETS"
		wpn_ammo.text = ""
		wpn_mags.text = ("speed %d m/s" % int(v.vel.length())) if fighter else ("boarders %d  ·  fighters %d" % [v.troops, v.parked_count()])
		wpn_kit.text = "" if fighter else "MISSILES %d / %d%s    SHUTTLE %s" % [v.missiles, v.max_missiles,
			"" if v.missile_cd <= 0.0 else " (%ds)" % ceili(v.missile_cd), "ready" if v.shuttle_cd <= 0.0 else "%ds" % ceili(v.shuttle_cd)]
		act_box.visible = false
		return
	vit_name.text = "%s  ·  %s" % [c.display, c.vessel.display_name]
	set_bar(vit_hp, c.hp / c.max_hp, _hp_col(c))
	vit_hp_text.text = "%d" % c.hp if c.state == "alive" else "DOWN"
	vit_armor.text = "ARMOR %d%%" % int((c.dr + G.dr_bonus(c.team)) * 100.0)
	set_bar(exo_bar, c.exo / c.exo_max(), Color(0.5, 0.8, 1.0))
	if c.armed and c.gl_mode:
		var left: int = c.breach_ammo if c.gl_breach else c.gl_ammo
		wpn_name.text = "BREACHING ROUND" if c.gl_breach else "40MM LAUNCHER"
		wpn_ammo.text = "%d" % left
		wpn_mags.text = "loading" if c._gl_cd > 0.0 else "B: next"
		wpn_ammo.add_theme_color_override("font_color", WARN if left <= 1 else TEXT)
	elif c.armed:
		wpn_name.text = c.weapon_model.substr(3).capitalize().to_upper()
		wpn_ammo.text = "%d" % c.mag
		wpn_mags.text = "/ %d mag%s" % [c.spare.size(), "" if c.spare.size() == 1 else "s"]
		wpn_ammo.add_theme_color_override("font_color", WARN if c.mag <= int(c.wstats.get("ammo_per_load", 30)) / 5 else TEXT)
	else:
		wpn_name.text = "UNARMED"
		wpn_ammo.text = "-"
		wpn_mags.text = "gear up at a locker (E)"
	wpn_kit.text = "GRENADES %d    REVIVE PENS %d    CHARGES %d%s%s%s" % [c.grenades.size(), c.medpens.size(), c.charges.size(),
		"    PURGE %s" % ("ON" if c.purging else "off") if c.role == "scientist" else "",
		"    REVIVE GUN %d" % c.revive_gun if c.role == "medic" else ("    40MM %d    BREACH %d" % [c.gl_ammo, c.breach_ammo] if c.role == "grenadier" else ""),
		"    CARRYING %s" % c.hauling.display if c.hauling != null and is_instance_valid(c.hauling) else ""]
	var act := ""
	var frac := 0.0
	if c.reload_t >= 0.0:
		act = "RELOADING"
		frac = 1.0 - c.reload_t / max(0.1, float(c.wstats.get("reload_s", 2.0)))
	elif c.revive_t >= 0.0:
		act = "TREATING" if c.revive_src == "bed" else "REVIVING"
		frac = 1.0 - c.revive_t / maxf(0.1, c.revive_len)
	elif c.gear_t >= 0.0:
		act = "GEARING UP"
		frac = 1.0 - c.gear_t / 3.0
	act_box.visible = act != ""
	act_label.text = act
	set_bar(act_bar, frac, Color(0.5, 0.85, 1.0))
	prompt.text = look_text


class Crosshair extends Control:
	var hud: Node

	func _draw() -> void:
		var c := size * 0.5
		var col: Color = Color(1.0, 0.3, 0.25) if hud.hit_t > 0.0 else Color(0.9, 0.95, 1.0, 0.9)
		var g: float = 5.0 + hud.hit_t * 30.0
		for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			draw_line(c + d * g, c + d * (g + 7.0), col, 2.0)
		draw_circle(c, 1.5, col)
		_draw_lock()

	## The helm's target lock: red brackets on the target, with range and missiles.
	func _draw_lock() -> void:
		var p: Node = G.possessed
		if p == null or not is_instance_valid(p) or p.piloting == null or not is_instance_valid(p.piloting):
			return
		var v: Node = p.piloting
		var lk = v.get("lock")
		if lk == null or not is_instance_valid(lk):
			return
		var cam: Camera3D = get_viewport().get_camera_3d()
		var center: Vector3 = lk.to_global(lk.aabb.get_center())
		if cam == null or cam.is_position_behind(center):
			return
		var sp := cam.unproject_position(center)
		var r: float = clampf(2600.0 / max(50.0, cam.global_position.distance_to(center)) * 6.0, 18.0, 90.0)
		var col := Color(1.0, 0.25, 0.2, 0.95)
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				var corner := sp + Vector2(sx, sy) * r
				draw_line(corner, corner - Vector2(sx, 0) * r * 0.45, col, 2.0)
				draw_line(corner, corner - Vector2(0, sy) * r * 0.45, col, 2.0)
		var font := get_theme_default_font()
		var dist: float = v.global_position.distance_to(lk.global_position)
		draw_string(font, sp + Vector2(-r, r + 16), "LOCK  %s  %.1f km" % [lk.display_name, dist / 1000.0],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
		for m in G.missiles:                         # our missiles in flight
			if is_instance_valid(m) and m.get("target") == lk and not cam.is_position_behind(m.global_position):
				draw_circle(cam.unproject_position(m.global_position), 3.0, Color(1.0, 0.85, 0.4))


# ------------------------------------------------------------------ alerts, boarding ops, squad roster

func _build_alerts() -> void:
	vignette = Vignette.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.visible = false
	add_child(vignette)
	move_child(vignette, 0)
	alert_panel = _panel(self, Color(0.35, 0.03, 0.03, 0.88), 6)
	_place(alert_panel, Control.PRESET_CENTER_TOP, Vector2(0, 46))
	alert_label = _lbl(alert_panel, "", 14, Color(1.0, 0.9, 0.85))
	alert_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	alert_panel.visible = false
	roster_panel = _panel(fps, BG, 8)
	_place(roster_panel, Control.PRESET_TOP_LEFT, Vector2(12, 44))
	roster_body = _col(roster_panel, 2)
	roster_panel.visible = false


## Boarding ops mustering on our side, and red alert where we stand.
func refresh_alerts() -> void:
	var lines: Array = []
	var c: Node = G.possessed if G.possessed and is_instance_valid(G.possessed) else null
	for v in G.vessels:
		if v.kind != "ship" or v.team != G.player_team or v.get("boarding") == null or v.boarding.is_empty():
			continue
		var b: Dictionary = v.boarding
		if not is_instance_valid(b["target"]):
			continue
		var here: bool = c != null and c.vessel == v and not c.piloting
		var joined: bool = c != null and c.mustered == v
		var where := "pod bay" if b["kind"] == "pods" else "hangar (shuttle)"
		var tail := ""
		if here:
			tail = "   ·   JOINED: stay at the %s" % where if joined else "   ·   get to the %s and press E to go" % where
		lines.append("BOARDING OP  %s → %s  ·  %s  ·  launch in %d s%s" % [v.display_name, b["target"].display_name,
			"PODS" if b["kind"] == "pods" else "SHUTTLE", ceili(b["t"]), tail])
	var red := false
	if c and c.riding and is_instance_valid(c.riding):
		var tgt: Node = c.riding.get("target")
		lines.append("RIDING %s  →  %s   ·   brace for breach" % ["BOARDING POD" if c.riding.has_method("_impact") else "BOARDING SHUTTLE",
			tgt.display_name if tgt and is_instance_valid(tgt) else "?"])
	elif c and c.vessel and is_instance_valid(c.vessel) and c.vessel.alarm > 0.0:
		red = true
		lines.append(("RED ALERT  ·  intruders aboard %s" if c.vessel.team == c.team else "RED ALERT  ·  %s is at general quarters")
			% c.vessel.display_name)
	alert_panel.visible = not lines.is_empty()
	alert_label.text = "\n".join(lines)
	vignette.visible = red
	if red:
		vignette.k = 0.5 + 0.5 * sin(G.time * 5.0)
		vignette.queue_redraw()


func refresh_roster(c: Node) -> void:
	var sq = c.squad if c else null
	roster_panel.visible = sq != null and sq.leader == c
	if not roster_panel.visible:
		return
	for ch in roster_body.get_children():
		ch.queue_free()
	var order: String = sq.order.get("type", "follow")
	if not sq.stack_door.is_empty():
		order = "stacked on door"
	elif not sq.clear.is_empty():
		order = "clearing room"
	_lbl(roster_body, "YOUR SQUAD  ·  %s  ·  %s%s%s%s" % [order.to_upper(), sq.formation.to_upper(),
		"  ·  BOUNDING" if sq.bounding() else "", "  ·  WEAPONS TIGHT" if sq.hold_fire else "",
		"  ·  SUPPRESSING" if not sq.suppress.is_empty() else ""], 11, DIM)
	for m in sq.members:
		if not is_instance_valid(m) or m == c:
			continue
		var r := _row(roster_body, 6)
		var hb := _bar(r, 44, 5)
		hb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		set_bar(hb, m.hp / m.max_hp if m.state == "alive" else 0.0, _hp_col(m))
		_lbl(r, "%s %s %s" % ["A" if m.fireteam == 0 else "B", m.role.replace("_", " "), "" if m.state == "alive" else "(%s)" % m.state.to_upper()], 11,
			TEXT if m.state == "alive" else WARN)
	_lbl(roster_body, "1 follow  2 hold  3 move/stack  4 breach+clear  5 suppress", 10, DIM)
	_lbl(roster_body, "6 regroup  7 formation  8 team B  9 weapons free/tight  0 frag  ·  T reinforce", 10, DIM)


class Vignette extends Control:
	var k := 0.0

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var a := 0.10 + 0.22 * k
		var steps := 10
		for i in steps:
			var t := float(i) / steps
			var col := Color(0.9, 0.0, 0.0, a * (1.0 - t) * 0.5)
			var d := 6.0 + t * 70.0
			draw_rect(Rect2(0, 0, w, d), col)
			draw_rect(Rect2(0, h - d, w, d), col)
			draw_rect(Rect2(0, 0, d, h), col)
			draw_rect(Rect2(w - d, 0, d, h), col)


# ------------------------------------------------------------------ deploy screen

const CLASS_INFO := {
	"rifleman": "Assault rifle, 4 mags, 2 grenades. The backbone of every squad.",
	"squad_leader": "Battle rifle, extra grenades, radio. Leads 5 AI soldiers: 1 follow, 2 hold, 3 move/stack.",
	"breacher": "Shotgun and 2 breaching charges: blows locked doors and sabotages modules.",
	"medic": "SMG, 8 revive pens and a revive gun (8 shots, 14 m). Brings the downed back.",
	"heavy": "LMG or arc cannon. Holds corridors.",
	"grenadier": "Bullpup with an underslung 40 mm launcher (B), 6 shells and 2 breaching rounds.",
	"eva_boarder": "Vacuum suit and mag boots, SMG and a charge.",
	"pilot": "Flight suit and a sidearm. Spawns by the hangar: E at a fighter to launch.",
	"engineer": "Unarmed. Repairs hull damage and sabotaged modules (gear up at a locker).",
	"scientist": "Unarmed. Purge emitter: the only thing that burns out the infection.",
}


func _build_deploy() -> void:
	deploy_panel = _panel(self, Color(0.03, 0.045, 0.07, 0.96), 16)
	deploy_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_place(deploy_panel, Control.PRESET_CENTER, Vector2.ZERO)
	deploy_body = _col(deploy_panel, 8)
	deploy_panel.visible = false


func deploy_open() -> bool:
	return deploy_panel.visible


func research_open() -> bool:
	return research_panel.visible


func close_panels() -> void:
	deploy_panel.visible = false
	research_panel.visible = false


func _btn(parent: Control, text: String, on: bool, cb: Callable, w: float = 150.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 30)
	b.add_theme_font_size_override("font_size", 12)
	b.add_theme_stylebox_override("normal", _style(Color(0.14, 0.3, 0.42, 1.0) if on else Color(0.06, 0.09, 0.13, 0.95), EDGE, 4))
	b.add_theme_stylebox_override("hover", _style(Color(0.1, 0.2, 0.3, 1.0), Color(0.45, 0.8, 1.0), 4))
	b.add_theme_stylebox_override("pressed", _style(Color(0.14, 0.3, 0.42, 1.0), Color(0.45, 0.8, 1.0), 4))
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func open_deploy(points: Array) -> void:
	research_panel.visible = false
	if deploy_spot == null or not points.has(deploy_spot):
		deploy_spot = points[0] if not points.is_empty() else null
	_fill_deploy(points)
	deploy_panel.visible = true


func _fill_deploy(points: Array) -> void:
	for c in deploy_body.get_children():
		c.queue_free()
	_lbl(deploy_body, "DEPLOY", 18)
	_lbl(deploy_body, "CLASS", 11, DIM)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	deploy_body.add_child(grid)
	for r in cmd.CLASSES:
		_btn(grid, r.replace("_", " ").capitalize(), r == deploy_role, func(): deploy_role = r; _fill_deploy(points), 128)
	var info := _lbl(deploy_body, CLASS_INFO.get(deploy_role, ""), 12, DIM)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size.x = 660
	_lbl(deploy_body, "SPAWN AT", 11, DIM)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.custom_minimum_size.x = 660
	deploy_body.add_child(row)
	for v in points:
		var tag: String = (" (boarded!)" if v.alarm > 0.0 else "")
		_btn(row, v.display_name + tag, v == deploy_spot, func(): deploy_spot = v; _fill_deploy(points), 200)
	var go := _row(deploy_body, 8)
	go.alignment = BoxContainer.ALIGNMENT_END
	if not cmd.soldier_mode:
		_btn(go, "CANCEL  (Esc)", false, func(): close_panels(), 140)
	_btn(go, "DEPLOY", true, func(): if deploy_spot: cmd.deploy(deploy_role, deploy_spot), 160)


# ------------------------------------------------------------------ research

func _build_research() -> void:
	research_panel = _panel(self, Color(0.03, 0.045, 0.07, 0.96), 16)
	research_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_place(research_panel, Control.PRESET_CENTER, Vector2.ZERO)
	research_body = _col(research_panel, 8)
	research_panel.visible = false


func toggle_research() -> void:
	if research_panel.visible:
		research_panel.visible = false
		return
	deploy_panel.visible = false
	_fill_research()
	research_panel.visible = true


func _fill_research() -> void:
	for c in research_body.get_children():
		c.queue_free()
	var team: int = G.player_team
	_lbl(research_body, "RESEARCH", 18)
	_lbl(research_body, "Costs circuitry; one project at a time. Circuitry: %d" % int(G.resources.get(team, {}).get("circuitry", 0)), 12, DIM)
	var cols: Control = null
	var bi := 0
	for branch in G.TECH_BRANCHES:
		if bi % 4 == 0:
			cols = _row(research_body, 12)                # two rows of four branches
		bi += 1
		var col := _col(cols, 6)
		_lbl(col, branch.to_upper(), 12, Color(0.5, 0.8, 1.0))
		for id in G.TECH:
			var t: Dictionary = G.TECH[id]
			if t["branch"] != branch:
				continue
			var done := G.has_tech(team, id)
			var busy: bool = not G.researching.get(team, []).is_empty() and G.researching[team][0] == id
			var label := "%s%s\n%s\n%d circuitry · %ds" % ["DONE  " if done else ("IN PROGRESS  " if busy else ""), t["name"],
				t["desc"], t["cost"], int(t["time"])]
			var b := _btn(col, label, done or busy, func():
				G.match_node.command("research", [id])
				_fill_research(), 200)
			b.custom_minimum_size.y = 58
			b.disabled = done or not G.tech_ok(team, id)
	_btn(research_body, "CLOSE  (Y)", false, func(): research_panel.visible = false, 140)
