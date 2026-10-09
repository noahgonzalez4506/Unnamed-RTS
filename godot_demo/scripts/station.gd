extends "res://scripts/vessel.gd"
## A station, outpost or ground base. Every module has its own hull, state, control
## room (a capture point) and sabotage points. Taking the root module (command,
## outpost or ground core) takes the whole station.

const CODES := {"CMD": "command_core", "OUT": "outpost_core", "RCT": "reactor", "MIN": "mining_rig",
	"GAS": "gas_skimmer", "REF": "refinery", "BRD": "breeder_reactor", "FAB": "fabricator", "CFD": "core_foundry",
	"ASM": "assembly_plant", "YDS": "shipyard_small", "YDM": "shipyard_medium", "YDL": "shipyard_large",
	"STO": "storage_depot", "FUE": "fuel_depot", "DOK": "docking_ring", "BAR": "barracks", "DEF": "defense_platform",
	"SHD": "shield_generator", "COM": "comm_relay", "GCR": "ground_core", "DRL": "surface_drill",
	"GBT": "ground_battery", "PAD": "landing_pads"}
const BOLT_SPEED := 700.0
const SQUAD := ["squad_leader", "rifleman", "rifleman", "breacher", "medic", "heavy", "grenadier", "rifleman"]

var modules := {}                  # code -> {name, hull, max, armor, state, team, center (local)}
var root_code := ""
var shields := 0.0
var max_shields := 0.0
var bolts: Array = []
var training: Array = []           # [time left, roles]
var reserve := 24                  # robots waiting in the barracks for a ship (see logistics.gd)
var reserve_cap := 60
var _recruit_t := 0.0
var repairs: Array = []            # {pos (local), amount, module}
var since_hit := 99.0
var selected := false
var _sel: MeshInstance3D


## The starter station as a T: the docking module (and the connector that reaches it)
## swings round from the second hub's side port to its open end port, so the docking boom
## runs out sideways across the end of the spine.
func _t_layout(cls_: String) -> void:
	var hub: Node3D = null
	for n in find_children("*H02_Deck*", "MeshInstance3D", true, false):
		hub = n
		break
	if hub == null:
		return
	var hb: AABB = (hub as MeshInstance3D).global_transform * (hub as MeshInstance3D).get_aabb()
	var pivot := Vector3(hb.get_center().x, 0.0, hb.get_center().z)
	var rot := Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3.ZERO)
	var xf := Transform3D(Basis(), pivot) * rot * Transform3D(Basis(), -pivot)
	var moved := {}
	for n in find_children("*", "", true, false):
		var nm := String(n.name)
		if not (n is Node3D) or not (nm.contains("M05DOK") or nm.contains("T02L")):
			continue
		var par: Node = n.get_parent()
		if par and (String(par.name).contains("M05DOK") or String(par.name).contains("T02L")):
			continue                                        # (moves with its parent)
		(n as Node3D).global_transform = xf * (n as Node3D).global_transform
		moved[n] = true


func setup_station(cls_: String, team_: int, faction_: int, name_: String) -> void:
	kind = "station"
	if cls_.begins_with("STATION_STARTER"):
		_t_layout(cls_)
	setup_vessel(cls_, team_, faction_, name_)
	supply_cap = 3000.0
	supplies = 1500.0
	setup_docks()
	for k in marks:
		var s := String(k)
		if s.ends_with("_ControlRoom") and s.begins_with("M") and _module_of(s) != "":
			var code := _module_of(s)
			var nm: String = CODES.get(code.substr(3), "module")
			var md: Dictionary = G.economy.get("modules", {}).get(nm, {})
			var mx := float(md.get("hull", 2500))
			var zone: Node3D = mark("Zone_" + code)
			modules[code] = {"name": nm, "hull": mx, "max": mx, "armor": float(md.get("armor", 0.2)),
				"state": "online", "team": team, "center": local_of(zone) if zone else local_of(marks[k])}
			add_capture_point(code, local_of(marks[k]), 5.0, code)
			if nm.ends_with("_core") and root_code == "":
				root_code = code
			show_module_state(code, "online")
	for code in modules:
		if modules[code]["name"] == "shield_generator":
			max_shields += 5000.0
	shields = max_shields
	_make_selection_ring()


