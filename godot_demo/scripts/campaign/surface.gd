extends RefCounted
## Planet surfaces: their own loaded worldspace, entered like a jump. A landing zone has
## 1-3 base locations; each holds an installation (outlaw camp, infected hive, colony,
## Ascendancy outpost, ruins) or lies open. Small ships, supply ships, mediums and the
## dropship can come down (they fly low and slow here); bases are fair game for ODST pods,
## the dropship's artillery and boarding parties, the same as anywhere.
##
##   campaign.surface = {"planet": i, "site": j}   while the player is down on a world

const GALAXY := preload("res://scripts/campaign/galaxy.gd")
const LANDERS := ["SMALL_FRIGATE", "SMALL_SUPPORT", "SMALL_DROP_FRIGATE", "MEDIUM"]
const GROUND_Y := -160.0              # ships fly over the terrain at y = 0
const AREA := 3400.0                  # the same scale as space: about 7 km across


static func planet_def(c) -> Dictionary:
	return c.system()["planets"][int(c.surface["planet"])]


static func site_def(c) -> Dictionary:
	var pl := planet_def(c)
	return pl["sites"][int(c.surface["site"])] if int(c.surface["site"]) < pl["sites"].size() else {}


static func layout(c) -> Dictionary:
	var pl := planet_def(c)
	var site := site_def(c)
	var b: Dictionary = GALAXY.BIOMES[pl["biome"]]
	var r := RandomNumberGenerator.new()
	r.seed = int(pl["seed"]) + int(c.surface["site"]) * 977
	var L := {"name": "%s, %s" % [site.get("name", pl["name"]), b["label"]], "nebula": (b["atmo"] as Color),
		"planet": {}, "fields": [], "field_mine": -1, "surface": true, "biome": pl["biome"], "seed": r.randi()}
	L["sun_rot"] = Vector3(r.randf_range(-60.0, -30.0), r.randf_range(0.0, 360.0), 0)
	L["sun_color"] = Color(1.0, 0.95, 0.88)
	# 1-3 base locations, spread out
	var n: int = 1 + r.randi() % 3
	var bases: Array = []
	for i in n:
		var a := r.randf() * TAU
		var p := Vector3(cos(a), 0, sin(a)) * r.randf_range(900.0, 2400.0)
		for k in 20:
			var ok := true
			for q in bases:
				if (q["pos"] as Vector3).distance_to(p) < 1300.0:
					ok = false
			if ok:
				break
			a = r.randf() * TAU
			p = Vector3(cos(a), 0, sin(a)) * r.randf_range(900.0, 2400.0)
		var kind: String = (site.get("kind", "outpost_site") if site.get("kind", "") != "ruins" else "pirate_camp") if i == 0 else ["pirate_camp", "colony", "pirate_camp", "outpost_site", "hive"][r.randi() % 5]
		if pl["biome"] == "infected":
			kind = "hive"
		bases.append({"pos": p + Vector3(0, GROUND_Y, 0), "kind": kind, "key": "%s_%d_%d_%d" % [c.current, int(c.surface["planet"]), int(c.surface["site"]), i]})
	L["bases"] = bases
	L["landing"] = Vector3(r.randf_range(-400, 400), 0, r.randf_range(-400, 400))
	# an abandoned city on about two worlds in five, away from the bases and the landing zone
	var rc := RandomNumberGenerator.new()
	rc.seed = int(L["seed"]) + 991
	if rc.randf() < 0.45 and pl["biome"] != "gas":
		var cc := Vector3.ZERO
		for t in 40:
			var a2 := rc.randf() * TAU
			cc = Vector3(cos(a2), 0, sin(a2)) * rc.randf_range(1200.0, 2300.0)
			var ok2 := true
			for bs in bases:
				if Vector2(cc.x - bs["pos"].x, cc.z - bs["pos"].z).length() < 1000.0:
					ok2 = false
			if Vector2(cc.x - L["landing"].x, cc.z - L["landing"].z).length() < 1100.0:
				ok2 = false
			if ok2:
				break
		L["city_site"] = {"center": cc, "radius": 330.0}
	return L


