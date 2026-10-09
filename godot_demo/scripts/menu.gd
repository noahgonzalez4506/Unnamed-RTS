extends Control
## Main menu: play against the AI, host or join a multiplayer match, settings.
## Choices are stored in G.config and read by the match.

const BG := Color(0.02, 0.03, 0.05)
const PANEL := Color(0.035, 0.05, 0.075, 0.92)
const EDGE := Color(0.33, 0.52, 0.72, 0.5)
const TEXT := Color(0.88, 0.92, 0.96)
const DIM := Color(0.56, 0.63, 0.71)
const ACCENT := Color(0.45, 0.8, 1.0)

var pages := {}
var team_pick := 1
var start_pick := "commander"
var diff_pick := 1
var ip_edit: LineEdit
var name_edit: LineEdit
var status: Label
var lobby_list: VBoxContainer
var lobby_side: Array = []         # the lobby's side / role buttons (shown as the host has us)
var lobby_role: Array = []


func _ready() -> void:
	G.load_settings()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var stars := Starfield.new()
	stars.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(stars)
	_title()
	pages["main"] = _main_page()
	pages["play"] = _play_page()
	pages["campaign"] = _campaign_page()
	pages["mp"] = _mp_page()
	pages["lobby"] = _lobby_page()
	pages["settings"] = _settings_page()
	show_page("main")
	if G.network:
		G.network.lobby_changed.connect(_refresh_lobby)
		G.network.status.connect(func(t): status.text = t)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_autotest()


## Command-line shortcuts for testing:  -- --host   /   -- --join 127.0.0.1
func _autotest() -> void:
	var args := OS.get_cmdline_user_args()
	if "--menushot" in args:
		await get_tree().create_timer(1.0).timeout
		show_page("play")
		await get_tree().create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args[-1])
		G.quit()
	if "--host" in args:
		G.network.host("Host")
		while G.network.players.size() < 2:
			await get_tree().create_timer(0.2).timeout
		await get_tree().create_timer(0.5).timeout
		G.network.start_match()
	elif "--join" in args:
		var ip: String = args[args.find("--join") + 1] if args.find("--join") + 1 < args.size() else "127.0.0.1"
		set_meta("auto", true)
		G.network.join(ip, "Client")
		while G.network.players.size() < 2:
			await get_tree().create_timer(0.2).timeout
		G.network.set_my_choice(2, "soldier")

func show_page(n: String) -> void:
	for k in pages:
		pages[k].visible = k == n


# ------------------------------------------------------------------ widgets

