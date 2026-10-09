extends CharacterBody3D
## Every person aboard: soldiers, ship crew, pirates and the infected.
##
## Lives inside a vessel (ship or station) as its child, so it moves with it. Paths
## come from the vessel's own navigation in vessel space. When the player takes
## direct control (G.possessed == self) the same body is driven by the keyboard.

const RIG := preload("res://scripts/rig.gd")
const GRENADE := preload("res://scripts/grenade.gd")
const BREACH_ROUND := preload("res://scripts/breach_round.gd")
const BODY_SHADER := preload("res://shaders/infected_body.gdshader")
const COMBAT_ROLES := ["rifleman", "breacher", "medic", "heavy", "grenadier", "squad_leader", "eva_boarder", "drop_trooper"]
const JOBS := {
	"bridge_officer": ["Bridge_*", "*CMD_ControlConsole", "*CMD_Operations", "*GCR_ControlConsole"],
	"pilot": ["Hangar_LandingPad_*", "*_CrewRoom", "PlayerSpawn_*"],
	"engineer": ["Reactor", "*_Core", "*_SabotagePoint_?", "Elevator_*_Stop_*", "*RCT_ControlRoom", "Workshop_*_Deck*", "Systems_*_Deck*"],
	"medical_officer": ["Medbay_*", "*_CrewRoom"],
	"scientist": ["Reactor", "*_Core", "Medbay_*_MedpenResupply", "*_ControlRoom"],
	"security": ["Armory_*_Resupply", "Armory_*_Counter", "*_ReadyLocker", "PlayerSpawn_*", "*_Garrison", "Berthing_*_Deck*", "ReadyRoom_*", "TroopDeck_Walkway"],
	"cargo_handler": ["CargoStorage_*", "Storage_*_Stores_*"],
}

# ---- identity
var team := 1
var faction := 1                  # whose gear/palette (1, 2, 3 pirates)
var role := "rifleman"
var vessel: Node3D = null
var rig: Node3D
var display := ""

# ---- health
var hp := 100.0
var max_hp := 100.0
var dr := 0.0
var state := "alive"              # alive, downed, dead
var bleed := 0.0
var core_left := true             # a fallen robot's core, retrievable by its own side
var convert_t := -1.0
var killed_by_infection := false

# ---- gear (physical inventory)
var weapon_model := ""
var wstats := {}
var mag := 0
var spare: Array = []             # slot names that still hold a full magazine
var medpens: Array = []
var grenades: Array = []
var emps: Array = []              # EMP grenades (slot names)
var stun_t := 0.0                 # > 0: staggered and blinded by an EMP
var charges: Array = []
var revive_kit := 0
var gl_ammo := 0                  # grenadier: 40 mm shells left (on the belt, right hip)
var breach_ammo := 0              # grenadier: breaching rounds left (a sleeve on each hip)
var gl_rounds: Array = []         # ...the shell models on the belt, one hidden per shot
var breach_rounds: Array = []     # ...the breaching-round models in the hip sleeves
var gl_mode := false              # grenadier in direct control: the trigger fires the launcher (B cycles)
var gl_breach := false            # ...loaded with a breaching round instead of a frag shell
var _gl_cd := 0.0                 # launcher: loading the next shell (AI: also holding off between shots)
var _gl_latch := false            # the trigger is still held from a launcher shot (no rifle fire yet)
var armed := false
var geared := 0                   # crew: 0 none, 1 ready locker, 2 armory
var purging := false              # scientist using a purge emitter
var intel: Array = []             # what this robot has seen: [time, text]

# ---- brain
var order := {}                   # from the commander: {type, pos (vessel space), target}
var target: Node = null
var target_seen := false
var los := false
var path := PackedVector3Array()
var path_i := 0
var goal := Vector3.INF
var run := false
var crouch := false
var in_cover: Array = []
var cover_cd := 0.0
var peek_t := 0.0
var fire_t := 0.0
var _kick_cd := 0.0
var burst := 0
var reload_t := -1.0
var task_t := 0.0
var task_pos := Vector3.INF
var working := false
var repairing := false
var carrying := false
var job_phase := 0
var revive_t := -1.0
var revive_who: Node = null
var gear_t := -1.0
var melee_t := 0.0
var stuck_t := 0.0
var last_pos := Vector3.ZERO
var force_t := 0.0
var think_t := 0.0
var look_yaw := 0.0
var look_pitch := 0.0
var selected := false
var ring: MeshInstance3D
var squad_id := 0
var kills := 0
var scramble_pad := ""
var _fp_cam_pitch := 0.0
var elev := {}                     # riding an elevator: {idx, from, to, stage, final, out}
var _settled := false              # standing still on a floor: no need to sweep the capsule
var squad = null                   # squad.gd, or null
var fireteam := 0                  # 0 = A, 1 = B (bounding overwatch)
# ---- the player's exo-suit movement (Advanced Warfare style)
var exo := 100.0                   # boost energy
var exo_cd := 0.0                  # regen delay after a boost
var air_boost := false             # the boost jump is used until you land
var slide_t := 0.0
var slide_dir := Vector3.ZERO
var ads := false                   # aiming down sights
var kick := 0.0                    # recoil the camera still has to climb
var piloting: Node = null          # the ship or fighter this player is flying
var fog_hidden := false           # out of the player's sight on open ground (fog.gd)
var riding: Node = null            # the boarding pod or shuttle carrying us
var mustered: Node = null          # the ship whose boarding party we joined (waiting at the bay)
var gunning := {}                  # the player in a gunner's seat: {ship, idx}
# ---- multiplayer
var owner_peer := 0                # a remote player drives this body (host side)
var net_pos := Vector3.INF         # puppets (client side): where the host says we are
var net_yaw := 0.0
var net_speed := 0.0
# ---- medical: every combat soldier carries 4 revive pens, medics 8 and a revive gun.
# With no pen to hand, friends drag or carry the downed to the nearest medbay bed.
const PENS := 4
const MEDIC_PENS := 8
const REVIVE_GUN := 8
const GUN_RANGE := 14.0
const BED_TREAT_S := 4.0
var revive_gun := 0                # medics: revive-gun shots left
var revive_src := "pen"            # what the revive in progress uses: pen, kit, gun, bed
var hauling: Node = null           # a downed friend we're dragging / carrying to the medbay
var carried_by: Node = null        # (downed) who is hauling us
var on_bed := false                # (downed) laid on a medbay bed, being treated
var _haul_to := Vector3.INF        # vessel space: where we're taking them (beside a bed, or a medic)
var _haul_bed := Vector3.INF       # vessel space: the bed's mattress (INF: hand over to a medic)
const KICK := {"rifle": 0.55, "battle_rifle": 0.9, "bullpup_gl": 0.77, "smg": 0.38, "shotgun": 3.2, "sniper": 4.5, "pistol": 1.3, "heavy": 0.5}


# ------------------------------------------------------------------ creation

func setup(v: Node3D, team_: int, faction_: int, role_: String) -> void:
	vessel = v
	team = team_
	faction = faction_
	role = role_
	collision_layer = G.LAYER_CHAR
	collision_mask = G.LAYER_WORLD | G.LAYER_DOOR
	floor_max_angle = deg_to_rad(46.0)
	floor_snap_length = 0.4
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.8
	col.shape = cap
	col.position.y = 0.9
	col.name = "Hitbox"
	add_child(col)
	rig = RIG.new()
	add_child(rig)
	var tag := "P" if faction == 3 else "F%d" % faction
	var path_ := "res://models/characters/char_%s_%s.glb" % [tag, role]
	if not ResourceLoader.exists(path_):
		path_ = "res://models/characters/char_%s_rifleman.glb" % tag
	rig.setup(path_, 2 if faction == 2 else 1)
	var rd: Dictionary = G.role_data(2 if faction == 2 else 1, role)
	dr = rd.get("damage_reduction", 0.0)
	var inv: Dictionary = rd.get("inventory", {})
	var prim = rd.get("primary")
	var sec = rd.get("secondary")
	var model: String = prim if prim else (sec if sec else "")
	for slot in inv:
		var item: String = inv[slot]
		if item.ends_with("Mag") or item.ends_with("Cell"):
			if model != "" and item.begins_with(model):
				spare.append(slot)
		elif item.ends_with("Medpen"):
			medpens.append(slot)
		elif item.ends_with("Grenade"):
			grenades.append(slot)
		elif item.ends_with("BreachCharge"):
			charges.append(slot)
		elif item.ends_with("ReviveKit"):
			revive_kit = 3
	if role in ["rifleman", "breacher"]:
		if grenades.size() >= 2:
			emps.append(grenades.pop_back())
		else:
			emps.append("emp_extra")
		for sl in emps:
			var sn: Node = rig.model.find_child("Slot_" + String(sl), true, false)
			if sn is MeshInstance3D:
				(sn as MeshInstance3D).material_override = G._mat(Color(0.3, 0.7, 1.0), 1.5)
	if role == "grenadier":
		_grenadier_kit()
	if model != "":
		give_weapon(model)
	if role == "medic":
		revive_gun = REVIVE_GUN
	top_up_pens()
	display = "%s %s" % [role.replace("_", " ").capitalize(), G.team_short(team)]
	ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.42
	tm.outer_radius = 0.5
	ring.mesh = tm
	ring.material_override = G._mat(G.team_color(team), 2.0)
	ring.position.y = 0.05
	ring.visible = false
	add_child(ring)
	think_t = randf() * 0.3
	look_yaw = rotation.y
	if role == "scientist":
		var emit: Node3D = load("res://models/items/item_F%d_PurgeEmitter.glb" % (2 if faction == 2 else 1)).instantiate()
		rig.set_held(emit)
	G.characters.append(self)
	vessel.board(self)


func give_weapon(model: String) -> void:
	weapon_model = model
	var fac := 2 if faction == 2 else 1
	wstats = G.weapon_stats(fac, model)
	var file := model
	if faction == 3:
		file = "P_" + model.substr(3)
	# a gun built in Godot (tests/make_bullpup.gd) replaces the exported .glb of the same name
	var scn := "res://models/weapons/weapon_%s.tscn" % file
	rig.set_weapon(scn if ResourceLoader.exists(scn) else "res://models/weapons/weapon_%s.glb" % file)
	mag = int(wstats.get("ammo_per_load", 30))
	armed = true


# ------------------------------------------------------------------ grenadier kit

const GL_ROUNDS := 6
const BREACH_ROUNDS := 2


## The 40 mm shells ride upright in loops on the belt, in an arc round the right hip from the
## front to the side, and a breaching round stands in a sleeve on each hip (the right one behind
## the shells). Measured off the hips mesh (belt included), so it fits both factions. Hung on the
## Hips bone (bones have identity rest rotation, so a node's local position is its model-space
## position minus the bone's). The rifleman model's hip grenade pouches are hidden: grenadiers
## carry no hand grenades.
func _grenadier_kit() -> void:
	gl_ammo = GL_ROUNDS
	breach_ammo = BREACH_ROUNDS
	for sl in ["GrenadeSlot_1", "GrenadeSlot_2"]:
		rig.show_slot(sl, false)
	if not rig.b.has("Hips"):
		return
	var bone: Node3D = rig.b["Hips"]
	var bone_pos: Vector3 = rig._model_pos("Hips")
	var hips := AABB(bone_pos + Vector3(-0.2, -0.07, -0.1), Vector3(0.4, 0.17, 0.25))
	var hm: Node = bone.find_child("Hips_mesh", false, false)
	if hm is MeshInstance3D:
		hips = _model_aabb(hm)
	# an ellipse just outside the belt; angles from the front (+z) round toward the right (-x)
	var mid := Vector3(0.0, hips.position.y + hips.size.y * 0.45, (hips.position.z + hips.end.z) * 0.5)
	var ax: float = hips.size.x * 0.5 + 0.024
	var az: float = hips.size.z * 0.5 + 0.024
	var on_belt := func(deg: float) -> Vector3:
		var a := deg_to_rad(deg)
		return mid + Vector3(-sin(a) * ax, 0.0, cos(a) * az)
	var webbing := StandardMaterial3D.new()
	webbing.albedo_color = Color(0.15, 0.14, 0.11)
	webbing.roughness = 0.9
	var kit := Node3D.new()
	kit.name = "GrenadierBelt"
	bone.add_child(kit)
	var loop := BoxMesh.new()
	loop.size = Vector3(0.05, 0.022, 0.046)
	gl_rounds.clear()
	for i in GL_ROUNDS:
		var deg: float = lerpf(28.0, 112.0, float(i) / (GL_ROUNDS - 1))
		var at: Vector3 = on_belt.call(deg)
		var turn := Basis(Vector3.UP, -deg_to_rad(deg))            # face out from the hip
		var lp := MeshInstance3D.new()
		lp.mesh = loop
		lp.material_override = webbing
		lp.basis = turn
		lp.position = at - bone_pos + Vector3(0, -0.012, 0)
		kit.add_child(lp)
		var sh: Node3D = GRENADE.shell_model()
		sh.basis = turn * Basis(Vector3.RIGHT, -PI * 0.5)          # nose up
		sh.position = at - bone_pos + Vector3(0, 0.004, 0)
		kit.add_child(sh)
		gl_rounds.append(sh)
	# the breaching rounds: right hip behind the shells, left hip
	breach_rounds.clear()
	var sleeve := BoxMesh.new()
	sleeve.size = Vector3(0.05, 0.085, 0.05)
	for deg in [146.0, -100.0]:
		var at: Vector3 = on_belt.call(deg)
		at += Vector3(at.x - mid.x, 0.0, at.z - mid.z).normalized() * 0.01      # a little proud of the shells
		var turn := Basis(Vector3.UP, -deg_to_rad(deg))
		var sl := MeshInstance3D.new()
		sl.mesh = sleeve
		sl.material_override = webbing
		sl.basis = turn
		sl.position = at - bone_pos + Vector3(0, -0.02, 0)
		kit.add_child(sl)
		var r: Node3D = BREACH_ROUND.build_model()
		r.basis = turn * Basis(Vector3.RIGHT, -PI * 0.5)           # nose up
		r.position = at - bone_pos + Vector3(0, 0.03, 0)
		kit.add_child(r)
		breach_rounds.append(r)
	kit_refresh()


