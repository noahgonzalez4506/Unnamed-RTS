extends RefCounted
## Campaign construction: what your stations can build, and the station segments themselves.
##   Ships, mining craft and troops go in a station's build queue (paid up front from the stores).
##   Station segments snap onto a 36 m grid next to the station or another segment.

const GRID := 36.0
const ITEMS := {
	"SMALL_FRIGATE": {"label": "Small frigate", "alloys": 480, "circuitry": 95, "time": 90.0, "yards": 0, "kind": "ship"},
	"SMALL_SUPPORT": {"label": "Supply ship (logistics)", "alloys": 400, "circuitry": 65, "time": 80.0, "yards": 0, "kind": "ship"},
	"SMALL_DROP_FRIGATE": {"label": "Dropship (16 ODST pods, 2× 120 mm artillery)", "alloys": 560, "circuitry": 120, "time": 100.0, "yards": 0, "kind": "ship"},
	"MEDIUM": {"label": "Medium cruiser", "alloys": 1200, "circuitry": 320, "time": 180.0, "yards": 1, "kind": "ship"},
	"LARGE": {"label": "Large battleship", "alloys": 2800, "circuitry": 720, "time": 300.0, "yards": 2, "kind": "ship"},
	"CORE_SHIP": {"label": "Station core ship (fly it somewhere and DEPLOY STATION)", "alloys": 1400, "circuitry": 300, "time": 120.0, "yards": 0, "kind": "ship", "cls": "SMALL_SUPPORT", "core": true},
	"MINER": {"label": "Mining craft", "alloys": 200, "circuitry": 25, "time": 40.0, "yards": 0, "kind": "miner"},
	"DARTER": {"label": "Cargo Darter (one more supply run at a time)", "alloys": 100, "circuitry": 15, "time": 25.0, "yards": 0, "kind": "darter"},
	"FIGHTER": {"label": "Fighter (to a ship with a free hangar pad)", "alloys": 130, "circuitry": 30, "time": 30.0, "yards": 0, "kind": "fighter"},
	"BOMBER": {"label": "Bomber (to a ship with a free hangar pad)", "alloys": 190, "circuitry": 50, "time": 40.0, "yards": 0, "kind": "bomber"},
	"TANK": {"label": "Tank", "alloys": 220, "circuitry": 45, "time": 35.0, "yards": 0, "kind": "vehicle", "v": "tank"},
	"IFV": {"label": "IFV (carries 6)", "alloys": 140, "circuitry": 30, "time": 28.0, "yards": 0, "kind": "vehicle", "v": "ifv"},
	"MRAP_AI": {"label": "MRAP, anti-infantry", "alloys": 80, "circuitry": 15, "time": 16.0, "yards": 0, "kind": "vehicle", "v": "mrap_ai"},
	"MRAP_AA": {"label": "MRAP, anti-air", "alloys": 90, "circuitry": 22, "time": 16.0, "yards": 0, "kind": "vehicle", "v": "mrap_aa"},
	"MRAP_AV": {"label": "MRAP, anti-vehicle", "alloys": 95, "circuitry": 25, "time": 16.0, "yards": 0, "kind": "vehicle", "v": "mrap_av"},
	"MECH": {"label": "Mech", "alloys": 150, "circuitry": 40, "time": 28.0, "yards": 0, "kind": "vehicle", "v": "mech"},
	"MORTAR": {"label": "Mortar carrier", "alloys": 120, "circuitry": 25, "time": 24.0, "yards": 0, "kind": "vehicle", "v": "mortar"},
	"MINIDROP": {"label": "Mini dropship (docks on a dropship)", "alloys": 150, "circuitry": 40, "time": 32.0, "yards": 0, "kind": "minidrop"},
	"SQUAD": {"label": "Boarding squad (6 troops, 1 core each)", "alloys": 110, "circuitry": 0, "cores": 6, "time": 30.0, "yards": 0, "kind": "troops"},
}
const SEGMENTS := {
	"refinery": {"label": "Refinery (ore into alloys)", "alloys": 320, "circuitry": 30, "size": Vector3(28, 14, 28), "color": Color(0.55, 0.42, 0.3)},
	"fabricator": {"label": "Fabricator (crystal + alloys into circuitry)", "alloys": 300, "circuitry": 20, "size": Vector3(24, 12, 24), "color": Color(0.35, 0.5, 0.55)},
	"reactor": {"label": "Reactor (makes tritium from fuel, for jumps)", "alloys": 240, "circuitry": 65, "size": Vector3(20, 18, 20), "color": Color(0.35, 0.55, 0.85)},
	"barracks": {"label": "Barracks (+20 troop capacity, faster recruits)", "alloys": 280, "circuitry": 30, "size": Vector3(30, 10, 24), "color": Color(0.45, 0.5, 0.4)},
	"shipyard": {"label": "Shipyard (1: mediums, 2: larges)", "alloys": 640, "circuitry": 160, "size": Vector3(34, 6, 34), "color": Color(0.6, 0.6, 0.62)},
	"storage": {"label": "Storage depot", "alloys": 200, "circuitry": 0, "size": Vector3(26, 12, 26), "color": Color(0.5, 0.45, 0.35)},
	"defense": {"label": "Defense platform (large gun)", "alloys": 400, "circuitry": 95, "size": Vector3(22, 8, 22), "color": Color(0.38, 0.4, 0.44)},
	"ciws": {"label": "Point defense (CIWS)", "alloys": 160, "circuitry": 45, "size": Vector3(14, 6, 14), "color": Color(0.38, 0.4, 0.44)},
	"habitat": {"label": "Habitat ring", "alloys": 240, "circuitry": 45, "size": Vector3(30, 8, 30), "color": Color(0.7, 0.72, 0.75)},
}


