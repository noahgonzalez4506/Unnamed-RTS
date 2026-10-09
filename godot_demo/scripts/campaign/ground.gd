extends "res://scripts/vessel.gd"
## The open ground of a landing zone, as a "vessel" infantry can live on: soldiers walk the
## terrain, the streets of ruined cities and round the wrecks with the same brains they use
## aboard ships. Navigation is baked only where there's something to do (the landing zone,
## the bases, the city), each its own walkable area.

var areas: Array = []              # [centre (local), radius]


func setup_ground(areas_: Array) -> void:
	kind = "ground"
	team = 0
	faction = 1
	cls = "GROUND"
	display_name = "the surface"
	areas = areas_
	aabb = AABB(Vector3(-4600, -500, -4600), Vector3(9200, 1000, 9200))


## The whole landing zone is walkable, in 160 m tiles: the tiles round the landing zone,
## bases and city are baked before anyone sets foot down; the rest bake in the background
## (corridors between them first, then outward), so convoys can go anywhere in the zone.
const TILE := 320.0
const CELL := 0.8
var _src: NavigationMeshSourceGeometryData3D
var _proto: NavigationMesh
var _queue: Array = []             # Vector2i tiles waiting to bake
var _done := {}                    # Vector2i -> true
var _busy := 0
var tiles_total := 0
var _bake_cd := 0.0


func _tile_of(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / TILE)), int(floor(p.z / TILE)))


func _tile_mesh(t: Vector2i) -> NavigationMesh:
	var nm: NavigationMesh = _proto.duplicate()
	# bake a border round the tile and trim it off: neighbouring tiles' edges then line up exactly
	var b: float = _proto.border_size
	nm.filter_baking_aabb = AABB(Vector3(t.x * TILE - b, -400.0, t.y * TILE - b), Vector3(TILE + b * 2.0, 800.0, TILE + b * 2.0))
	return nm


var _regions := {}                 # tile -> region RID (so a tile can be rebaked)
var _nm_tile := {}                 # baking navmesh -> tile


func _add_region(nm: NavigationMesh, t: Vector2i = Vector2i(-99999, -99999)) -> void:
	if t == Vector2i(-99999, -99999) and _nm_tile.has(nm):
		t = _nm_tile[nm]
		_nm_tile.erase(nm)
	var reg := NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(reg, nav_map)
	NavigationServer3D.region_set_navigation_mesh(reg, nm)
	if t != Vector2i(-99999, -99999):
		if _regions.has(t):
			NavigationServer3D.free_rid(_regions[t])
		_regions[t] = reg
	else:
		_loose_regions.append(reg)


var _loose_regions: Array = []     # regions with no tile (freed with the ground)


func _free_nav() -> void:
	_queue.clear()
	for t in _regions:
		NavigationServer3D.free_rid(_regions[t])
	_regions.clear()
	for reg in _loose_regions:
		NavigationServer3D.free_rid(reg)
	_loose_regions.clear()
	super()


## Something was built on the ground at runtime (a player outpost structure): carve its
## footprint out of the navigation and rebake the tiles under it in the background.
func add_obstacle(center: Vector3, size: Vector2, yaw: float) -> void:
	if _src == null:
		return
	var b := Basis(Vector3.UP, yaw)
	var hx := size.x * 0.5 + CELL
	var hz := size.y * 0.5 + CELL
	var pts := PackedVector3Array()
	for c in [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz)]:
		pts.append(center + b * c)
	_src.add_projected_obstruction(pts, center.y - 2.0, 8.0, true)
	var tiles := {}
	for p in pts:
		tiles[_tile_of(p)] = true
	for t in tiles:
		var nm := _tile_mesh(t)
		_nm_tile[nm] = t
		_done[t] = true
		_busy += 1
		NavigationServer3D.bake_from_source_geometry_data_async(nm, _src,
			Callable(G, "nav_tile_baked").bind(nav_map, nm, weakref(self)))