static func populate(m: Node) -> void:
	var c = G.campaign
	var L: Dictionary = m.system
	G.standing = c.standing
	G.team_names = {1: c.company}
	G.resources[1] = c.stores
	for t in [2, 5, 6, 7]:
		G.resources[t] = {"alloys": 99999.0, "circuitry": 9999.0, "cores": 999.0}
	var P: Dictionary = _ground(m, L)
	m.terrain_P = P
	load("res://scripts/campaign/ruins.gd").build(m, L, P)
	# outlaw camps and infected hives are built right onto the ground (part of its navigation)
	var CAMPS = load("res://scripts/campaign/camps.gd")
	for bs in L["bases"]:
		var w0: Dictionary = c.world.get(bs["key"], {})
		if w0.get("destroyed", false):
			continue
		var t0: int = int(w0.get("team", {"pirate_camp": 3, "hive": 4}.get(bs["kind"], 0)))
		if t0 == 4:
			CAMPS.hive(m, bs["pos"], bs["key"], L, P)
			bs["built"] = true
			if w0.get("gravemind", false) and not m.city.is_empty():
				CAMPS.gravemind(m, m.city["center"], bs["key"], L, P)
		elif bs["kind"] == "pirate_camp" and t0 == 3:
			CAMPS.outlaw_camp(m, bs["pos"], bs["key"], L, P)
			bs["built"] = true
	load("res://scripts/campaign/outposts.gd").restore(m)    # our own outposts on this world
	_flora(m, L, P, float(P["sea_h"]))
	# the open ground: infantry walk it (terrain, wrecks and ruins become its colliders)
	var gnd: Node3D = load("res://scripts/campaign/ground.gd").new()
	gnd.name = "Ground"
	m.add_child(gnd)
	for ch in m.get_children():
		if ch is StaticBody3D:
			ch.reparent(gnd, true)
	var areas: Array = [[Vector3(L["landing"].x, GROUND_Y, L["landing"].z), 330.0]]
	for bs in L["bases"]:
		areas.append([Vector3(bs["pos"].x, GROUND_Y, bs["pos"].z) + Vector3(0, 0, 0), 300.0])
	if not m.city.is_empty():
		areas.append([m.city["center"], float(m.city["radius"])])
	gnd.setup_ground(areas)
	gnd.cover = m.ground_cover
	m.ground = gnd
	# the bases
	for bs in L["bases"]:
		var w: Dictionary = c.world.get(bs["key"], {})
		if w.get("destroyed", false) or bs.get("built", false) or w.get("outpost", false):
			continue
		var kind: String = bs["kind"]
		var team: int = int(w.get("team", {"pirate_camp": 3, "hive": 4, "colony": 6, "asc_outpost": 2, "ruins": 0, "outpost_site": 0}.get(kind, 0)))
		if team == 0:
			_marker(m, bs["pos"], "OPEN BASE LOCATION" if kind == "outpost_site" else "RUINS")
			continue
		if team in [3, 4]:
			continue                                   # (outlaws and the infection only ever build on the ground: camps.gd)
		var cls := "GROUND_FORT" if kind in ["pirate_camp", "hive", "asc_outpost"] else "GROUND_MINE"
		var fac: int = {3: 3, 4: 3, 2: 2}.get(team, 1)
		var crew: Array = m.PIRATE_FORT_CREW if team in [3, 2] else (["engineer", "cargo_handler", "security"] if team != 4 else [])
		var v: Node3D = m._station(cls, team, fac, {"pirate_camp": "Outlaw Camp", "hive": "Infected Hive", "colony": "Colony Works",
			"asc_outpost": "Ascendancy Outpost"}.get(kind, "Outpost"), bs["pos"], crew)
		v.set_meta("key", bs["key"])
		v.set_meta("spawn_team", team)                 # (snapshot records a capture against this)
		if team == 2:
			for kk in ["tank", "mrap_ai", "ifv"]:
				m.ground_vehicles.append([bs["pos"] + Vector3(randf_range(-150, 150), 0, randf_range(-150, 150)), kk, 2, 2])
		if team == 4:
			m.derelicts.append(v)                      # (overrun by the infection once crews spawn)
	# the ships that came down
	var k := 0
	for e in c.fleet:
		if int(e["system"]) != c.current or not c.landed_here(e):
			continue
		var p: Vector3 = L["landing"] + Vector3((k % 3) * 220.0, 0, (k / 3) * 260.0)
		k += 1
		var s2: Node3D = m._ship(e["cls"], 1, int(e.get("fac", 1)), e["name"], p, load("res://scripts/campaign/sector.gd").crew_for(e), int(e.get("variant", 0)))
		m.restore_hangar(s2, e)
		s2.hull = s2.max_hull * float(e.get("hull", 1.0))
		s2.troops = mini(s2.berth_cap, int(e.get("troops", s2.troops)))
		s2.supplies = float(e.get("supplies", s2.supplies))
		s2.set_meta("fleet_id", int(e["id"]))
		m.restore_ship_infection(s2, e)
		s2.speed *= 0.4                                # low and slow in the atmosphere