## Show as many shells and breaching rounds as are left.
func kit_refresh() -> void:
	for i in gl_rounds.size():
		(gl_rounds[i] as Node3D).visible = i < gl_ammo
	for i in breach_rounds.size():
		(breach_rounds[i] as Node3D).visible = i < breach_ammo


## A mesh's bounds in the character model's space (at rest).
func _model_aabb(mi: MeshInstance3D) -> AABB:
	var xf := Transform3D.IDENTITY
	var n: Node = mi
	while n != null and n != rig.model:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf * mi.get_aabb()


# ------------------------------------------------------------------ helpers

func is_up() -> bool:
	return state == "alive"


func eye() -> Vector3:
	return global_position + Vector3.UP * (1.1 if crouch else 1.6)


func chest() -> Vector3:
	return global_position + Vector3.UP * (0.8 if crouch else 1.25)


func is_crew() -> bool:
	return not role in COMBAT_ROLES and not team in [3, 4]


func is_combatant() -> bool:
	return armed and (role in COMBAT_ROLES or role == "security" or geared > 0 or team in [3, 4] or role == "infected")


func set_selected(on: bool) -> void:
	selected = on
	ring.visible = on and state != "dead"


func go(p: Vector3, running: bool = false) -> void:
	## Walk to a point in vessel space.
	if goal != Vector3.INF and goal.distance_to(p) < 0.4 and path_i < path.size():
		run = running
		return
	goal = p
	run = running
	var _pt := Time.get_ticks_usec()
	path = vessel.path_local(position, p)
	G.stat("us_char_path", Time.get_ticks_usec() - _pt)
	G.stat("char_paths")
	path_i = 0
	stuck_t = 0.0


## Walk somewhere for a job. Crew on shift take the elevator between decks;
## soldiers and anyone during an alarm use the ramps.
func travel(p: Vector3) -> void:
	if is_crew() and vessel.alarm <= 0.0 and _elevator_go(p):
		return
	go(p, false)


func _elevator_go(p: Vector3) -> bool:
	if vessel.elevators.is_empty() or abs(p.y - position.y) < 2.0:
		return false
	var from_d := int(round(position.y / 4.0))
	var to_d := int(round(p.y / 4.0))
	if from_d < 0 or to_d < 0:
		return false                                     # the troop deck: take the ramps
	var best := -1
	var bd := INF
	for i in vessel.elevators.size():
		var e: Dictionary = vessel.elevators[i]
		var d := Vector2(position.x - e["center"].x, position.z - e["center"].z).length()
		if to_d < e["decks"] and from_d < e["decks"] and d < bd:
			bd = d
			best = i
	if best < 0:
		return false
	var c: Vector3 = vessel.elevators[best]["center"]
	var side := 1.0 if c.x >= 0.0 else -1.0
	var out: Vector3 = vessel.snap_local(Vector3(c.x - side * 2.6, from_d * 4.0, c.z))
	elev = {"idx": best, "from": from_d, "to": to_d, "stage": "approach", "final": p, "side": side, "t": 0.0}
	goal = Vector3.INF
	go(out, false)
	return true


func _doors_open(e: Dictionary, deck: int) -> bool:
	return e["deck"] == deck and e["target"] == deck and e["doors"][deck]["amt"] > 0.85


## One step of an elevator ride. Returns the horizontal velocity to use, or null to follow the path.
func _elevator_step(dt: float):
	var e: Dictionary = vessel.elevators[elev["idx"]]
	var c: Vector3 = e["center"]
	elev["t"] += dt
	if elev["t"] > 60.0:                               # something went wrong: give up and walk
		var f: Vector3 = elev["final"]
		elev = {}
		go(f, false)
		return null
	match elev["stage"]:
		"approach":
			if arrived(0.7):
				elev["stage"] = "wait"
				vessel.call_elevator(elev["idx"], elev["from"])
			return null
		"wait":
			if _doors_open(e, elev["from"]):
				elev["stage"] = "enter"
				stop()
			elif e["target"] == e["deck"] and e["deck"] != elev["from"]:
				vessel.call_elevator(elev["idx"], elev["from"])
			return Vector3.ZERO
		"enter":
			var to := Vector3(c.x - position.x, 0, c.z - position.z)
			if to.length() < 0.45:
				elev["stage"] = "ride"
				vessel.call_elevator(elev["idx"], elev["to"])
				G.stat("elevator_rides")
				return Vector3.ZERO
			return to.normalized() * 1.8
		"ride":
			if _doors_open(e, elev["to"]):
				elev["stage"] = "exit"
			elif e["target"] == e["deck"] and e["deck"] != elev["to"]:
				vessel.call_elevator(elev["idx"], elev["to"])
			return Vector3.ZERO
		"exit":
			var out := Vector3(c.x - elev["side"] * 2.6, position.y, c.z)
			var to2 := Vector3(out.x - position.x, 0, out.z - position.z)
			if to2.length() < 0.5:
				var f2: Vector3 = elev["final"]
				elev = {}
				go(f2, false)
				return null
			return to2.normalized() * 1.8
	return null


## Climb into a boarding pod or shuttle: out of sight and out of the fight until it lands.
func embark(craft: Node) -> void:
	riding = craft
	mustered = null
	stop()
	elev = {}
	working = false
	carrying = false
	visible = false
	collision_layer = 0


## Step out of a pod or shuttle into vessel v at local position lp.
func disembark_to(v: Node3D, lp: Vector3) -> void:
	riding = null
	visible = true
	collision_layer = G.LAYER_CHAR
	if v != vessel:
		vessel.leave(self)
		reparent(v, false)
		vessel = v
		v.board(self)
	position = lp + Vector3.UP * 0.05
	velocity = Vector3.ZERO
	_settled = false
	stop()
	order = {}
	run = true


func stop() -> void:
	path = PackedVector3Array()
	path_i = 0
	goal = Vector3.INF


func arrived(r: float = 0.6) -> bool:
	return goal == Vector3.INF or path_i >= path.size() or Vector3(position.x - goal.x, 0, position.z - goal.z).length() < r


# ------------------------------------------------------------------ damage

func take_damage(dmg: float, attacker: Node, _from: Vector3 = Vector3.ZERO) -> void:
	if state == "dead":
		return
	if G.is_client():
		return                                         # the host decides who gets hurt
	var d := dmg * (1.0 - clampf(dr + G.dr_bonus(team), 0.0, 0.75))
	if attacker and is_instance_valid(attacker) and attacker.team == 4:
		killed_by_infection = true
	if state == "downed":
		bleed -= d * 0.25
		if bleed <= 0.0:
			die(attacker)
		return
	hp -= d
	if attacker and is_instance_valid(attacker) and attacker != self and attacker.get("team") != null:
		if target == null or not is_instance_valid(target):
			target = attacker
		if vessel and vessel.team == team:
			vessel.raise_alarm(vessel.to_local(attacker.global_position))
	if hp <= 0.0:
		if team == 4 or d > 90.0 + max_hp * 0.5:
			die(attacker)
		else:
			go_down(attacker)


func go_down(attacker: Node) -> void:
	drop_haul()
	state = "downed"
	bleed = 25.0
	hp = 0.0
	stop()
	reload_t = -1.0
	rig.reload = -1.0
	working = false
	repairing = false
	purging = false
	$Hitbox.shape.height = 0.8
	$Hitbox.position.y = 0.3
	if self == G.possessed:
		G.say("You are down - hold on for a medic (%d s)" % bleed, team)


func die(attacker: Node) -> void:
	if state == "dead":
		return
	drop_haul()
	if carried_by != null and is_instance_valid(carried_by) and carried_by.hauling == self:
		carried_by.drop_haul()
	carried_by = null
	on_bed = false
	state = "dead"
	set_meta("dead_at", G.time)
	stop()
	collision_layer = 0
	set_selected(false)
	purging = false
	if attacker and is_instance_valid(attacker) and attacker.get("kills") != null:
		attacker.kills += 1
	if scramble_pad != "":
		scramble_pad = ""
	# the infection converts bodies it reaches before their side recovers the core
	var z: Dictionary = vessel.zone_at(position) if vessel else {}
	if team != 4 and not G.is_client() and (killed_by_infection or (not z.is_empty() and z["infected"])):
		convert_t = 6.0
	if self == G.possessed and G.commander:
		G.commander.on_possessed_died()


func revive(by: Node) -> void:
	if state != "downed":
		return
	if by == null:
		by = self
	if carried_by != null and is_instance_valid(carried_by) and carried_by.hauling == self:
		carried_by.drop_haul()
	carried_by = null
	on_bed = false
	state = "alive"
	hp = 80.0 if G.has_tech(team, "a2") else 45.0
	if by != self and by.revive_src == "bed":
		hp = max_hp                                     # a medbay patches you up properly
	$Hitbox.shape.height = 1.8
	$Hitbox.position.y = 0.9
	if self == G.possessed:
		G.say("Revived by %s" % by.display, team)


func _convert(quiet: bool = false) -> void:
	## Rise again as one of the infected. The infection reads what this robot saw.
	if not quiet and G.match_node and G.match_node.has_method("infection_learn"):
		G.match_node.infection_learn(self)
	var old := team
	team = 4
	state = "alive"
	core_left = false
	killed_by_infection = false
	# fragile: they win by numbers and by turning the dead, not by soaking fire
	# (about a third of a soldier's toughness: a short burst puts one down)
	max_hp = 34.0 if armed else 26.0
	hp = max_hp
	dr = 0.0
	collision_layer = G.LAYER_CHAR
	$Hitbox.shape.height = 1.8
	$Hitbox.position.y = 0.9
	role = "infected" if armed else "swarmer"
	display = "Infected " + display.split(" ")[0]
	var ov := ShaderMaterial.new()
	ov.shader = BODY_SHADER
	for mi in rig.find_children("*", "MeshInstance3D", true, false):
		mi.material_overlay = ov
	rig.twitch = 1.0
	ring.material_override = G._mat(G.team_color(4), 2.0)
	target = null
	order = {}
	_infected_growths()
	if not quiet:
		G.say("The infection raised a fallen %s of %s" % [role_label(), G.team_name(old)], old)
		G.stat("converted")


