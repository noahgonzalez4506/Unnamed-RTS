extends "res://scripts/ship_helpers.gd"
## Anything with an interior: ships and stations. Handles what the generator's
## naming rules describe: markers, doors, elevators, turrets, zones (for the
## infection), cover points, capture points, navigation and the deck cutaway.
##
## Navigation is baked in the vessel's OWN space and queried in its own space, so
## crews keep walking correctly while the ship flies and turns.

const CUT := preload("res://shaders/cutaway.gdshader")
const CUT_A := preload("res://shaders/cutaway_alpha.gdshader")
const INF := preload("res://shaders/infection.gdshader")

var team := 0
var faction := 1                  # whose crew palette (1, 2, 3 = pirates)
var cls := ""
var variant := 0                  # which procedural interior layout (0 = classic)
var display_name := ""
var kind := "ship"                # "ship" or "station"
var marks := {}                   # short marker name -> Node3D (e.g. "Bridge_CaptainChair", "M01CMD_ControlRoom")
var cover: Array = []             # [local position, low cover?, direction toward the cover (local)]
var nav_map: RID
var nav_region: RID
var doors: Array = []             # see the doors section
var elevators: Array = []         # {car, doors, deck, target, y, decks, center}
var zones: Array = []             # {name, center, half, infected, growth, purge, neighbors, spawn_t, module}
var occupants: Array = []         # characters aboard
var turrets: Array = []           # {node, cool, rest_yaw, base_pos}
var capture_points: Array = []    # {name, pos (local), progress, by, radius, module}
var alarm := 0.0                  # seconds of alarm left
var last_enemy := Vector3.INF     # local
var supplies := 100.0             # ammo, medical stores, parts: spent at armories and on repairs
var supply_cap := 300.0
var crew_roster: Array = []       # the roles this vessel is meant to have aboard (logistics refills it)
var destroyed := false
var aabb := AABB()                # local bounds
var inf_mat: ShaderMaterial
var pick: Area3D
var _door_t := 0.0
var _cap_t := 0.0
var _inf_t := 0.0
var _mat_cache := {}
var _light_mats: Array = []       # [shader material, normal colour, energy]: the ceiling lights (red alert)
var _red_on := false


# ------------------------------------------------------------------ setup

func setup_vessel(cls_: String, team_: int, faction_: int, name_: String) -> void:
	cls = cls_
	team = team_
	faction = faction_
	display_name = name_
	var prefix := cls + "_"
	inf_mat = ShaderMaterial.new()
	inf_mat.shader = INF
	var first := true
	var inner_top := 1.0e9
	for n0 in find_children("*_Interior", "MeshInstance3D", true, false):
		inner_top = minf(inner_top, ((n0 as MeshInstance3D).global_transform * (n0 as MeshInstance3D).get_aabb()).end.y - global_position.y)
	for n in find_children("*", "", true, false):
		var nm := String(n.name)
		if n is MeshInstance3D:
			if nm.ends_with("_Accent") and inner_top < 1.0e8:
				_strip_inner_bands(n, inner_top)
			_restyle(n)
			var bb: AABB = transform.affine_inverse() * (n.global_transform * n.get_aabb())
			aabb = bb if first else aabb.merge(bb)
			first = false
		elif n is StaticBody3D:
			var owner_name := String(n.get_parent().name)
			n.collision_layer = G.LAYER_DOOR if _is_door(owner_name) else G.LAYER_WORLD
			n.collision_mask = 0
		elif n.get_class() == "Node3D" and nm.begins_with(prefix):
			marks[nm.substr(prefix.length())] = n
	for k in marks:
		var m: Node3D = marks[k]
		if k.begins_with("CoverPt_"):
			var bits: PackedStringArray = k.split("_")
			var d := Vector3.ZERO
			match bits[2]:
				"XP": d = Vector3.RIGHT
				"XN": d = Vector3.LEFT
				"YP": d = Vector3.FORWARD          # Blender +Y = Godot -Z
				"YN": d = Vector3.BACK
			cover.append([m.position, bits[1] == "L", d])
		elif k.begins_with("Zone_"):
			zones.append({"name": k, "center": m.position, "half": m.scale.abs(), "infected": false, "growth": 0.0,
				"purge": 0.0, "neighbors": [], "spawn_t": 0.0, "module": _module_of(k)})
	_link_zones()
	_find_doors()
	_find_breach_walls()
	_find_elevators()
	_find_turrets()
	_make_pick()
	_update_infection_overlay()


func _module_of(k: String) -> String:
	for bit in k.split("_"):
		if bit.length() == 6 and bit.begins_with("M") and bit.substr(1, 2).is_valid_int():
			return bit
	return ""


func _is_door(n: String) -> bool:
	return (n.contains("Connector_") and n.contains("Door")) or n.contains("BreachDoor_") \
		or n.contains("RoomDoor_") or n.contains("SecureDoor_") or n.contains("BlastDoor_") or n.contains("Door_S") \
		or n.contains("AirlockPort_Door") or n.contains("AirlockStbd_Door") or n.contains("ElevatorDoor_") \
		or n.contains("OuterDoor") or n.contains("InnerDoor") or n.contains("CargoBayDoor")


## Some hulls' accent paint includes full-width bands that end up *inside* the hull at
## head height, right across the corridors. Drop those triangles (the outside paint stays).
static var _band_cache := {}


func _strip_inner_bands(mi: MeshInstance3D, top: float) -> void:
	if mi.mesh == null:
		return
	if _band_cache.has(mi.mesh):
		mi.mesh = _band_cache[mi.mesh]
		return
	var out := ArrayMesh.new()
	for si in mi.mesh.get_surface_count():
		var arr: Array = mi.mesh.surface_get_arrays(si)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		if idx.is_empty():
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			out.surface_set_material(out.get_surface_count() - 1, mi.mesh.surface_get_material(si))
			continue
		var keep := PackedInt32Array()
		for t in range(0, idx.size(), 3):
			var a: Vector3 = mi.transform * v[idx[t]]
			var b: Vector3 = mi.transform * v[idx[t + 1]]
			var c: Vector3 = mi.transform * v[idx[t + 2]]
			var lo := a.min(b).min(c)
			var hi := a.max(b).max(c)
			var inside: bool = hi.x - lo.x > 5.0 and lo.y > -4.6 and hi.y < top - 0.3 and absf((lo.x + hi.x) * 0.5) < 1.5
			if not inside:
				keep.append(idx[t])
				keep.append(idx[t + 1])
				keep.append(idx[t + 2])
		arr[Mesh.ARRAY_INDEX] = keep
		if keep.is_empty():
			continue
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(out.get_surface_count() - 1, mi.mesh.surface_get_material(si))
	_band_cache[mi.mesh] = out
	mi.mesh = out


