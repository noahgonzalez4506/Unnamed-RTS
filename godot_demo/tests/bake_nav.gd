extends Node
## Bakes the navigation for every ship and station type into res://nav/ and checks it:
##   godot --headless --path . res://tests/bake_nav.tscn
## Run it again after re-exporting models. Each path is checked against the walls.
const SHIP := preload("res://scripts/ship.gd")
const STATION := preload("res://scripts/station.gd")
const JOBS := [["ships_F1/ship_LARGE.glb", "LARGE", SHIP], ["ships_F1/ship_SMALL_FRIGATE.glb", "SMALL_FRIGATE", SHIP],
	["ships_X/ship_XL.glb", "XL", SHIP], ["ships_F1/ship_MEDIUM.glb", "MEDIUM", SHIP],
	["stations_F1/STATION_FORTRESS.glb", "STATION_FORTRESS", STATION], ["stations_P/GROUND_FORT.glb", "GROUND_FORT", STATION],
	["ships_F1/ship_LARGE_v1.glb", "LARGE_v1", SHIP], ["ships_F1/ship_LARGE_v2.glb", "LARGE_v2", SHIP],
	["ships_F1/ship_LARGE_v3.glb", "LARGE_v3", SHIP], ["ships_F1/ship_MEDIUM_v1.glb", "MEDIUM_v1", SHIP],
	["ships_F1/ship_MEDIUM_v2.glb", "MEDIUM_v2", SHIP], ["ships_F1/ship_MEDIUM_v3.glb", "MEDIUM_v3", SHIP],
	["ships_F1/ship_SMALL_FRIGATE_v1.glb", "SMALL_FRIGATE_v1", SHIP], ["ships_F1/ship_SMALL_FRIGATE_v2.glb", "SMALL_FRIGATE_v2", SHIP],
	["ships_F1/ship_SMALL_FRIGATE_v3.glb", "SMALL_FRIGATE_v3", SHIP], ["ships_X/ship_XL_v1.glb", "XL_v1", SHIP],
	["ships_X/ship_XL_v2.glb", "XL_v2", SHIP], ["ships_X/ship_XL_v3.glb", "XL_v3", SHIP],
	["ships_F1/ship_SMALL_SUPPORT.glb", "SMALL_SUPPORT", SHIP], ["ships_F1/ship_SMALL_SUPPORT_v1.glb", "SMALL_SUPPORT_v1", SHIP],
	["ships_F1/ship_SMALL_SUPPORT_v2.glb", "SMALL_SUPPORT_v2", SHIP], ["ships_F1/ship_SMALL_SUPPORT_v3.glb", "SMALL_SUPPORT_v3", SHIP],
	["ships_F1/ship_SMALL_DROP_FRIGATE.glb", "SMALL_DROP_FRIGATE", SHIP], ["ships_F1/ship_SMALL_DROP_FRIGATE_v1.glb", "SMALL_DROP_FRIGATE_v1", SHIP],
	["ships_F1/ship_SMALL_DROP_FRIGATE_v2.glb", "SMALL_DROP_FRIGATE_v2", SHIP], ["ships_F1/ship_SMALL_DROP_FRIGATE_v3.glb", "SMALL_DROP_FRIGATE_v3", SHIP],
	["stations_P/GROUND_MINE.glb", "GROUND_MINE", STATION],
	["stations_F1/STATION_STARTER.glb", "STATION_STARTER", STATION], ["stations_F1/STATION_FUEL_HUB.glb", "STATION_FUEL_HUB", STATION],
	["stations_F1/STATION_INDUSTRIAL.glb", "STATION_INDUSTRIAL", STATION], ["stations_F1/OUTPOST_MINING.glb", "OUTPOST_MINING", STATION],
	["stations_F1/STATION_STARTER_2.glb", "STATION_STARTER_2", STATION], ["stations_F1/STATION_STARTER_3.glb", "STATION_STARTER_3", STATION]]


func _ready() -> void:
	G.reset()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://nav"))
	var only: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("cell="):
			G.set_meta("nav_cell", float(a.substr(5)))
		elif a != "":
			only.append(a)
	for j in JOBS:
		if not only.is_empty() and not (j[1] in only):
			continue
		var v: Node3D = load("res://models/" + j[0]).instantiate()
		v.set_script(j[2])
		add_child(v)
		if j[2] == SHIP:
			var bits: PackedStringArray = String(j[1]).split("_v")
			v.variant = int(bits[1]) if bits.size() > 1 else 0
			v.setup_ship(bits[0], 1, 1, j[1])
		else:
			v.setup_station(j[1], 1, 1, j[1])
		var t0 := Time.get_ticks_msec()
		print("NAV start ", j[1])
		var nm: NavigationMesh = v.make_navmesh()
		print("NAV baked ", j[1], " in ", Time.get_ticks_msec() - t0, " ms")
		ResourceSaver.save(nm, "res://nav/%s.res" % j[1])
		v.use_navmesh(nm)
		for f in 60:
			await get_tree().physics_frame

		print("NAV map ready: ", v.nav_ok(), " iter ", NavigationServer3D.map_get_iteration_id(v.nav_map), " regions ", NavigationServer3D.map_get_regions(v.nav_map).size(), " cell ", NavigationServer3D.map_get_cell_size(v.nav_map), " nm cell ", nm.cell_size)
		var ra: Vector3 = v.random_local()
		var rb: Vector3 = v.random_local()
		print("NAV sample ", ra, " ", rb, " path ", v.path_local(ra, rb).size())
		var bad := 0
		var n := 0
		for i in 60:
			var a: Vector3 = v.random_local()
			var b: Vector3 = v.random_local()
			var p: PackedVector3Array = v.path_local(a, b)
			for k in range(1, p.size()):
				var h := G.ray(v.to_global(p[k - 1]) + Vector3.UP * 0.9, v.to_global(p[k]) + Vector3.UP * 0.9, [], G.LAYER_WORLD)
				n += 1
				if not h.is_empty():
					bad += 1
					if bad <= 4:
						print("NAVBAD ", h.collider.get_parent().name, " at ", v.to_local(h.position), " seg ", p[k - 1], " -> ", p[k])
		# the troop deck must connect to deck 0 by the access ramps
		var tb: Node3D = v.mark("TroopDeck_Walkway")
		var d0: Node3D = v.mark("PlayerSpawn_Deck0")
		if tb and d0:
			var a2: Vector3 = v.snap_local(v.local_of(tb))
			var b2: Vector3 = v.snap_local(v.local_of(d0))
			var tp: PackedVector3Array = v.path_local(a2, b2)
			var ok: bool = tp.size() > 1 and tp[tp.size() - 1].distance_to(b2) < 1.0 and absf(a2.y - v.local_of(tb).y) < 0.6
			print("NAV %s troop deck to deck 0: %s" % [j[1], "OK" if ok else "NO PATH"])
		print("NAV %-18s %5d ms  polys %5d  path segments through walls: %d of %d" % [j[1], Time.get_ticks_msec() - t0,
			nm.get_polygon_count(), bad, n])
		v.queue_free()
	G.quit()