## What the infection makes of a robot: a fleshy mass bursting out of the head with a
## cluster of glowing eyes, spines and a pulsing sac on the back, one arm swollen into a
## club and the other grown into a bone blade (swarmers) and tendrils trailing from the
## spine. Each one comes out a little different. (Plus the vein shader and the hunch.)
func _infected_growths() -> void:
	var flesh := G._mat(Color(0.32, 0.1, 0.28), 0.25)
	var flesh2 := G._mat(Color(0.48, 0.16, 0.38), 0.35)
	var glow := G._mat(Color(0.95, 0.35, 1.0), 4.0)
	var bone := G._mat(Color(0.7, 0.62, 0.55))
	var sph := func(r: float) -> SphereMesh:
		var sm := SphereMesh.new()
		sm.radius = r
		sm.height = r * 2.0
		sm.radial_segments = 8
		sm.rings = 4
		return sm
	var cone := func(r: float, h: float) -> CylinderMesh:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = r
		cm.height = h
		cm.radial_segments = 5
		return cm
	var add := func(bn: String, mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> void:
		var bone_n: Node3D = rig.b.get(bn)
		if bone_n == null:
			return
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.position = pos
		mi.rotation = rot
		mi.scale = scl
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bone_n.add_child(mi)
	# the head: a split, swollen mass with a cluster of eyes
	add.call("Head", sph.call(0.17), flesh, Vector3(randf_range(-0.05, 0.05), 0.14, 0.02), Vector3.ZERO, Vector3(1.0, 1.25, 1.1))
	add.call("Head", sph.call(0.1), flesh2, Vector3(0.1, 0.24, -0.03))
	for i in 3 + randi() % 3:
		add.call("Head", sph.call(0.028), glow, Vector3(randf_range(-0.09, 0.09), randf_range(0.05, 0.2), -0.15))
	# the back: spines and a pulsing sac
	add.call("UpperChest", sph.call(0.19), flesh2, Vector3(0, 0.08, 0.16), Vector3.ZERO, Vector3(1.2, 1.0, 0.9))
	add.call("UpperChest", sph.call(0.07), glow, Vector3(0.05, 0.12, 0.28))
	for i in 3 + randi() % 3:
		add.call("UpperChest", cone.call(0.035, randf_range(0.25, 0.45)), bone, Vector3(randf_range(-0.15, 0.15), randf_range(0.0, 0.2), 0.2),
			Vector3(randf_range(0.6, 1.2), 0, randf_range(-0.5, 0.5)))
	# tendrils off the spine
	for i in 2:
		add.call("Spine", cone.call(0.04, 0.55), flesh, Vector3((i * 2 - 1) * 0.1, -0.05, 0.12), Vector3(2.4, 0, (i * 2 - 1) * 0.4))
	# arms: one swollen club, one bone blade (swarmers) or overgrown (gunners)
	var club_left := randf() < 0.5
	add.call("LeftLowerArm" if club_left else "RightLowerArm", sph.call(0.12), flesh, Vector3(0, 0.12, 0), Vector3.ZERO, Vector3(1.0, 1.6, 1.0))
	if role == "swarmer":
		add.call("RightLowerArm" if club_left else "LeftLowerArm", cone.call(0.05, 0.6), bone, Vector3(0, 0.38, 0), Vector3.ZERO)
	else:
		add.call("RightUpperArm" if club_left else "LeftUpperArm", sph.call(0.08), flesh2, Vector3(0, 0.1, 0.03))
	# lumps on the legs
	for bn in ["LeftUpperLeg", "RightLowerLeg", "LeftUpperArm"]:
		add.call(bn, sph.call(randf_range(0.06, 0.1)), flesh2 if randf() < 0.5 else flesh, Vector3(randf_range(-0.06, 0.06), randf_range(0.0, 0.2), randf_range(-0.06, 0.06)))
	rig.scale = Vector3.ONE * randf_range(0.95, 1.15)


func role_label() -> String:
	return role.replace("_", " ")


# ------------------------------------------------------------------ per frame

func _physics_process(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	_phys(dt)
	G.stat("us_char_phys", Time.get_ticks_usec() - t0)


func _phys(dt: float) -> void:
	if vessel == null or not is_instance_valid(vessel):
		return
	if state == "dead":
		if convert_t > 0.0:
			convert_t -= dt
			if convert_t <= 0.0:
				_convert()
		if not is_on_floor():
			velocity.y -= 9.8 * dt
			velocity.x = 0
			velocity.z = 0
			move_and_slide()
		return
	if state == "downed":
		if G.is_client():
			_puppet(dt)
			return
		_downed_physics(dt)
		return
	if riding != null:
		velocity = Vector3.ZERO
		_timers(dt)
		return
	# EMP'd: staggered and blind for a moment (no moving, no shooting, no seeing). A client's
	# puppets just show it (flag 128) and keep following the host.
	if stun_t > 0.0 and G.is_client() and self != G.possessed:
		stun_t = 0.0
	if stun_t > 0.0:
		stun_t -= dt
		rig.twitch = 1.0
		target = null
		target_seen = false
		los = false
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= 9.8 * dt
		move_and_slide()
		if stun_t <= 0.0 and role != "infected":
			rig.twitch = 0.0
		return
	if position.y < vessel.aabb.position.y - 15.0 and vessel.nav_ok():
		# fell off the hull into the void: back to the ship's cargo hold (or anywhere safe aboard)
		var hold: Array = vessel.marks_like("CargoStorage_*") + vessel.marks_like("Storage_*_Stores_*")
		position = vessel.snap_local(vessel.local_of(hold[0])) if not hold.is_empty() else vessel.random_local()
		velocity = Vector3.ZERO
		G.stat("void_rescues")
	if self == G.possessed:
		if piloting or not gunning.is_empty():
			_timers(dt)                                 # seated at the helm / in the cockpit
		else:
			_player_physics(dt)
		if G.is_client() and G.network:
			G.network.send_my_state(self)
	elif G.is_client():
		_puppet(dt)
	elif owner_peer != 0:
		_timers(dt)                                     # a remote player moves this body
	else:
		_ai_physics(dt)


## Client side: follow what the host reports.
func _puppet(dt: float) -> void:
	if net_pos == Vector3.INF:
		return
	var before := position
	position = position.lerp(net_pos, clampf(dt * 12.0, 0.0, 1.0))
	if position.distance_to(net_pos) > 4.0:
		position = net_pos
	rotation.y = lerp_angle(rotation.y, net_yaw, clampf(dt * 12.0, 0.0, 1.0))
	velocity = (position - before) / max(dt, 0.001)


func _process(dt: float) -> void:
	if vessel == null or not is_instance_valid(vessel):
		return
	# hide people above the commander's cutaway
	var cut: float = G.cut_height                       # (reading the shader global back is very slow)
	var show_: bool = (global_position.y < cut - 0.4 or vessel.kind == "ground") and riding == null and not fog_hidden
	rig.visible = show_
	if not show_:
		return
	var cam := get_viewport().get_camera_3d()
	var far := cam != null and cam.global_position.distance_to(global_position) > 90.0
	if far and Engine.get_process_frames() % 6 != get_instance_id() % 6:
		return
	rig.speed = Vector3(velocity.x, 0, velocity.z).length() if not G.is_client() or self == G.possessed else net_speed
	rig.crouch = crouch or slide_t > 0.0
	rig.ads = ads and self == G.possessed
	rig.mode = "dead" if state == "dead" else ("downed" if state == "downed" else ("seated" if piloting else _anim_mode()))
	if reload_t >= 0.0:
		rig.reload = 1.0 - reload_t / max(0.1, float(wstats.get("reload_s", 2.0)))
	else:
		rig.reload = -1.0
	rig.aiming = (target != null and los) or (self == G.possessed and armed)
	rig.aim_pitch = look_pitch if self == G.possessed else _ai_pitch()
	rig.animate(dt * (6.0 if far else 1.0))


func _anim_mode() -> String:
	if revive_t >= 0.0:
		return "kneel"
	if carrying:
		return "carry"
	if working or gear_t >= 0.0 or purging:
		return "work"
	return "normal"


func _ai_pitch() -> float:
	if target and is_instance_valid(target) and los:
		var d: Vector3 = target.chest() - eye()
		return atan2(d.y, Vector2(d.x, d.z).length())
	return 0.0


# ------------------------------------------------------------------ AI movement

func _ai_physics(dt: float) -> void:
	think_t -= dt
	if think_t <= 0.0:
		think_t = 0.25
		_think()
	var v := Vector3.ZERO
	var spd := (4.3 if run else 2.2) * (0.55 if crouch else 1.0) * (1.0 + G.tech_bonus(team, "troop_speed"))
	if role == "swarmer":
		spd = 6.5
	if hauling != null:
		spd = 3.2 if target == null else 1.6         # carry at a jog; drag, crouched, under fire
	if revive_t >= 0.0 or gear_t >= 0.0 or working or purging and arrived():
		spd = 0.0
	var ev = null
	if not elev.is_empty():
		if vessel.alarm > 0.0 and elev["stage"] in ["approach", "wait"]:
			elev = {}                                   # alarm: forget the lift, run
		else:
			ev = _elevator_step(dt)
	if ev != null:
		v = ev
	elif path_i < path.size() and spd > 0.0:
		var wp: Vector3 = path[path_i]
		var to := wp - position
		to.y = 0.0
		if to.length() < 0.35:
			path_i += 1
		else:
			v = to.normalized() * spd
			# a closed door in the way: owners' doors open by themselves, enemies must breach
			var d: Dictionary = vessel.door_blocking(position, to)
			if not d.is_empty() and team != vessel.team:
				v = Vector3.ZERO
				_force_door(d, dt)
	if _sep != Vector3.ZERO and elev.is_empty() and revive_t < 0.0:
		if v != Vector3.ZERO:
			v += _sep * 2.2                                # slide past each other instead of stacking
		elif _sep.length() > 0.4 and not working and (vessel.alarm > 0.0 or team != vessel.team):
			v = _sep.normalized() * 1.2                    # shuffle apart while standing (in a fight)
			_settled = false
	var vg: Vector3 = vessel.global_basis * v          # paths are in the vessel's space; physics is in the world's
	velocity.x = vg.x
	velocity.z = vg.z
	# standing still on the deck: skip the collision sweep (most of the crew most of the time)
	if v.length_squared() < 0.0001 and _settled and elev.is_empty():
		velocity = Vector3.ZERO
	elif vessel.kind == "ground" and path_i < path.size() and _far_from_view():
		# out on the open ground and well away from the camera: just walk the path (its
		# points already sit on the walkable surface) and skip the physics sweep
		var nv: Vector3 = v * dt
		position += nv
		var wpy: float = (path[path_i] as Vector3).y
		position.y = lerpf(position.y, wpy, clampf(dt * 4.0, 0.0, 1.0))
		_settled = false
	else:
		if not is_on_floor():
			velocity.y = max(velocity.y - 9.8 * dt, -20.0)
		else:
			velocity.y = 0.0
		var _mt := Time.get_ticks_usec()
		move_and_slide()
		G.stat("us_char_move", Time.get_ticks_usec() - _mt)
		_settled = is_on_floor() and v.length_squared() < 0.0001
	# face where we shoot, else where we go
	var face_dir := Vector3.ZERO
	if target and is_instance_valid(target) and los:
		face_dir = vessel.to_local(target.global_position) - position
	elif v.length() > 0.1:
		face_dir = v
	if face_dir.length() > 0.01:
		rotation.y = rotate_toward(rotation.y, atan2(-face_dir.x, -face_dir.z), dt * 8.0)
	# stuck? try again from where we are
	if path_i < path.size() and spd > 0.0:
		if position.distance_to(last_pos) < 0.02:
			stuck_t += dt
			if stuck_t > 2.0 and goal != Vector3.INF:
				var g := goal
				goal = Vector3.INF
				go(g + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)), run)
		else:
			stuck_t = 0.0
	last_pos = position
	_ai_fire(dt)
	_timers(dt)


const KICK_DMG := 90.0


func _force_door(d: Dictionary, dt: float) -> void:
	## Boarders get through doors by kind:
	##   ordinary doors: kick them in (a kick every ~0.8 s, about three to break one)
	##   heavy blast doors: a breaching charge if we have one, else shoot it down
	##   secure doors (bridge, hangar, cargo, reactor, locked rooms): a charge only. With
	##   none, wait for the squad's breacher; a lone boarder burns through with a cutter, slowly.
	d["force"] += dt
	var kind: String = d.get("kind", "door")
	var to_door: Vector3 = (d["center"] as Vector3) - position
	to_door.y = 0.0
	if to_door.length() > 0.1:
		rotation.y = rotate_toward(rotation.y, atan2(-to_door.x, -to_door.z), dt * 8.0)
	if kind == "door":
		if d["force"] > 0.8:
			d["force"] = 0.0
			kick_door(d)
		return
	if d.get("charged", false):
		return                                       # someone set a charge: stay back
	if not charges.is_empty() and d["force"] > 1.5:
		rig.show_slot(charges.pop_back(), false)
		vessel.plant_charge(d, self)
		G.say("%s set a breaching charge aboard %s" % [display, vessel.display_name], team)
		return
	if kind == "heavy" and armed:
		_shoot_door(d)
	elif kind == "secure" and d["force"] > 45.0 and (squad == null or not _squad_has_charges()):
		vessel.breach_door(d)                         # cut through at last