## Swap the imported materials for the cutaway shader (and add the infection overlay).
func _restyle(mi: MeshInstance3D) -> void:
	if mi.mesh == null:
		return
	var see_through := false
	for i in mi.mesh.get_surface_count():
		var src: Material = mi.mesh.surface_get_material(i)
		if src == null:
			continue
		if not _mat_cache.has(src):
			var sm := ShaderMaterial.new()
			if src is BaseMaterial3D:
				var bm: BaseMaterial3D = src
				var transparent := bm.albedo_color.a < 0.99 or bm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
				sm.shader = CUT_A if transparent else CUT
				sm.set_shader_parameter("albedo", bm.albedo_color)
				if not transparent:
					sm.set_shader_parameter("metallic", bm.metallic)
					sm.set_shader_parameter("roughness", bm.roughness)
				if bm.emission_enabled:
					sm.set_shader_parameter("emission", bm.emission)
					sm.set_shader_parameter("emission_energy", bm.emission_energy_multiplier)
					if String(src.resource_name).contains("Lights"):
						_light_mats.append([sm, bm.emission, bm.emission_energy_multiplier])
			else:
				sm.shader = CUT
			_mat_cache[src] = sm
		mi.set_surface_override_material(i, _mat_cache[src])
		if (_mat_cache[src] as ShaderMaterial).shader == CUT_A:
			see_through = true
	# (no growth over glass, hangar shields and other see-through surfaces: on a transparent
	# surface the overlay flickered and speckled)
	if not see_through:
		mi.material_overlay = inf_mat


func _make_pick() -> void:
	pick = Area3D.new()
	pick.collision_layer = G.LAYER_PICK
	pick.collision_mask = 0
	pick.monitoring = false
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = aabb.size
	cs.shape = bs
	cs.position = aabb.get_center()
	pick.add_child(cs)
	add_child(pick)
	pick.set_meta("unit", self)


# ------------------------------------------------------------------ navigation

const NAV_CELL := 0.15


func bake_navigation() -> void:
	## Load the pre-baked navigation for this class (res://nav/), or bake it now.
	## Baking must happen while the vessel sits at the world origin with no rotation.
	var key := ("%s.res" % cls) if variant == 0 else ("%s_v%d.res" % [cls, variant])
	var nm: NavigationMesh = null
	for dir in ["res://nav/", "user://navcache/"]:
		if ResourceLoader.exists(dir + key):
			nm = load(dir + key)
			break
	if nm == null:
		nm = make_navmesh()
		DirAccess.make_dir_recursive_absolute("user://navcache")
		ResourceSaver.save(nm, "user://navcache/" + key)
	use_navmesh(nm)


func make_navmesh() -> NavigationMesh:
	var cell: float = G.get_meta("nav_cell", NAV_CELL)
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.35
	nm.agent_height = 1.75
	nm.agent_max_climb = 0.35
	nm.agent_max_slope = 46.0
	nm.cell_size = cell
	nm.cell_height = cell
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = G.LAYER_WORLD
	# ships: only the inside counts (the roof, hull ledges and fins are not somewhere to walk)
	if kind == "ship":
		for mi in find_children("*_Decks", "MeshInstance3D", true, false):
			var bb: AABB = transform.affine_inverse() * ((mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb())
			# from just under deck 0 to head height on the top deck (the roof stays out)
			bb.position -= Vector3(0.5, 0.6, 0.5)
			bb.size += Vector3(1.0, 0.6 + 3.0, 1.0)
			nm.filter_baking_aabb = bb
			break
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, src, self)
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	return nm


func use_navmesh(nm: NavigationMesh) -> void:
	nav_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_cell_size(nav_map, nm.cell_size)
	NavigationServer3D.map_set_cell_height(nav_map, nm.cell_height)
	NavigationServer3D.map_set_active(nav_map, true)
	nav_region = NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(nav_region, nav_map)
	NavigationServer3D.region_set_navigation_mesh(nav_region, nm)
	NavigationServer3D.map_force_update(nav_map)          # usable right away, not next frame


func nav_ok() -> bool:
	return nav_map.is_valid() and NavigationServer3D.map_get_iteration_id(nav_map) > 0


func path_local(from: Vector3, to: Vector3) -> PackedVector3Array:
	if not nav_ok():
		return PackedVector3Array()                       # not ready yet: wait rather than walk into walls
	return NavigationServer3D.map_get_path(nav_map, from, to, true)


func snap_local(p: Vector3) -> Vector3:
	return NavigationServer3D.map_get_closest_point(nav_map, p) if nav_ok() else p


func random_local() -> Vector3:
	if not nav_ok():
		return Vector3.ZERO
	var deck := randi() % maxi(1, int(round(aabb.end.y / 4.0)))
	var p := Vector3(randf_range(aabb.position.x, aabb.end.x) * 0.8, deck * 4.0 + 0.3,
		randf_range(aabb.position.z, aabb.end.z) * 0.9)
	return snap_local(p)


## A clear spot to put someone (local): on a deck floor, nothing solid around them, nobody
## already standing there. Near `near` (within r) if given, else anywhere aboard.
func clear_spot(near: Vector3 = Vector3.INF, r: float = 6.0) -> Vector3:
	if not nav_ok():
		return Vector3.ZERO if near == Vector3.INF else near
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.35
	q.shape = sph
	q.collision_mask = G.LAYER_WORLD
	var fallback := Vector3.INF
	for i in 18:
		var p: Vector3
		if near == Vector3.INF:
			p = random_local()
		else:
			var a := randf() * TAU
			p = snap_local(near + Vector3(cos(a), 0, sin(a)) * randf_range(0.0, r))
		if fallback == Vector3.INF:
			fallback = p
		if kind != "ground" and fmod(p.y + 400.0, 4.0) > 0.7:
			continue                                   # on top of something, not a deck floor
		q.transform = Transform3D(Basis(), to_global(p + Vector3(0, 1.0, 0)))
		if not space.intersect_shape(q, 1).is_empty():
			continue                                   # inside machinery or a wall
		var crowded := false
		for c in near_occupants(p, 1.0):
			if is_instance_valid(c) and c.state != "dead" and c.position.distance_to(p) < 0.8:
				crowded = true
				break
		if crowded:
			continue
		return p
	return fallback


func mark(name_: String) -> Node3D:
	return marks.get(name_, null)


func marks_like(pattern: String) -> Array:
	var out: Array = []
	for k in marks:
		if String(k).match(pattern):
			out.append(marks[k])
	return out


func local_of(n: Node3D) -> Vector3:
	return to_local(n.global_position)