func _make_selection_ring() -> void:
	_sel = MeshInstance3D.new()
	var t := TorusMesh.new()
	var r := maxf(aabb.size.x, aabb.size.z) * 0.55
	t.inner_radius = r
	t.outer_radius = r + 3.0
	t.rings = 64
	_sel.mesh = t
	_sel.material_override = G._mat(G.team_color(team), 1.5)
	_sel.position = Vector3(aabb.get_center().x, -2.0, aabb.get_center().z)
	_sel.visible = false
	add_child(_sel)


func set_selected(on: bool) -> void:
	selected = on
	_sel.visible = on
	_sel.material_override = G._mat(G.team_color(team), 1.5)


func module_ok(code: String) -> bool:
	return modules.has(code) and modules[code]["state"] == "online"


func modules_online() -> int:
	var n := 0
	for code in modules:
		if modules[code]["state"] == "online":
			n += 1
	return n


func set_module_state(code: String, st: String) -> void:
	if not modules.has(code) or modules[code]["state"] == st:
		return
	modules[code]["state"] = st
	show_module_state(code, st)
	G.say("%s %s (%s): %s" % [display_name, code, modules[code]["name"].replace("_", " "), st.to_upper()], team)


# ------------------------------------------------------------------ per frame

func _physics_process(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	vessel_process(dt)
	G.stat("us_vessel_common", Time.get_ticks_usec() - t0)
	_update_bolts(dt)
	if destroyed:
		return
	since_hit += dt
	if since_hit > 8.0 and shields < max_shields and _shield_up():
		shields = min(max_shields, shields + max_shields * 0.02 * dt)
	_turrets(dt)
	if G.is_client():
		return
	_training(dt)
	_repair_tick(dt)
	_infection_states()


func _shield_up() -> bool:
	for code in modules:
		if modules[code]["name"] == "shield_generator" and modules[code]["state"] == "online":
			return true
	return false


## A module whose compartment the infection holds stops working until it is purged.
func _infection_states() -> void:
	for z in zones:
		var code: String = z["module"]
		if code == "" or not modules.has(code):
			continue
		var st: String = modules[code]["state"]
		if z["infected"] and z["growth"] > 0.5 and st != "infected" and st != "destroyed":
			set_module_state(code, "infected")
		elif not z["infected"] and st == "infected":
			set_module_state(code, "disabled")          # engineers take it from here
			_add_module_repairs(code)


func _turrets(dt: float) -> void:
	for t in turrets:
		t["cool"] -= dt
		var code: String = t.get("module", "")
		var st: String = modules.get(code, {}).get("state", "online")
		if st != "online" and not (st == "sabotaged" and randf() < 0.5):
			continue
		var owner_team: int = modules.get(code, {}).get("team", team)
		var node: Node3D = t["node"]
		var tgt := _target_for(node.global_position, owner_team)
		if tgt == null:
			continue
		var aim_p: Vector3 = tgt.global_position
		if tgt.get("aabb") != null:
			aim_p = tgt.to_global(tgt.aabb.get_center())
		if aim_turret(t, aim_p, dt) and t["cool"] <= 0.0:
			var small: bool = tgt in G.fighters or tgt in G.pods or tgt in G.missiles
			t["cool"] = randf_range(0.45, 0.6) if small else randf_range(2.0, 2.4)
			_fire(t, tgt, aim_p, (7.0 if small else 12.0) * G.turret_mult(owner_team), owner_team)


func _target_for(from: Vector3, owner_team: int) -> Node:
	var best: Node = null
	var bd := 900.0
	for f in G.fighters + G.pods + G.missiles:
		if is_instance_valid(f) and G.enemies(owner_team, f.team):
			var d: float = from.distance_to(f.global_position)
			if d < bd:
				bd = d
				best = f
	if best:
		return best
	bd = 1500.0
	for v in G.vessels:
		if v != self and is_instance_valid(v) and not v.destroyed and v.kind == "ship" and G.enemies(owner_team, v.team):
			var d2: float = from.distance_to(v.global_position)
			if d2 < bd:
				bd = d2
				best = v
	return best


func _fire(t: Dictionary, tgt: Node, aim_p: Vector3, dmg: float, owner_team: int) -> void:
	var from := turret_muzzle(t)
	var to := aim_p + Vector3(randf_range(-4, 4), randf_range(-3, 3), randf_range(-4, 4))
	var c := Color(1.0, 0.72, 0.28) if faction == 1 else Color(1.0, 0.2, 0.45)
	if owner_team == 3:
		c = Color(0.55, 1.0, 0.35)
	var m := MeshInstance3D.new()
	m.mesh = G._box_mesh
	m.material_override = G._mat(c, 6.0)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().root.add_child(m)
	m.global_position = from
	m.look_at(to, Vector3.UP)
	m.scale = Vector3(0.45, 0.45, 11.0)
	bolts.append([m, from, to, 0.0, max(0.05, from.distance_to(to) / BOLT_SPEED), tgt, dmg])
	G.flash(from, c, 8.0, 16.0, 0.07)
	if G.sfx:
		G.sfx.play("cannon", from, -3.0, true)
	t["kick"] = 1.0
	G.stat("station_shots")


func _update_bolts(dt: float) -> void:
	for i in range(bolts.size() - 1, -1, -1):
		var b: Array = bolts[i]
		if not is_instance_valid(b[0]):
			bolts.remove_at(i)
			continue
		b[3] += dt
		var k: float = b[3] / b[4]
		if k >= 1.0:
			(b[0] as Node).queue_free()
			bolts.remove_at(i)
			var tgt: Object = b[5] if is_instance_valid(b[5]) else null
			if tgt != null and not G.is_client():
				var small_t: bool = tgt in G.fighters or tgt in G.pods or tgt in G.missiles
				if small_t:
					if randf() < (0.3 if tgt in G.pods else 0.45):
						tgt.take_hit(b[6], b[2])
				elif not tgt.get("destroyed"):
					tgt.take_hit(b[6], b[2], self)
		else:
			(b[0] as Node3D).global_position = (b[1] as Vector3).lerp(b[2], k)


func armor() -> float:
	return 3.0


func take_hit(dmg: float, at: Vector3, _by: Node = null) -> void:
	if destroyed:
		return
	if G.is_client():
		G.flash(at, Color(0.4, 0.7, 1.0) if shields > 0.0 else Color(1.0, 0.6, 0.2), 4.0, 14.0, 0.1)
		return
	since_hit = 0.0
	if _by != null and is_instance_valid(_by) and _by.get("team") != null:
		set_meta("last_hit_team", _by.team)
	if shields > 0.0:
		shields = max(0.0, shields - dmg)
		G.flash(at, Color(0.4, 0.7, 1.0), 5.0, 18.0, 0.12)
		return
	var lp := to_local(at)
	var best := ""
	var bd := 1e9
	for code in modules:
		var d: float = (modules[code]["center"] as Vector3).distance_to(lp)
		if d < bd and modules[code]["state"] != "destroyed":
			bd = d
			best = code
	if best == "":
		return
	var md: Dictionary = modules[best]
	md["hull"] -= dmg * (1.0 - md["armor"])
	G.explosion(at, 3.0)
	if md["hull"] <= md["max"] * 0.5 and md["state"] == "online":
		set_module_state(best, "disabled")
		_add_module_repairs(best)
	if md["hull"] <= 0.0:
		md["hull"] = 0.0
		set_module_state(best, "destroyed")
		if best == root_code:
			destroyed = true
			G.say("%s's %s was DESTROYED!" % [display_name, md["name"].replace("_", " ")], team)
			if G.match_node:
				G.match_node.on_station_lost(self, 0)


# ------------------------------------------------------------------ sabotage and repair

func _add_module_repairs(code: String) -> void:
	for n in marks_like(code + "_SabotagePoint_?"):
		repairs.append({"pos": snap_local(local_of(n)), "amount": 500.0, "module": code})


## Boarders planted charges in a module.
func sabotage(code: String, by_team: int) -> void:
	if not modules.has(code) or not G.enemies(by_team, modules[code]["team"]) or modules[code]["state"] == "destroyed":
		return
	modules[code]["hull"] -= modules[code]["max"] * 0.2
	G.explosion(to_global(modules[code]["center"]) + Vector3.UP * 2.0, 3.0)
	set_module_state(code, "sabotaged")
	_add_module_repairs(code)
	G.stat("sabotage")


func repair_point() -> Vector3:
	return repairs[0]["pos"] if not repairs.is_empty() else Vector3.INF


func _repair_tick(dt: float) -> void:
	if repairs.is_empty():
		return
	var job: Dictionary = repairs[0]
	for c in occupants:
		if c.repairing and c.state == "alive" and c.team == team and c.position.distance_to(job["pos"]) < 2.0:
			job["amount"] -= 60.0 * dt
	if job["amount"] > 0.0:
		return
	room_repaired(repairs.pop_front())
	G.stat("repairs_done")
	if not job.has("module"):
		return
	var code: String = job["module"]
	if not modules.has(code):
		return
	var md: Dictionary = modules[code]
	md["hull"] = min(md["max"], md["hull"] + 500.0)
	for j in repairs:
		if j.get("module", "") == code:
			return
	if md["state"] in ["sabotaged", "disabled"]:
		md["hull"] = max(md["hull"], md["max"] * 0.6)
		set_module_state(code, "online")


func on_captured(cp: Dictionary, by: int) -> void:
	var code: String = cp.get("module", "")
	if code == "" or not modules.has(code):
		return
	modules[code]["team"] = by
	if code == root_code:
		team = by
		for c in modules:
			modules[c]["team"] = by
		for p in capture_points:
			p["owner"] = by
		G.say("%s has been CAPTURED by %s!" % [display_name, G.team_name(by)], by)
		if G.match_node:
			G.match_node.on_station_lost(self, by)
	else:
		G.say("%s: module %s captured by %s" % [display_name, code, G.team_name(by)], by)


# ------------------------------------------------------------------ barracks

## Logistics, every couple of seconds: the barracks turn out robots for the fleet and
## the fabricators make supplies, both paid for from the side's stockpile.
func produce(dt: float) -> void:
	var r: Dictionary = G.resources.get(team, {})
	if not r.is_empty():
		var camp: bool = G.campaign != null and team == 1
		if supplies < supply_cap and r.get("alloys", 0.0) > 5.0:
			var make: float = minf(6.0 * dt, supply_cap - supplies)
			supplies += make
			r["alloys"] -= make * (0.05 if camp else 0.25)
		_recruit_t += dt
		if _recruit_t >= 18.0 and reserve < reserve_cap and can_train() and r.get("alloys", 0.0) >= 40.0 and r.get("cores", 0.0) >= 1.0:
			_recruit_t = 0.0
			reserve += 1
			r["alloys"] -= 10.0 if (G.campaign != null and team == 1) else 40.0
			r["cores"] -= 1.0
	elif team == 3:                                   # pirates scrounge what they need
		supplies = minf(supply_cap, supplies + 2.0 * dt)
		_recruit_t += dt
		if _recruit_t >= 30.0 and reserve < 20:
			_recruit_t = 0.0
			reserve += 1


# ------------------------------------------------------------------ docks

## Ship berths at the ends of the docking arms, and small-craft pads on the ring.
var berths: Array = []             # {marker, ship (or null), yaw}
var _pads_rr := 0


func setup_docks() -> void:
	berths.clear()
	for m in marks_like("*_ShipBerth_*"):
		var code := _module_of(String(m.name))
		var center: Vector3 = modules[code]["center"] if modules.has(code) else Vector3.ZERO
		var arm: Vector3 = local_of(m) - center
		arm.y = 0.0
		# a ship lies alongside the arm's end: its length across the arm
		berths.append({"marker": m, "ship": null, "yaw": atan2(-arm.z, arm.x)})


## A free berth for ship v (or the one it already holds), else {}.
func claim_berth(v: Node) -> Dictionary:
	for b in berths:
		if b["ship"] == v:
			return b
	for b in berths:
		if b["ship"] == null or not is_instance_valid(b["ship"]) or b["ship"].destroyed:
			b["ship"] = v
			return b
	return {}


func release_berth(v: Node) -> void:
	for b in berths:
		if b["ship"] == v:
			b["ship"] = null


## A landing pad for a small craft (Darter, shuttle, miner): local position.
func craft_pad() -> Vector3:
	var pads: Array = marks_like("*_DarterPad_*") + marks_like("*_MinerBerth_*")
	if pads.is_empty():
		return aabb.get_center() + Vector3.UP * (aabb.size.y * 0.5 + 12.0)
	_pads_rr += 1
	return local_of(pads[_pads_rr % pads.size()])


func can_train() -> bool:
	# in the campaign any station of ours can raise a squad (barracks segments make it faster)
	if G.match_node and G.match_node.get("campaign_mode") and team == 1:
		return true
	for code in modules:
		if modules[code]["name"] == "barracks" and modules[code]["state"] == "online" and modules[code]["team"] == team:
			return true
	return false


func train_cost() -> Vector2:
	# alloys, cores (one core per soldier)
	if G.match_node and G.match_node.get("campaign_mode") and team == 1:
		return Vector2(160.0, float(SQUAD.size()) + G.tech_bonus(team, "squad_extra"))
	return Vector2(400.0, 8.0)


## Why a squad can't be trained here right now ("" if it can).
func train_problem() -> String:
	var r: Dictionary = G.resources.get(team, {})
	var cost := train_cost()
	if r.is_empty():
		return "no stores"
	if not can_train():
		return "%s has no working barracks" % display_name
	if float(r.get("alloys", 0.0)) < cost.x:
		return "needs %d alloys (have %d)" % [int(cost.x), int(r.get("alloys", 0.0))]
	if float(r.get("cores", 0.0)) < cost.y:
		return "needs %d cores (have %d)" % [int(cost.y), int(r.get("cores", 0.0))]
	if training.size() >= G.CAPS["squads_training"]:
		return "already training %d squads" % training.size()
	return ""


func train_squad() -> bool:
	if train_problem() != "":
		return false
	var r: Dictionary = G.resources.get(team, {})
	var cost := train_cost()
	r["alloys"] = float(r["alloys"]) - cost.x
	r["cores"] = float(r["cores"]) - cost.y
	var roles: Array = SQUAD.duplicate()
	for xi in int(G.tech_bonus(team, "squad_extra")):
		roles.append("rifleman")
	training.append([30.0, roles])
	G.say("%s: squad of %d in training (30 s)" % [display_name, SQUAD.size()], team)
	return true


func _training(dt: float) -> void:
	if training.is_empty():
		return
	training[0][0] -= dt
	if training[0][0] > 0.0:
		return
	var roles: Array = training.pop_front()[1]
	var spots: Array = marks_like("*_Garrison")
	if spots.is_empty():
		spots = marks_like("*_ControlRoom")
	G.match_node.spawn_squad(self, local_of(spots[0]), team, faction, roles, false)
	G.say("%s: a new squad is ready" % display_name, team)


# ------------------------------------------------------------------ boarding

## Pods dock at module airlocks: [approach, impact, interior, door pattern], nearest first.
var _entries: Array = []


func boarding_entries(from: Vector3) -> Array:
	if _entries.is_empty():
		_entries = _make_entries()
	var out := _entries.duplicate()
	out.sort_custom(func(a, b): return a[1].global_position.distance_to(from) < b[1].global_position.distance_to(from))
	return out


func _make_entries() -> Array:
	var out: Array = []
	for k in marks:
		var s := String(k)
		if not s.ends_with("_EVAEntry") or not s.contains("_Airlock"):
			continue
		var base := s.trim_suffix("_EVAEntry")
		var ins: Node3D = mark(base + "_Inside")
		if ins == null:
			continue
		var impact: Node3D = marks[k]
		var app := Node3D.new()                     # 40 m straight out from the airlock
		add_child(app)
		var outward := impact.position - ins.position
		outward.y = 0.0
		app.position = impact.position + outward.normalized() * 40.0
		out.append([app, impact, ins, "*%s_Door" % base])
	return out


func command_point_local() -> Vector3:
	var m: Node3D = mark(root_code + "_ControlRoom")
	return local_of(m) if m else Vector3.ZERO