func _squad_has_charges() -> bool:
	for m in squad.alive():
		if not m.charges.is_empty():
			return true
	return false


func kick_door(d: Dictionary) -> void:
	rig.kick_t = 0.0
	var push: Vector3 = (d["center"] as Vector3) - position
	push.y = 0.0
	vessel.damage_door(d, KICK_DMG * (1.4 if role == "heavy" else 1.0), push.normalized(), true)


func _shoot_door(d: Dictionary) -> void:
	if reload_t >= 0.0 or fire_t > 0.0:
		return
	if mag <= 0:
		if not spare.is_empty():
			reload_t = float(wstats.get("reload_s", 2.0))
		return
	var rpm: float = float(wstats.get("rpm", 300))
	fire_t = 1.0 / min(rpm / 60.0, 6.0)
	var aim: Vector3 = vessel.to_global(d["center"] + Vector3(randfn(0, 0.3), randfn(0, 0.3), randfn(0, 0.3)))
	fire(eye(), (aim - eye()).normalized())


func _timers(dt: float) -> void:
	_kick_cd = max(0.0, _kick_cd - dt)
	_gl_cd = maxf(0.0, _gl_cd - dt)
	if reload_t >= 0.0:
		reload_t -= dt
		if reload_t < 0.0:
			if not spare.is_empty():
				rig.show_slot(spare.pop_back(), false)
				mag = int(wstats.get("ammo_per_load", 30))
	if revive_t >= 0.0:
		revive_t -= dt
		if revive_who == null or not is_instance_valid(revive_who) or revive_who.state != "downed":
			revive_t = -1.0
		elif revive_t < 0.0:
			var who: Node = revive_who
			revive_who = null
			match revive_src:
				"gun":
					revive_gun = maxi(0, revive_gun - 1)
				"bed":
					vessel.supplies = maxf(0.0, vessel.supplies - 3.0)
				"kit":
					revive_kit = maxi(0, revive_kit - 1)
				_:
					if not medpens.is_empty():
						rig.show_slot(medpens.pop_back(), false)
			if revive_src == "gun":
				G.tracer(chest(), who.global_position + Vector3.UP * 0.3, Color(0.4, 1.0, 0.6), 0.06, 0.35)
			who.revive(self)
			G.stat("revives_" + revive_src)
	if gear_t >= 0.0:
		gear_t -= dt
		if gear_t < 0.0:
			_finish_gear_up()
	melee_t -= dt
	fire_t -= dt
	cover_cd -= dt


# ------------------------------------------------------------------ AI thinking

var _far_t := 0.0
var _far := false


func _far_from_view() -> bool:
	_far_t -= 0.016
	if _far_t <= 0.0:
		_far_t = 0.5
		var cam := get_viewport().get_camera_3d()
		_far = cam == null or cam.global_position.distance_to(global_position) > 70.0
	return _far


func _think() -> void:
	var t0 := Time.get_ticks_usec()
	_separation()
	_think2()
	G.stat("us_char_think", Time.get_ticks_usec() - t0)


## Personal space: a push away from teammates closer than about a metre, so squads
## don't pile into one spot at a breach, a door stack or a corner.
var _sep := Vector3.ZERO


func _separation() -> void:
	_sep = Vector3.ZERO
	if team == 4 or not is_combatant():
		return
	for o in vessel.near_occupants(position, 2.0):
		if o == self or o.team != team or o.state != "alive":
			continue
		var d: Vector3 = position - o.position
		if absf(d.y) > 1.5:
			continue
		d.y = 0.0
		var l := d.length()
		if l < 1.15:
			if l < 0.05:
				d = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
				l = 0.05
			_sep += d.normalized() * (1.15 - l) / 1.15


func _think2() -> void:
	_perceive()
	if not elev.is_empty() and elev["stage"] in ["approach", "wait"] and (target != null or not order.is_empty()):
		elev = {}
	_pick_up_cores()
	if team == 4:
		_brain_infected()
		return
	if gear_t >= 0.0 or revive_t >= 0.0:
		return
	if hauling != null:
		_haul()
		return
	if has_meta("retreat_to"):
		go(get_meta("retreat_to"), true)               # falling back to the pods: run, shooting as we go
		return
	if armed and target and is_combatant() and _medic_in_combat():
		return
	if armed and target and is_combatant():
		_brain_combat()
		return
	if target and not armed and role != "gunner":
		_brain_unarmed_threat()
		return
	_brain_duty()


func _perceive() -> void:
	if target and is_instance_valid(target) and target.state == "alive" and target.vessel == vessel:
		var h := G.ray(eye(), target.chest(), [get_rid(), target.get_rid()], G.LAYER_WORLD | G.LAYER_DOOR)
		los = h.is_empty()
		if los:
			_saw(target)
			return
	else:
		target = null
		los = false
	var best: Node = null
	# nearest enemies first, and only a few sight lines per look (a swarm in range would
	# otherwise mean dozens of ray casts per soldier, several times a second)
	var cands: Array = []
	for c in vessel.near_occupants(position, 48.0):
		if c == self or c.state != "alive" or not G.enemies(team, c.team):
			continue
		var d: float = position.distance_to(c.position)
		if d < 48.0:
			cands.append([d, c])
	if cands.size() > 1:
		cands.sort_custom(func(a, b): return a[0] < b[0])
	var tries := 0
	for cd in cands:
		if tries >= 3:
			break
		tries += 1
		var c: Node = cd[1]
		var h := G.ray(eye(), c.chest(), [get_rid(), c.get_rid()], G.LAYER_WORLD | G.LAYER_DOOR)
		if h.is_empty():
			best = c
			break
	if best:
		target = best
		los = true
		_saw(best)
	elif target:
		los = false


func _saw(c: Node) -> void:
	if vessel.team == team or team == 4:
		vessel.raise_alarm(c.position)
	if intel.size() > 30:
		intel.pop_front()
	intel.append([G.time, "%s aboard %s" % [c.display, vessel.display_name]])


func _pick_up_cores() -> void:
	for c in vessel.near_occupants(position, 2.0):
		if c.state == "dead" and c.core_left and c.team == team and c.convert_t < 0.0 \
				and position.distance_to(c.position) < 1.6:
			c.core_left = false
			if G.resources.has(team):
				G.resources[team]["cores"] += 1
			# scavenge: take a magazine from the fallen
			if armed and spare.size() < 3:
				spare.append("scavenged_%d" % randi())


func _brain_combat() -> void:
	var tl: Vector3 = vessel.to_local(target.global_position)
	var dist := position.distance_to(tl)
	var wrange: float = clamp(float(wstats.get("range_m", 40)) * 1.1, 12.0, 50.0)
	# low on health: medpen when we can
	if hp < 45 and medpens.size() > 1 and (not los or not in_cover.is_empty()):     # keep a pen for a friend
		rig.show_slot(medpens.pop_back(), false)
		hp = min(max_hp, hp + 40)
	# out of everything: back off and resupply
	if mag <= 0 and spare.is_empty() and reload_t < 0.0:
		_resupply()
		return
	if mag <= 0 and reload_t < 0.0:
		reload_t = float(wstats.get("reload_s", 2.0))
	# a player leading us gave a positional order (hold, regroup, split, stack, clear): obey it, shooting as we go
	if squad and squad.leader_player() != null and squad.leader != self and squad.commanded():
		var sp: Vector3 = squad.slot_for(self)
		if sp != Vector3.INF:
			in_cover = []
			if position.distance_to(sp) > 1.1:
				if goal == Vector3.INF or goal.distance_to(sp) > 0.8:
					go(sp, true)
			else:
				stop()
				crouch = squad.stack_door.is_empty() == false or squad.order.get("type", "") == "hold"
			return
	# grenades at targets hiding behind cover or bunched up
	if not grenades.is_empty() and los and dist > 6.0 and dist < 22.0 and randf() < 0.06:
		_throw_grenade(target.global_position)
	# squads bound: one fireteam moves to the next cover while the other holds and fires
	if squad and squad.bounding() and fireteam == squad.moving_team and dist > 7.0:
		var bp: Vector3 = squad.bound_point(self)
		if bp != Vector3.INF and position.distance_to(bp) > 1.2:
			in_cover = []
			crouch = false
			if goal == Vector3.INF or goal.distance_to(bp) > 1.0:
				go(bp, true)
			return
	# cover: pick a spot that puts something between us and them
	if in_cover.is_empty() or not _cover_good(in_cover, tl):
		if cover_cd <= 0.0:
			cover_cd = 2.5
			var cp := _find_cover(tl, 11.0)
			if not cp.is_empty():
				in_cover = cp
				go(cp[0], true)
			elif dist > wrange * 0.8 or not los:
				go(_toward(tl, dist - wrange * 0.6), true)
				in_cover = []
	elif arrived(0.5):
		stop()
		# peek out of low cover to shoot, duck back to reload
		peek_t -= 0.25
		if in_cover[1]:
			crouch = reload_t >= 0.0 or peek_t < 0.0
			if peek_t < -1.2:
				peek_t = 1.8
	if not los and in_cover.is_empty() and arrived():
		go(_toward(tl, max(0.0, dist - 6.0)), true)


func _toward(tl: Vector3, how_far: float) -> Vector3:
	var d := (tl - position)
	if d.length() < 0.1:
		return position
	return vessel.snap_local(position + d.normalized() * how_far)


func _cover_good(cp: Array, tl: Vector3) -> bool:
	var to_t: Vector3 = (tl - cp[0])
	to_t.y = 0.0
	return to_t.normalized().dot(cp[2]) > 0.3


func _find_cover(tl: Vector3, radius: float) -> Array:
	var best: Array = []
	var bd := radius
	var pool: Array = vessel.cover_near(position, radius) if vessel.has_method("cover_near") else vessel.cover
	for cp in pool:
		var p: Vector3 = cp[0]
		if abs(p.y - position.y) > 1.5:
			continue
		var d := position.distance_to(p)
		if d > bd or not _cover_good(cp, tl):
			continue
		var taken := false
		for c in vessel.near_occupants(p, 1.5):
			if c != self and c.state == "alive" and ((not c.in_cover.is_empty() and c.in_cover[0].distance_to(p) < 0.9)
					or (c.goal != Vector3.INF and c.goal.distance_to(p) < 0.9) or c.position.distance_to(p) < 0.7):
				taken = true
				break
		if not taken:
			best = cp
			bd = d
	return best


func _brain_unarmed_threat() -> void:
	# unarmed crew run for the nearest locker or armory to gear up
	if vessel.team == team:
		_gear_up()
	else:
		target = null


func _brain_duty() -> void:
	crouch = false
	in_cover = []
	# 1. revive the fallen, or get them to the medbay
	if _tend_downed():
		return
	# 2. heal
	if hp < 60 and medpens.size() > 1:
		rig.show_slot(medpens.pop_back(), false)
		hp = min(max_hp, hp + 40)
	# 3. ammo
	if armed and mag <= 0 and spare.is_empty():
		_resupply()
		return
	if role == "grenadier" and gl_ammo <= 0 and breach_ammo <= 0 and _resupply_possible():
		_resupply()                                       # launcher shells and breaching rounds
		return
	if armed and mag < int(wstats.get("ammo_per_load", 30)) / 3 and not spare.is_empty() and reload_t < 0.0:
		reload_t = float(wstats.get("reload_s", 2.0))
	# 4. in a squad: hold your slot around the leader (the leader runs the squad's orders)
	if squad and squad.leader and is_instance_valid(squad.leader) and squad.leader != self and squad.leader.vessel == vessel:
		_follow_squad()
		return
	if squad and squad.leader == self and _squad_lagging():
		stop()                                         # let the stragglers catch up
		return
	# 5. orders from the commander
	if not order.is_empty():
		_follow_order()
		return
	# 5. boarders: take the objective
	if vessel.team != team and is_combatant():
		_boarder_objective()
		return
	# 6. alarm: defenders hunt, unarmed crew gear up (scrambled pilots run for their fighters instead)
	# engineers keep repairing and scientists keep purging unless the enemy is in sight
	var keep_working: bool = role in ["engineer", "scientist"] and target == null
	if vessel.alarm > 0.0 and vessel.team == team and not (role == "pilot" and scramble_pad != "") and role != "gunner" and not keep_working:
		if not armed or (geared == 0 and not role in COMBAT_ROLES and role != "security" and role != "bridge_officer"):
			if role != "bridge_officer":
				_gear_up()
				return
		if is_combatant() and role != "bridge_officer" and vessel.last_enemy != Vector3.INF:
			working = false
			repairing = false
			carrying = false
			if position.distance_to(vessel.last_enemy) > 3.0:
				go(vessel.last_enemy, true)
			return
	# 7. the job
	_job()