# ------------------------------------------------------------------ doors
##
## Every door is modeled CLOSED and sits on the DOOR physics layer (kept out of the
## navigation bake), so paths run through doorways and the doors themselves decide
## who gets through:
##   kind "door"   ordinary room / corridor doors. Open for their own crew. Boarders
##                 kick them in (about 3 kicks), shoot them down, frag them or blow them.
##   kind "heavy"  compartment blast doors and station bulkheads. Too heavy to kick:
##                 shoot them down (slow), or a breaching charge.
##   kind "secure" bridge, hangar, cargo bay, reactor and locked rooms (armory, comms,
##                 systems): breaching charge ONLY. Bullets and grenades just scorch them.
## Destroyed doors stay open for good (blown off, or kicked flat onto the deck).

const DOOR_HP := {"door": 240.0, "heavy": 1400.0, "secure": 1.0e9}
const KICK_DMG := 90.0
const CHARGE_FUSE := 3.0
var _door_grid := {}              # Vector3i cell -> [door index]
var _door_moving: Array = []      # doors sliding right now
var _charges: Array = []          # [door, fuse left, mesh, team, by, push dir]


func door_kind(n: String) -> String:
	if n.contains("SecureDoor_") or n.contains("BreachDoor_"):
		return "secure"
	if n.contains("BlastDoor_") or (n.contains("Connector_") and n.contains("Door")):
		return "heavy"
	return "door"


func _find_doors() -> void:
	var inv := global_transform.affine_inverse()
	for mi in find_children("*", "MeshInstance3D", true, false):
		var n := String(mi.name)
		if not (n.contains("RoomDoor_") or n.contains("SecureDoor_") or n.contains("BreachDoor_")
				or n.contains("BlastDoor_") or n.contains("Door_S") or (n.contains("Connector_") and n.contains("Door"))):
			continue
		var bb: AABB = mi.get_aabb()
		var to_v: Transform3D = inv * mi.global_transform
		# the thin horizontal axis is the door's normal, the long one the way it slides
		var thin_x: bool = bb.size.x < bb.size.z
		var wa_node := Vector3(0, 0, 1) if thin_x else Vector3(1, 0, 0)
		var width: float = bb.size.z if thin_x else bb.size.x
		var nrm: Vector3 = (to_v.basis * (Vector3(1, 0, 0) if thin_x else Vector3(0, 0, 1)))
		nrm.y = 0.0
		var wa: Vector3 = to_v.basis * wa_node
		wa.y = 0.0
		var kind_ := door_kind(n)
		var d := {"node": mi, "name": n, "kind": kind_, "open": false, "breached": false, "fallen": false,
			"center": to_v * bb.get_center(), "n": nrm.normalized(), "wa": wa.normalized(), "half": width * 0.5,
			"force": 0.0, "hp": DOOR_HP[kind_], "amt": 0.0, "rest": mi.transform,
			"slide": mi.transform.basis * wa_node * width * 0.97, "idx": doors.size(), "kick_t": 0.0}
		for sb in mi.find_children("*", "StaticBody3D", true, false):
			sb.set_meta("door_of", self)
			sb.set_meta("door_idx", d["idx"])
		doors.append(d)
		var cell := _door_cell(d["center"])
		if not _door_grid.has(cell):
			_door_grid[cell] = []
		_door_grid[cell].append(d["idx"])


# ------------------------------------------------------------------ breachable walls
## Weak wall sections (BreachWall_n in the hull files, marked with hazard stripes): solid until
## a breaching charge or a grenadier's breaching round blows a doorway through. Each is
## door-shaped (kind "wall") so the squad stack-and-breach logic works on them; when one
## goes, a navigation link joins its two sides.

var breach_walls: Array = []
var _wall_links: Array = []


func _find_breach_walls() -> void:
	var inv := global_transform.affine_inverse()
	for mi in find_children("*BreachWall_*", "MeshInstance3D", true, false):
		var n := String(mi.name)
		if n.contains("_Charge"):
			continue
		var bb: AABB = mi.get_aabb()
		var to_v: Transform3D = inv * mi.global_transform
		var thin_x: bool = bb.size.x < bb.size.z
		var wa_node := Vector3(0, 0, 1) if thin_x else Vector3(1, 0, 0)
		var nrm: Vector3 = to_v.basis * (Vector3(1, 0, 0) if thin_x else Vector3(0, 0, 1))
		nrm.y = 0.0
		var wa: Vector3 = to_v.basis * wa_node
		wa.y = 0.0
		var c: Vector3 = to_v * bb.get_center()
		var d := {"node": mi, "name": n, "kind": "wall", "open": false, "breached": false, "fallen": false,
			"center": c, "n": nrm.normalized(), "wa": wa.normalized(), "half": (bb.size.z if thin_x else bb.size.x) * 0.5,
			"force": 0.0, "hp": 1.0e9, "amt": 0.0, "rest": mi.transform, "slide": Vector3.ZERO, "idx": -1,
			"kick_t": 0.0, "wall": breach_walls.size()}
		breach_walls.append(d)


## The unbreached wall section nearest p (vessel space) within r.
func wall_near(p: Vector3, r: float = 1.8) -> Dictionary:
	var best: Dictionary = {}
	var bd := r
	for d in breach_walls:
		if d["breached"]:
			continue
		var rel: Vector3 = (d["center"] as Vector3) - p
		if absf(rel.y - 1.2) > 1.6:
			continue
		var dd: float = Vector2(rel.x, rel.z).length()
		if dd < bd:
			bd = dd
			best = d
	return best


## Floor points on either side of a wall section (vessel space): [the side facing `toward`, the other].
func wall_sides(d: Dictionary, toward: Vector3) -> Array:
	var nrm: Vector3 = d["n"]
	var base: Vector3 = (d["center"] as Vector3) - Vector3(0, (d["center"] as Vector3).y - floorf(((d["center"] as Vector3).y + 0.5) / 4.0) * 4.0, 0)
	var s := 1.0 if (toward - (d["center"] as Vector3)).dot(nrm) >= 0.0 else -1.0
	return [snap_local(base + nrm * s * 1.1), snap_local(base - nrm * s * 1.1)]


