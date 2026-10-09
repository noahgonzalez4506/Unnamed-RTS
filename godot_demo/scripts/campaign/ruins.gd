extends RefCounted
## What's lying about on a world: wrecked tanks and APCs to take cover behind, and on some
## worlds an abandoned city. Cities hide salvage caches (cores, alloys, research data):
## bring a ship over a cache to recover it. A city may be overrun by the infection or
## picked over by outlaw scavengers in MRAPs (outlaws only ever field MRAPs).

const SURFACE := preload("res://scripts/campaign/surface.gd")
const MRAP := preload("res://scripts/campaign/mrap.gd")


static func build(m: Node, L: Dictionary, P: Dictionary) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = int(L["seed"]) + 4242
	var gy: float = SURFACE.GROUND_Y - 2.0
	# battlefield wrecks scattered round the landing zone and the bases
	var wreck_mat := StandardMaterial3D.new()
	wreck_mat.albedo_color = Color(0.22, 0.2, 0.18)
	wreck_mat.roughness = 0.9
	var spots: Array = [L["landing"]]
	for bs in L["bases"]:
		spots.append(bs["pos"])
	for i in 40:
		var c: Vector3 = spots[r.randi() % spots.size()]
		var a := r.randf() * TAU
		var p := Vector3(c.x, 0, c.z) + Vector3(cos(a), 0, sin(a)) * r.randf_range(80.0, 700.0)
		p.y = gy + SURFACE.height(P, L, p.x, p.z)
		_wreck(m, p, r, wreck_mat, r.randf() < 0.5)
	# an abandoned city (about two worlds in five; where it is was settled in the layout, so
	# the terrain under it is level)
	if L.has("city_site"):
		_city(m, L, P, r)


## A burnt-out tank or APC: a hull, a tilted turret or troop box, a few wheels; solid cover.
static func _wreck(m: Node, p: Vector3, r: RandomNumberGenerator, mat: Material, tank: bool) -> void:
	var root := StaticBody3D.new()
	root.collision_layer = G.LAYER_WORLD
	root.position = p
	root.rotation = Vector3(r.randf_range(-0.12, 0.12), r.randf() * TAU, r.randf_range(-0.15, 0.15))
	m.add_child(root)
	var hull := Vector3(4.2, 1.6, 7.5) if tank else Vector3(3.6, 2.4, 7.0)
	_block(root, hull, Vector3(0, hull.y * 0.5, 0), mat, true)
	if tank:
		var tur := _block(root, Vector3(2.8, 1.0, 3.0), Vector3(0.3, hull.y + 0.5, -0.4), mat, true)
		tur.rotation = Vector3(0.1, r.randf_range(-1, 1), 0.25)
		_block(root, Vector3(0.35, 0.35, 4.5), Vector3(0.3, hull.y + 0.7, -3.6), mat, false).rotation.x = -0.25
	else:
		_block(root, Vector3(3.0, 1.0, 3.2), Vector3(0, hull.y + 0.5, 1.5), mat, true)
	for k in 6:
		var w := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.7
		cm.bottom_radius = 0.7
		cm.height = 0.5
		w.mesh = cm
		w.material_override = mat
		w.rotation.z = PI * 0.5
		w.position = Vector3((1 if k % 2 == 0 else -1) * hull.x * 0.55, 0.6, -2.4 + (k / 2) * 2.4)
		root.add_child(w)