static func count_segments(entry: Dictionary, type: String) -> int:
	var n := 0
	for sg in entry.get("segments", []):
		if sg["type"] == type:
			n += 1
	return n


static func can_afford(costs: Dictionary) -> bool:
	var st: Dictionary = G.campaign.stores
	for k in ["alloys", "circuitry", "cores"]:
		if float(st.get(k, 0.0)) < float(costs.get(k, 0)):
			return false
	return true


static func pay(costs: Dictionary) -> void:
	var st: Dictionary = G.campaign.stores
	for k in ["alloys", "circuitry", "cores"]:
		st[k] = float(st.get(k, 0.0)) - float(costs.get(k, 0))


## Queue something at a station (its campaign record). Returns a message.
static func order(entry: Dictionary, item: String) -> String:
	var it: Dictionary = ITEMS[item]
	if count_segments(entry, "shipyard") < int(it["yards"]):
		return "Needs %d shipyard segment%s on this station" % [it["yards"], "" if it["yards"] == 1 else "s"]
	if not can_afford(it):
		return "Not enough in the stores (%d alloys, %d circuitry%s)" % [it["alloys"], it["circuitry"],
			", %d cores" % it["cores"] if it.has("cores") else ""]
	var q: Array = entry.get("queue", [])
	if q.size() >= 6:
		return "The build queue is full"
	pay(it)
	q.append({"item": item, "left": float(it["time"])})
	entry["queue"] = q
	return "%s queued at %s" % [it["label"], entry["name"]]


## Every second of campaign time: the head of each queue makes progress.
static func tick(dt: float) -> void:
	var c = G.campaign
	for entry in c.stations:
		var q: Array = entry.get("queue", [])
		if q.is_empty():
			continue
		var head: Dictionary = q[0]
		head["left"] = float(head["left"]) - dt * (1.0 + G.tech_bonus(1, "build_speed"))
		if head["left"] <= 0.0:
			q.pop_front()
			_deliver(entry, head["item"])


static func _station_node(entry: Dictionary) -> Node:
	for v in G.vessels:
		if v.kind == "station" and v.get_meta("key", "") == entry["key"] and not v.destroyed:
			return v
	return null