func _open_wall(d: Dictionary) -> void:
	if not nav_ok():
		return
	var sides := wall_sides(d, (d["center"] as Vector3) + (d["n"] as Vector3))
	var l := NavigationServer3D.link_create()
	NavigationServer3D.link_set_map(l, nav_map)
	NavigationServer3D.link_set_bidirectional(l, true)
	NavigationServer3D.link_set_start_position(l, sides[0])
	NavigationServer3D.link_set_end_position(l, sides[1])
	NavigationServer3D.link_set_enabled(l, true)
	_wall_links.append(l)
	# rubble and scorch round the hole
	var frame := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.12, 0.12, 0.12)
	frame.mesh = bm
	frame.material_override = G._mat(Color(1.0, 0.45, 0.15), 2.5)
	add_child(frame)
	for i in 10:
		var bit := MeshInstance3D.new()
		var bb := BoxMesh.new()
		bb.size = Vector3(randf_range(0.15, 0.45), randf_range(0.05, 0.15), randf_range(0.15, 0.4))
		bit.mesh = bb
		bit.material_override = G._mat(Color(0.18, 0.19, 0.21), 0.0)
		add_child(bit)
		var side: float = 1.0 if i % 2 == 0 else -1.0
		bit.position = sides[0 if side > 0 else 1] + (d["wa"] as Vector3) * randf_range(-1.0, 1.0) + Vector3(0, 0.05, 0)
		bit.rotation.y = randf() * TAU
	frame.queue_free()


func _exit_tree() -> void:
	for l in _wall_links:
		NavigationServer3D.free_rid(l)
	_wall_links.clear()


## The navigation map and region are server-side: free them with the vessel, or every
## reload (jumps, landings, zone switches) leaves another active map behind.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_free_nav()


func _free_nav() -> void:
	if nav_region.is_valid():
		NavigationServer3D.free_rid(nav_region)
		nav_region = RID()
	if nav_map.is_valid():
		NavigationServer3D.free_rid(nav_map)
		nav_map = RID()


func _door_cell(p: Vector3) -> Vector3i:
	return Vector3i(floori(p.x / 4.0), floori(p.y / 4.0), floori(p.z / 4.0))


func _door_collision(d: Dictionary, on: bool) -> void:
	for c in (d["node"] as Node).find_children("*", "CollisionShape3D", true, false):
		c.set_deferred("disabled", not on)


func _set_door(d: Dictionary, open: bool) -> void:
	if d["open"] == open or d["breached"]:
		return
	d["open"] = open
	if open:
		G.stat("door_openings")
	_door_collision(d, not open)
	if not _door_moving.has(d):
		_door_moving.append(d)


func _animate_doors(dt: float) -> void:
	for d in _door_moving.duplicate():
		var want := 1.0 if d["open"] else 0.0
		d["amt"] = move_toward(d["amt"], want, dt * (2.2 if d["kind"] == "door" else 1.3))
		if d["breached"]:
			_door_moving.erase(d)
			continue
		var n: Node3D = d["node"]
		var t: Transform3D = d["rest"]
		var e: float = d["amt"] * d["amt"] * (3.0 - 2.0 * d["amt"])     # ease in/out
		n.transform = Transform3D(t.basis, t.origin + d["slide"] * e)
		if d["amt"] == want:
			_door_moving.erase(d)
	# the shake on a door that's being kicked
	for d in doors:
		if d["kick_t"] > 0.0:
			d["kick_t"] = max(0.0, d["kick_t"] - dt)
			if not d["breached"]:
				var t2: Transform3D = d["rest"]
				var push: Vector3 = d.get("push_n", Vector3.ZERO)
				(d["node"] as Node3D).transform = Transform3D(t2.basis, t2.origin + push * sin(d["kick_t"] * 40.0) * 0.03 * d["kick_t"] / 0.25)


## Blown off its frame: gone, with a blast on the far side.
func breach_door(d: Dictionary, by: Node = null, push: Vector3 = Vector3.ZERO) -> void:
	if d["breached"]:
		return
	_destroy_door(d)
	G.stat("doors_breached")
	(d["node"] as Node3D).visible = false
	G.explosion(to_global(d["center"]), 1.6 if d["kind"] != "wall" else 2.4)
	if d["kind"] == "wall":
		G.stat("walls_breached")
		_open_wall(d)
	if by != null and push != Vector3.ZERO:
		G.blast(to_global(d["center"] + push * 1.2), 2.6, 70.0, by)
	raise_alarm(d["center"])


## Kicked in / shot down: the panel falls flat onto the deck, away from whoever did it.
func knock_down(d: Dictionary, push: Vector3) -> void:
	if d["breached"]:
		return
	_destroy_door(d)
	G.stat("doors_knocked_down")
	d["fallen"] = true
	_lay_flat(d, push)
	G.flash(to_global(d["center"]), Color(1.0, 0.85, 0.6), 2.0, 3.0, 0.08)
	raise_alarm(d["center"])


func _lay_flat(d: Dictionary, push: Vector3) -> void:
	var n: Node3D = d["node"]
	var t: Transform3D = d["rest"]
	# push in the parent's space; the door's local up is its parent's up (doors aren't rotated)
	var nrm: Vector3 = d["n"]
	var sgn := 1.0 if push.dot(nrm) >= 0.0 else -1.0
	var axis_p: Vector3 = (n.get_parent() as Node3D).global_basis.inverse() * (global_basis * d["wa"])
	axis_p = axis_p.normalized()
	var push_p: Vector3 = (n.get_parent() as Node3D).global_basis.inverse() * (global_basis * (nrm * sgn))
	var best := Basis()
	for ang in [PI / 2 - 0.06, -(PI / 2 - 0.06)]:
		var rb := Basis(axis_p, ang)
		if (rb * Vector3.UP).dot(push_p) > 0.0:
			best = rb
	n.transform = Transform3D(best * t.basis, t.origin + push_p.normalized() * 0.12 + Vector3.UP * 0.06)
	n.visible = true


func _destroy_door(d: Dictionary) -> void:
	d["breached"] = true
	d["open"] = true
	d["hp"] = 0.0
	_door_collision(d, false)


## Bullets, kicks and explosions. Secure doors shrug off everything but a charge.
func damage_door(d: Dictionary, dmg: float, push: Vector3, kick: bool = false) -> void:
	if d["breached"] or G.is_client():
		return
	if d["kind"] == "secure" or (kick and d["kind"] != "door"):
		G.flash(to_global(d["center"]) + global_basis * (-push * 0.1), Color(1.0, 0.7, 0.4), 0.6, 1.0, 0.04)
		return
	d["hp"] -= dmg
	d["push_n"] = d["n"] * (1.0 if push.dot(d["n"]) >= 0.0 else -1.0)
	if kick:
		d["kick_t"] = 0.25
	if d["hp"] <= 0.0:
		knock_down(d, push)


## Called by bullets that hit a door's collider.
func door_hit(body: Object, dmg: float, from_world: Vector3) -> void:
	var i: int = body.get_meta("door_idx", -1)
	if i < 0 or i >= doors.size():
		return
	var d: Dictionary = doors[i]
	var push := to_local(from_world).direction_to(d["center"])
	push.y = 0.0
	damage_door(d, dmg, push.normalized())