## Terrain: rolling ground, ridged mountains toward the edges and valleys between, all from
## the landing zone's own seed (every world, and every zone on it, looks different). Level
## pads under the bases and the landing zone; trees, bushes, grass and rocks by biome.
static func _terrain_params(L: Dictionary) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = int(L["seed"])
	var base := FastNoiseLite.new()
	base.seed = r.randi()
	base.frequency = r.randf_range(0.00035, 0.0008)
	base.fractal_octaves = 5
	var ridge := FastNoiseLite.new()
	ridge.seed = r.randi()
	ridge.frequency = r.randf_range(0.0004, 0.0009)
	ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridge.fractal_octaves = 4
	var warp := FastNoiseLite.new()
	warp.seed = r.randi()
	warp.frequency = 0.0004
	return {"base": base, "ridge": ridge, "warp": warp, "amp": r.randf_range(60.0, 110.0),
		"mount": r.randf_range(80.0, 150.0), "edge": r.randf_range(0.4, 1.0)}


## Ground height (relative to GROUND_Y) at x, z.
static func height(P: Dictionary, L: Dictionary, x: float, z: float) -> float:
	var wx: float = x + (P["warp"] as FastNoiseLite).get_noise_2d(x, z) * 300.0
	var wz: float = z + (P["warp"] as FastNoiseLite).get_noise_2d(z + 999.0, x) * 300.0
	var h: float = (P["base"] as FastNoiseLite).get_noise_2d(wx, wz) * float(P["amp"])
	var rg: float = maxf(0.0, (P["ridge"] as FastNoiseLite).get_noise_2d(wx, wz))
	var edge: float = clampf((Vector2(x, z).length() - AREA * 0.55) / (AREA * 0.7), 0.0, 1.0) * float(P["edge"])
	h += rg * float(P["mount"]) * (0.35 + edge)
	h += edge * 120.0
	var flat := 1.0
	for bs in L["bases"]:
		flat = minf(flat, clampf((Vector2(x - bs["pos"].x, z - bs["pos"].z).length() - 260.0) / 420.0, 0.0, 1.0))
	flat = minf(flat, clampf((Vector2(x - L["landing"].x, z - L["landing"].z).length() - 500.0) / 500.0, 0.0, 1.0))
	if L.has("city_site"):                               # the city sits on level ground
		var cs: Dictionary = L["city_site"]
		flat = minf(flat, clampf((Vector2(x - cs["center"].x, z - cs["center"].z).length() - float(cs["radius"]) - 40.0) / 380.0, 0.0, 1.0))
	return minf(h * flat, 135.0)                       # (ships fly over it at y = 0)


static func _ground(m: Node, L: Dictionary) -> Dictionary:
	var b: Dictionary = GALAXY.BIOMES[L["biome"]]
	var cols: Array = b["cols"]
	var P := _terrain_params(L)
	var pm := PlaneMesh.new()
	pm.size = Vector2(AREA * 2.6, AREA * 2.6)
	pm.subdivide_width = 200
	pm.subdivide_depth = 200
	var st := SurfaceTool.new()
	st.create_from(pm, 0)
	var arr: Array = st.commit_to_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var colors := PackedColorArray()
	var sea_h: float = -9999.0 if float(b["sea"]) < 0.2 else -float(P["amp"]) * 0.35
	for k in verts.size():
		var v := verts[k]
		var y := height(P, L, v.x, v.z)
		verts[k] = Vector3(v.x, y, v.z)
		var t := clampf((y + 80.0) / 260.0, 0.0, 1.0)
		var low: Color = (cols[2] as Color).darkened(0.15) if sea_h > -9000.0 else (cols[1] as Color)
		var col: Color = low.lerp(cols[2], smoothstep(0.3, 0.55, t)).lerp(cols[3], smoothstep(0.75, 0.92, t))
		if y < sea_h + 4.0:
			col = (cols[1] as Color).lerp(Color(0.8, 0.75, 0.55), 0.5)            # shore
		col = col.darkened(randf() * 0.06)
		colors.append(col)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_NORMAL] = null
	_minimap_image(m, verts, colors, sea_h, cols[0], AREA * 1.3)
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var st2 := SurfaceTool.new()
	st2.create_from(am, 0)
	st2.generate_normals()
	var mesh := st2.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mi.material_override = mat
	mi.position.y = GROUND_Y - 2.0
	m.add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = G.LAYER_WORLD
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)
	body.position.y = GROUND_Y - 2.0
	m.add_child(body)
	if sea_h > -9000.0:
		var wm := MeshInstance3D.new()
		var wp := PlaneMesh.new()
		wp.size = Vector2(AREA * 2.6, AREA * 2.6)
		wm.mesh = wp
		var wmat := StandardMaterial3D.new()
		wmat.albedo_color = Color((cols[0] as Color).r, (cols[0] as Color).g, (cols[0] as Color).b, 0.85)
		wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		wmat.roughness = 0.1
		wmat.metallic = 0.3
		if L["biome"] == "lava":
			wmat.emission_enabled = true
			wmat.emission = Color(1.0, 0.35, 0.05)
			wmat.emission_energy_multiplier = 2.0
		wm.material_override = wmat
		wm.position.y = GROUND_Y - 2.0 + sea_h
		m.add_child(wm)
	P["sea_h"] = sea_h
	return P