static func _deliver(entry: Dictionary, item: String) -> void:
	var c = G.campaign
	var it: Dictionary = ITEMS[item]
	var here: bool = int(entry["system"]) == c.current and G.match_node != null
	var st: Node = _station_node(entry) if here else null
	var base := Vector3(float(entry["pos"][0]), 0, float(entry["pos"][1]))
	match it["kind"]:
		"ship":
			var nm: String = G.ship_name(1)
			var a := randf() * TAU
			var p: Vector3 = base + Vector3(cos(a), 0, sin(a)) * 420.0
			var cls: String = it.get("cls", item)
			if it.get("core", false):
				nm = "Core " + nm
			var e := {"id": c.new_id(), "cls": cls, "name": nm, "variant": 1 + randi() % 3, "system": int(entry["system"]),
				"pos": [p.x, p.z], "yaw": 0.0, "hull": 1.0, "troops": 8, "supplies": 120.0, "cargo": {}}
			if it.get("core", false):
				e["core"] = true
			c.fleet.append(e)
			if st:
				var s: Node3D = G.match_node.spawn_runtime_ship(cls, 1, 1, nm, p, load("res://scripts/campaign/sector.gd").SHIP_CREWS.get(cls, []), "", int(e["variant"]))
				s.set_meta("fleet_id", e["id"])
				if it.get("core", false):
					s.set_meta("core_ship", true)
			G.say("%s launched from %s: the %s" % [it["label"], entry["name"], nm], 1)
		"miner":
			var m := {"id": c.new_id(), "system": int(entry["system"]), "station": entry["key"]}
			c.miners.append(m)
			if st:
				var mc: Node3D = load("res://scripts/campaign/miner.gd").new()
				G.match_node.add_child(mc)
				mc.setup(st, m)
				G.match_node.miner_crafts.append(mc)
			G.say("A new mining craft is working out of %s" % entry["name"], 1)
		"vehicle":
			# parked in the station's vehicle depot: a supply ship or dropship loads it (LOAD VEHICLES)
			var dep: Array = entry.get("vehicles", [])
			dep.append(it["v"])
			entry["vehicles"] = dep
			G.say("%s ready in the %s vehicle depot (%d parked): load it aboard a supply ship or dropship with LOAD VEHICLES" % [it["label"], entry["name"], dep.size()], 1)
		"minidrop":
			# docks on a dropship with a free cradle (2 each); extras follow a dropship and dock when one leaves
			var drops: Array = c.fleet.filter(func(fe): return fe["cls"] == "SMALL_DROP_FRIGATE")
			if drops.is_empty():
				var q4: Array = entry.get("queue", [])
				q4.append({"item": item, "left": 30.0})
				entry["queue"] = q4
				G.say("A mini dropship needs a dropship to dock on: build one first", 1)
			else:
				var done := false
				for fe2 in drops:
					if int(fe2.get("minidrops", 0)) < 2:
						fe2["minidrops"] = int(fe2.get("minidrops", 0)) + 1
						G.say("A mini dropship docked on %s" % fe2["name"], 1)
						done = true
						break
				if not done:
					var pick: Dictionary = drops[randi() % drops.size()]
					pick["minidrop_reserve"] = int(pick.get("minidrop_reserve", 0)) + 1
					G.say("A mini dropship is following %s, waiting for a free cradle" % pick["name"], 1)
		"darter":
			entry["darters"] = int(entry.get("darters", 0)) + 1
			if st:
				st.set_meta("darters", entry["darters"])
			G.say("A new cargo Darter is flying from %s" % entry["name"], 1)
		"fighter", "bomber":
			var placed := false
			if G.match_node and here:                     # (a carrier in the station's own system)
				var ships: Array = G.vessels.filter(func(v): return v.kind == "ship" and v.team == 1 and not v.destroyed)
				ships.sort_custom(func(a, b): return a.global_position.distance_to(base) < b.global_position.distance_to(base))
				for s2 in ships:
					for i in s2.pads.size():
						if s2.pads[i]["parked"] == null:
							s2.park_fighter(i, "FIGHTER" if it["kind"] == "fighter" else "BOMBER")
							G.say("A new %s is on %s's hangar deck" % [it["kind"], s2.display_name], 1)
							placed = true
							break
					if placed:
						break
			if not placed:
				var q2: Array = entry.get("queue", [])
				q2.append({"item": item, "left": 20.0})       # no free pad yet: wait and try again
				entry["queue"] = q2
				if int(entry.get("hangar_note", -1)) != int(c.day / 60.0):
					entry["hangar_note"] = int(c.day / 60.0)              # (say it now and then, not every retry)
					G.say("The new %s waits at %s for a carrier with a free hangar pad" % [it["kind"], entry["name"]], 1)
		"troops":
			if st:
				st.reserve += 6
			else:
				entry["reserve"] = int(entry.get("reserve", 0)) + 6
			G.say("Six troops are ready in the barracks at %s" % entry["name"], 1)
	G.stat("built_" + item)


# ------------------------------------------------------------------ station segments

static func snap(local: Vector3) -> Vector3:
	return Vector3(round(local.x / GRID) * GRID, 0, round(local.z / GRID) * GRID)


## Can a segment go at this (snapped) spot: touching the station or another segment, not overlapping?
static func spot_ok(st: Node, entry: Dictionary, p: Vector3) -> bool:
	var core: AABB = st.aabb
	var core_flat := Rect2(Vector2(core.position.x, core.position.z), Vector2(core.size.x, core.size.z))
	if core_flat.grow(4.0).has_point(Vector2(p.x, p.z)):
		return false                                   # inside the station itself
	for sg in entry.get("segments", []):
		if Vector2(p.x - float(sg["x"]), p.z - float(sg["z"])).length() < GRID * 0.5:
			return false                               # taken
	if core_flat.grow(GRID * 0.75).has_point(Vector2(p.x, p.z)):
		return true                                    # alongside the station
	for sg in entry.get("segments", []):
		if Vector2(p.x - float(sg["x"]), p.z - float(sg["z"])).length() < GRID * 1.05:
			return true                                # next to another segment
	return false