## Explosions (grenades, rockets) knock out ordinary and heavy doors nearby.
func blast_doors(at_world: Vector3, radius: float, dmg: float) -> void:
	var p := to_local(at_world)
	if not aabb.grow(radius).has_point(p):
		return
	for d in doors:
		if d["breached"]:
			continue
		var dist: float = (d["center"] as Vector3).distance_to(p)
		if dist < radius + 0.5:
			var push: Vector3 = p.direction_to(d["center"])
			push.y = 0.0
			damage_door(d, dmg * 2.0 * (1.0 - dist / (radius + 0.5) * 0.5), push.normalized())


## Plant a breaching charge: it blows after a short fuse (any kind of door).
func plant_charge(d: Dictionary, by: Node) -> bool:
	if d["breached"] or d.get("charged", false) or G.is_client():
		return false                                     # (a client's charge is the host's to set)
	d["charged"] = true
	var push: Vector3 = (d["center"] as Vector3) - (by.position if by and by.get("vessel") == self else d["center"])
	push.y = 0.0
	var nrm: Vector3 = d["n"]
	push = nrm * (1.0 if push.dot(nrm) >= 0.0 else -1.0)
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 0.3, 0.08)
	m.mesh = bm
	m.material_override = G._mat(Color(1.0, 0.15, 0.1), 4.0)
	add_child(m)
	m.position = d["center"] - push * 0.12 + Vector3(0, -0.1, 0)
	m.look_at(to_global(m.position + push), Vector3.UP)
	_charges.append([d, CHARGE_FUSE, m, by.team if by else 0, by, push])
	G.say("Breaching charge set", by.team if by else 0)
	return true


func _update_charges(dt: float) -> void:
	for c in _charges.duplicate():
		c[1] -= dt
		var m: MeshInstance3D = c[2]
		if is_instance_valid(m):
			m.visible = fmod(c[1], 0.5) > 0.2 or c[1] < 0.6        # blinking
		if c[1] <= 0.0:
			_charges.erase(c)
			if is_instance_valid(m):
				m.queue_free()
			var by: Node = c[4] if is_instance_valid(c[4]) else null
			breach_door(c[0], by, c[5])


## The closed door in the way of someone at local position p heading in direction dir:
## a door whose doorway they are actually walking into (not one they're passing).
func door_blocking(p: Vector3, dir: Vector3, reach: float = 1.9) -> Dictionary:
	var cell := _door_cell(p)
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				for i in _door_grid.get(cell + Vector3i(dx, dy, dz), []):
					var d: Dictionary = doors[i]
					if d["open"] or d["breached"]:
						continue
					var rel: Vector3 = (d["center"] as Vector3) - p
					if absf(rel.y - 1.3) > 1.4:
						continue
					var nrm: Vector3 = d["n"]
					var dn := rel.dot(nrm)
					if absf(dn) > reach or absf(rel.dot(d["wa"])) > d["half"] + 0.45:
						continue
					if dir.length() < 0.01:
						return d
					var dd := dir.normalized().dot(nrm)
					if absf(dd) > 0.3 and signf(dd) == signf(dn):
						return d
	return {}


## The door nearest p (vessel space, any state), within r metres of its centre line.
func door_near(p: Vector3, r: float = 2.0) -> Dictionary:
	var best: Dictionary = {}
	var bd := r
	var cell := _door_cell(p)
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				for i in _door_grid.get(cell + Vector3i(dx, dy, dz), []):
					var d: Dictionary = doors[i]
					var rel: Vector3 = (d["center"] as Vector3) - p
					rel.y = 0.0
					if rel.length() < bd and absf((d["center"] as Vector3).y - 1.3 - p.y) < 1.6:
						bd = rel.length()
						best = d
	return best


## Doors open for their own crew standing near them.
func _update_doors() -> void:
	var want := {}
	for c in occupants:
		if not is_instance_valid(c) or c.state != "alive" or c.team != team:
			continue
		var cell := _door_cell(c.position)
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					for i in _door_grid.get(cell + Vector3i(dx, dy, dz), []):
						if not want.has(i) and (c.position + Vector3(0, 1.3, 0)).distance_to(doors[i]["center"]) < 2.6:
							want[i] = true
	for d in doors:
		if not d["breached"]:
			_set_door(d, want.has(d["idx"]))


# ------------------------------------------------------------------ elevators

func _find_elevators() -> void:
	for i in range(1, 6):
		var car: Node3D = null
		for mi in find_children("*_Elevator_%d" % i, "MeshInstance3D", true, false):
			car = mi
		if car == null:
			break
		var ds: Array = []
		var k := 0
		while true:
			var found := find_children("*_ElevatorDoor_%d_D%d" % [i, k], "MeshInstance3D", true, false)
			if found.is_empty():
				break
			var dn: Node3D = found[0]
			# deck 0's door is modeled open (shifted 1.85 m), the others closed
			var closed := dn.position + (Vector3(0, 0, 1.85) if k == 0 else Vector3.ZERO)
			ds.append({"node": dn, "closed": closed, "open": closed + Vector3(0, 0, -1.85), "amt": 1.0 if k == 0 else 0.0})
			k += 1
		elevators.append({"car": car, "doors": ds, "deck": 0, "target": 0, "y": 0.0, "decks": ds.size(),
			"wait": 0.0, "center": Vector3(car.position.x, 0, car.position.z)})


## Send an elevator to a deck. Returns the elevator's index or -1.
func call_elevator(idx: int, deck: int) -> void:
	if idx < 0 or idx >= elevators.size():
		return
	var e: Dictionary = elevators[idx]
	e["target"] = clampi(deck, 0, e["decks"] - 1)


func elevator_at(p_local: Vector3) -> int:
	for i in elevators.size():
		var c: Vector3 = elevators[i]["center"]
		if abs(p_local.x - c.x) < 2.6 and abs(p_local.z - c.z) < 2.6:
			return i
	return -1


func _update_elevators(dt: float) -> void:
	for e in elevators:
		var car: Node3D = e["car"]
		var moving: bool = e["target"] != e["deck"]
		# doors: open at the car's deck while it waits, closed while it moves
		for k in e["doors"].size():
			var d: Dictionary = e["doors"][k]
			var want := 1.0 if (not moving and k == e["deck"] and e["wait"] <= 0.0) else 0.0
			d["amt"] = move_toward(d["amt"], want, dt * 1.6)
			d["node"].position = d["closed"].lerp(d["open"], d["amt"])
		if not moving:
			e["wait"] = max(0.0, e["wait"] - dt)
			continue
		var doors_shut := true
		for d in e["doors"]:
			if d["amt"] > 0.01:
				doors_shut = false
		if not doors_shut:
			continue
		var ty: float = e["target"] * 4.0
		var y0: float = e["y"]
		var y1: float = move_toward(y0, ty, dt * 2.5)
		var dy := y1 - y0
		e["y"] = y1
		car.position.y = y1
		for c in occupants:                     # carry everyone standing in the car
			if abs(c.position.x - e["center"].x) < 1.4 and abs(c.position.z - e["center"].z) < 1.4 \
					and c.position.y > y0 - 0.6 and c.position.y < y0 + 2.0:
				c.position.y += dy
		if abs(y1 - ty) < 0.001:
			e["deck"] = e["target"]
			e["wait"] = 0.0