func _follow_squad() -> void:
	working = false
	carrying = false
	var sp: Vector3 = squad.slot_for(self)
	if sp == Vector3.INF:
		return
	# the squad's breacher at a stacked door kicks it in or sets the charge
	if not squad.stack_door.is_empty() and squad.stack_breacher() == self:
		var dc: Vector3 = squad.stack_door["center"]
		if role == "grenadier" and breach_ammo > 0 and _gl_cd <= 0.0 and squad.stack_door.get("kind", "door") != "door" \
				and G.enemies(team, vessel.team) and _breach_shot(squad.stack_door):
			return
		if Vector2(position.x - dc.x, position.z - dc.z).length() < 1.7 and absf(position.y + 1.3 - dc.y) < 1.5:
			stop()
			if G.enemies(team, vessel.team):
				_force_door(squad.stack_door, 0.25)
			return
	var lead_run: bool = squad.leader.run or squad.leader.velocity.length() > 3.5
	if position.distance_to(sp) > 1.1:
		if goal == Vector3.INF or goal.distance_to(sp) > 0.8:
			go(sp, lead_run or position.distance_to(sp) > 6.0)
	else:
		stop()
		crouch = not squad.stack_door.is_empty() or squad.order.get("type", "") == "hold"


func _squad_lagging() -> bool:
	var far := 0
	for c in squad.alive():
		if c != self and c.position.distance_to(position) > 9.0:
			far += 1
	return far > squad.alive().size() / 2


func _nearest(pred: Callable, radius: float) -> Node:
	var best: Node = null
	var bd := radius
	for c in vessel.near_occupants(position, radius):
		if c != self and pred.call(c):
			var d: float = position.distance_to(c.position)
			if d < bd:
				best = c
				bd = d
	return best


func _follow_order() -> void:
	match order.get("type", ""):
		"move":
			if order.get("vessel") != vessel:
				order = {}
				return
			if arrived(0.8):
				if order.get("pos", Vector3.INF).distance_to(position) < 1.5:
					stop()
					order = {"type": "hold", "pos": position}
				else:
					go(order["pos"], true)
			elif goal == Vector3.INF or goal.distance_to(order["pos"]) > 0.5:
				go(order["pos"], true)
		"attack":
			var t: Node = order.get("target")
			if t == null or not is_instance_valid(t) or t.state != "alive" or t.vessel != vessel:
				order = {}
				return
			target = t
			go(t.position, true)
		"hold":
			pass
		"sabotage":
			if order.get("vessel") != vessel:
				order = {}
				return
			if position.distance_to(order["pos"]) < 1.6:
				stop()
				working = true
				task_t -= 0.25
				if task_t <= -4.0:
					task_t = 0.0
					working = false
					if not charges.is_empty():
						rig.show_slot(charges.pop_back(), false)
					vessel.sabotage(order["module"], team)
					order = {}
			else:
				go(order["pos"], true)


func _boarder_objective() -> void:
	var cp: Dictionary = {}
	var bd := INF
	for p in vessel.capture_points:
		if p["owner"] == team:
			continue
		var d := position.distance_to(p["pos"])
		if p["name"].contains("Command") or p["name"].contains("Bridge"):
			d *= 0.3                                  # the bridge / command core comes first
		if d < bd:
			bd = d
			cp = p
	if cp.is_empty():
		return
	# everyone takes a different spot around the objective, not the same square metre
	var k: int = get_instance_id() / 7
	var a: float = (k % 19) * 2.39996
	var r: float = 1.4 + (k % 5) * 0.75
	var offs := Vector3(cos(a) * r, 0, sin(a) * r)
	if squad:
		squad.objective = cp["pos"]
	if position.distance_to(cp["pos"]) > 2.5:
		go(vessel.snap_local(cp["pos"] + offs), true)


func _job() -> void:
	purging = false
	if role == "gunner":
		_man_gun()
		return
	if role == "scientist":
		for z in vessel.zones:
			if z["infected"] and z["growth"] > 0.0:
				if vessel.zone_at(position) == z:
					stop()
					purging = true
				else:
					go(vessel.snap_local(z["center"] - Vector3(0, z["half"].y - 0.05, 0)), false)
				return
	if role in COMBAT_ROLES and vessel.team == team and team != 4 and order.is_empty():
		_off_duty()
		return
	if role in COMBAT_ROLES or team in [3, 4]:
		working = false
		return                                      # soldiers hold where they were posted
	if role == "engineer" and vessel.has_method("repair_point"):
		var rp: Vector3 = vessel.repair_point()
		if rp != Vector3.INF:
			if position.distance_to(rp) < 1.6:
				stop()
				working = true
				repairing = true
			else:
				repairing = false
				working = false
				go(rp, false)
			return
	repairing = false
	if role == "pilot" and scramble_pad != "":
		var pad: Node3D = vessel.mark(scramble_pad)
		if pad:
			var pl: Vector3 = vessel.snap_local(vessel.local_of(pad))
			if Vector2(position.x - pl.x, position.z - pl.z).length() < 4.0:
				vessel.pilot_arrived(self, scramble_pad)
			else:
				go(pl, true)
			return
	if role == "cargo_handler":
		_cargo_job()
		return
	task_t -= 0.25
	if task_pos == Vector3.INF or task_t <= 0.0:
		working = false
		var pats: Array = JOBS.get(role, [])
		if vessel.alarm <= 0.0 and randf() < 0.22:
			pats = ["Quarters_*_Cabin*", "Mess_*_Deck*", "Mess_*_Galley", "Medbay_*_Bed_*"]   # off shift: eat, sleep
		var cands: Array = []
		for p in pats:
			cands += vessel.marks_like(p)
		if cands.is_empty() or randf() < 0.25:
			task_pos = vessel.random_local()
		else:
			task_pos = vessel.snap_local(vessel.local_of(cands[randi() % cands.size()]))
		task_t = randf_range(14.0, 30.0)
		travel(task_pos)
		return
	if arrived(0.7) and elev.is_empty():
		stop()
		working = role != "security"


func _cargo_job() -> void:
	## Haul crates between storage and the cargo bay pads (stations: between storage spots).
	var storage: Array = vessel.marks_like("CargoStorage_*") + vessel.marks_like("*_CargoStorage_*")
	var pads: Array = vessel.marks_like("CargoBay_DarterPad_*_CrewWork_*")
	if pads.is_empty():
		pads = storage
	if storage.is_empty():
		task_pos = vessel.random_local() if task_pos == Vector3.INF else task_pos
		if arrived():
			go(vessel.random_local())
		return
	if task_pos == Vector3.INF:
		var pick_from: Array = storage if job_phase == 0 else pads
		task_pos = vessel.snap_local(vessel.local_of(pick_from[randi() % pick_from.size()]))
		travel(task_pos)
		return
	if arrived(0.8) and elev.is_empty():
		stop()
		working = true
		task_t -= 0.25
		if task_t <= -3.0:
			task_t = 0.0
			working = false
			if job_phase == 0:
				carrying = true
				var crate := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(0.5, 0.35, 0.4)
				crate.mesh = bm
				crate.material_override = G._mat(Color(0.75, 0.6, 0.25), 0.0)
				rig.set_held(crate)
				job_phase = 1
			else:
				carrying = false
				rig.set_held(null)
				job_phase = 0
			task_pos = Vector3.INF


func _gear_up() -> void:
	if vessel.supplies < 3.0 or vessel.room_down("armory"):
		return                                         # the armories are bare: nothing to gear up with
	var spots: Array = vessel.marks_like("Armory_*_Resupply") + vessel.marks_like("ReadyLocker_*") + vessel.marks_like("*_ReadyLocker")
	var best: Node3D = null
	var bd := INF
	for s in spots:
		var d := position.distance_to(vessel.local_of(s))
		if d < bd:
			best = s
			bd = d
	if best == null:
		return
	var lp: Vector3 = vessel.snap_local(vessel.local_of(best))
	working = false
	carrying = false
	if role != "scientist":
		rig.set_held(null)
	if position.distance_to(lp) < 1.4:
		stop()
		gear_t = 3.0 if String(best.name).contains("Armory") else 2.0
		set_meta("gear_spot", String(best.name))
	else:
		go(lp, true)


func _finish_gear_up() -> void:
	var armory := String(get_meta("gear_spot", "")).contains("Armory")
	var fac := 2 if faction == 2 else 1
	var gun := "rifle" if armory else "smg"
	var model: String = G.data["weapons"][str(fac)][gun]["model"]
	give_weapon(model)
	spare = ["locker_1", "locker_2"] if not armory else ["armory_1", "armory_2", "armory_3"]
	dr = max(dr, 0.30 if armory else 0.12)
	if armory:
		top_up_pens(true)
		grenades.append("armory_grenade")
	geared = 2 if armory else 1
	vessel.supplies = maxf(0.0, vessel.supplies - 3.0)
	G.say("%s geared up at the %s" % [display, "armory" if armory else "ready locker"], team)


## Somewhere aboard to rearm: our own ship, with supplies and a working armory or locker.
func _resupply_possible() -> bool:
	if vessel == null or vessel.team != team or vessel.supplies < 1.0 or vessel.room_down("armory"):
		return false
	return not (vessel.marks_like("Armory_*_Resupply") + vessel.marks_like("ReadyLocker_*") + vessel.marks_like("*_ReadyLocker")).is_empty()


func _resupply() -> void:
	if vessel.team != team or vessel.supplies < 1.0 or vessel.room_down("armory"):
		return
	var spots: Array = vessel.marks_like("Armory_*_Resupply") + vessel.marks_like("ReadyLocker_*") + vessel.marks_like("*_ReadyLocker")
	if spots.is_empty():
		return
	var s: Node3D = spots[randi() % spots.size()]
	var lp: Vector3 = vessel.snap_local(vessel.local_of(s))
	if position.distance_to(lp) < 1.5:
		spare = ["re_1", "re_2", "re_3"]
		mag = int(wstats.get("ammo_per_load", 30))
		vessel.supplies = maxf(0.0, vessel.supplies - 1.0)
		top_up_pens(true)
		if role == "grenadier":
			gl_ammo = GL_ROUNDS
			breach_ammo = BREACH_ROUNDS
			kit_refresh()
	else:
		go(lp, true)


# ------------------------------------------------------------------ the infected

func _brain_infected() -> void:
	if target and is_instance_valid(target) and target.state == "alive":
		var tl: Vector3 = vessel.to_local(target.global_position)
		go(tl, true)
		if role == "swarmer" and position.distance_to(tl) < 1.7 and melee_t <= 0.0:
			melee_t = 0.8
			rig.throw_t = 0.3
			target.take_damage(22.0, self, global_position)
		return
	# no prey in sight: spread the growth through the vessel
	var here: Dictionary = vessel.zone_at(position)
	if not here.is_empty() and not here["infected"]:
		here["purge"] -= 0.25
		if here["purge"] < -8.0:
			vessel.infect_zone(here)
		return
	if arrived():
		var clean: Array = vessel.zones.filter(func(z): return not z["infected"])
		if not clean.is_empty():
			var z: Dictionary = clean[randi() % clean.size()]
			go(vessel.snap_local(z["center"] - Vector3(0, z["half"].y - 0.05, 0)), true)
		else:
			go(vessel.random_local(), false)


# ------------------------------------------------------------------ weapons

func _ai_fire(dt: float) -> void:
	if armed and squad and not squad.suppress.is_empty() and (target == null or not los) and reload_t < 0.0:
		_suppress_fire()
		return
	if not armed or target == null or not is_instance_valid(target) or not los or target.state != "alive":
		return
	if squad and squad.hold_fire and position.distance_to(target.position) > 8.0 and target.get("target") != self:
		return                                           # weapons tight: only close or direct threats
	if reload_t >= 0.0 or (crouch and in_cover.size() > 0 and in_cover[1]):
		return
	if role == "grenadier" and _ai_launcher():
		return
	if mag <= 0:
		if reload_t < 0.0 and not spare.is_empty():
			reload_t = float(wstats.get("reload_s", 2.0))
		return
	if fire_t > 0.0:
		return
	var rpm: float = float(wstats.get("rpm", 300))
	var sps: float = min(rpm / 60.0, 6.0)
	fire_t = 1.0 / sps
	burst += 1
	if burst >= 4 + randi() % 4:
		burst = 0
		fire_t += randf_range(0.35, 0.8)
	var spread := 1.2
	if velocity.length() > 0.5:
		spread += 1.5
	if team == 4:
		spread *= 3.0
	var aim: Vector3 = target.chest() + Vector3(randfn(0, 0.15), randfn(0, 0.2), randfn(0, 0.15))
	var dir := (aim - eye()).normalized()
	dir = dir.rotated(Vector3.UP, deg_to_rad(randfn(0, spread))).rotated(dir.cross(Vector3.UP).normalized(), deg_to_rad(randfn(0, spread)))
	fire(eye(), dir, (rpm / 60.0) / sps)