static func place(st: Node, entry: Dictionary, type: String, p: Vector3) -> String:
	var spec: Dictionary = SEGMENTS[type]
	if not spot_ok(st, entry, p):
		return "Segments must snap next to the station or another segment"
	if not can_afford(spec):
		return "Not enough in the stores (%d alloys, %d circuitry)" % [spec["alloys"], spec["circuitry"]]
	pay(spec)
	var segs: Array = entry.get("segments", [])
	segs.append({"type": type, "x": p.x, "z": p.z})
	entry["segments"] = segs
	build_segment(st, type, p)
	if type == "barracks":
		st.reserve_cap += 20
	G.stat("segments_built")
	return "%s built" % spec["label"].get_slice(" (", 0)


static func _mat(c: Color, emit: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.6
	m.metallic = 0.3
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	return m


static func _box(parent: Node3D, size: Vector3, pos: Vector3, c: Color, emit: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(c, emit)
	mi.position = pos
	parent.add_child(mi)
	return mi


## The segment's model (a few blocks, a truss back to its neighbour) and, for gun
## platforms, a working station turret.
static func build_segment(st: Node, type: String, p: Vector3) -> Node3D:
	var spec: Dictionary = SEGMENTS[type]
	var sz: Vector3 = spec["size"]
	var col: Color = spec["color"]
	var root := Node3D.new()
	root.name = "Segment_%s" % type
	st.add_child(root)
	root.position = p + Vector3(0, st.aabb.get_center().y - st.aabb.size.y * 0.25, 0)
	_box(root, sz, Vector3(0, 0, 0), col)
	match type:
		"reactor":
			_box(root, Vector3(sz.x * 1.1, 2.0, sz.z * 1.1), Vector3(0, sz.y * 0.2, 0), Color(0.4, 0.75, 1.0), 3.0)
		"refinery":
			_box(root, Vector3(4, 16, 4), Vector3(sz.x * 0.3, sz.y, sz.z * 0.3), col.darkened(0.3))
			_box(root, Vector3(sz.x * 0.6, 2, 2), Vector3(0, sz.y * 0.5 + 1, 0), Color(1.0, 0.55, 0.2), 2.0)
		"shipyard":
			for k in [-1, 1]:
				_box(root, Vector3(2.5, 14, sz.z), Vector3(k * sz.x * 0.45, 7, 0), col.darkened(0.2))
			_box(root, Vector3(sz.x, 2, 3), Vector3(0, 14, -sz.z * 0.4), Color(1.0, 0.8, 0.3), 2.0)
		"storage":
			for k in 3:
				_box(root, Vector3(8, 6, sz.z * 0.8), Vector3((k - 1) * 9.0, sz.y * 0.5 + 3.0, 0), Color(0.6 - k * 0.08, 0.4, 0.3))
		"habitat":
			var ring := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = sz.x * 0.45
			tm.outer_radius = sz.x * 0.6
			ring.mesh = tm
			ring.material_override = _mat(col)
			ring.position.y = sz.y
			root.add_child(ring)
		"barracks":
			_box(root, Vector3(sz.x * 0.9, 1, 1), Vector3(0, sz.y * 0.2, sz.z * 0.5), Color(0.6, 0.9, 1.0), 2.5)
	# a truss back toward the station's middle
	var back: Vector3 = -Vector3(p.x, 0, p.z).normalized()
	_box(root, Vector3(3, 3, GRID * 0.5), back * GRID * 0.5, Color(0.3, 0.32, 0.35)).look_at_from_position(root.global_position + root.global_basis * (back * GRID * 0.5), root.global_position + root.global_basis * back * GRID, Vector3.UP)
	if type in ["defense", "ciws"]:
		var big := type == "defense"
		var yaw := MeshInstance3D.new()
		var hm := BoxMesh.new()
		hm.size = Vector3(7, 4, 8) if big else Vector3(3, 3, 3)
		yaw.mesh = hm
		yaw.material_override = _mat(Color(0.32, 0.34, 0.37))
		yaw.position = Vector3(0, sz.y * 0.5 + 2.0, 0)
		root.add_child(yaw)
		var bar := MeshInstance3D.new()
		var bb := BoxMesh.new()
		bb.size = Vector3(1.2, 1.2, 12.0) if big else Vector3(0.6, 0.6, 4.0)
		bar.mesh = bb
		bar.material_override = _mat(Color(0.2, 0.2, 0.22))
		bar.position = Vector3(0, 0.5, -bb.size.z * 0.5)
		yaw.add_child(bar)
		st.turrets.append({"node": yaw, "cool": 0.0, "rest_yaw": 0.0, "base_pos": yaw.position, "kick": 0.0,
			"bar": bar, "bar_rest": bar.position, "module": ""})
	return root