# ------------------------------------------------------------------ turrets

func _find_turrets() -> void:
	for mi in find_children("*Turret_*", "MeshInstance3D", true, false):
		if String(mi.name).ends_with("_Barrels"):
			continue
		var bar: Node3D = null
		for c in mi.get_children():
			if String(c.name).ends_with("_Barrels"):
				bar = c
		turrets.append({"node": mi, "cool": randf() * 2.0, "rest_yaw": mi.rotation.y, "base_pos": mi.position,
			"kick": 0.0, "bar": bar, "bar_rest": bar.position if bar else Vector3.ZERO,
			"module": _module_of(String(mi.name))})


## Swing a turret toward a world point. Returns true when it is pointing there.
func aim_turret(t: Dictionary, world_target: Vector3, dt: float) -> bool:
	var n: Node3D = t["node"]
	var lp: Vector3 = n.get_parent().to_local(world_target) - n.position
	var want := atan2(-lp.x, -lp.z)                         # barrels point along local -Z
	n.rotation.y = rotate_toward(n.rotation.y, want, dt * 1.6)
	t["kick"] = move_toward(t["kick"], 0.0, dt * 3.0)
	var bar: Node3D = t["bar"]
	if bar:                                                 # the barrels slam back and ease out again
		bar.position = t["bar_rest"] + Vector3(0, 0, 1) * t["kick"] * 0.9
	else:
		n.position = t["base_pos"] + n.transform.basis.z * t["kick"] * 0.6
	return abs(angle_difference(n.rotation.y, want)) < 0.12


func turret_muzzle(t: Dictionary) -> Vector3:
	var n: Node3D = t["node"]
	var reach_ := 3.2 * n.scale.x
	if t["bar"]:
		var bb: AABB = (t["bar"] as MeshInstance3D).get_aabb()
		reach_ = max(abs(bb.position.z), abs(bb.end.z))
	return n.global_position - n.global_transform.basis.z * reach_ + n.global_transform.basis.y * 0.8


# ------------------------------------------------------------------ zones and the infection

func _link_zones() -> void:
	var pad := 0.8 if kind == "ship" else 9.0
	for a in zones:
		for z in zones:
			if a == z:
				continue
			var d: Vector3 = (a["center"] - z["center"]).abs() - a["half"] - z["half"]
			if d.x < pad and d.y < pad and d.z < pad:
				a["neighbors"].append(z)


func zone_at(p_local: Vector3) -> Dictionary:
	for z in zones:
		var d: Vector3 = (p_local - z["center"]).abs() - z["half"]
		if d.x < 0.3 and d.y < 0.5 and d.z < 0.3:
			return z
	return {}


func infect_zone(z: Dictionary) -> void:
	if z.is_empty() or z["infected"]:
		return
	z["infected"] = true
	z["growth"] = max(z["growth"], 0.05)
	z["purge"] = 0.0
	z["spawn_t"] = 10.0
	raise_alarm(z["center"])
	if team == 1 or team == 2:                           # only news when it's aboard a real side's vessel
		G.say("%s: the infection has taken compartment %s" % [display_name, z["name"].trim_prefix("Zone_")], team)
	_update_infection_overlay()


func infected_fraction() -> float:
	if zones.is_empty():
		return 0.0
	var n := 0
	for z in zones:
		if z["infected"]:
			n += 1
	return float(n) / zones.size()


func _update_infection(dt: float) -> void:
	var changed := false
	for z in zones:
		if z["infected"]:
			# scientists with purge emitters burn it back (and it can't regrow while they do):
			# one clears a small room in about 20 s, a big one takes longer, more go faster
			var purgers := 0
			for c in occupants:
				if c.state == "alive" and c.purging and not zone_at(c.position).is_empty() and zone_at(c.position) == z:
					purgers += 1
			if purgers == 0 and z["growth"] < 1.0:
				z["growth"] = min(1.0, z["growth"] + dt / 20.0)
				changed = true
			if purgers > 0:
				var area: float = maxf(16.0, float(z["half"].x) * float(z["half"].z) * 4.0)
				var rate: float = clampf(60.0 / area, 0.4, 1.2) / 20.0
				z["growth"] -= dt * rate * (1.0 + 0.6 * (purgers - 1))
				changed = true
				if z["growth"] <= 0.0:
					z["infected"] = false
					z["growth"] = 0.0
					G.say("%s: %s purged clean" % [display_name, z["name"].trim_prefix("Zone_")], team)
			elif z["growth"] >= 1.0:
				z["spawn_t"] -= dt
				if z["spawn_t"] <= 0.0:
					z["spawn_t"] = 40.0
					var nb: Array = z["neighbors"].filter(func(x): return not x["infected"])
					if not nb.is_empty() and G.time > 60.0:
						infect_zone(nb[randi() % nb.size()])
					if G.match_node and G.match_node.has_method("spawn_swarmer"):
						G.match_node.spawn_swarmer(self, z)
	if changed:
		_update_infection_overlay()


func _update_infection_overlay() -> void:
	var mins: Array = []
	var maxs: Array = []
	var gr: Array = []
	for z in zones:
		if z["infected"] and mins.size() < 32:
			mins.append(z["center"] - z["half"] - Vector3(0.3, 0.3, 0.3))
			maxs.append(z["center"] + z["half"] + Vector3(0.3, 0.3, 0.3))
			gr.append(z["growth"])
	while mins.size() < 32:
		mins.append(Vector3.ZERO)
		maxs.append(Vector3.ZERO)
		gr.append(0.0)
	inf_mat.set_shader_parameter("count", _infected_count())
	inf_mat.set_shader_parameter("bmin", PackedVector3Array(mins))
	inf_mat.set_shader_parameter("bmax", PackedVector3Array(maxs))
	inf_mat.set_shader_parameter("growth", PackedFloat32Array(gr))


func _infected_count() -> int:
	var n := 0
	for z in zones:
		if z["infected"]:
			n += 1
	return min(n, 32)


# ------------------------------------------------------------------ alarm, capture, occupants

