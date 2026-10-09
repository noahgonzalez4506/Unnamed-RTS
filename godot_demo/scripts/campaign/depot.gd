extends RefCounted
## Ground cargo. A landed supply ship can put crates down at the foot of its front ramp: a
## forward supply depot. Troops near it rearm and get fresh med pens, and vehicles near it
## are patched up. The crates are cover too. LOAD CARGO goes the other way: the ramp comes
## down and the depot's crates and any salvage your troops have secured are hauled up into
## the front bay, then into the fleet's stores. Depots stay on the world between landings.

const BAYS := preload("res://scripts/campaign/bays.gd")
const CARGO_VIEW := preload("res://scripts/campaign/cargo_view.gd")
const UNLOAD := ["munitions", "munitions", "munitions", "medical", "medical", "alloys"]
const CRATE_COST := 25.0          # alloys per crate put down
const CHARGE := 30.0              # resupplies per crate before it's empty
const REACH := 20.0               # troops this close to a crate can rearm
const HAUL_DEPOT := 160.0         # LOAD CARGO: depot crates this close to the ramp
const HAUL_SECURED := 650.0       # ...and secured salvage this close


static func key() -> String:
	var c = G.campaign
	return "depot_%d_%d_%d" % [c.current, int(c.surface.get("planet", 0)), int(c.surface.get("site", 0))]


static func _record() -> Array:
	var w: Dictionary = G.campaign.world.get(key(), {})
	if not w.has("crates"):
		w["crates"] = []
		G.campaign.world[key()] = w
	return w["crates"]


static func is_hauler(s: Node) -> bool:
	return is_instance_valid(s) and s.get("kind") == "ship" and s.cls == "SMALL_SUPPORT"


## Rebuild the crates recorded on this world (called when the surface loads).
static func restore(m: Node) -> void:
	m.set_meta("depot_crates", [])
	for rec in _record():
		_spawn(m, Vector3(float(rec[0]), 0, float(rec[1])), String(rec[2]), rec)


static func _spawn(m: Node, world_xz: Vector3, good: String, rec: Array) -> Node3D:
	var b := StaticBody3D.new()
	b.collision_layer = G.LAYER_WORLD
	m.add_child(b)
	b.global_position = Vector3(world_xz.x, m.ground_y(world_xz.x, world_xz.z), world_xz.z)
	b.rotation.y = randf() * TAU
	b.scale = Vector3.ONE * 1.5
	CARGO_VIEW._crate(b, Vector3(0, 0.53, 0), good)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.2, 1.05, 1.2)
	cs.shape = bs
	cs.position.y = 0.53
	b.add_child(cs)
	b.set_meta("rec", rec)
	b.set_meta("good", good)
	for k in 4:
		var d := Vector3(sin(k * PI * 0.5), 0, cos(k * PI * 0.5))
		m.ground_cover.append([b.global_position + d * 1.6, true, -d])
	(m.get_meta("depot_crates") as Array).append(b)
	return b


## UNLOAD CARGO: six crates down the ramp, laid out in two rows by its foot.
static func unload(m: Node, s: Node) -> String:
	if not m.on_surface or m.ground == null:
		return "Land first"
	if not is_hauler(s):
		return "Only supply ships carry ground cargo (front bay)"
	var r: Dictionary = G.campaign.stores
	var cost := CRATE_COST * UNLOAD.size()
	if float(r.get("alloys", 0.0)) < cost:
		return "Not enough alloys to fill a depot (%d needed)" % int(cost)
	r["alloys"] = float(r["alloys"]) - cost
	BAYS.ramp_down(s)
	var foot: Vector3 = BAYS.ramp_foot(s)
	var out: Vector3 = foot - s.global_position
	out.y = 0.0
	out = out.normalized()
	var side := out.cross(Vector3.UP)
	var recs := _record()
	var n := 0
	for i in UNLOAD.size():
		var p: Vector3 = foot + out * (10.0 + (i / 3) * 3.5) + side * ((i % 3) * 3.2 - 3.2) + Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4))
		var rec: Array = [p.x, p.z, UNLOAD[i], CHARGE]
		recs.append(rec)
		var b := _spawn(m, foot, UNLOAD[i], rec)
		var tw := b.create_tween()
		tw.tween_interval(1.6 + i * 0.5)
		tw.tween_property(b, "global_position", Vector3(p.x, m.ground_y(p.x, p.z), p.z), 1.4)
		n += 1
	s.get_tree().create_timer(6.0 + UNLOAD.size() * 0.5).timeout.connect(func():
		if is_instance_valid(s):
			BAYS.ramp_up(s))
	return "%s: ramp down, %d supply crates unloaded. Troops near them rearm, vehicles are patched up" % [s.display_name, n]