func _style(bg: Color, edge: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = edge
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


func _label(parent: Node, text: String, size: int = 14, col: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	parent.add_child(l)
	return l


func _button(parent: Node, text: String, cb: Callable, wide: float = 300.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(wide, 40)
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_stylebox_override("normal", _style(Color(0.06, 0.09, 0.13, 0.9), EDGE))
	b.add_theme_stylebox_override("hover", _style(Color(0.1, 0.18, 0.26, 0.95), ACCENT))
	b.add_theme_stylebox_override("pressed", _style(Color(0.14, 0.26, 0.36, 1.0), ACCENT))
	b.add_theme_stylebox_override("focus", _style(Color(0.1, 0.18, 0.26, 0.95), ACCENT))
	b.add_theme_color_override("font_color", TEXT)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _choice(parent: Node, label: String, options: Array, current: int, cb: Callable) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var l := _label(row, label, 13, DIM)
	l.custom_minimum_size.x = 110
	var group := ButtonGroup.new()
	var buttons: Array = []
	for i in options.size():
		var b := Button.new()
		b.text = options[i]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == current
		b.custom_minimum_size = Vector2(130, 34)
		b.add_theme_font_size_override("font_size", 13)
		b.add_theme_stylebox_override("normal", _style(Color(0.06, 0.09, 0.13, 0.9), EDGE))
		b.add_theme_stylebox_override("pressed", _style(Color(0.14, 0.3, 0.42, 1.0), ACCENT))
		b.add_theme_stylebox_override("hover", _style(Color(0.1, 0.18, 0.26, 0.95), ACCENT))
		b.toggled.connect(func(on): if on: cb.call(i))
		row.add_child(b)
		buttons.append(b)
	return buttons


func _page() -> VBoxContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _style(PANEL, EDGE))
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 0.5
	p.anchor_bottom = 0.5
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	p.offset_top = 60
	p.offset_bottom = 60
	add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	v.set_meta("panel", p)
	return v


func _title() -> void:
	var v := VBoxContainer.new()
	v.anchor_left = 0.5
	v.anchor_right = 0.5
	v.grow_horizontal = Control.GROW_DIRECTION_BOTH
	v.offset_top = 70
	add_child(v)
	var t := _label(v, "STARSHIP  KIT", 54, TEXT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var s := _label(v, "FLEET COMMAND  ·  BOARDING ACTION", 15, ACCENT)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status = _label(self, "", 13, DIM)
	status.anchor_top = 1.0
	status.anchor_bottom = 1.0
	status.offset_left = 16
	status.offset_top = -30
	_label(self, "v0.3 demo", 12, DIM).position = Vector2(16, 12)


# ------------------------------------------------------------------ pages

func _wrap(v: VBoxContainer) -> Control:
	return v.get_meta("panel")


func _main_page() -> Control:
	var v := _page()
	_button(v, "CAMPAIGN", func(): show_page("campaign"))
	_button(v, "SKIRMISH VS AI", func(): show_page("play"))
	_button(v, "MULTIPLAYER", func(): show_page("mp"))
	_button(v, "SETTINGS", func(): show_page("settings"))
	_button(v, "QUIT", func(): G.quit())
	return _wrap(v)


func _play_page() -> Control:
	var v := _page()
	_label(v, "SKIRMISH", 18)
	_choice(v, "Side", ["Vanguard (F1)", "Ascendancy (F2)"], 0, func(i): team_pick = i + 1)
	_choice(v, "Start as", ["Commander", "Soldier"], 0, func(i): start_pick = ["commander", "soldier"][i])
	_choice(v, "Rival AI", ["Easy", "Normal", "Hard"], 1, func(i): diff_pick = i)
	_label(v, "Commanders run the fleet from above and can drop into any unit (Tab).\nSoldiers pick a class and spawn; J opens the deploy screen.", 12, DIM)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	_button(row, "BACK", func(): show_page("main"), 140)
	_button(row, "LAUNCH", _launch_single, 200)
	return _wrap(v)


var company_edit: LineEdit
var continue_btn: Button


func _campaign_page() -> Control:
	var v := _page()
	_label(v, "CAMPAIGN", 18)
	_label(v, "Run your own company: one frigate, two mining craft and a starter station.\nExplore, trade, take jobs, fight pirates and the infection.", 12, DIM)
	_label(v, "Company name", 12, DIM)
	company_edit = LineEdit.new()
	company_edit.text = "Kestrel Company"
	company_edit.custom_minimum_size = Vector2(300, 34)
	v.add_child(company_edit)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	_button(row, "BACK", func(): show_page("main"), 140)
	_button(row, "NEW CAMPAIGN", _new_campaign, 200)
	continue_btn = _button(v, "CONTINUE SAVED CAMPAIGN", _continue_campaign)
	continue_btn.disabled = not load("res://scripts/campaign/campaign.gd").has_save()
	return _wrap(v)


func _new_campaign() -> void:
	var CAMP = load("res://scripts/campaign/campaign.gd")
	G.campaign = CAMP.new_game(randi() % 900000 + 1, company_edit.text)
	G.campaign.save()
	G.config = {"mode": "campaign", "team": 1, "start": "commander", "difficulty": 1}
	get_tree().change_scene_to_file("res://match.tscn")


func _continue_campaign() -> void:
	var CAMP = load("res://scripts/campaign/campaign.gd")
	var c = CAMP.load_game()
	if c == null:
		status.text = "No saved campaign"
		return
	G.campaign = c
	G.config = {"mode": "campaign", "team": 1, "start": "commander", "difficulty": 1}
	get_tree().change_scene_to_file("res://match.tscn")


func _launch_single() -> void:
	G.config = {"mode": "single", "team": team_pick, "start": start_pick, "difficulty": diff_pick}
	G.campaign = null
	get_tree().change_scene_to_file("res://match.tscn")


func _mp_page() -> Control:
	var v := _page()
	_label(v, "MULTIPLAYER", 18)
	var r1 := HBoxContainer.new()
	v.add_child(r1)
	_label(r1, "Name", 13, DIM).custom_minimum_size.x = 110
	name_edit = LineEdit.new()
	name_edit.text = G.settings.get("name", "Commander")
	name_edit.custom_minimum_size.x = 260
	r1.add_child(name_edit)
	var r2 := HBoxContainer.new()
	v.add_child(r2)
	_label(r2, "Host address", 13, DIM).custom_minimum_size.x = 110
	ip_edit = LineEdit.new()
	ip_edit.text = G.settings.get("last_ip", "127.0.0.1")
	ip_edit.custom_minimum_size.x = 260
	r2.add_child(ip_edit)
	_label(v, "Hosting opens UDP port %d. Players on other networks need it forwarded." % G.PORT, 12, DIM)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	_button(row, "BACK", func(): show_page("main"), 120)
	_button(row, "HOST", _host, 150)
	_button(row, "JOIN", _join, 150)
	return _wrap(v)


func _host() -> void:
	G.settings["name"] = name_edit.text
	G.save_settings()
	if G.network.host(name_edit.text):
		show_page("lobby")
		_refresh_lobby()


func _join() -> void:
	G.settings["name"] = name_edit.text
	G.settings["last_ip"] = ip_edit.text
	G.save_settings()
	if G.network.join(ip_edit.text, name_edit.text):
		show_page("lobby")
		status.text = "Connecting to %s..." % ip_edit.text


func _lobby_page() -> Control:
	var v := _page()
	_label(v, "LOBBY", 18)
	lobby_list = VBoxContainer.new()
	lobby_list.add_theme_constant_override("separation", 4)
	lobby_list.custom_minimum_size = Vector2(520, 120)
	v.add_child(lobby_list)
	lobby_side = _choice(v, "My side", ["Vanguard (F1)", "Ascendancy (F2)"], 0, func(i): G.network.set_my_choice(i + 1, ""))
	lobby_role = _choice(v, "My role", ["Commander", "Soldier"], 0, func(i): G.network.set_my_choice(0, ["commander", "soldier"][i]))
	_label(v, "Sides without a human commander are run by the AI. Any number of soldiers per side.", 12, DIM)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	_button(row, "LEAVE", func(): G.network.leave(); show_page("mp"), 140)
	var start := _button(row, "START MATCH", func(): G.network.start_match(), 200)
	start.set_meta("host_only", true)
	return _wrap(v)


func _refresh_lobby() -> void:
	if lobby_list == null:
		return
	for c in lobby_list.get_children():
		c.queue_free()
	for id in G.network.players:
		var p: Dictionary = G.network.players[id]
		var l := _label(lobby_list, "%s%s   ·   %s   ·   %s" % [p["name"], "  (host)" if id == 1 else "",
			G.team_name(p["team"]), p["role"].capitalize()], 14, G.team_color(p["team"]))
		l.add_theme_color_override("font_outline_color", Color.BLACK)
	var me: Dictionary = G.network.players.get(multiplayer.get_unique_id(), {})
	if not me.is_empty():                            # (a joiner starts as a soldier, maybe on side 2)
		for i in lobby_side.size():
			(lobby_side[i] as Button).set_pressed_no_signal(int(me["team"]) == i + 1)
		for i in lobby_role.size():
			(lobby_role[i] as Button).set_pressed_no_signal(me["role"] == ["commander", "soldier"][i])
	for b in pages["lobby"].find_children("*", "Button", true, false):
		if b.has_meta("host_only"):
			b.disabled = not multiplayer.is_server()


func _settings_page() -> Control:
	var v := _page()
	_label(v, "SETTINGS", 18)
	var r := HBoxContainer.new()
	v.add_child(r)
	_label(r, "Mouse sensitivity", 13, DIM).custom_minimum_size.x = 160
	var sens := HSlider.new()
	sens.min_value = 0.2
	sens.max_value = 3.0
	sens.step = 0.05
	sens.value = G.settings.get("sens", 1.0)
	sens.custom_minimum_size.x = 240
	sens.value_changed.connect(func(x): G.settings["sens"] = x)
	r.add_child(sens)
	var r2 := HBoxContainer.new()
	v.add_child(r2)
	_label(r2, "Field of view", 13, DIM).custom_minimum_size.x = 160
	var fov := HSlider.new()
	fov.min_value = 65
	fov.max_value = 110
	fov.step = 1
	fov.value = G.settings.get("fov", 85)
	fov.custom_minimum_size.x = 240
	fov.value_changed.connect(func(x): G.settings["fov"] = x)
	r2.add_child(fov)
	var fs := CheckBox.new()
	fs.text = "Fullscreen"
	fs.button_pressed = G.settings.get("fullscreen", false)
	fs.toggled.connect(func(on): G.settings["fullscreen"] = on; G.apply_settings())
	v.add_child(fs)
	var fps := CheckBox.new()
	fps.text = "Show frame rate"
	fps.button_pressed = G.settings.get("show_fps", true)
	fps.toggled.connect(func(on): G.settings["show_fps"] = on)
	v.add_child(fps)
	var vs := CheckBox.new()
	vs.text = "V-Sync"
	vs.button_pressed = G.settings.get("vsync", true)
	vs.toggled.connect(func(on): G.settings["vsync"] = on; G.apply_settings())
	v.add_child(vs)
	_button(v, "SAVE AND BACK", func(): G.save_settings(); show_page("main"))
	return _wrap(v)


class Starfield extends Control:
	var pts: Array = []
	var t := 0.0

	func _ready() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 3
		for i in 260:
			pts.append([Vector2(rng.randf(), rng.randf()), rng.randf_range(0.3, 1.0), rng.randf_range(4, 30)])
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(dt: float) -> void:
		t += dt
		queue_redraw()

	func _draw() -> void:
		for p in pts:
			var x: float = fmod(p[0].x * size.x - t * p[2], size.x)
			if x < 0:
				x += size.x
			draw_circle(Vector2(x, p[0].y * size.y), p[1] * 1.3, Color(0.8, 0.85, 1.0, p[1] * 0.7))