## Red alert: the ceiling lights pulse red while the alarm lasts.
func _red_alert_lights() -> void:
	var on := alarm > 0.0 and not destroyed
	if on:
		var k: float = 0.55 + 0.45 * sin(G.time * 5.0)
		for m in _light_mats:
			m[0].set_shader_parameter("emission", Color(1.0, 0.08, 0.04))
			m[0].set_shader_parameter("emission_energy", m[2] * (0.4 + 1.4 * k))
	elif _red_on:
		for m in _light_mats:
			m[0].set_shader_parameter("emission", m[1])
			m[0].set_shader_parameter("emission_energy", m[2])
	_red_on = on


## Posts with nobody alive to fill them (roles), for the logistics to send replacements.
func crew_missing() -> Array:
	var have := {}
	for c in occupants:
		if is_instance_valid(c) and c.team == team and c.state != "dead":
			have[c.role] = have.get(c.role, 0) + 1
	var out: Array = []
	var need := {}
	for r in crew_roster:
		need[r] = need.get(r, 0) + 1
	for r in need:
		for i in max(0, need[r] - have.get(r, 0)):
			out.append(r)
	return out


## Where people and cargo come aboard (vessel space): a cargo bay pad, else a hangar pad, else the garrison.
func arrival_point() -> Vector3:
	for pat in ["CargoBay_DarterPad_?", "Hangar_LandingPad_?", "*_Garrison", "PlayerSpawn_*", "*_ControlRoom"]:
		var m: Array = marks_like(pat)
		if not m.is_empty():
			return snap_local(local_of(m[0]))
	return random_local()


## Boarding craft on the way: general quarters, red lights, before anyone is aboard.
func red_alert(why: String) -> void:
	if alarm <= 0.0 and G.sfx:
		G.sfx.play("alarm", to_global(aabb.get_center()), -4.0, true)
	if alarm <= 0.0:
		G.say("RED ALERT aboard %s: %s" % [display_name, why], team)
	alarm = max(alarm, 75.0)


func raise_alarm(at_local: Vector3) -> void:
	if alarm <= 0.0 and team == G.player_team:
		G.say("ALERT: intruders aboard %s" % display_name, team)
	alarm = 90.0
	last_enemy = at_local


func board(c: Node) -> void:
	if not occupants.has(c):
		occupants.append(c)


func leave(c: Node) -> void:
	occupants.erase(c)


func add_capture_point(name_: String, local_pos: Vector3, radius: float, module_: String = "") -> void:
	capture_points.append({"name": name_, "pos": local_pos, "progress": 0.0, "by": 0, "radius": radius,
		"module": module_, "owner": team})


func _update_capture(dt: float) -> void:
	for cp in capture_points:
		var counts := {}
		for c in occupants:
			if c.state == "alive" and c.team != 4 and (c.position - cp["pos"]).length() < cp["radius"]:
				counts[c.team] = counts.get(c.team, 0) + 1
		var owner: int = cp["owner"]
		var attackers: Array = counts.keys().filter(func(t): return t != owner)
		if counts.has(owner) or attackers.size() != 1:
			cp["progress"] = max(0.0, cp["progress"] - dt * 0.1)
			continue
		var t: int = attackers[0]
		if cp["by"] != t:
			cp["by"] = t
			cp["progress"] = 0.0
		cp["progress"] += dt / 15.0 * min(3, counts[t]) / 2.0
		if cp["progress"] >= 1.0:
			cp["progress"] = 0.0
			cp["owner"] = t
			on_captured(cp, t)


func on_captured(_cp: Dictionary, _by: int) -> void:
	pass                                     # ship.gd / station.gd


# ------------------------------------------------------------------ who's near whom
## Characters look for each other (targets, teammates, cover being taken) many times a
## second. On a ship that's a handful; on a world's open ground it can be a couple of
## hundred, so they're bucketed into a coarse grid and a lookup only checks nearby cells.

const GRID_CELL := 16.0
var _grid := {}
var _grid_frame := -1


func near_occupants(p: Vector3, r: float) -> Array:
	if occupants.size() < 40:
		return occupants
	var f := Engine.get_physics_frames()
	if f - _grid_frame >= 6:
		_grid_frame = f
		_grid.clear()
		for c in occupants:
			if is_instance_valid(c):
				var k := Vector2i(int(floor(c.position.x / GRID_CELL)), int(floor(c.position.z / GRID_CELL)))
				if _grid.has(k):
					(_grid[k] as Array).append(c)
				else:
					_grid[k] = [c]
	var out: Array = []
	var x0 := int(floor((p.x - r) / GRID_CELL))
	var x1 := int(floor((p.x + r) / GRID_CELL))
	var z0 := int(floor((p.z - r) / GRID_CELL))
	var z1 := int(floor((p.z + r) / GRID_CELL))
	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			var cell = _grid.get(Vector2i(x, z))
			if cell != null:
				for c in cell:
					if is_instance_valid(c):
						out.append(c)
	return out


# ------------------------------------------------------------------ demolition charges
## Boarders can wreck a vessel's medbay (no more patching up in its beds) or its armory
## (no more rearming at its lockers). A charge is a visible, blinking, beeping package
## that goes off after 10 seconds unless a defender gets to it and defuses it (E, or any
## crewman standing on it for 3 s). Engineers repair a wrecked room back into service.

var rooms_down := {}               # "medbay" / "armory" -> true while wrecked
var demo_charges: Array = []       # {node, local, t, team, room, defuse}
var _demo_ai_t := 0.0
const DEMO_FUSE := 10.0


func room_down(room: String) -> bool:
	return rooms_down.get(room, false)


## Where to put a charge to wreck `room` (local), or INF if this vessel hasn't one.
func room_spot(room: String) -> Vector3:
	var ms: Array = marks_like("Medbay_*_Bed_*") if room == "medbay" else (marks_like("Armory_*_Resupply") + marks_like("Armory_*_Counter") + marks_like("*_ReadyLocker"))
	if ms.is_empty():
		return Vector3.INF
	return local_of(ms[0])


func room_near(p_local: Vector3, r: float = 3.0) -> String:
	for room in ["medbay", "armory"]:
		var sp := room_spot(room)
		if sp != Vector3.INF and sp.distance_to(p_local) < r and not room_down(room):
			for ch in demo_charges:
				if ch["room"] == room:
					return ""
			return room
	return ""