func bake_ground() -> void:
	var t0 := Time.get_ticks_msec()
	nav_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_cell_size(nav_map, CELL)
	NavigationServer3D.map_set_cell_height(nav_map, 0.3)
	NavigationServer3D.map_set_edge_connection_margin(nav_map, 1.2)
	NavigationServer3D.map_set_active(nav_map, true)
	_proto = NavigationMesh.new()
	_proto.cell_size = CELL
	_proto.cell_height = 0.3
	_proto.agent_radius = CELL
	_proto.agent_height = 1.8
	_proto.agent_max_climb = 0.6
	_proto.agent_max_slope = 40.0
	_proto.border_size = CELL * 4.0                  # tiles meet seamlessly
	_proto.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	_proto.geometry_collision_mask = G.LAYER_WORLD
	_src = NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(_proto, _src, self)
	# 1. the places that matter, now
	var first := {}
	for a in areas:
		var c: Vector3 = a[0]
		var r: float = minf(float(a[1]), 340.0)
		var lo := _tile_of(c - Vector3(r, 0, r))
		var hi := _tile_of(c + Vector3(r, 0, r))
		for x in range(lo.x, hi.x + 1):
			for y in range(lo.y, hi.y + 1):
				first[Vector2i(x, y)] = true
	for t in first:
		var nm := _tile_mesh(t)
		NavigationServer3D.bake_from_source_geometry_data(nm, _src)
		_add_region(nm, t)
		_done[t] = true
	NavigationServer3D.map_force_update(nav_map)
	# 2. corridors between them, then everything else outward from the landing zone
	var lz: Vector3 = areas[0][0]
	for a in areas.slice(1):
		var b: Vector3 = a[0]
		var steps := int(lz.distance_to(b) / (TILE * 0.5)) + 1
		for k in steps + 1:
			var p: Vector3 = lz.lerp(b, float(k) / steps)
			for d in [Vector3.ZERO, Vector3(TILE * 0.5, 0, 0), Vector3(0, 0, TILE * 0.5)]:
				var tt := _tile_of(p + d)
				if not _done.has(tt) and not tt in _queue:
					_queue.append(tt)
	var all: Array = []
	var lo2 := _tile_of(aabb.position * 0.95)
	var hi2 := _tile_of(aabb.end * 0.95)
	for x in range(lo2.x, hi2.x + 1):
		for y in range(lo2.y, hi2.y + 1):
			var t2 := Vector2i(x, y)
			if not _done.has(t2) and not t2 in _queue:
				all.append(t2)
	var lzt := _tile_of(lz)
	all.sort_custom(func(a, b): return (a - lzt).length_squared() < (b - lzt).length_squared())
	_queue += all
	tiles_total = _done.size() + _queue.size()
	print("Ground navigation: %d tiles now (%d ms), %d more in the background" % [_done.size(), Time.get_ticks_msec() - t0, _queue.size()])


var _prune_t := 5.0


func _process(dt: float) -> void:
	# the open ground fills with the fallen: clear bodies a minute after the fight moved on
	_prune_t -= dt
	if _prune_t <= 0.0:
		_prune_t = 5.0
		for c in occupants.duplicate():
			if is_instance_valid(c) and c.state == "dead" and c.convert_t < 0.0 and c != G.possessed \
					and G.time - float(c.get_meta("dead_at", G.time)) > 60.0:
				if G.match_node and G.match_node.logistics:
					G.match_node.logistics._remove_person(c)
				else:
					occupants.erase(c)
					G.characters.erase(c)
					c.queue_free()
	_bake_cd -= dt
	while _busy < 1 and _bake_cd <= 0.0 and not _queue.is_empty() and _src != null:
		_bake_cd = 0.25                                # (one tile at a time, a few a second: no stutter)
		var t: Vector2i = _queue.pop_front()
		if _done.has(t):
			continue
		_done[t] = true
		var nm := _tile_mesh(t)
		_nm_tile[nm] = t
		_busy += 1
		NavigationServer3D.bake_from_source_geometry_data_async(nm, _src,
			Callable(G, "nav_tile_baked").bind(nav_map, nm, weakref(self)))


func tile_baked(nm: NavigationMesh) -> void:
	_busy -= 1
	_add_region(nm)


func baked_fraction() -> float:
	return float(_done.size() - _busy) / maxf(1.0, float(tiles_total))


func random_local() -> Vector3:
	if areas.is_empty() or not nav_ok():
		return Vector3.ZERO
	var a: Array = areas[randi() % areas.size()]
	var c: Vector3 = a[0]
	return snap_local(c + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * float(a[1]) * 0.8)


## A random walkable point within r of p.
func near_local(p: Vector3, r: float) -> Vector3:
	return snap_local(p + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * r)


func arrival_point() -> Vector3:
	return random_local()


# ------------------------------------------------------------------ cover, by grid cell
var _cover_grid := {}


func cover_near(p: Vector3, r: float) -> Array:
	if _cover_grid.is_empty() and not cover.is_empty():
		for cp in cover:
			var k := Vector2i(int(floor(cp[0].x / 24.0)), int(floor(cp[0].z / 24.0)))
			if not _cover_grid.has(k):
				_cover_grid[k] = []
			_cover_grid[k].append(cp)
	var out: Array = []
	var c0 := Vector2i(int(floor(p.x / 24.0)), int(floor(p.z / 24.0)))
	var n := int(ceil(r / 24.0))
	for x in range(c0.x - n, c0.x + n + 1):
		for y in range(c0.y - n, c0.y + n + 1):
			var k2 := Vector2i(x, y)
			if _cover_grid.has(k2):
				out += _cover_grid[k2]
	return out