## The minimap's backdrop for this landing zone: the terrain's own colours from above, water
## where the sea covers it, a little hill shading. Kept on the match as meta "ground_map"
## (an ImageTexture covering +-half metres).
static func _minimap_image(m: Node, verts: PackedVector3Array, colors: PackedColorArray, sea_h: float, water: Color, half: float) -> void:
	const N := 160
	var img := Image.create(N, N, false, Image.FORMAT_RGB8)
	var hgt := PackedFloat32Array()
	hgt.resize(N * N)
	hgt.fill(-1.0e9)
	for k in verts.size():
		var v := verts[k]
		var px := clampi(int((v.x / half * 0.5 + 0.5) * N), 0, N - 1)
		var pz := clampi(int((v.z / half * 0.5 + 0.5) * N), 0, N - 1)
		var col: Color = colors[k]
		if v.y < sea_h:
			col = water.lerp(Color(0.05, 0.1, 0.2), clampf((sea_h - v.y) / 60.0, 0.0, 0.6))
		img.set_pixel(px, pz, col)
		hgt[pz * N + px] = maxf(hgt[pz * N + px], v.y)
	for z in N:                                          # light from the north-west
		for x in N:
			var h0: float = hgt[z * N + x]
			var h1: float = hgt[maxi(z - 1, 0) * N + maxi(x - 1, 0)]
			if h0 > -1.0e8 and h1 > -1.0e8 and h0 > sea_h:
				var c: Color = img.get_pixel(x, z)
				img.set_pixel(x, z, c.lightened(clampf((h0 - h1) / 40.0, 0.0, 0.25)) if h0 >= h1 else c.darkened(clampf((h1 - h0) / 40.0, 0.0, 0.3)))
	m.set_meta("ground_map", ImageTexture.create_from_image(img))
	m.set_meta("ground_map_half", half)


# ------------------------------------------------------------------ trees, bushes, grass, rocks

const FLORA := {
	"jungle": {"tree": 3200, "bush": 4000, "grass": 12000, "rock": 600, "tree_kind": "broad"},
	"ocean": {"tree": 1400, "bush": 1800, "grass": 7000, "rock": 500, "tree_kind": "palm"},
	"desert": {"tree": 250, "bush": 900, "grass": 2500, "rock": 2600, "tree_kind": "cactus"},
	"ice": {"tree": 1400, "bush": 300, "grass": 0, "rock": 2200, "tree_kind": "pine"},
	"lava": {"tree": 0, "bush": 300, "grass": 0, "rock": 3200, "tree_kind": "dead"},
	"barren": {"tree": 0, "bush": 0, "grass": 0, "rock": 3800, "tree_kind": "dead"},
	"infected": {"tree": 1600, "bush": 2400, "grass": 5000, "rock": 1200, "tree_kind": "spire"},
	"gas": {"tree": 0, "bush": 0, "grass": 0, "rock": 0, "tree_kind": "dead"},
}