func plant_demo(p_local: Vector3, room: String, by_team: int) -> void:
	var n := Node3D.new()
	add_child(n)
	n.position = p_local + Vector3(0, 0.4, 0)
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.4, 0.25, 0.3)
	body.mesh = bm
	body.material_override = G._mat(Color(0.25, 0.25, 0.22))
	n.add_child(body)
	var lamp := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.06
	sm.height = 0.12
	lamp.mesh = sm
	lamp.material_override = G._mat(Color(1.0, 0.15, 0.1), 6.0)
	lamp.position = Vector3(0, 0.16, 0)
	lamp.name = "Lamp"
	n.add_child(lamp)
	demo_charges.append({"node": n, "local": p_local, "t": DEMO_FUSE, "team": by_team, "room": room, "defuse": 0.0})
	G.say("%s: demolition charges on the %s! Defuse them (E) or lose it" % [display_name, room], team)
	G.say("Charges set on the %s's %s: 10 s" % [display_name, room], by_team)
	raise_alarm(p_local)


## Defuse a charge near p (local) if it isn't ours. True if one was defused.
func defuse_near(p_local: Vector3, by_team: int) -> bool:
	for ch in demo_charges:
		if ch["team"] != by_team and (ch["local"] as Vector3).distance_to(p_local) < 2.4:
			_remove_charge(ch)
			G.say("%s: charge on the %s defused" % [display_name, ch["room"]], team)
			return true
	return false


func _remove_charge(ch: Dictionary) -> void:
	if is_instance_valid(ch["node"]):
		ch["node"].queue_free()
	demo_charges.erase(ch)


func _charges_tick(dt: float) -> void:
	for ch in demo_charges.duplicate():
		ch["t"] = float(ch["t"]) - dt
		var lamp: Node3D = ch["node"].get_node_or_null("Lamp") if is_instance_valid(ch["node"]) else null
		if lamp:
			lamp.visible = fmod(float(ch["t"]), 1.0 if ch["t"] > 3.0 else 0.3) > (0.5 if ch["t"] > 3.0 else 0.15)
		# a defender standing on it works it loose
		for c in occupants:
			if is_instance_valid(c) and c.state == "alive" and c.team != ch["team"] and c != G.possessed \
					and c.position.distance_to(ch["local"]) < 1.8:
				ch["defuse"] = float(ch["defuse"]) + dt
				break
		if float(ch["defuse"]) >= 3.0:
			_remove_charge(ch)
			G.say("%s: charge on the %s defused" % [display_name, ch["room"]], team)
			continue
		if float(ch["t"]) <= 0.0:
			var wp: Vector3 = to_global(ch["local"])
			_remove_charge(ch)
			G.explosion(wp, 6.0)
			G.blast(wp, 6.0, 90.0, null)
			rooms_down[ch["room"]] = true
			if get("repairs") != null:
				get("repairs").append({"pos": snap_local(ch["local"]), "amount": 900.0, "room": ch["room"]})
			G.say("%s: the %s is WRECKED%s" % [display_name, ch["room"],
				" (no healing in its beds)" if ch["room"] == "medbay" else " (no rearming at its lockers)"], team)
			G.stat("rooms_wrecked")
	# boarders who find themselves in a medbay or armory set charges
	_demo_ai_t -= dt
	if _demo_ai_t > 0.0:
		return
	_demo_ai_t = 3.0
	_retreat_check()
	for c in occupants:
		if not is_instance_valid(c) or c.state != "alive" or c == G.possessed or not G.enemies(c.team, team) or c.team == 4:
			continue
		if not c.role in ["breacher", "drop_trooper", "heavy", "squad_leader"]:
			continue
		var room := room_near(c.position, 5.0)
		if room != "" and randf() < 0.5:
			plant_demo(c.position, room, c.team)
			return


## A boarding action that's lost: when the boarders are down to a handful and outnumbered
## two to one, the survivors fall back to where they came in (pod breaches, airlocks) and
## get out; they rejoin the berths of their nearest ship.
func _retreat_check() -> void:
	if not has_method("boarding_entries"):
		return
	var mine := 0
	var att := {}
	for c in occupants:
		if not is_instance_valid(c) or c.state != "alive":
			continue
		if c.team == team:
			mine += 1
		elif c.team != 4 and G.enemies(c.team, team):
			att[c.team] = int(att.get(c.team, 0)) + 1
	for t in att:
		var n: int = att[t]
		if n > 3 or mine < maxi(4, n * 2):
			continue
		var outs: Array = []
		for e in call("boarding_entries", global_position):
			if e.size() > 2 and e[2] is Node3D:
				outs.append(snap_local(to_local((e[2] as Node3D).global_position)))
		if outs.is_empty():
			continue
		for c in occupants:
			if not is_instance_valid(c) or c.state != "alive" or c.team != t or c == G.possessed:
				continue
			var best: Vector3 = outs[0]
			for o in outs:
				if (o as Vector3).distance_to(c.position) < best.distance_to(c.position):
					best = o
			if not c.has_meta("retreat_to"):
				c.set_meta("retreat_to", best)
				if t == 1 or team == 1:
					G.say("Boarders on %s are falling back to their pods" % display_name, t)
			c.order = {"type": "move", "pos": best, "vessel": self}
			c.run = true
	# the ones who made it out
	for c in occupants.duplicate():
		if is_instance_valid(c) and c.state == "alive" and c.has_meta("retreat_to") and c.position.distance_to(c.get_meta("retreat_to")) < 2.5:
			var home: Node = null
			var bd := 1.0e9
			for v in G.vessels:
				if is_instance_valid(v) and not v.destroyed and v.team == c.team and v.kind == "ship" and v != self:
					var d: float = v.global_position.distance_to(global_position)
					if d < bd:
						bd = d
						home = v
			if home:
				home.troops = mini(home.berth_cap, home.troops + 1)
			G.match_node.logistics._remove_person(c)
			G.stat("boarders_retreated")


## A wrecked room is back in service once its repair job is done.
func room_repaired(job: Dictionary) -> void:
	if job.has("room"):
		rooms_down.erase(job["room"])
		G.say("%s: the %s is back in service" % [display_name, job["room"]], team)


func vessel_process(dt: float) -> void:
	# a network client only animates: charges, captures and the infection are the host's to run
	# (the slow sync brings their results: doors, walls, teams, zones)
	var host := not G.is_client()
	if host:
		if not demo_charges.is_empty() or _demo_ai_t <= 0.0:
			_charges_tick(dt)
		else:
			_demo_ai_t -= dt
	alarm = max(0.0, alarm - dt)
	_door_t -= dt
	if _door_t <= 0.0:
		_door_t = 0.15
		_update_doors()
	_animate_doors(dt)
	if host and not _charges.is_empty():
		_update_charges(dt)
	_update_elevators(dt)
	_red_alert_lights()
	if host:
		_cap_t -= dt
		if _cap_t <= 0.0:
			_cap_t = 0.5
			_update_capture(0.5)
		_inf_t -= dt
		if _inf_t <= 0.0:
			_inf_t = 0.5
			_update_infection(0.5)
	inf_mat.set_shader_parameter("to_local", global_transform.affine_inverse())
