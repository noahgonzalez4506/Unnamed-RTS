extends HBoxContainer
## Command card along the bottom of the screen: buttons for what the selected units can do
## (the same orders as the hotkeys), so nothing has to be remembered.

var cmd: Node
var _sig := ""


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	mouse_filter = Control.MOUSE_FILTER_PASS


func _process(_dt: float) -> void:
	var vp := get_viewport_rect().size
	position = Vector2(vp.x * 0.5 - size.x * 0.5, vp.y - 46)
	visible = G.possessed == null and not cmd.selection.is_empty()
	if visible and cmd.selection.all(func(u): return not is_instance_valid(u)):
		visible = false
	if not visible:
		return
	var ships: Array = cmd.selection.filter(func(u): return is_instance_valid(u) and u.get("kind") == "ship" and u.team == cmd.TEAM)
	var people: Array = cmd.selection.filter(func(u): return is_instance_valid(u) and u.get("rig") != null and u.team == cmd.TEAM)
	var vehs: Array = cmd.selection.filter(func(u): return is_instance_valid(u) and u.get("is_vehicle") == true)
	var sig := "%d/%d/%d/%s" % [ships.size(), people.size(), vehs.size(), ",".join(ships.map(func(x): return String(x.cls) + ("*" if x.has_meta("core_ship") else "")))]
	if sig == _sig:
		return
	_sig = sig
	for ch in get_children():
		ch.queue_free()
	if not ships.is_empty():
		_b("BOARD (B)", func(): cmd.cmd_board())
		_b("EVA BOARD", func(): cmd.cmd_board("eva"))
		_b("FIGHTERS (L)", func(): cmd.cmd_fighters())
		_b("RESUPPLY (U)", func():
			for s in cmd.selection:
				if is_instance_valid(s) and s.get("kind") == "ship":
					G.match_node.command("resupply", [G.vessels.find(s)]))
		_b("STOP", func():
			for s in cmd.selection:
				if is_instance_valid(s) and s.get("kind") == "ship":
					s.move_target = Vector3.INF
					s.attack_target = null)
		if ships.any(func(x): return x.cls == "SMALL_DROP_FRIGATE") and cmd.camp_ui and G.match_node.on_surface:
			_b("ODST DROP", func():
				cmd._pending = "odst"
				cmd.log_event("Right-click the ground: the dropship flies over it and fires its pods straight down", cmd.TEAM))
			_b("MINI DROPSHIP", func():
				cmd._pending = "minidrop"
				cmd.log_event("Right-click the ground where the mini dropship should land", cmd.TEAM))
		if ships.any(func(x): return x.cls == "SMALL_DROP_FRIGATE"):
			_b("NAPALM ON/OFF", func():
				for x in cmd.selection:
					if is_instance_valid(x) and x.get("cls") == "SMALL_DROP_FRIGATE":
						x.napalm = not x.napalm
						cmd.log_event("%s artillery: %s rounds" % [x.display_name, "NAPALM" if x.napalm else "high-explosive"], cmd.TEAM))
		if cmd.camp_ui and G.match_node.on_surface:
			_b("DEPLOY VEHICLES", func():
				for x in cmd.selection:
					if is_instance_valid(x) and x.get("kind") == "ship":
						cmd.log_event("%s: %d vehicles deployed" % [x.display_name, G.match_node.deploy_vehicles(x)], cmd.TEAM))
			_b("RECALL VEHICLES", func():
				for x in cmd.selection:
					if is_instance_valid(x) and x.get("kind") == "ship":
						cmd.log_event("%s: %d vehicles back aboard" % [x.display_name, G.match_node.recall_vehicles(x)], cmd.TEAM))
			_b("DEPLOY TROOPS", func():
				for x in cmd.selection:
					if is_instance_valid(x) and x.get("kind") == "ship":
						cmd.log_event("%s: %d troops deployed" % [x.display_name, G.match_node.deploy_troops(x)], cmd.TEAM))
			_b("RECALL TROOPS", func():
				for x in cmd.selection:
					if is_instance_valid(x) and x.get("kind") == "ship":
						cmd.log_event("%s: %d troops back aboard" % [x.display_name, G.match_node.recall_troops(x)], cmd.TEAM))
			var haul := false
			for x in cmd.selection:
				if is_instance_valid(x) and x.get("kind") == "ship" and x.cls == "SMALL_SUPPORT":
					haul = true
			if haul:
				_b("UNLOAD CARGO", func():
					for x in cmd.selection:
						if is_instance_valid(x) and x.get("kind") == "ship" and x.cls == "SMALL_SUPPORT":
							cmd.log_event(G.match_node.DEPOT.unload(G.match_node, x), cmd.TEAM))
				_b("LOAD CARGO", func():
					for x in cmd.selection:
						if is_instance_valid(x) and x.get("kind") == "ship" and x.cls == "SMALL_SUPPORT":
							cmd.log_event(G.match_node.DEPOT.load_cargo(G.match_node, x), cmd.TEAM))
				var ah := false
				for x in cmd.selection:
					if is_instance_valid(x) and x.get("kind") == "ship" and x.cls == "SMALL_SUPPORT" and x.has_meta("fleet_id"):
						ah = ah or G.campaign.fleet_entry(int(x.get_meta("fleet_id"))).get("auto_haul", false)
				_b("AUTO HAUL: %s" % ("ON" if ah else "OFF"), func():
					for x in cmd.selection:
						if is_instance_valid(x) and x.get("kind") == "ship" and x.cls == "SMALL_SUPPORT" and x.has_meta("fleet_id"):
							var fe: Dictionary = G.campaign.fleet_entry(int(x.get_meta("fleet_id")))
							if not fe.is_empty():
								fe["auto_haul"] = not ah
					cmd.log_event("Auto haul %s: landed supply ships load secured salvage by themselves" % ("off" if ah else "ON"), cmd.TEAM))
			_b("TAKE OFF", func(): G.match_node.take_off())
		elif cmd.camp_ui:
			_b("LAND", func(): cmd.camp_ui.toggle_landing(cmd.selection.duplicate()))
			if ships.any(func(x): return x.has_meta("core_ship")):
				_b("DEPLOY STATION", func():
					for x in cmd.selection.duplicate():
						if is_instance_valid(x) and x.get("kind") == "ship" and x.has_meta("core_ship"):
							cmd.log_event(G.match_node.deploy_station(x), cmd.TEAM)
							break)
			if ships.any(func(x): return x.cls in G.match_node.HAULERS):
				_b("LOAD VEHICLES", func():
					for x in cmd.selection:
						if is_instance_valid(x) and x.get("kind") == "ship" and x.cls in G.match_node.HAULERS:
							cmd.log_event(G.match_node.load_vehicles(x), cmd.TEAM))
				_b("UNLOAD VEHICLES", func():
					for x in cmd.selection:
						if is_instance_valid(x) and x.get("kind") == "ship" and x.cls in G.match_node.HAULERS:
							cmd.log_event(G.match_node.unload_vehicles(x), cmd.TEAM))
		if cmd.camp_ui:
			_b("JUMP (O)", func(): cmd.camp_ui.toggle_map())
			_b("STATION (P)", func(): cmd.camp_ui.toggle_services())
	if not vehs.is_empty() and vehs.any(func(v): return v.team == cmd.TEAM):
		_b("DRIVE (Tab)", func(): cmd.possess_selected())
	if vehs.any(func(v): return v.kind == "ifv"):
		_b("UNLOAD", func():
			for x in cmd.selection:
				if is_instance_valid(x) and x.get("is_vehicle") == true and x.kind == "ifv":
					cmd.log_event("%d troops out" % x.unload(), cmd.TEAM))
		_b("LOAD TROOPS", func():
			for x in cmd.selection:
				if is_instance_valid(x) and x.get("is_vehicle") == true and x.kind == "ifv":
					cmd.log_event("%d troops aboard the IFV" % x.load_troops(), cmd.TEAM))
	if not people.is_empty():
		_b("HOLD (H)", func(): G.match_node.command("hold", [cmd._ids(people.filter(func(c): return is_instance_valid(c)))]))
		_b("TAKE CONTROL (Tab)", func(): cmd.possess_selected())
		_b("SABOTAGE (K)", func(): cmd.cmd_sabotage())
		var tip := Label.new()
		tip.text = "  right-click a friendly ship: ride a Darter there  ·  an enemy ship: board it"
		tip.add_theme_font_size_override("font_size", 11)
		tip.modulate = Color(0.7, 0.78, 0.86)
		add_child(tip)


func _b(t: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(cb)
	add_child(b)
