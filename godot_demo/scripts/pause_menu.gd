extends CanvasLayer
## The Esc menu: pauses the game; resume, settings (sensitivity, field of view, fog of war,
## volume, graphics quality, fullscreen, v-sync, frame rate), save (campaign), back to the
## main menu, quit. Settings are kept in user://settings.cfg.

const BG := Color(0.03, 0.05, 0.08, 0.94)
const TEXT := Color(0.88, 0.92, 0.96)
const DIM := Color(0.56, 0.63, 0.71)

var root: Control
var box: VBoxContainer
var page := "main"


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(cc)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(18)
	sb.border_color = Color(0.3, 0.45, 0.6, 0.8)
	sb.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(380, 0)
	cc.add_child(panel)
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	visible = false
	_apply_audio()
	_apply_quality()


func is_open() -> bool:
	return visible


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	visible = true
	# in multiplayer the game runs on for everyone (a paused host would freeze every client)
	get_tree().paused = not (G.network and G.network.active)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show("main")


func close() -> void:
	visible = false
	get_tree().paused = false
	G.save_settings()
	if G.possessed and is_instance_valid(G.possessed):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		if page != "main":
			_show("main")
		else:
			close()
		get_viewport().set_input_as_handled()


func _clear() -> void:
	for ch in box.get_children():
		ch.queue_free()


func _label(text: String, size: int = 13, col: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	box.add_child(l)
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(340, 34)
	b.pressed.connect(cb)
	box.add_child(b)
	return b


func _slider(text: String, key: String, lo: float, hi: float, step: float, dflt: float, cb: Callable = Callable()) -> void:
	var r := HBoxContainer.new()
	box.add_child(r)
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = 150
	l.add_theme_color_override("font_color", DIM)
	r.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(G.settings.get(key, dflt))
	s.custom_minimum_size.x = 190
	s.value_changed.connect(func(x):
		G.settings[key] = x
		if cb.is_valid():
			cb.call())
	r.add_child(s)


func _check(text: String, key: String, dflt: bool, cb: Callable = Callable()) -> void:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = bool(G.settings.get(key, dflt))
	c.toggled.connect(func(on):
		G.settings[key] = on
		if cb.is_valid():
			cb.call())
	box.add_child(c)


func _show(p: String) -> void:
	page = p
	_clear()
	match p:
		"main":
			_label("PAUSED", 20)
			_button("RESUME", close)
			_button("SETTINGS", func(): _show("settings"))
			if G.campaign and G.match_node and G.match_node.get("campaign_mode"):
				_button("SAVE GAME", func():
					G.campaign.snapshot()
					_label("Saved" if G.campaign.save() else "Couldn't save", 12, DIM))
			_button("MAIN MENU", _to_menu)
			_button("QUIT TO DESKTOP", _quit)
		"settings":
			_label("SETTINGS", 18)
			_slider("Mouse sensitivity", "sens", 0.2, 3.0, 0.05, 1.0)
			_slider("Field of view", "fov", 65, 110, 1, 85)
			_slider("Volume", "volume", 0.0, 1.0, 0.05, 0.8, _apply_audio)
			var q := HBoxContainer.new()
			box.add_child(q)
			var ql := Label.new()
			ql.text = "Graphics"
			ql.custom_minimum_size.x = 150
			ql.add_theme_color_override("font_color", DIM)
			q.add_child(ql)
			var ob := OptionButton.new()
			for n in ["Low", "Medium", "High"]:
				ob.add_item(n)
			ob.selected = int(G.settings.get("quality", 2))
			ob.focus_mode = Control.FOCUS_NONE
			ob.item_selected.connect(func(i):
				G.settings["quality"] = i
				_apply_quality())
			q.add_child(ob)
			_check("Fog of war", "fog", true)
			_check("Fullscreen", "fullscreen", false, G.apply_settings)
			_check("V-Sync", "vsync", true, G.apply_settings)
			_check("Show frame rate", "show_fps", true)
			_button("BACK", func():
				G.save_settings()
				_show("main"))


func _apply_audio() -> void:
	var v: float = float(G.settings.get("volume", 0.8))
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.0001)))
	AudioServer.set_bus_mute(0, v <= 0.001)


## Low: no shadows, half-resolution 3D; medium: shadows, 75 %; high: everything, full.
func _apply_quality() -> void:
	var q: int = int(G.settings.get("quality", 2))
	var vp := get_viewport()
	if vp == null:
		return
	vp.scaling_3d_scale = [0.6, 0.8, 1.0][q]
	vp.msaa_3d = Viewport.MSAA_DISABLED if q < 2 else Viewport.MSAA_2X
	for l in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
		(l as DirectionalLight3D).shadow_enabled = q > 0


func _save_campaign() -> void:
	if G.campaign and G.match_node and G.match_node.get("campaign_mode"):
		G.campaign.snapshot()
		G.campaign.save()


func _to_menu() -> void:
	_save_campaign()
	get_tree().paused = false
	G.save_settings()
	if G.network and G.network.has_method("leave"):
		G.network.leave()
	get_tree().change_scene_to_file("res://menu.tscn")


func _quit() -> void:
	_save_campaign()
	G.save_settings()
	get_tree().quit()