static func _part(st: SurfaceTool, mesh: Mesh, xf: Transform3D, col: Color) -> void:
	var a: Array = mesh.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	for i in idx:
		st.set_color(col)
		st.set_normal((xf.basis * n[i]).normalized())
		st.add_vertex(xf * v[i])


static func _model(kind: String, cols: Array) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.35
	trunk.bottom_radius = 0.6
	trunk.height = 6.0
	trunk.radial_segments = 6
	var bark := Color(0.32, 0.22, 0.14)
	match kind:
		"broad":
			_part(st, trunk, Transform3D(Basis(), Vector3(0, 3, 0)), bark)
			var crown := SphereMesh.new()
			crown.radius = 3.6
			crown.height = 5.5
			crown.radial_segments = 8
			crown.rings = 5
			_part(st, crown, Transform3D(Basis(), Vector3(0, 7.5, 0)), Color(0.16, 0.38, 0.14))
			_part(st, crown, Transform3D(Basis().scaled(Vector3.ONE * 0.7), Vector3(1.8, 6.4, 0.6)), Color(0.2, 0.44, 0.16))
		"palm":
			_part(st, trunk, Transform3D(Basis(Vector3.FORWARD, 0.12).scaled(Vector3(0.7, 1.6, 0.7)), Vector3(0.5, 4.5, 0)), Color(0.45, 0.35, 0.22))
			var leaf := BoxMesh.new()
			leaf.size = Vector3(0.6, 0.15, 5.0)
			for k in 6:
				var bs := Basis(Vector3.UP, k * TAU / 6.0) * Basis(Vector3.RIGHT, 0.45)
				_part(st, leaf, Transform3D(bs, Vector3(1.0, 9.2, 0) + bs * Vector3(0, 0, 2.2)), Color(0.22, 0.5, 0.18))
		"pine":
			_part(st, trunk, Transform3D(Basis(), Vector3(0, 2, 0)), bark)
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 2.8
			cone.height = 9.0
			cone.radial_segments = 7
			_part(st, cone, Transform3D(Basis(), Vector3(0, 7, 0)), Color(0.15, 0.3, 0.22).lerp(Color(0.9, 0.95, 1.0), 0.35))
		"cactus":
			var c := CylinderMesh.new()
			c.top_radius = 0.5
			c.bottom_radius = 0.6
			c.height = 5.0
			c.radial_segments = 7
			_part(st, c, Transform3D(Basis(), Vector3(0, 2.5, 0)), Color(0.3, 0.45, 0.25))
			_part(st, c, Transform3D(Basis().scaled(Vector3(0.7, 0.45, 0.7)), Vector3(1.0, 3.0, 0)), Color(0.3, 0.45, 0.25))
		"spire":
			var sp := CylinderMesh.new()
			sp.top_radius = 0.0
			sp.bottom_radius = 1.4
			sp.height = 11.0
			sp.radial_segments = 6
			_part(st, sp, Transform3D(Basis(Vector3.FORWARD, 0.15), Vector3(0, 5.5, 0)), Color(0.45, 0.15, 0.55))
			var bulb := SphereMesh.new()
			bulb.radius = 1.2
			bulb.height = 2.4
			bulb.radial_segments = 6
			bulb.rings = 4
			_part(st, bulb, Transform3D(Basis(), Vector3(0.6, 8.0, 0)), Color(0.85, 0.35, 1.0))
		"bush":
			var bsh := SphereMesh.new()
			bsh.radius = 1.3
			bsh.height = 1.8
			bsh.radial_segments = 6
			bsh.rings = 4
			_part(st, bsh, Transform3D(Basis(), Vector3(0, 0.7, 0)), (cols[1] as Color).lerp(Color(0.2, 0.4, 0.15), 0.6))
			_part(st, bsh, Transform3D(Basis().scaled(Vector3.ONE * 0.7), Vector3(0.9, 0.5, 0.3)), (cols[1] as Color).lerp(Color(0.25, 0.45, 0.18), 0.5))
		"grass":
			var blade := BoxMesh.new()
			blade.size = Vector3(0.08, 0.9, 0.02)
			for k in 5:
				var bs2 := Basis(Vector3.UP, k * 1.3) * Basis(Vector3.RIGHT, 0.25)
				_part(st, blade, Transform3D(bs2, Vector3(cos(k * 1.3) * 0.25, 0.45, sin(k * 1.3) * 0.25)), (cols[1] as Color).lightened(0.15))
	return st.commit()