## LOAD CARGO: the depot's crates near the ramp and every salvage cache our troops have
## secured are hauled up the ramp into the front bay. Crates go back into stores; salvage rides
## in the ship's hold until it reaches one of our stations. `salvage_only` (AUTO HAUL) leaves
## the depot alone and says nothing when there's nothing to load.
static func load_cargo(m: Node, s: Node, salvage_only: bool = false) -> String:
	if not m.on_surface or m.ground == null:
		return "Land first"
	if not is_hauler(s):
		return "Only supply ships can load ground cargo (front bay)"
	var foot: Vector3 = BAYS.ramp_foot(s)
	var crates: Array = m.get_meta("depot_crates", [])
	var hauled: Array = []
	var gains := {}
	for b in crates.duplicate():
		if salvage_only or not is_instance_valid(b) or b.global_position.distance_to(foot) > HAUL_DEPOT:
			continue
		var rec: Array = b.get_meta("rec")
		var left: float = float(rec[3]) / CHARGE
		# what's left in a crate goes back to stores as alloys
		gains["alloys"] = float(gains.get("alloys", 0.0)) + CRATE_COST * left
		_record().erase(rec)
		crates.erase(b)
		hauled.append(b)
	var salvaged := 0
	for cache in m.caches.duplicate():
		if not is_instance_valid(cache) or cache.has_meta("hauling"):
			continue
		var d: float = cache.global_position.distance_to(foot)
		if (d < HAUL_DEPOT and not salvage_only) or (cache.has_meta("secured") and d < HAUL_SECURED):
			cache.set_meta("hauling", true)
			hauled.append(cache)
			salvaged += 1
	if hauled.is_empty():
		if salvage_only:
			return ""
		return "Nothing to load: put a depot down (UNLOAD CARGO), or have troops secure salvage within %d m" % int(HAUL_SECURED)
	BAYS.ramp_down(s)
	var r: Dictionary = G.campaign.stores
	for g in gains:
		r[g] = float(r.get(g, 0.0)) + float(gains[g])
	var i := 0
	for n in hauled:
		var tw: Tween = n.create_tween()
		tw.tween_interval(1.4 + i * 0.4)
		tw.tween_property(n, "global_position", foot + Vector3.UP * 0.5, clampf(n.global_position.distance_to(foot) / 40.0, 0.8, 8.0))
		tw.tween_property(n, "global_position", s.global_position, 1.2)
		if n.has_meta("cache"):
			tw.tween_callback(func():
				if is_instance_valid(n):
					m._take_cache(n, s if is_instance_valid(s) else null))
		else:
			tw.tween_callback(n.queue_free)
		i += 1
	s.get_tree().create_timer(12.0).timeout.connect(func():
		if is_instance_valid(s):
			BAYS.ramp_up(s))
	return "%s: loading %d crates and %d salvage caches into the front bay%s" % [s.display_name, hauled.size() - salvaged, salvaged,
		" (salvage rides in the hold until you reach one of your stations)" if salvaged > 0 else ""]


## Once a second: depots rearm troops and patch vehicles; troops standing on salvage secure it.
static func tick(m: Node) -> void:
	if m.ground == null:
		return
	var crates: Array = m.get_meta("depot_crates", [])
	for b in crates.duplicate():
		if not is_instance_valid(b):
			crates.erase(b)
			continue
		var rec: Array = b.get_meta("rec")
		if float(rec[3]) <= 0.0:
			continue
		var good: String = b.get_meta("good")
		var bp: Vector3 = b.global_position
		for c in m.ground.occupants:
			if not is_instance_valid(c) or c.team != 1 or c.state != "alive" or c.global_position.distance_to(bp) > REACH:
				continue
			if good == "munitions" and c.armed and c.spare.size() < 3:
				c.spare = ["re_1", "re_2", "re_3"]
				rec[3] = float(rec[3]) - 1.0
			elif good == "medical" and c.medpens.size() < c.pen_cap():
				c.top_up_pens(true)
				rec[3] = float(rec[3]) - 1.0
		if good == "alloys":
			for v in G.vehicles:
				if is_instance_valid(v) and v.team == 1 and v.hp < v.max_hp and v.global_position.distance_to(bp) < REACH + 8.0:
					v.hp = minf(v.max_hp, v.hp + 25.0)
					rec[3] = float(rec[3]) - 0.25
		if float(rec[3]) <= 0.0:
			b.scale = Vector3(1.5, 0.5, 1.5)             # emptied: flattened, kept as cover
	for cache in m.caches:
		if not is_instance_valid(cache) or cache.has_meta("secured"):
			continue
		var cp: Vector3 = cache.global_position
		var got := false
		for c in m.ground.occupants:
			if is_instance_valid(c) and c.team == 1 and c.state == "alive" and c.global_position.distance_to(cp) < 8.0:
				got = true
				break
		if not got:
			for v in G.vehicles:
				if is_instance_valid(v) and v.team == 1 and v.global_position.distance_to(cp) < 10.0:
					got = true
					break
		if got:
			cache.set_meta("secured", true)
			for ch in cache.get_children():
				if ch is Label3D:
					(ch as Label3D).text = "SECURED: %s  ·  load with a supply ship" % String(cache.get_meta("cache")).to_upper()
					(ch as Label3D).modulate = Color(0.5, 1.0, 0.6)
			G.say("Salvage secured (%s): bring a supply ship within %d m and LOAD CARGO" % [cache.get_meta("cache"), int(HAUL_SECURED)], 1)