## Suppressing fire on the point the squad leader marked.
func _suppress_fire() -> void:
	var p: Vector3 = vessel.to_global(squad.suppress["pos"])
	var to_l: Vector3 = squad.suppress["pos"] - position
	to_l.y = 0.0
	if to_l.length() > 0.1:
		rotation.y = atan2(-to_l.x, -to_l.z)
	if fire_t > 0.0:
		return
	if mag <= 0:
		if not spare.is_empty():
			reload_t = float(wstats.get("reload_s", 2.0))
		return
	var h := G.ray(eye(), p, [get_rid()], G.LAYER_WORLD | G.LAYER_DOOR)
	if not h.is_empty() and (h.position as Vector3).distance_to(p) > 2.0:
		return                                            # no line of fire from here
	var rpm: float = float(wstats.get("rpm", 300))
	fire_t = 1.0 / min(rpm / 60.0, 6.0) * randf_range(1.0, 1.6)
	var dir := (p + Vector3(randfn(0, 0.5), randfn(0, 0.4), randfn(0, 0.5)) - eye()).normalized()
	fire(eye(), dir)
	G.stat("suppress_shots")


## Fire one shot (or a shotgun blast) from `from` along `dir`. `mult` scales damage.
func fire(from: Vector3, dir: Vector3, mult: float = 1.0) -> void:
	if mag <= 0:
		return
	mag -= 1
	rig.recoil = 1.0
	var muzzle: Vector3 = rig.muzzle_position()
	if self == G.possessed and G.commander and G.commander.viewmodel and G.commander.viewmodel.visible:
		var vm: Vector3 = G.commander.viewmodel.muzzle_world()
		if vm != Vector3.INF:
			muzzle = vm                                   # the tracer leaves the gun you can see
	var energy: bool = wstats.get("type", "ballistic") == "energy"
	var col := Color(1.0, 0.8, 0.35) if not energy else (Color(1.0, 0.25, 0.45) if faction == 2 else Color(0.45, 1.0, 0.4))
	if faction == 3:
		col = Color(0.55, 1.0, 0.45)
	G.flash(muzzle, col, 3.0, 4.0, 0.05)
	if G.sfx:
		G.sfx.play("energy" if energy else weapon_class().replace("battle_rifle", "rifle").replace("bullpup_gl", "rifle"), muzzle, 0.0 if self == G.possessed else -6.0)
	var pellets: int = int(wstats.get("pellets", 1))
	var dmg: float = shot_damage() * mult * G.dmg_mult(team)
	var rng_m: float = float(wstats.get("range_m", 60)) * 2.0
	for i in pellets:
		var d := dir
		if pellets > 1:
			d = (dir + Vector3(randfn(0, 0.06), randfn(0, 0.06), randfn(0, 0.06))).normalized()
		var hit := G.ray(from, from + d * rng_m, [get_rid()])
		var end: Vector3 = hit.position if not hit.is_empty() else from + d * rng_m
		G.tracer(muzzle, end, col, 0.05 if energy else 0.025, 0.07 if energy else 0.04)
		if G.network and G.network.active and multiplayer.is_server() and i == 0:
			G.network.queue_fx("t", muzzle, end, col)
		if hit.is_empty():
			continue
		var who: Object = hit.collider
		if who != null and who.has_meta("door_of"):
			var dv: Node = who.get_meta("door_of")
			if is_instance_valid(dv):
				dv.door_hit(who, dmg, from)
			G.flash(end - d * 0.1, col, 1.2, 1.5, 0.04)
		elif who != null and who.has_meta("vehicle"):
			var veh: Node = who.get_meta("vehicle")
			if is_instance_valid(veh):
				# small arms barely scratch armour; a heavy's gun or a breacher's shotgun does a little more
				veh.take_hit(dmg * (0.35 if role in ["heavy", "breacher"] else 0.12), end, self, 0.5)
			G.flash(end - d * 0.1, Color(1.0, 0.8, 0.5), 1.5, 1.5, 0.04)
		elif who != null and who.has_method("take_damage") and who != self:
			var falloff: float = 1.0 if pellets == 1 else clamp(1.4 - from.distance_to(end) / rng_m, 0.2, 1.0)
			who.take_damage(dmg * falloff, self, from)
			if self == G.possessed and G.commander:
				G.commander.hit_marker(who.state != "alive")
		else:
			G.flash(end - d * 0.1, col, 1.2, 1.5, 0.04)
		var splash: float = float(wstats.get("splash_radius_m", 0.0))
		if splash > 0.0:
			G.blast(end, splash, dmg * 0.5, self)


func _throw_grenade(at: Vector3, emp: bool = false) -> void:
	var pool: Array = emps if emp else grenades
	if pool.is_empty():
		return
	rig.show_slot(pool.pop_back(), false)
	rig.throw_t = 0.0
	var gr := preload("res://scripts/grenade.gd").new()
	get_tree().root.add_child(gr)
	gr.emp = emp
	gr.launch(eye() + Vector3.UP * 0.2, at, self, 2 if faction == 2 else 1)


## Fire a 40 mm shell from the underslung launcher. Returns the shell (null when empty).
func fire_launcher(from: Vector3, dir: Vector3) -> Node3D:
	if gl_ammo <= 0:
		return null
	gl_ammo -= 1
	kit_refresh()
	var st: Dictionary = G.data.get("items", {}).get("GLShell", {})
	_gl_cd = float(st.get("reload_s", 1.6))
	rig.recoil = 1.0
	var gr := GRENADE.new()
	get_tree().root.add_child(gr)
	gr.fire_shell(from, dir, self, st)
	G.flash(from + dir * 0.2, Color(1.0, 0.75, 0.4), 2.0, 2.5, 0.06)
	if G.sfx:
		G.sfx.play("shotgun", from, -2.0 if self == G.possessed else -8.0)
	return gr


## Fire a breaching round from the launcher. `aim` is the door/wall dict it's meant for.
func fire_breach_round(from: Vector3, dir: Vector3, aim: Dictionary = {}) -> Node3D:
	if breach_ammo <= 0:
		return null
	breach_ammo -= 1
	kit_refresh()
	var st: Dictionary = G.data.get("items", {}).get("BreachRound", {})
	_gl_cd = float(G.data.get("items", {}).get("GLShell", {}).get("reload_s", 1.6))
	rig.recoil = 1.0
	var r := BREACH_ROUND.new()
	get_tree().root.add_child(r)
	r.fire(from, dir, self, st, aim)
	G.flash(from + dir * 0.2, Color(1.0, 0.75, 0.4), 1.6, 2.0, 0.06)
	if G.sfx:
		G.sfx.play("shotgun", from, -4.0 if self == G.possessed else -10.0)
	return r


## AI grenadier as the squad's breacher: from 12 m or less with a clear line, fire a breaching
## round at the stacked wall or door instead of walking up to it. True when it fired.
func _breach_shot(d: Dictionary) -> bool:
	var dw: Vector3 = vessel.to_global(d["center"])
	var from := _gl_muzzle()
	if from.distance_to(dw) > 12.0:
		return false
	var hit := G.ray(from, dw, [get_rid()], G.LAYER_WORLD | G.LAYER_DOOR)
	if not hit.is_empty() and (hit.position as Vector3).distance_to(dw) > 1.2:
		return false                                      # something else in the way
	stop()
	var to_d: Vector3 = (d["center"] as Vector3) - position
	if Vector2(to_d.x, to_d.z).length() > 0.1:
		rotation.y = atan2(-to_d.x, -to_d.z)
	if fire_breach_round(from, (dw - from).normalized(), d) == null:
		return false
	d["charged"] = true                                   # the rest of the stack waits for it
	G.say("%s fired a breaching round aboard %s" % [display, vessel.display_name], team)
	return true


## The launcher's muzzle in the world (the gun's GLMuzzle marker), else just below the eye.
func _gl_muzzle() -> Vector3:
	if rig.weapon:
		var m: Node3D = rig.weapon.find_child("GLMuzzle", true, false)
		if m:
			return m.global_position
	return eye() + Vector3.DOWN * 0.3


## B: rifle -> launcher (frag) -> launcher (breaching round) -> rifle, skipping what's run out.
func _cycle_launcher() -> void:
	if not gl_mode:
		gl_mode = gl_ammo > 0 or breach_ammo > 0
		gl_breach = gl_ammo <= 0
	elif not gl_breach and breach_ammo > 0:
		gl_breach = true
	else:
		gl_mode = false
		gl_breach = false


## AI grenadier: a shell into a group of hostiles or onto one in cover, 8-35 m off, with no
## friendlies near the burst. Returns true when it fired.
func _ai_launcher() -> bool:
	if gl_ammo <= 0 or _gl_cd > 0.0 or not target is Node3D:
		return false
	var tp: Vector3 = (target as Node3D).global_position
	var dist := global_position.distance_to(tp)
	if dist < 8.0 or dist > 35.0:
		return false
	var others := 0
	for o in G.characters:
		if not is_instance_valid(o) or o == target or o == self or o.state == "dead":
			continue
		if o.global_position.distance_to(tp) > 4.5:
			continue
		if not G.enemies(team, o.team):
			return false                                  # a friend (downed ones too) would be in the burst
		if o.state == "alive":
			others += 1
	var ic = target.get("in_cover")
	var covered: bool = (ic is Array and not (ic as Array).is_empty()) or target.get("crouch") == true
	if others < 1 and not covered:
		return false
	var st: Dictionary = G.data.get("items", {}).get("GLShell", {})
	var from := _gl_muzzle()
	var dir := _lob(from, tp + Vector3.UP * 0.3, float(st.get("speed_m_s", 50.0)))
	if dir == Vector3.ZERO:
		return false
	dir = dir.rotated(Vector3.UP, deg_to_rad(randfn(0.0, 1.2)))
	if not G.ray(from, from + dir * 3.0, [get_rid()], G.LAYER_WORLD | G.LAYER_DOOR).is_empty():
		return false                                      # the first stretch is blocked
	fire_launcher(from, dir)
	_gl_cd = maxf(_gl_cd, randf_range(5.0, 8.0))          # don't empty the belt in one go
	return true


## The low arc from `from` that lands on `to` at launch speed `v` (ZERO when out of reach).
static func _lob(from: Vector3, to: Vector3, v: float) -> Vector3:
	var d := to - from
	var h := Vector2(d.x, d.z).length()
	if h < 0.5:
		return Vector3.ZERO
	var g := 9.8
	var v2 := v * v
	var disc := v2 * v2 - g * (g * h * h + 2.0 * d.y * v2)
	if disc < 0.0:
		return Vector3.ZERO
	var ang := atan((v2 - sqrt(disc)) / (g * h))
	var flat := Vector3(d.x, 0.0, d.z).normalized()
	return (flat * cos(ang) + Vector3.UP * sin(ang)).normalized()


func stun(t: float) -> void:
	if state != "alive":
		return
	stun_t = maxf(stun_t, t)
	if self == G.possessed and G.commander and G.commander.has_method("emp_static"):
		G.commander.emp_static(t)


# ------------------------------------------------------------------ the player in control