static func _scatter(m: Node, mesh: Mesh, n: int, L: Dictionary, P: Dictionary, sea_h: float, smin: float, smax: float,
		r: RandomNumberGenerator, mat: Material, max_slope_h: float = 999.0) -> void:
	if n <= 0:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = n
	var placed := 0
	var tries := 0
	while placed < n and tries < n * 3:
		tries += 1
		# mostly round the landing zone, the bases and the city; a light scatter elsewhere
		var x := 0.0
		var z := 0.0
		if r.randf() < 0.85:
			var hubs: Array = [L["landing"]]
			for bs in L["bases"]:
				hubs.append(bs["pos"])
			if G.match_node and not G.match_node.city.is_empty():
				hubs.append(G.match_node.city["center"] + Vector3(G.match_node.city["radius"] + 200.0, 0, 0))
			var hb: Vector3 = hubs[r.randi() % hubs.size()]
			var a := r.randf() * TAU
			var rad := sqrt(r.randf()) * 900.0
			x = hb.x + cos(a) * rad
			z = hb.z + sin(a) * rad
		else:
			x = r.randf_range(-AREA * 1.25, AREA * 1.25)
			z = r.randf_range(-AREA * 1.25, AREA * 1.25)
		var near := false
		for bs in L["bases"]:
			if Vector2(x - bs["pos"].x, z - bs["pos"].z).length() < 300.0:
				near = true
		if near or Vector2(x - L["landing"].x, z - L["landing"].z).length() < 520.0:
			continue
		if G.match_node and not G.match_node.city.is_empty() and Vector2(x - G.match_node.city["center"].x, z - G.match_node.city["center"].z).length() < float(G.match_node.city["radius"]):
			continue                                    # (the streets stay clear)
		var y := height(P, L, x, z)
		if y < sea_h + 3.0 or y > max_slope_h:
			continue
		var s := r.randf_range(smin, smax)
		var bs3 := Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3.ONE * s)
		mm.set_instance_transform(placed, Transform3D(bs3, Vector3(x, GROUND_Y - 2.0 + y - 0.3, z)))
		placed += 1
	mm.visible_instance_count = placed
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if smax < 2.0 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mi.visibility_range_end = 900.0 if smax < 2.0 else 3200.0
	m.add_child(mi)


static func _flora(m: Node, L: Dictionary, P: Dictionary, sea_h: float) -> void:
	var f: Dictionary = FLORA.get(L["biome"], FLORA["barren"])
	var cols: Array = GALAXY.BIOMES[L["biome"]]["cols"]
	var r := RandomNumberGenerator.new()
	r.seed = int(L["seed"]) + 31
	var vmat := StandardMaterial3D.new()
	vmat.vertex_color_use_as_albedo = true
	vmat.roughness = 0.9
	if L["biome"] == "infected":
		vmat.emission_enabled = true
		vmat.emission = Color(0.5, 0.15, 0.6)
		vmat.emission_energy_multiplier = 0.6
	_scatter(m, _model(f["tree_kind"], cols), int(f["tree"] * 0.5), L, P, sea_h, 0.8, 1.9, r, vmat, 110.0)
	_scatter(m, _model("bush", cols), int(f["bush"] * 0.45), L, P, sea_h, 0.6, 1.6, r, vmat)
	_scatter(m, _model("grass", cols), int(f["grass"] * 0.35), L, P, sea_h, 0.8, 1.6, r, vmat, 90.0)
	var rr := RandomNumberGenerator.new()
	rr.seed = int(L["seed"]) + 77
	var rock: Mesh = load("res://scripts/system_gen.gd")._rock_mesh(rr)
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = (cols[2] as Color).darkened(0.25)
	rmat.roughness = 0.95
	_scatter(m, rock, int(f["rock"] * 0.5), L, P, sea_h - 100.0, 0.6, 6.0, r, rmat)


static func _marker(m: Node, p: Vector3, text: String) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 90.0
	tm.outer_radius = 96.0
	ring.mesh = tm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.9, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.9, 1.0)
	mat.emission_energy_multiplier = 1.5
	ring.material_override = mat
	ring.position = p + Vector3.UP * 0.5
	m.add_child(ring)
	var lab := Label3D.new()
	lab.text = text
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.font_size = 64
	lab.pixel_size = 0.5
	lab.no_depth_test = true
	lab.modulate = Color(0.6, 0.95, 1.0)
	lab.position = p + Vector3.UP * 60.0
	m.add_child(lab)