static func _block(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, solid: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	if solid and parent is StaticBody3D:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		cs.position = pos
		parent.add_child(cs)
	return mi


## A sprawled, procedural ruin: streets wander out from the old centre and branch (random
## walks), buildings line both sides at random sizes and heights, some collapsed to rubble.
## Salvage caches lie in the streets. Then whoever's there: outlaws or the infection.
static func _city(m: Node, L: Dictionary, P: Dictionary, r: RandomNumberGenerator) -> void:
	var gy: float = SURFACE.GROUND_Y - 2.0
	var center: Vector3 = L["city_site"]["center"]
	center.y = 0.0
	var R: float = L["city_site"]["radius"]
	var th := r.randf() * PI                           # the grid's heading
	var ax := Vector3(cos(th), 0, -sin(th))           # = Basis(UP, th) * X, so lots turned by th line up
	var az := Vector3(sin(th), 0, cos(th))
	var BLOCK := 64.0
	var n := int(R / BLOCK)
	var asphalt := _mat3(Color(0.16, 0.16, 0.17), 0.95)
	var walk := _mat3(Color(0.42, 0.41, 0.39), 0.95)
	var paint := _mat3(Color(0.75, 0.72, 0.55), 0.9)
	var stone := _mat3(Color(0.55, 0.52, 0.47), 0.95)
	var metal := _mat3(Color(0.25, 0.26, 0.27), 0.6)
	var concrete := _mat3(Color(0.48, 0.47, 0.45), 0.95)
	var rust := _mat3(Color(0.42, 0.33, 0.27), 0.9)
	var dark := _mat3(Color(0.12, 0.12, 0.13), 0.9)
	var pal: Array = []                          # weathered concrete, brick, plaster, stained steel
	for c in [Color(0.5, 0.49, 0.46), Color(0.55, 0.42, 0.34), Color(0.47, 0.3, 0.25), Color(0.6, 0.57, 0.5),
			Color(0.42, 0.44, 0.47), Color(0.56, 0.5, 0.38), Color(0.38, 0.4, 0.36)]:
		pal.append(_mat3(c, 0.95))
	var trims: Array = [_mat3(Color(0.3, 0.29, 0.27), 0.9), _mat3(Color(0.68, 0.66, 0.6), 0.9), _mat3(Color(0.33, 0.24, 0.2), 0.9)]
	var deco := Node3D.new()
	m.add_child(deco)
	var gp := func(i: float, j: float) -> Vector3:
		return center + ax * (i * BLOCK) + az * (j * BLOCK)
	# streets: the grid lines inside the city's circle (a few broken off for a ruined look)
	var streets: Array = []
	for i in range(-n, n + 1):
		for j in range(-n, n):
			for dir in 2:
				var a0: Vector3 = gp.call(i, j) if dir == 0 else gp.call(j, i)
				var a1: Vector3 = gp.call(i, j + 1) if dir == 0 else gp.call(j + 1, i)
				if Vector2(a0.x - center.x, a0.z - center.z).length() > R or Vector2(a1.x - center.x, a1.z - center.z).length() > R:
					continue
				if absf(i) > 1 and r.randf() < 0.12:
					continue
				streets.append([a0, a1, 14.0 if i % 3 == 0 else 10.0])
	for sg in streets:
		var a0: Vector3 = sg[0]
		var a1: Vector3 = sg[1]
		var wd: float = sg[2]
		var mid: Vector3 = (a0 + a1) * 0.5
		var dvec: Vector3 = a1 - a0
		var ln: float = dvec.length()
		var yaw := atan2(dvec.x, dvec.z)
		var road := _flat(deco, Vector3(wd, 0.12, ln + wd), mid + Vector3(0, gy + 0.06, 0), yaw, asphalt)
		road.name = "Road"
		for sd in [-1.0, 1.0]:                    # sidewalks
			var off: Vector3 = Basis(Vector3.UP, yaw) * Vector3(sd * (wd * 0.5 + 1.2), 0, 0)
			_flat(deco, Vector3(2.4, 0.25, ln - 2.0), mid + off + Vector3(0, gy + 0.12, 0), yaw, walk)
		if wd > 12.0:                              # a faded centre line on the avenues
			var k := 0.0
			while k < ln - 4.0:
				var pp: Vector3 = a0 + dvec.normalized() * (k + 2.0)
				_flat(deco, Vector3(0.25, 0.13, 2.2), pp + Vector3(0, gy + 0.07, 0), yaw, paint)
				k += 6.0
		# street lamps, some bent over; the odd wrecked car (cover)
		var lk := 8.0
		while lk < ln - 4.0:
			var lp: Vector3 = a0 + dvec.normalized() * lk + Basis(Vector3.UP, yaw) * Vector3(wd * 0.5 + 0.6, 0, 0)
			var pole := _flat(deco, Vector3(0.15, 5.5, 0.15), lp + Vector3(0, gy + 2.75, 0), yaw, metal)
			if r.randf() < 0.25:
				pole.rotation.z = r.randf_range(0.4, 1.1)
			else:
				_flat(deco, Vector3(1.2, 0.15, 0.3), lp + Vector3(0, gy + 5.5, 0) - Basis(Vector3.UP, yaw) * Vector3(0.5, 0, 0), yaw, metal)
			lk += 22.0 + r.randf_range(-4.0, 4.0)
		if r.randf() < 0.45:
			var cp: Vector3 = a0.lerp(a1, r.randf_range(0.2, 0.8)) + Basis(Vector3.UP, yaw) * Vector3(r.randf_range(-wd * 0.3, wd * 0.3), 0, 0)
			_car(m, Vector3(cp.x, gy, cp.z), yaw + r.randf_range(-0.5, 0.5), rust if r.randf() < 0.5 else pal[r.randi() % pal.size()], dark)
		if r.randf() < 0.18:                     # a concrete barricade across part of the street
			var bp: Vector3 = a0.lerp(a1, r.randf_range(0.3, 0.7))
			var bb := StaticBody3D.new()
			bb.collision_layer = G.LAYER_WORLD
			m.add_child(bb)
			bb.position = Vector3(bp.x, gy, bp.z)
			bb.rotation.y = yaw + PI * 0.5
			for q in 3:
				_block(bb, Vector3(2.2, 0.9, 0.6), Vector3(q * 2.4 - 2.4, 0.45, 0), concrete, true)
			for sd2 in [-1.0, 1.0]:
				m.ground_cover.append([bb.to_global(Vector3(0, 0, sd2 * 1.0)), true, bb.global_basis * Vector3(0, 0, -sd2)])
	# blocks: the market square in the middle, buildings lining the streets everywhere else
	var placed: Array = []
	var far := 0.0
	var towers := 0
	for i in range(-n, n):
		for j in range(-n, n):
			var bc: Vector3 = gp.call(i + 0.5, j + 0.5)
			var dist_c: float = Vector2(bc.x - center.x, bc.z - center.z).length()
			if dist_c > R - BLOCK * 0.5:
				continue
			far = maxf(far, dist_c + BLOCK * 0.5)
			if i == 0 and j == 0 or (i == -1 and j == 0 and r.randf() < 0.0):
				_market(m, deco, bc, th, BLOCK - 22.0, gy, stone, walk, metal, dark, r)
				continue
			if r.randf() < 0.08:
				_park(deco, bc, th, BLOCK - 22.0, gy, r)
				continue
			# 2-4 lots per block, set back from the street, facing it
			var lots: Array = [[-1, -1], [1, -1], [-1, 1], [1, 1]]
			lots.shuffle()
			for lt in lots.slice(0, 2 + r.randi() % 3):
				var w: float = r.randf_range(12.0, 18.0)
				var dp: float = maxf(12.0, w * r.randf_range(0.75, 1.2))
				# keep the walls off the sidewalks: the lot centre is BLOCK/4 from the street on each
				# side (depth runs along ax, width along az); avenues (every third line) are 14 m wide
				var sx: int = i + (1 if lt[0] > 0 else 0)
				var sz: int = j + (1 if lt[1] > 0 else 0)
				var room_x: float = BLOCK * 0.25 - (14.0 if sx % 3 == 0 else 10.0) * 0.5 - 2.8
				var room_z: float = BLOCK * 0.25 - (14.0 if sz % 3 == 0 else 10.0) * 0.5 - 2.8
				dp = minf(dp, room_x * 2.0)
				w = minf(w, room_z * 2.0)
				var lp: Vector3 = bc + ax * (float(lt[0]) * (BLOCK * 0.25)) + az * (float(lt[1]) * (BLOCK * 0.25))
				var face: float = th + (PI * 0.5 if lt[0] > 0 else -PI * 0.5)
				var p: Vector3 = Vector3(lp.x, gy, lp.z)
				var b := StaticBody3D.new()
				b.collision_layer = G.LAYER_WORLD
				b.position = p
				b.rotation.y = face
				m.add_child(b)
				placed.append(p)
				var mat: Material = pal[r.randi() % pal.size()] if r.randf() < 0.85 else rust
				var trim: Material = trims[r.randi() % trims.size()]
				_block(b, Vector3(w + 1.0, 1.4, dp + 1.0), Vector3(0, -0.65, 0), concrete, true)     # foundation
				if dist_c < 140.0 and towers < 3 and r.randf() < 0.35:
					towers += 1
					_tower(m, b, w, dp, mat, trim, dark, r, P, L, gy)
					continue
				if r.randf() < 0.12:
					for k in 4:
						var sl := _block(b, Vector3(w * r.randf_range(0.4, 0.8), 1.4, dp * r.randf_range(0.3, 0.6)),
							Vector3(r.randf_range(-3, 3), 0.7 + k * 0.9, r.randf_range(-3, 3)), mat, true)
						sl.rotation = Vector3(r.randf_range(-0.3, 0.3), r.randf() * TAU, r.randf_range(-0.3, 0.3))
					continue
				var h: float = r.randf_range(4.0, 14.0) * clampf(1.4 - dist_c / 380.0, 0.5, 1.2)
				_house(m, b, w, dp, h, mat, trim, dark, r, P, L, gy)
	m.city = {"center": Vector3(center.x, SURFACE.GROUND_Y, center.z), "radius": far + 60.0}
	var lab := Label3D.new()
	lab.text = "ABANDONED CITY"
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.font_size = 64
	lab.pixel_size = 0.6
	lab.no_depth_test = true
	lab.modulate = Color(0.85, 0.85, 0.75)
	lab.position = center + Vector3(0, gy + 120.0, 0)
	lab.visibility_range_begin = 650.0           # (only from a distance: close up it's in the way)
	lab.visibility_range_begin_margin = 100.0
	lab.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	m.add_child(lab)
	# salvage caches, in the streets
	var key0: String = "%s_city" % L["seed"]
	var taken: Array = []                         # (ids come back from a saved game as floats)
	for t in (G.campaign.world.get(key0, {}).get("taken", []) if G.campaign else []):
		taken.append(int(t))
	for i in 4 + r.randi() % 3:
		if streets.is_empty():
			continue
		# draw every number first, so taking one cache doesn't move the others (or the occupants)
		var sg3: Array = streets[r.randi() % streets.size()]
		var cp: Vector3 = (sg3[0] as Vector3).lerp(sg3[1], r.randf())
		cp.y = gy + SURFACE.height(P, L, cp.x, cp.z) + 1.0
		var kind: String = ["cores", "alloys", "research", "alloys", "cores"][r.randi() % 5]
		if i in taken:
			continue
		var cache := Node3D.new()
		cache.position = cp
		cache.set_meta("cache", kind)
		cache.set_meta("cache_id", i)
		cache.set_meta("city", key0)
		m.add_child(cache)
		var cm := MeshInstance3D.new()
		var cb := BoxMesh.new()
		cb.size = Vector3(2, 1.4, 2)
		cm.mesh = cb
		var gm := StandardMaterial3D.new()
		gm.albedo_color = {"cores": Color(0.6, 0.3, 0.9), "alloys": Color(0.7, 0.7, 0.75), "research": Color(0.3, 0.8, 1.0)}[kind]
		gm.emission_enabled = true
		gm.emission = gm.albedo_color
		gm.emission_energy_multiplier = 1.2
		cm.material_override = gm
		cache.add_child(cm)
		var cl := Label3D.new()
		cl.text = "SALVAGE: %s" % kind.to_upper()
		cl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		cl.font_size = 64
		cl.pixel_size = 0.12
		cl.outline_size = 12
		cl.no_depth_test = true
		cl.fixed_size = false
		cl.position = Vector3(0, 3, 0)
		cache.add_child(cl)
		m.caches.append(cache)
	# who's here: the infection, outlaw scavengers (infantry with 1-3 of their MRAPs), or nobody
	var roll := r.randf()
	var cc := Vector3(center.x, SURFACE.GROUND_Y + SURFACE.height(P, L, center.x, center.z), center.z)
	if roll < 0.3:
		for k in 2:
			m.ground_spawns.append([cc + Vector3(r.randf_range(-80, 80), 0, r.randf_range(-80, 80)), 4, ["x", "x", "x", "x", "x"]])
		for k in 1 + r.randi() % 2:
			m.ground_vehicles.append([cc + Vector3(r.randf_range(-90, 90), 0, r.randf_range(-90, 90)), ["tank", "mrap_ai", "mech"][r.randi() % 3], 4, 1])
		load("res://scripts/campaign/camps.gd").infest_city(m, center, far, key0, L, P)
		G.say("Something moves in the ruins: the city is infected", 1)
	elif roll < 0.75:
		for i in 1 + r.randi() % 2:
			var mr: Node3D = MRAP.new()
			m.add_child(mr)
			mr.setup(3, center, far, L, P)
		for k in 2:                                    # 12 scavengers in two gangs of six
			m.ground_spawns.append([cc + Vector3(r.randf_range(-100, 100), 0, r.randf_range(-100, 100)), 3,
				["squad_leader", "rifleman", "rifleman", "heavy", "rifleman", "medic"]])
		G.say("Outlaw scavengers are working the ruins", 1)


## A ruined building you can fight through. Each one rolls its own footprint, palette, trim,
## storefront or windowed ground floor, interior layout and how far it has decayed: blown-out
## upper walls, jagged piers, caved-in roofs, sagging awnings, rubble spilled in and out.
## Every wall adds cover points on both faces, so troops can garrison it or clear it room by room.
static func _house(m: Node, b: StaticBody3D, w: float, dp: float, h: float, mat: Material, trim: Material, dark: Material,
		r: RandomNumberGenerator, P: Dictionary = {}, L: Dictionary = {}, gy: float = 0.0) -> void:
	var hw := w * 0.5
	var hd := dp * 0.5
	var stories: int = 2 if h >= 9.0 and r.randf() < 0.75 else 1
	var sh := r.randf_range(3.4, 3.9)                 # storey height
	var decay := r.randf()                            # 0 tidy shell .. 1 badly ruined
	var walls := [[Vector3(-hw, 0, -hd), Vector3(hw, 0, -hd)], [Vector3(hw, 0, -hd), Vector3(hw, 0, hd)],
		[Vector3(hw, 0, hd), Vector3(-hw, 0, hd)], [Vector3(-hw, 0, hd), Vector3(-hw, 0, -hd)]]
	var door_wall := r.randi() % 4
	var shop: int = door_wall if r.randf() < 0.35 else -1      # a storefront: wide openings on the street face
	for st in stories:
		var y0 := st * sh
		for k in 4:
			_window_wall(m, b, walls[k][0] + Vector3(0, y0, 0), walls[k][1] + Vector3(0, y0, 0), sh, mat,
				st == 0 and (k == door_wall or (k == (door_wall + 2) % 4 and r.randf() < 0.5)), r,
				decay * (0.35 + st * 0.75), 2.6 if (st == 0 and k == shop) else r.randf_range(1.3, 1.8))
		if st == 1:
			# the upper floor, with a stairwell gap where the ramp comes up
			_layer(m, _block(b, Vector3(w - 1.0, 0.4, dp - 5.0), Vector3(0, sh, -2.0), mat, true), 1)
			_layer(m, _block(b, Vector3(w - 4.0, 0.4, 4.0), Vector3(1.5, sh, hd - 2.5), mat, true), 1)
	# a trim ledge round each storey line, sometimes broken
	if r.randf() < 0.7:
		for st in stories:
			for k in 4:
				if r.randf() < decay * 0.4:
					continue
				var a0: Vector3 = walls[k][0]
				var a1: Vector3 = walls[k][1]
				var dd := a1 - a0
				var ln := dd.length() * (1.0 if r.randf() > decay * 0.5 else r.randf_range(0.4, 0.8))
				var dir := dd.normalized()
				var out := dir.cross(Vector3.UP)
				var mid := a0 + dir * ln * 0.5 - out * 0.45 + Vector3(0, (st + 1) * sh - 0.2, 0)
				var lg := _block(b, Vector3(0.35, 0.3, ln), mid, trim, false)
				lg.rotation.y = atan2(dir.x, dir.z)
	if stories == 2:
		var ramp := _block(b, Vector3(2.2, 0.3, 9.0), Vector3(-hw + 2.0, sh * 0.5, hd - 5.5), mat, true)
		ramp.rotation.x = -atan2(sh, 9.0)
		(b.get_child(b.get_child_count() - 1) as Node3D).rotation.x = ramp.rotation.x
	_roof(m, b, w, dp, sh * stories, decay, trim, dark, r, 2 if stories == 2 else 1)
	# storefront awning, often sagging off one bracket
	if shop >= 0 and r.randf() < 0.75:
		var a0: Vector3 = walls[shop][0]
		var a1: Vector3 = walls[shop][1]
		var dir := (a1 - a0).normalized()
		var out := dir.cross(Vector3.UP)
		var aw := _block(b, Vector3(1.8, 0.15, (a1 - a0).length() * 0.8), (a0 + a1) * 0.5 - out * 1.2 + Vector3(0, 2.9, 0), trim, false)
		aw.rotation = Vector3(0, atan2(dir.x, dir.z), 0)
		aw.rotate_object_local(Vector3(0, 0, 1), -0.18 * signf(out.x + out.z + 0.01))
		if decay > 0.5:
			aw.rotate_object_local(Vector3(1, 0, 0), r.randf_range(-0.35, 0.35))
	# interior: one of a few room layouts, partitions with their own doorways
	var lay := r.randi() % 3
	if lay != 1:      # wall across the depth (leaves the stairwell corridor open)
		_window_wall(m, b, Vector3(r.randf_range(-0.2, 0.2) * w, 0, -hd + 0.6), Vector3(r.randf_range(-0.2, 0.2) * w, 0, hd - 4.6), sh, mat, true, r, decay * 0.3)
	if lay != 0:      # wall across the width
		var zz := r.randf_range(-0.25, 0.05) * dp
		_window_wall(m, b, Vector3(-hw + 3.6, 0, zz), Vector3(hw - 0.6, 0, zz), sh, mat, true, r, decay * 0.3)
	if stories == 2 and r.randf() < 0.7:
		var zu := -hd * r.randf_range(0.15, 0.4)
		_window_wall(m, b, Vector3(-hw + 0.6, sh, zu), Vector3(hw - 0.6, sh, zu), sh, mat, true, r, decay * 0.6)
	# furniture and junk: counters, shelving, crates, a toppled cabinet
	for k in 2 + r.randi() % 4:
		var fl: int = r.randi() % stories
		var rp := Vector3(r.randf_range(-hw + 2, hw - 2), fl * sh, r.randf_range(-hd + 2, hd - 5))
		match r.randi() % 4:
			0:
				var c := _block(b, Vector3(r.randf_range(1.6, 3.0), 1.0, 0.9), rp + Vector3(0, 0.5 + (0.2 if fl else 0.0), 0), dark, true)
				c.rotation.y = 0.0
				_cover(m, b, rp + Vector3(0, 0, 1.1), true, Vector3(0, 0, -1))
			1:
				var sv := _block(b, Vector3(0.6, 2.1, r.randf_range(1.5, 2.6)), rp + Vector3(0, 1.05 + (0.2 if fl else 0.0), 0), trim, false)
				if decay > 0.6:
					sv.rotation.z = r.randf_range(0.6, 1.2)
					sv.position.y -= 0.5
			2:
				for q in 1 + r.randi() % 3:
					var cr := _block(b, Vector3.ONE * r.randf_range(0.7, 1.1), rp + Vector3(r.randf_range(-0.8, 0.8), 0.45 + (0.2 if fl else 0.0) + q * 0.3, r.randf_range(-0.8, 0.8)), dark, false)
					cr.rotation.y = r.randf() * TAU
				_cover(m, b, rp + Vector3(0, 0, 1.3), true, Vector3(0, 0, -1))
			_:
				var tb := _block(b, Vector3(1.8, 0.8, 0.9), rp + Vector3(0, 0.4 + (0.2 if fl else 0.0), 0), dark, false)
				tb.rotation = Vector3(0, r.randf() * TAU, PI * 0.5 if decay > 0.5 else 0.0)
	# rubble spilled inside and out, more the further gone it is
	for k in int(decay * 10.0):
		var inside := r.randf() < 0.4
		var rp: Vector3
		if inside:
			rp = Vector3(r.randf_range(-hw + 1, hw - 1), 0.0, r.randf_range(-hd + 1, hd - 5))
		else:
			var side := r.randi() % 4
			var along := r.randf_range(-0.9, 0.9)
			rp = [Vector3(along * hw, 0, -hd - r.randf_range(0.6, 3.0)), Vector3(hw + r.randf_range(0.6, 3.0), 0, along * hd),
				Vector3(along * hw, 0, hd + r.randf_range(0.6, 3.0)), Vector3(-hw - r.randf_range(0.6, 3.0), 0, along * hd)][side]
		var sz := Vector3(r.randf_range(0.6, 2.2), r.randf_range(0.3, 0.9), r.randf_range(0.6, 2.2))
		var ch := _block(b, sz, rp + Vector3(0, sz.y * 0.35 + _ground_off(b, rp, P, L, gy), 0), mat if r.randf() < 0.6 else trim, false)
		ch.rotation = Vector3(r.randf_range(-0.4, 0.4), r.randf() * TAU, r.randf_range(-0.4, 0.4))


## The roof (or top floor slab): intact, with a parapet, or caved in to a few sagging pieces.
static func _roof(m: Node, b: StaticBody3D, w: float, dp: float, y: float, decay: float, trim: Material, dark: Material, r: RandomNumberGenerator, lvl: int) -> void:
	if decay < 0.6:
		_layer(m, _block(b, Vector3(w + 0.6, 0.4, dp + 0.6), Vector3(0, y, 0), dark, true), lvl)
		if r.randf() < 0.55:
			for k in 4:
				var vert := k % 2 == 0
				var off := (dp * 0.5 if vert else w * 0.5) + 0.1
				var sgn := -1.0 if k < 2 else 1.0
				var pos := Vector3(0, y + 0.6, sgn * off) if vert else Vector3(sgn * off, y + 0.6, 0)
				var sz := Vector3(w + 0.8, 0.8, 0.3) if vert else Vector3(0.3, 0.8, dp + 0.8)
				_layer(m, _block(b, sz, pos, trim, false), lvl)
		if r.randf() < 0.4:          # rooftop plant: a vent box or a tank
			_layer(m, _block(b, Vector3(r.randf_range(1.5, 3), r.randf_range(1, 2.2), r.randf_range(1.5, 3)),
				Vector3(r.randf_range(-w, w) * 0.25, y + 1.0, r.randf_range(-dp, dp) * 0.25), trim, false), lvl)
		return
	# caved in: two or three pieces left, one sagging down into the room
	var n := 2 + r.randi() % 2
	for i in n:
		if r.randf() < 0.35:
			continue
		var fz := -dp * 0.5 + dp * (i + 0.5) / n
		var piece := _block(b, Vector3(w + 0.6, 0.4, dp / n), Vector3(0, y, fz), dark, false)
		if r.randf() < 0.5:
			piece.rotation.x = r.randf_range(0.2, 0.5) * (1.0 if fz < 0 else -1.0)
			piece.position.y -= 1.0
		_layer(m, piece, lvl)


## How far the ground at a building-local point sits above (or below) the building's base.
static func _ground_off(b: Node3D, lp: Vector3, P: Dictionary, L: Dictionary, gy: float) -> float:
	if P.is_empty():
		return 0.0
	var wp := b.position + Basis(Vector3.UP, b.rotation.y) * lp
	return gy + SURFACE.height(P, L, wp.x, wp.z) - b.position.y


## A gutted high-rise: an enterable ground storey, then a frame of columns snapped off at
## different heights, floor slabs missing or hanging, scraps of facade, and a fan of rubble
## spilled out on the side it is leaning toward. The rubble near the base is solid low cover.
static func _tower(m: Node, b: StaticBody3D, w: float, dp: float, mat: Material, trim: Material, dark: Material,
		r: RandomNumberGenerator, P: Dictionary, L: Dictionary, gy: float) -> void:
	var floors := r.randi_range(5, 10)
	var sh := 3.8
	var hw := w * 0.5
	var hd := dp * 0.5
	var lean := Vector3(r.randf_range(-1, 1), 0, r.randf_range(-1, 1)).normalized()
	var walls := [[Vector3(-hw, 0, -hd), Vector3(hw, 0, -hd)], [Vector3(hw, 0, -hd), Vector3(hw, 0, hd)],
		[Vector3(hw, 0, hd), Vector3(-hw, 0, hd)], [Vector3(-hw, 0, hd), Vector3(-hw, 0, -hd)]]
	var dw := r.randi() % 4
	for k in 4:
		_window_wall(m, b, walls[k][0], walls[k][1], sh, mat, k == dw or k == (dw + 2) % 4, r, 0.25, 2.2)
	# the frame (tracking how high each side still stands, so nothing floats)
	var side_top := {-1.0: 0.0, 1.0: 0.0}
	for ix in [-1, 0, 1]:
		for iz in [-1, 0, 1]:
			if ix == 0 and iz == 0:
				continue
			var cp := Vector3(ix * (hw - 0.5), 0, iz * (hd - 0.5))
			var top := floors * sh * r.randf_range(0.45, 1.0)
			if cp.normalized().dot(lean) > 0.3:
				top *= r.randf_range(0.4, 0.7)
			top = maxf(top, sh * 1.5)
			for hs in [-1.0, 1.0]:
				if ix == 0 or float(ix) == hs:
					side_top[hs] = maxf(side_top[hs], top)
			_layer(m, _block(b, Vector3(1.0, top - sh, 1.0), Vector3(cp.x, sh + (top - sh) * 0.5, cp.z), mat, true), 2)
	# floors: halves present or gone, the odd one hanging
	for f in range(1, floors):
		for half in [-1.0, 1.0]:
			var keep := 0.85 - f * 0.06 - (0.2 if Vector3(half, 0, 0).dot(lean) > 0.3 else 0.0)
			if f * sh > float(side_top[half]) - 0.3:
				continue
			if f == 1 or r.randf() < keep:
				var hang := f > 1 and r.randf() < 0.18
				var sl := _block(b, Vector3(w * 0.5 - 0.1, 0.45, dp - 0.3), Vector3(half * w * 0.25, f * sh, 0), mat, f == 1)
				if hang:
					sl.rotation.z = half * r.randf_range(0.2, 0.55)
					sl.position.y -= 1.2
				_layer(m, sl, 1 if f == 1 else 2)
		# scraps of facade: spandrel bands and window mullions
		for k in 4:
			if f * sh + 1.2 < minf(side_top[-1.0], side_top[1.0]) and r.randf() < 0.5 - f * 0.03:
				var a0: Vector3 = walls[k][0]
				var a1: Vector3 = walls[k][1]
				var dir := (a1 - a0).normalized()
				var ln := (a1 - a0).length() * r.randf_range(0.25, 0.9)
				var st0 := r.randf_range(0.0, (a1 - a0).length() - ln)
				var band := _block(b, Vector3(0.45, 1.1, ln), a0 + dir * (st0 + ln * 0.5) + Vector3(0, f * sh + 0.6, 0), trim, false)
				band.rotation.y = atan2(dir.x, dir.z)
				_layer(m, band, 2)
	# rubble fan toward the lean
	var reach := hw + floors * sh * 0.6
	var ang0 := atan2(lean.z, lean.x)
	for i in 16 + r.randi() % 12:
		var ang := ang0 + r.randf_range(-1.0, 1.0)
		var dist := r.randf_range(hw * 0.9, reach)
		var lp := Vector3(cos(ang) * dist, 0, sin(ang) * dist)
		var solid := dist < hw + 9.0 and r.randf() < 0.45
		var sz := Vector3(r.randf_range(1.5, 4.5), r.randf_range(0.6, 1.3) if solid else r.randf_range(0.4, 2.2), r.randf_range(1.5, 4.0))
		var go := _ground_off(b, lp, P, L, gy)
		var ch := _block(b, sz, lp + Vector3(0, go + sz.y * (0.5 if solid else 0.3), 0), mat if r.randf() < 0.7 else trim, solid)
		if solid:
			var yaw := r.randf() * TAU
			ch.rotation.y = yaw
			(b.get_child(b.get_child_count() - 1) as Node3D).rotation.y = yaw
			_cover(m, b, lp - lp.normalized() * (sz.x * 0.5 + 0.8) + Vector3(0, go, 0), true, lp.normalized())
		else:
			ch.rotation = Vector3(r.randf_range(-0.5, 0.5), r.randf() * TAU, r.randf_range(-0.5, 0.5))
	# a fallen section of frame lying across the rubble
	if r.randf() < 0.7:
		var lp2 := lean * (hw + floors * sh * 0.3)
		var gird := _block(b, Vector3(1.0, 1.0, floors * sh * 0.5), lp2 + Vector3(0, _ground_off(b, lp2, P, L, gy) + 1.2, 0), mat, false)
		gird.rotation = Vector3(r.randf_range(0.1, 0.3), atan2(lean.x, lean.z) + r.randf_range(-0.5, 0.5), 0)


## One storey of wall from a to c: piers between window openings (a sill to crouch behind and
## shoot over), or a doorway. Window points on the inside are low cover facing out, so troops
## garrisoning a building fire out of its windows.
static func _window_wall(m: Node, b: StaticBody3D, a: Vector3, c: Vector3, sh: float, mat: Material, door: bool, r: RandomNumberGenerator,
		decay: float = 0.0, win: float = 1.6) -> void:
	var d := c - a
	var L := Vector2(d.x, d.z).length()
	var dir := Vector3(d.x, 0, d.z) / L
	var nrm := dir.cross(Vector3.UP)
	var yaw := atan2(dir.x, dir.z)
	var pier := 1.4
	var n := maxi(1, int((L - pier) / (pier + win)))
	var used := pier + n * (pier + win)
	var pad := (L - used) * 0.5
	var door_i: int = r.randi() % n if door else -1
	var parts: Array = []                            # [along, length, y0, height]
	parts.append([0.0, pad + pier, 0.0, sh])
	for i in n:
		var s0: float = pad + pier + i * (pier + win)
		if i == door_i:
			parts.append([s0, win, 2.5, sh - 2.5])        # lintel over the doorway
		else:
			parts.append([s0, win, 0.0, 1.0])             # sill
			parts.append([s0, win, 2.2, sh - 2.2])        # over the window
			var wp: Vector3 = a + dir * (s0 + win * 0.5)
			_cover(m, b, wp + nrm * 0.9, true, -nrm)      # inside, at the window
			_cover(m, b, wp - nrm * 0.9, true, nrm)       # outside, under it
		parts.append([s0 + win, pier if i < n - 1 else pier + pad, 0.0, sh])
	var upper := a.y > 0.5
	for p in parts:
		# decay: blown-out panels up top, jagged broken piers, the odd missing sill
		if upper and r.randf() < decay * 0.3:
			continue
		if float(p[2]) > 0.0 and r.randf() < decay * 0.25:
			continue
		if float(p[3]) <= 1.0 and r.randf() < decay * 0.12:
			continue
		if upper and float(p[3]) >= sh - 0.01 and r.randf() < decay * 0.5:
			p = [p[0], p[1], 0.0, sh * r.randf_range(0.35, 0.85)]
		var mid: Vector3 = a + dir * (float(p[0]) + float(p[1]) * 0.5) + Vector3(0, float(p[2]) + float(p[3]) * 0.5, 0)
		var blk := _block(b, Vector3(0.6, float(p[3]), float(p[1])), mid, mat, true)
		blk.rotation.y = yaw
		(b.get_child(b.get_child_count() - 1) as Node3D).rotation.y = yaw


static func _cover(m: Node, b: Node3D, local_p: Vector3, low: bool, toward: Vector3) -> void:
	var wp: Vector3 = b.to_global(local_p)
	var wd: Vector3 = (b.global_basis * toward).normalized()
	m.ground_cover.append([wp, low, wd])


## Floors and roofs the commander's cutaway peels off (level 1: upper floor, 2: roof).
static func _layer(m: Node, mi: MeshInstance3D, level: int) -> void:
	if "roofs" in m:
		m.roofs.append([mi, level])



static func _mat3(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


## A flat, non-solid piece of street dressing (roads, kerbs, paint, poles).
static func _flat(parent: Node3D, size: Vector3, pos: Vector3, yaw: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = yaw
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if size.y < 0.5 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi


## An abandoned car: solid low cover in the street.
static func _car(m: Node, p: Vector3, yaw: float, body: Material, dark: Material) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = G.LAYER_WORLD
	m.add_child(b)
	b.position = p
	b.rotation.y = yaw
	_block(b, Vector3(1.9, 0.8, 4.4), Vector3(0, 0.6, 0), body, true)
	_block(b, Vector3(1.7, 0.6, 2.2), Vector3(0, 1.3, -0.2), dark, false)
	for sd in [-1.0, 1.0]:
		m.ground_cover.append([b.to_global(Vector3(sd * 1.6, 0, 0)), true, b.global_basis * Vector3(-sd, 0, 0)])


## The market square: paving, a dry fountain, rows of stalls under tattered awnings
## (their counters are cover), crates and benches.
static func _market(m: Node, deco: Node3D, c: Vector3, th: float, size: float, gy: float, stone: Material,
		walk: Material, metal: Material, dark: Material, r: RandomNumberGenerator) -> void:
	_flat(deco, Vector3(size, 0.2, size), c + Vector3(0, gy + 0.1, 0), th, stone)
	var fb := StaticBody3D.new()
	fb.collision_layer = G.LAYER_WORLD
	m.add_child(fb)
	fb.position = Vector3(c.x, gy, c.z)
	var basin := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 4.0
	cm.bottom_radius = 4.3
	cm.height = 0.9
	basin.mesh = cm
	basin.material_override = walk
	basin.position.y = 0.45
	fb.add_child(basin)
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 4.2
	cyl.height = 0.9
	cs.shape = cyl
	cs.position.y = 0.45
	fb.add_child(cs)
	var pil := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.5
	pm.bottom_radius = 0.8
	pm.height = 3.2
	pil.mesh = pm
	pil.material_override = walk
	pil.position.y = 1.6
	fb.add_child(pil)
	for k in 6:
		var d := Vector3(cos(k * TAU / 6.0), 0, sin(k * TAU / 6.0))
		m.ground_cover.append([fb.global_position + d * 5.2, true, -d])
	var cloths := [Color(0.62, 0.22, 0.18), Color(0.2, 0.42, 0.55), Color(0.65, 0.55, 0.22), Color(0.3, 0.5, 0.3), Color(0.5, 0.3, 0.5)]
	var basis := Basis(Vector3.UP, th)
	for row in [-1.0, 1.0]:
		for k in 5:
			var sp: Vector3 = c + basis * Vector3(-size * 0.36 + k * size * 0.18, 0, row * size * 0.3)
			var st := StaticBody3D.new()
			st.collision_layer = G.LAYER_WORLD
			m.add_child(st)
			st.position = Vector3(sp.x, gy, sp.z)
			st.rotation.y = th + (PI if row > 0 else 0.0)
			_block(st, Vector3(3.2, 1.0, 1.0), Vector3(0, 0.5, 0), dark, true)                     # the counter
			for sx in [-1.5, 1.5]:
				_block(st, Vector3(0.12, 2.6, 0.12), Vector3(sx, 1.3, -0.4), metal, false)
				_block(st, Vector3(0.12, 2.2, 0.12), Vector3(sx, 1.1, 1.3), metal, false)
			var aw := _block(st, Vector3(3.6, 0.06, 2.4), Vector3(0, 2.45, 0.5), _mat3(cloths[r.randi() % cloths.size()], 1.0), false)
			aw.rotation.x = r.randf_range(0.15, 0.35) if r.randf() > 0.2 else r.randf_range(0.6, 1.0)
			for q in r.randi() % 3:
				var cr := _block(st, Vector3.ONE * r.randf_range(0.5, 0.8), Vector3(r.randf_range(-1.2, 1.2), 1.3, r.randf_range(-0.2, 0.2)), _mat3(Color(0.45, 0.36, 0.22), 0.9), false)
				cr.rotation.y = r.randf() * TAU
			m.ground_cover.append([st.to_global(Vector3(0, 0, 1.2)), true, st.global_basis * Vector3(0, 0, -1)])
	for k in 4:                                       # benches round the fountain
		var d2 := Vector3(cos(k * TAU / 4.0 + 0.4), 0, sin(k * TAU / 4.0 + 0.4))
		_flat(deco, Vector3(2.2, 0.5, 0.6), c + d2 * 8.0 + Vector3(0, gy + 0.25, 0), atan2(d2.x, d2.z) + PI * 0.5, metal)


## A small overgrown park: grass, a few trees, a broken bench.
static func _park(deco: Node3D, c: Vector3, th: float, size: float, gy: float, r: RandomNumberGenerator) -> void:
	_flat(deco, Vector3(size, 0.15, size), c + Vector3(0, gy + 0.05, 0), th, _mat3(Color(0.28, 0.36, 0.2), 1.0))
	var leaf := _mat3(Color(0.22, 0.34, 0.16), 1.0)
	var bark := _mat3(Color(0.3, 0.22, 0.15), 1.0)
	for k in 5 + r.randi() % 4:
		var tp: Vector3 = c + Basis(Vector3.UP, th) * Vector3(r.randf_range(-size, size) * 0.4, 0, r.randf_range(-size, size) * 0.4)
		_flat(deco, Vector3(0.4, 4.0, 0.4), tp + Vector3(0, gy + 2.0, 0), 0.0, bark)
		var crown := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = r.randf_range(2.0, 3.2)
		sm.height = sm.radius * 1.6
		crown.mesh = sm
		crown.material_override = leaf
		crown.position = tp + Vector3(0, gy + 5.0, 0)
		deco.add_child(crown)