func _player_physics(dt: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var sprint := Input.is_action_pressed("sprint") and input.y < -0.1 and not ads
	var on_floor := is_on_floor()
	ads = (Input.is_action_pressed("aim") or get_meta("force_ads", false)) and armed and slide_t <= 0.0
	# exo energy
	exo_cd -= dt
	if exo_cd <= 0.0:
		exo = min(exo_max(), exo + 30.0 * dt)
	if on_floor:
		air_boost = false
	# slide: sprint + crouch
	if Input.is_action_just_pressed("crouch") and sprint and on_floor and slide_t <= 0.0:
		slide_t = 0.75
		slide_dir = (global_basis * Vector3(input.x, 0, input.y)).normalized()
	slide_t -= dt
	crouch = (Input.is_action_pressed("crouch") and slide_t <= 0.0) or slide_t > 0.0
	_set_crouch_shape(crouch)
	var spd := 3.2
	if sprint:
		spd = 5.4
	if crouch:
		spd *= 0.55
	if ads:
		spd *= 0.6
	if hauling != null:
		spd = minf(spd, 3.0)
	if revive_t >= 0.0 or gear_t >= 0.0:
		spd = 0.0
	rotation.y = look_yaw
	var want := (global_basis * Vector3(input.x, 0, input.y)) * spd
	if slide_t > 0.0:
		want = slide_dir * lerpf(4.0, 9.5, slide_t / 0.75)
	var accel := 14.0 if on_floor else 2.5                # snappy on the deck, floaty in the air
	velocity.x = move_toward(velocity.x, want.x, accel * spd * dt + (60.0 * dt if slide_t > 0.0 else 0.0))
	velocity.z = move_toward(velocity.z, want.z, accel * spd * dt + (60.0 * dt if slide_t > 0.0 else 0.0))
	# jumping: a normal jump, then an exo boost jump in the air
	if Input.is_action_just_pressed("jump"):
		if on_floor:
			velocity.y = 4.6
		elif not air_boost and exo >= 25.0:
			air_boost = true
			exo -= 25.0
			exo_cd = 0.8
			velocity.y = 6.2
			var fwd := global_basis * Vector3(input.x, 0, input.y)
			velocity += fwd * 2.5
			G.flash(global_position + Vector3.UP * 0.4, Color(0.5, 0.8, 1.0), 2.0, 3.0, 0.1)
	# boost dash in any direction (V)
	if Input.is_action_just_pressed("dash") and exo >= 30.0:
		exo -= 30.0
		exo_cd = 0.8
		var d := global_basis * Vector3(input.x, 0, input.y)
		if d.length() < 0.1:
			d = -global_basis.z
		d = d.normalized()
		velocity.x = d.x * 13.0
		velocity.z = d.z * 13.0
		if not on_floor:
			velocity.y = max(velocity.y, 1.0)
		G.flash(global_position + Vector3.UP * 0.9, Color(0.5, 0.8, 1.0), 2.0, 3.0, 0.1)
	if not on_floor:
		velocity.y = max(velocity.y - 11.0 * dt, -25.0)
	elif velocity.y < 0.0:
		velocity.y = 0.0
	move_and_slide()
	_timers(dt)
	# shooting (no shooting while sprinting or sliding: the gun is down)
	kick = move_toward(kick, 0.0, dt * 6.0)
	var can_fire := armed and fire_t <= 0.0 and reload_t < 0.0 and not sprint and slide_t <= 0.0
	if role == "grenadier" and Input.is_action_just_pressed("launcher") and armed:
		_cycle_launcher()
	if gl_mode and Input.is_action_just_pressed("fire") and armed and _gl_cd <= 0.0 and not sprint and slide_t <= 0.0 and G.commander:
		var gcam: Camera3D = G.commander.fps_cam
		var gd := -gcam.global_transform.basis.z
		var gfrom: Vector3 = gcam.global_position + gd * 0.5 + Vector3.DOWN * 0.12
		if G.is_client():
			G.network.send_action(self, "breach" if gl_breach else "gl", [gfrom, gd])
		if gl_breach:
			fire_breach_round(gfrom, gd)
		else:
			fire_launcher(gfrom, gd)
		look_pitch = clampf(look_pitch + deg_to_rad(3.5), -1.45, 1.45)
		kick = 1.0
		_gl_latch = true                                  # no rifle fire until the trigger is let go
		if (breach_ammo if gl_breach else gl_ammo) <= 0:
			_cycle_launcher()
	if _gl_latch and not Input.is_action_pressed("fire"):
		_gl_latch = false
	if Input.is_action_pressed("fire") and can_fire and not gl_mode and not _gl_latch and G.commander:
		if mag > 0:
			var rpm: float = float(wstats.get("rpm", 300))
			fire_t = 60.0 / rpm
			var cam: Camera3D = G.commander.fps_cam
			var spread := (0.15 if ads else 0.9) * (0.6 if crouch else 1.0) * G.spread_mult(team)
			if not on_floor:
				spread += 1.5
			var d := -cam.global_transform.basis.z
			d = (d + Vector3(randfn(0, 1), randfn(0, 1), randfn(0, 1)) * deg_to_rad(spread) * 0.5).normalized()
			if G.is_client():
				G.network.send_fire(self, cam.global_position, d)
			fire(cam.global_position, d)
			# recoil: the view climbs and wanders a little; aiming and crouching tame it
			var k: float = KICK.get(wstats.get("class", "rifle"), 0.6) * (0.55 if ads else 1.0) * (0.75 if crouch else 1.0)
			look_pitch = clampf(look_pitch + deg_to_rad(k), -1.45, 1.45)
			look_yaw += deg_to_rad(randfn(0.0, k * 0.35))
			kick = 1.0
		elif not spare.is_empty():
			reload_t = float(wstats.get("reload_s", 2.0)) * (0.8 if G.has_tech(team, "w3") else 1.0)
			if G.is_client():
				G.network.send_action(self, "reload", [])      # (the host's copy of us reloads too)
	if Input.is_action_just_pressed("reload") and reload_t < 0.0 and not spare.is_empty() and armed:
		reload_t = float(wstats.get("reload_s", 2.0)) * (0.8 if G.has_tech(team, "w3") else 1.0)
		if G.is_client():
			G.network.send_action(self, "reload", [])
	if Input.is_action_just_pressed("grenade") and (not grenades.is_empty() or not emps.is_empty()) and G.commander:
		var cam: Camera3D = G.commander.fps_cam
		var at := cam.global_position - cam.global_transform.basis.z * 18.0
		# frags first; with Shift held (or no frags left) an EMP
		var emp := not emps.is_empty() and (grenades.is_empty() or Input.is_key_pressed(KEY_SHIFT))
		if G.is_client():
			G.network.send_action(self, "grenade", [at, emp])
		_throw_grenade(at, emp)
	if Input.is_action_just_pressed("medpen") and not medpens.is_empty() and hp < max_hp:
		rig.show_slot(medpens.pop_back(), false)
		hp = min(max_hp, hp + 40)
		if G.is_client():
			G.network.send_action(self, "medpen", [])
	# the vessel tracks what its people see, even when you drive
	think_t -= dt
	if think_t <= 0.0:
		think_t = 0.3
		if not G.is_client():
			_perceive()
			_pick_up_cores()


func exo_max() -> float:
	return 140.0 if G.has_tech(team, "a3") else 100.0


var _crouched_shape := false


func _set_crouch_shape(on: bool) -> void:
	if on == _crouched_shape or state != "alive":
		return
	_crouched_shape = on
	$Hitbox.shape.height = 1.2 if on else 1.8
	$Hitbox.position.y = 0.6 if on else 0.9


## The player pressed "use" while looking at something.
func player_use(hit: Dictionary) -> String:
	var med := _player_medical()
	if med != "":
		return med
	# elevators: call the car to this deck, or ride to the next deck
	var e: int = vessel.elevator_at(position)
	if e >= 0:
		var el: Dictionary = vessel.elevators[e]
		var my_deck := int(round(position.y / 4.0))
		var in_car: bool = abs(position.x - el["center"].x) < 1.4 and abs(position.z - el["center"].z) < 1.4
		if in_car:
			vessel.call_elevator(e, (el["deck"] + 1) % el["decks"])
			return "Elevator to deck %d" % ((el["deck"] + 1) % el["decks"])
		vessel.call_elevator(e, my_deck)
		return "Elevator called to deck %d" % my_deck
	# gear up at a locker or armory on our own vessel
	if vessel.team == team and vessel.room_down("armory"):
		for s in vessel.marks_like("Armory_*_Resupply") + vessel.marks_like("Armory_*_Counter") + vessel.marks_like("ReadyLocker_*") + vessel.marks_like("*_ReadyLocker"):
			if position.distance_to(vessel.local_of(s)) < 3.0:
				return "The armory is wrecked: engineers have to repair it first"
	if vessel.team == team:
		for s in vessel.marks_like("Armory_*_Resupply") + vessel.marks_like("Armory_*_Counter") + vessel.marks_like("ReadyLocker_*") + vessel.marks_like("*_ReadyLocker"):
			if position.distance_to(vessel.local_of(s)) < 3.0:
				if vessel.supplies < 4.0:
					return "The armory is bare: this ship needs a supply run"
				vessel.supplies -= 4.0
				spare = ["re_1", "re_2", "re_3"]
				for slot in ["MagSlot_1", "MagSlot_2", "MagSlot_3", "MagSlot_4", "MagSlot_5", "MagSlot_6"]:
					rig.show_slot(slot, true)
				if role != "grenadier":                   # grenadiers carry no hand grenades
					while grenades.size() < 2:
						grenades.append("armory_grenade_%d" % grenades.size())
				top_up_pens(true)
				if role == "breacher":
					while charges.size() < 2:
						charges.append("armory_charge_%d" % charges.size())
				if role == "grenadier":
					gl_ammo = GL_ROUNDS
					breach_ammo = BREACH_ROUNDS
					kit_refresh()
				if not armed:
					set_meta("gear_spot", String(s.name))
					_finish_gear_up()
				return "Resupplied: mags, grenades, medpens (ship supplies %d)" % int(vessel.supplies)
	# an enemy door in front of us: kick it in, or set a charge on a heavy / secure one
	var dd: Dictionary = vessel.door_blocking(position, -transform.basis.z, 1.6)
	if not dd.is_empty() and team != vessel.team:
		if dd["kind"] == "door":
			if _kick_cd > 0.0:
				return ""
			_kick_cd = 0.65
			kick_door(dd)
			return "Kicked the door" if not dd["breached"] else "Door down"
		if dd.get("charged", false):
			return "Charge set: stand clear"
		if not charges.is_empty():
			rig.show_slot(charges.pop_back(), false)
			vessel.plant_charge(dd, self)
			return "Breaching charge set: 3 seconds"
		return "Security door: needs a breaching charge" if dd["kind"] == "secure" else "Blast door: shoot it down or use a charge"
	# a weak wall section (hazard stripes): a charge blows a doorway through it
	var wd: Dictionary = vessel.wall_near(position, 1.6) if vessel.has_method("wall_near") else {}
	if not wd.is_empty():
		if wd.get("charged", false):
			return "Charge set: stand clear"
		if not charges.is_empty():
			rig.show_slot(charges.pop_back(), false)
			vessel.plant_charge(wd, self)
			return "Wall charge set: 3 seconds"
		return "Weak wall: a breaching charge will blow a way through"
	return ""


# ------------------------------------------------------------------ medical

func pen_cap() -> int:
	if role in ["medic", "medical_officer"]:
		return MEDIC_PENS
	if role in COMBAT_ROLES or role == "security":
		return PENS
	return 0


## Fill up on revive pens (spawn, armory, resupply); medics also reload the revive gun.
func top_up_pens(refill_gun: bool = false) -> void:
	var cap := pen_cap()
	while medpens.size() < cap:
		medpens.append("pen_%d" % medpens.size())
	if refill_gun and role == "medic":
		revive_gun = REVIVE_GUN


func _downed_physics(dt: float) -> void:
	var c: Node = carried_by
	if c != null and (not is_instance_valid(c) or c.state != "alive" or c.vessel != vessel or c.hauling != self):
		carried_by = null
		c = null
	if on_bed:
		pass                                            # stabilised on a medbay bed
	elif c != null:
		bleed -= dt * 0.2                               # pressure on the wound while they move us
	else:
		bleed -= dt
	if bleed <= 0.0:
		die(null)
		return
	if c != null:
		var back: Vector3 = c.transform.basis.z         # characters face -Z: +Z is behind them
		back.y = 0.0
		back = back.normalized()
		if c == G.possessed or c.target != null or c.crouch:
			position = c.position + back * 0.9          # dragged along the deck by the harness
			rotation.y = c.rotation.y + PI
		else:
			position = c.position + Vector3.UP * 1.15 + back * 0.05   # over the shoulder
			rotation.y = c.rotation.y + PI * 0.5
		velocity = Vector3.ZERO
		_settled = false
		return
	if on_bed:
		velocity = Vector3.ZERO
		return
	velocity = Vector3(0, velocity.y - 9.8 * dt if not is_on_floor() else 0.0, 0)
	move_and_slide()


## Let go of whoever we're hauling (they slump to the deck where they are).
func drop_haul() -> void:
	var h: Node = hauling
	hauling = null
	carrying = false
	_haul_to = Vector3.INF
	_haul_bed = Vector3.INF
	if h != null and is_instance_valid(h) and h.carried_by == self:
		h.carried_by = null
		if h.state == "downed" and not h.on_bed:
			h.position = Vector3(h.position.x, position.y + 0.05, h.position.z)


func start_haul(d: Node) -> bool:
	if d.carried_by != null and is_instance_valid(d.carried_by) and d.carried_by != self:
		return false
	var dest := _medbay_for(d)
	if dest.is_empty():
		return false
	hauling = d
	d.carried_by = self
	d.on_bed = false
	_haul_to = dest[0]
	_haul_bed = dest[1]
	carrying = true
	G.stat("hauls")
	if self == G.possessed or d == G.possessed:
		G.say("%s is getting %s to the medbay" % [display, d.display], team)
	return true


## Where to take a downed friend: [floor point beside a free medbay bed, mattress] on our own
## vessel, or failing that [a teammate who can revive them, INF].
func _medbay_for(d: Node) -> Array:
	var best: Array = []
	var bd := 1.0e9
	if vessel.team == team and not vessel.room_down("medbay"):
		for b in vessel.marks_like("Medbay_*_Bed_*"):
			var top: Vector3 = vessel.local_of(b)
			if _bed_taken(top, d):
				continue
			var dist: float = position.distance_to(top) + absf(top.y - position.y) * 6.0
			if dist < bd:
				bd = dist
				best = [vessel.snap_local(top - Vector3(0, 0.75, 0)), top]
	if best.is_empty():
		var m: Node = _nearest(func(c): return c.team == team and c.state == "alive" and c != d \
			and (c.medpens.size() > 0 or c.revive_gun > 0 or c.revive_kit > 0), 45.0)
		if m:
			best = [m.position, Vector3.INF]
	return best


func _bed_taken(top: Vector3, d: Node) -> bool:
	for o in vessel.occupants:
		if o == d:
			continue
		if o.state == "downed" and o.position.distance_to(top) < 0.9:
			return true
		if o != self and o.hauling != null and o._haul_bed != Vector3.INF and o._haul_bed.distance_to(top) < 0.3:
			return true
	return false


func _free_bed_near(p: Vector3, r: float, d: Node) -> Vector3:
	for b in vessel.marks_like("Medbay_*_Bed_*"):
		var top: Vector3 = vessel.local_of(b)
		if Vector2(top.x - p.x, top.z - p.z).length() < r and absf(top.y - 0.75 - p.y) < 1.2 and not _bed_taken(top, d):
			return top
	return Vector3.INF


## AI: carry on toward the medbay (or a medic) with the one we're hauling.
func _haul() -> void:
	var h: Node = hauling
	if h == null or not is_instance_valid(h) or h.state != "downed" or h.vessel != vessel or h.carried_by != self:
		drop_haul()
		return
	carrying = true
	crouch = target != null
	if _haul_bed == Vector3.INF:
		var dest := _medbay_for(h)                      # the medic moves; a bed may have come free
		if dest.is_empty():
			drop_haul()
			return
		_haul_to = dest[0]
		_haul_bed = dest[1]
	var near_r := 1.2 if _haul_bed != Vector3.INF else 1.8
	if Vector2(position.x - _haul_to.x, position.z - _haul_to.z).length() < near_r and absf(position.y - _haul_to.y) < 1.6:
		stop()
		var bed := _haul_bed
		drop_haul()
		if bed == Vector3.INF:
			return                                      # set down beside the medic
		h.position = bed + Vector3(0, 0.05, 0)          # onto the bed, and treat them
		h.on_bed = true
		h.rotation.y = rotation.y
		_begin_revive(h, "bed")
		return
	if goal == Vector3.INF or goal.distance_to(_haul_to) > 0.8:
		go(_haul_to, true)


var revive_len := 3.0


func _begin_revive(d: Node, src: String) -> void:
	revive_who = d
	revive_src = src
	revive_len = {"pen": 3.0, "kit": 4.0, "gun": 1.5, "bed": BED_TREAT_S}.get(src, 3.0)
	revive_t = revive_len
	d.set_meta("tend", [self, G.time])


func _revive_source(d: Node, dist: float) -> String:
	if d.on_bed:
		return "bed"
	if revive_gun > 0 and dist > 2.0:
		return "gun"
	if not medpens.is_empty():
		return "pen"
	if revive_kit > 0:
		return "kit"
	if revive_gun > 0:
		return "gun"
	return ""


func _claimed_by_other(c: Node) -> bool:
	if not c.has_meta("tend"):
		return false
	var t: Array = c.get_meta("tend")
	return t[0] != self and is_instance_valid(t[0]) and t[0].state == "alive" and G.time - float(t[1]) < 1.0


func _clear_shot(d: Node) -> bool:
	return G.ray(eye(), d.global_position + Vector3.UP * 0.3, [get_rid(), d.get_rid()], G.LAYER_WORLD | G.LAYER_DOOR).is_empty()


## Someone else close by who can revive d and isn't busy fighting.
func _helper_near(d: Node) -> bool:
	for o in vessel.near_occupants(d.position, 10.0):
		if o == self or o == d or o.team != team or o.state != "alive" or o == G.possessed:
			continue
		if o.position.distance_to(d.position) > 10.0:
			continue
		if (o.medpens.size() > 0 or o.revive_kit > 0 or o.revive_gun > 0) and (o.role == "medic" or o.target == null):
			return true
	return false


## Duty brain: revive a downed friend, or get them to the medbay. True when busy with it.
func _tend_downed() -> bool:
	var has_src := not medpens.is_empty() or revive_kit > 0 or revive_gun > 0
	var r := 25.0 if role in ["medic", "medical_officer"] else 12.0
	var d: Node = _nearest(func(c): return c.team == team and c.state == "downed" and not _claimed_by_other(c) \
		and (has_src or c.on_bed or c.carried_by == null or not is_instance_valid(c.carried_by)), r)
	if d == null:
		return false
	var dist := position.distance_to(d.position)
	var src := _revive_source(d, dist)
	if src == "":
		# nothing to revive with: carry them to the medbay, unless someone who can is close by
		if _helper_near(d) or not start_haul(d):
			return false
		_haul()
		return true
	d.set_meta("tend", [self, G.time])
	var flat := Vector2(position.x - d.position.x, position.z - d.position.z).length()
	var ok := false
	match src:
		"gun":
			ok = dist < GUN_RANGE and _clear_shot(d)
		"bed":
			ok = flat < 1.9 and absf(d.position.y - position.y) < 1.6
		_:
			ok = dist < 1.3
	if ok:
		stop()
		_begin_revive(d, src)
		return true
	var to: Vector3 = vessel.snap_local(d.position)
	if goal == Vector3.INF or goal.distance_to(to) > 0.8:
		go(to, true)
	return true


## Combat brain: medics revive under fire (the gun from cover, a pen up close); anyone
## standing over a downed friend out of the line of fire uses a pen.
func _medic_in_combat() -> bool:
	var medic := role == "medic"
	var d: Node = _nearest(func(c): return c.team == team and c.state == "downed" and not c.on_bed and not _claimed_by_other(c),
		GUN_RANGE if medic else 1.6)
	if d == null:
		return false
	var dist := position.distance_to(d.position)
	if medic and revive_gun > 0 and dist > 1.6 and _clear_shot(d):
		stop()
		_begin_revive(d, "gun")
		return true
	if dist < 1.6 and (not medpens.is_empty() or revive_kit > 0) and (medic or not los):
		stop()
		_begin_revive(d, "pen" if not medpens.is_empty() else "kit")
		return true
	return false


## The downed friend the player's revive gun is pointed at.
func _gun_target() -> Node:
	if revive_gun <= 0:
		return null
	var fwd: Vector3 = -transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var best: Node = null
	var bd := GUN_RANGE
	for o in vessel.near_occupants(position, GUN_RANGE):
		if o == self or o.team != team or o.state != "downed":
			continue
		var d: Vector3 = o.position - position
		var l := d.length()
		d.y = 0.0
		if l < bd and l > 0.1 and d.normalized().dot(fwd) > 0.93 and _clear_shot(o):
			best = o
			bd = l
	return best


## The player pressed E: medical actions come first. "" when there was nothing to do.
func _player_medical() -> String:
	if hauling != null:
		var h: Node = hauling
		var bed := _free_bed_near(position, 2.6, h)
		drop_haul()
		if bed != Vector3.INF and h.state == "downed":
			h.position = bed + Vector3(0, 0.05, 0)
			h.on_bed = true
			_begin_revive(h, "bed")
			return "Treating %s on the medbay bed" % h.display
		return "Set %s down" % h.display
	var d := _nearest(func(c): return c.team == team and c.state == "downed", 2.0)
	if d:
		if d.on_bed:
			_begin_revive(d, "bed")
			return "Treating %s" % d.display
		var src := _revive_source(d, 0.0)
		if src != "":
			_begin_revive(d, src)
			return "Reviving %s%s" % [d.display, " (revive gun)" if src == "gun" else ""]
		if d.carried_by != null and is_instance_valid(d.carried_by):
			return "%s is already being carried" % d.display
		hauling = d
		d.carried_by = self
		d.on_bed = false
		carrying = true
		return "Dragging %s: get them onto a medbay bed (E)" % d.display
	var g := _gun_target()
	if g:
		_begin_revive(g, "gun")
		return "Revive gun on %s (%d left)" % [g.display, revive_gun - 1]
	return ""


## What E would do right now, for the HUD prompt ("" when nothing medical).
func medical_prompt() -> String:
	if hauling != null:
		return ("E  lay %s on the bed" if _free_bed_near(position, 2.6, hauling) != Vector3.INF else "E  set %s down  (find a medbay bed)") % hauling.display
	var d := _nearest(func(c): return c.team == team and c.state == "downed", 2.0)
	if d:
		if d.on_bed:
			return "E  treat %s" % d.display
		if not medpens.is_empty() or revive_kit > 0 or revive_gun > 0:
			return "E  revive %s" % d.display
		return "E  drag %s to the medbay" % d.display
	var g := _gun_target()
	if g:
		return "E  revive gun: %s  (%d left)" % [g.display, revive_gun]
	return ""


## Gunners: go to a free gun's seat on our own ship and stay on it (the gun only fires while
## someone is there). Kill the gunners and the guns go quiet.
func _man_gun() -> void:
	working = false
	if not vessel.has_method("free_gun_for") or vessel.team != team:
		return
	var i: int = vessel.free_gun_for(self)
	if i < 0:
		return
	var seat: Vector3 = vessel.turrets[i]["seat"]
	if Vector2(position.x - seat.x, position.z - seat.z).length() < 1.1 and absf(position.y - seat.y) < 1.5:
		stop()
		working = true
	elif goal == Vector3.INF or goal.distance_to(seat) > 0.5:
		go(seat, vessel.alarm > 0.0)


## Soldiers aboard their own ship with nothing to do: turns in the berths, then a walk round
## the decks on patrol, then back.
func _off_duty() -> void:
	working = false
	if squad and squad.leader != self:
		return                                      # (they follow their leader's rounds)
	task_t -= 0.25
	if task_t > 0.0 and not arrived():
		return
	if task_t > 0.0:
		return                                      # resting / standing a post
	if job_phase % 2 == 0:
		var bunks: Array = vessel.marks_like("Bunk_Berthing_*")
		if not bunks.is_empty():
			go(vessel.snap_local(vessel.local_of(bunks[randi() % bunks.size()]) + Vector3(randf_range(-0.6, 0.6), 0, 0)), false)
		task_t = randf_range(25.0, 50.0)
	else:
		go(vessel.random_local(), false)
		task_t = randf_range(15.0, 30.0)
	job_phase += 1


# ---- time to kill: each weapon class is tuned so a steady burst on an unarmoured target
# takes about this long (misses and armour stretch it): SMG ~5 s, assault rifle ~3.5-4 s.
const TTK := {"smg": 4.0, "rifle": 3.0, "battle_rifle": 2.6, "bullpup_gl": 2.6, "heavy": 2.8, "pistol": 3.4, "shotgun": 1.1, "sniper": 1.6}
static var _wclass := {}


func weapon_class() -> String:
	if _wclass.is_empty():
		for f in G.data.get("weapons", {}):
			for k in G.data["weapons"][f]:
				_wclass[G.data["weapons"][f][k].get("model", "")] = k
	var m := weapon_model
	if faction == 3:
		m = "F1_" + m.substr(3)
	return _wclass.get(m, _wclass.get(weapon_model, "rifle"))


func shot_damage() -> float:
	var rps: float = clampf(float(wstats.get("rpm", 300)) / 60.0, 0.6, 10.0)
	var pellets: float = maxf(1.0, float(wstats.get("pellets", 1)))
	var ttk: float = TTK.get(weapon_class(), 3.0)
	return 100.0 / (ttk * rps * (pellets * 0.6 if pellets > 1.0 else 1.0))
