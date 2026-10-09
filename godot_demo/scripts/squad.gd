extends RefCounted
## A squad: a leader and up to two fireteams that move and fight together.
##
##   * Moving: a wedge around the leader in open rooms, single file in corridors
##     (a slot that would put someone in a wall falls back into the file).
##   * In contact: bounding overwatch. One fireteam holds cover and fires while the
##     other bounds to the next cover toward the objective; they swap every few
##     seconds, or as soon as the movers are in cover.
##   * At a locked enemy door: stack up on both sides, the breacher blows it, and
##     the squad flows in behind the first pair.
##   * The leader is a player or an AI. If the leader falls, the next best takes over.

var id := 0
var team := 1
var vessel: Node3D
var leader: Node = null
var members: Array = []
var order := {}                    # {type: move|hold|follow, pos (local)} from a commander or the leading player
var objective := Vector3.INF       # where the squad is going (local)
var contact := false               # someone in the squad sees the enemy
var enemy_at := Vector3.INF        # last known enemy position (local)
var moving_team := 0               # the fireteam that bounds; the other covers
var bound_t := 0.0
var stack_door: Dictionary = {}    # a door the squad is stacked on
var stack_t := 0.0
var heading := Vector3.FORWARD     # the way the formation faces (local)
var _last_leader_pos := Vector3.INF
# --- orders a leading player can give (match.squad_command) ---
var formation := "wedge"           # wedge | file | line
var spacing := 1.0                 # 0.7 tight (regroup), 1.0 normal, 1.7 spread out
var hold_fire := false             # weapons tight: only fire at threats that are close
var suppress := {}                 # {pos (local), until}: everyone with a line of fire pours it on
var split := {}                    # {pos (local)}: fireteam B holds there while A stays with the leader
var clear := {}                    # {door, center (room, local), until}: after a breach, flow in and take corners
var _regroup_until := 0.0

# wedge slots for fireteams A (index 0-3) and B (4-7): (side, back) in metres
const WEDGE := [Vector2(-1.6, 1.4), Vector2(1.6, 1.4), Vector2(-3.0, 2.8), Vector2(3.0, 2.8),
	Vector2(-1.2, 4.6), Vector2(1.2, 4.6), Vector2(-2.6, 6.0), Vector2(2.6, 6.0)]


func add(c: Node) -> void:
	if members.has(c):
		return
	members.append(c)
	c.squad = self
	c.fireteam = (members.size() - 1) % 2
	var player_leads: bool = leader != null and (leader == G.possessed or leader.owner_peer != 0)
	if leader == null or (c.role == "squad_leader" and leader.role != "squad_leader" and not player_leads) \
			or ((c == G.possessed or c.owner_peer != 0) and not player_leads):
		leader = c


func remove(c: Node) -> void:
	members.erase(c)
	if c.get("squad") == self:
		c.squad = null
	if leader == c:
		leader = null
		_promote()


func _promote() -> void:
	var best: Node = null
	var score := -1
	for c in members:
		if c.state != "alive":
			continue
		var s: int = {"squad_leader": 5, "rifleman": 3, "grenadier": 2, "breacher": 2, "heavy": 2, "medic": 1}.get(c.role, 1)
		if c == G.possessed or c.owner_peer != 0:
			s = 10                                      # a player always leads
		if s > score:
			score = s
			best = c
	leader = best


func alive() -> Array:
	return members.filter(func(c): return is_instance_valid(c) and c.state == "alive" and c.vessel == vessel)


## Called by the match a few times a second.
func update(dt: float) -> void:
	for c in members.duplicate():
		if not is_instance_valid(c) or c.state == "dead" or c.team != team:
			remove(c)
	if leader == null or not is_instance_valid(leader) or leader.state != "alive" or leader.vessel != vessel:
		_promote()
	if leader == null:
		return
	if leader.vessel != vessel:
		vessel = leader.vessel
	# which way are we facing: the way the leader is going
	var lp: Vector3 = leader.position
	if _last_leader_pos != Vector3.INF:
		var d := lp - _last_leader_pos
		d.y = 0.0
		if d.length() > 0.3:
			heading = d.normalized()
	_last_leader_pos = lp
	# contact?
	contact = false
	for c in alive():
		if c.target and is_instance_valid(c.target) and c.los:
			contact = true
			enemy_at = vessel.to_local(c.target.global_position)
			break
	# bounding: swap the moving fireteam every few seconds
	bound_t -= dt
	if contact and bound_t <= 0.0:
		bound_t = 4.5
		moving_team = 1 - moving_team
	# a locked enemy door in the leader's way: stack on it
	if stack_door.is_empty() and G.enemies(team, vessel.team):
		# the way the leader is about to go (next waypoint), or any closed door right at his elbow
		var dir: Vector3 = heading
		if leader.get("path") != null and leader.path_i < leader.path.size():
			dir = leader.path[leader.path_i] - leader.position
			dir.y = 0.0
		var d2: Dictionary = vessel.door_blocking(leader.position, dir, 2.4)
		if d2.is_empty() and leader.velocity.length() < 0.5:
			d2 = vessel.door_blocking(leader.position, Vector3.ZERO, 1.8)
		if not d2.is_empty():
			stack_door = d2
			stack_t = 0.0
	if not stack_door.is_empty():
		stack_t += dt
		if stack_door["breached"] or stack_door["open"] or stack_t > 25.0:
			if stack_door["breached"]:
				bound_t = 0.0                  # the door's down: flow in
			if (stack_door["breached"] or stack_door["open"]) and stack_door.get("clear_after", false):
				stack_door.erase("clear_after")
				_start_clear(stack_door)
			stack_door = {}
	# heavy resistance through the open way in: blow a hole through a weak wall instead
	_wall_t -= dt
	if _wall_t <= 0.0 and contact and stack_door.is_empty() and clear.is_empty() and leader_player() == null \
			and enemy_at != Vector3.INF and vessel.get("breach_walls") != null and G.enemies(team, vessel.team):
		_wall_t = 3.0
		_consider_wall()
	if not clear.is_empty() and G.time > clear["until"]:
		clear = {}
	if not suppress.is_empty() and G.time > suppress["until"]:
		suppress = {}
	if spacing < 1.0 and G.time > _regroup_until:
		spacing = 1.0


var _wall_t := 3.0


func _consider_wall() -> void:
	# how hard is it: hostiles near where the enemy is
	var foes := 0
	for c in vessel.near_occupants(enemy_at, 10.0):
		if is_instance_valid(c) and c.state == "alive" and G.enemies(team, c.team):
			foes += 1
	if foes < 3:
		return
	var has_charge := false
	for m in alive():
		if not m.charges.is_empty():
			has_charge = true
			break
	if not has_charge:
		return
	var best: Dictionary = {}
	var bd := 18.0
	for w in vessel.breach_walls:
		if w["breached"] or w.get("charged", false):
			continue
		var wc: Vector3 = w["center"]
		if absf(wc.y - 1.2 - leader.position.y) > 1.6:
			continue
		var d: float = wc.distance_to(leader.position)
		if d > bd:
			continue
		# the far side has to be toward the enemy, and the enemy close to it
		var nrm: Vector3 = w["n"]
		if signf((enemy_at - wc).dot(nrm)) == signf((leader.position - wc).dot(nrm)):
			continue
		if wc.distance_to(enemy_at) > 16.0:
			continue
		bd = d
		best = w
	if best.is_empty():
		return
	best["clear_after"] = true
	stack_door = best
	stack_t = 0.0
	G.say("Squad %d: heavy contact, breaching a wall" % id, team)


func bounding() -> bool:
	return contact and alive().size() >= 4


## Where member c should stand right now (vessel space), or INF to let it decide.
func slot_for(c: Node) -> Vector3:
	if leader == null or c == leader:
		return Vector3.INF
	var team_ := alive()
	var i := team_.find(c)
	if i < 0:
		return Vector3.INF
	if not stack_door.is_empty():
		return _stack_slot(c, i)
	if not clear.is_empty():
		return _clear_slot(c, i)
	if not split.is_empty() and c.fireteam == 1:
		return _slot_at(split["pos"], i / 2, heading)
	if order.get("type", "") == "hold" and order.has("pos"):
		var pos: Vector3 = order["pos"]
		if leader.vessel != vessel:
			return Vector3.INF
		return _slot_at(pos, i, heading)
	return _slot_at(leader.position, i, heading)


func _slot_at(center: Vector3, i: int, face: Vector3) -> Vector3:
	var w: Vector2 = WEDGE[i % WEDGE.size()]
	if formation == "file":
		w = Vector2(0.35 * (1 if i % 2 == 0 else -1), 1.4 * (i + 1))
	elif formation == "line":
		w = Vector2(1.6 * (int(i / 2) + 1) * (1 if i % 2 == 0 else -1), 0.6)
	w *= spacing
	var right := face.cross(Vector3.UP).normalized()
	var want := center + right * w.x - face * w.y
	var snapped_: Vector3 = vessel.snap_local(want)
	if snapped_.distance_to(want) > 0.9:
		# no room for the wedge here (a corridor): fall into single file behind the leader
		want = center - face * (1.3 * (i + 1))
		snapped_ = vessel.snap_local(want)
	return snapped_


var _stack_cache: Dictionary = {}
var _stack_frame := -1


## Stack slots along the wall on both sides of the doorway, on the squad's side of the door,
## worked out from the door's own axes so a leader standing in the doorway can't collapse them.
func _stack_slot(c: Node, _i: int) -> Vector3:
	var f := Engine.get_physics_frames()
	if f != _stack_frame or not _stack_cache.has(c):
		_stack_frame = f
		_stack_cache = _stack_slots()
	return _stack_cache.get(c, Vector3.INF)


func _stack_slots() -> Dictionary:
	var out := {}
	var dc: Vector3 = stack_door["center"]
	var n: Vector3 = stack_door.get("n", Vector3.FORWARD)
	var wa: Vector3 = stack_door.get("wa", Vector3.RIGHT)
	var half: float = stack_door.get("half", 0.8)
	var team_ := alive()
	# which side of the door are we on: the squad's centre of mass decides (the leader may be in the doorway)
	var com := Vector3.ZERO
	for m in team_:
		com += m.position
	com /= maxf(1.0, float(team_.size()))
	var s: float = (com - dc).dot(n)
	if absf(s) < 0.3 and leader != null:
		s = (leader.position - dc).dot(n)
	var near: Vector3 = n * (1.0 if s >= 0.0 else -1.0)
	var floor_: Vector3 = dc - Vector3(0, 1.3, 0)
	var taken: Array = []
	if leader != null and leader.vessel == vessel:
		taken.append(leader.position)
	var br: Node = stack_breacher()
	if br != null and br != leader:
		var bp: Vector3 = vessel.snap_local(floor_ + near * 0.75)
		out[br] = bp
		taken.append(bp)
	var k := 0
	for m in team_:
		if m == leader or m == br:
			continue
		var side: float = 1.0 if k % 2 == 0 else -1.0
		var rank: int = k / 2
		var p := Vector3.INF
		# along the wall beside the frame; further out down the wall, then back from it, until clear of the others
		for tries in 6:
			var want: Vector3 = floor_ + near * (0.55 + 0.45 * rank + 0.7 * tries) \
				+ wa * side * (half + 0.55 + 0.8 * rank)
			var sp: Vector3 = vessel.snap_local(want)
			var ok := true
			for q in taken:
				if Vector2(sp.x - q.x, sp.z - q.z).length() < 0.75:
					ok = false
					break
			if ok:
				p = sp
				break
		if p == Vector3.INF:
			p = vessel.snap_local(floor_ + near * (1.5 + 0.8 * k))
		out[m] = p
		taken.append(p)
		k += 1
	return out


## Bounding: the next cover toward the objective for a member of the moving fireteam.
func bound_point(c: Node) -> Vector3:
	var goal := enemy_at if enemy_at != Vector3.INF else objective
	if goal == Vector3.INF:
		return Vector3.INF
	var to: Vector3 = goal - c.position
	to.y = 0.0
	var step: Vector3 = c.position + to.normalized() * min(8.0, max(0.0, to.length() - 6.0))
	var best: Array = []
	var bd := 7.0
	for cp in vessel.cover:
		var p: Vector3 = cp[0]
		if abs(p.y - c.position.y) > 1.5:
			continue
		var d := p.distance_to(step)
		var facing: Vector3 = (goal - p)
		facing.y = 0.0
		if d < bd and facing.normalized().dot(cp[2]) > 0.3 and not _claimed(p, c):
			bd = d
			best = cp
	if not best.is_empty():
		return best[0]
	# no free cover: an open spot near the step, clear of the others
	var a: float = (members.find(c) % 8) * 0.785
	return vessel.snap_local(step + Vector3(cos(a), 0, sin(a)) * 1.2)


## Someone else in the squad is in, or heading for, that spot.
func _claimed(p: Vector3, me: Node) -> bool:
	for m in members:
		if m == me or not is_instance_valid(m) or m.state != "alive":
			continue
		if m.position.distance_to(p) < 0.9 or (m.goal != Vector3.INF and m.goal.distance_to(p) < 0.9):
			return true
	return false



# ------------------------------------------------------------------ breach and clear

## The door is down: the squad flows into the room beyond and takes the corners.
func _start_clear(d: Dictionary) -> void:
	var dc: Vector3 = d["center"]
	var nrm: Vector3 = d["n"]
	var side := 1.0 if (dc - leader.position).dot(nrm) >= 0.0 else -1.0
	var inside: Vector3 = vessel.snap_local(dc + nrm * side * 3.5 - Vector3(0, 1.3, 0))
	clear = {"door": dc, "center": inside, "dir": nrm * side, "until": G.time + 14.0, "go_at": G.time}
	# against a hostile room: someone bangs it first (an EMP if anyone has one, else a frag),
	# and nobody goes in until it's gone off
	if not G.enemies(team, vessel.team):
		return
	var thrower: Node = null
	var use_emp := false
	var bd := 9.0
	for m in alive():
		if m == leader_player():
			continue
		var has_emp: bool = not m.emps.is_empty()
		if not has_emp and m.grenades.is_empty():
			continue
		var dd: float = m.position.distance_to(dc)
		if dd < bd or (has_emp and not use_emp and dd < 9.0):
			bd = dd
			thrower = m
			use_emp = has_emp
	if thrower:
		thrower._throw_grenade(vessel.to_global(inside + Vector3(0, 0.3, 0) + nrm * side * 1.5), use_emp)
		G.say("%s: %s out!" % [thrower.display, "EMP" if use_emp else "frag"], team)
		clear["go_at"] = G.time + (2.1 if use_emp else 2.9)
		clear["until"] += 3.0


## Entry order: the first pair goes in and peels left and right along the entry wall,
## the next pair pushes to the far corners, the rest hold the doorway.
func _clear_slot(_c: Node, i: int) -> Vector3:
	var fwd: Vector3 = clear["dir"]
	var right: Vector3 = fwd.cross(Vector3.UP).normalized()
	var door: Vector3 = clear["door"] - Vector3(0, 1.3, 0)
	var s := 1.0 if i % 2 == 0 else -1.0
	var want: Vector3
	if G.time < float(clear.get("go_at", 0.0)):
		# wait for the bang beside the doorway, off the line of the opening
		return vessel.snap_local(door - fwd * (0.9 + 0.6 * (i / 2)) + right * s * 1.6)
	match i / 2:
		0:
			want = door + fwd * 1.2 + right * s * 2.2           # along the entry wall
		1:
			want = door + fwd * 4.5 + right * s * 2.4           # far corners
		2:
			want = door + fwd * 2.8 + right * s * 0.9           # center
		_:
			want = door - fwd * 1.4 + right * s * 1.2           # outside, covering the doorway
	return vessel.snap_local(want)


## Who opens the stacked door: for an ordinary door the nearest heavy/rifleman kicks it;
## for blast and security doors, whoever carries a breaching charge. Chosen once per door.
func stack_breacher() -> Node:
	if stack_door.is_empty() or stack_door.get("charged", false):
		return null
	var cur = stack_door.get("breacher")
	if cur != null and is_instance_valid(cur) and cur.state == "alive" and cur != leader_player() \
			and (stack_door.get("kind", "door") == "door" or not cur.charges.is_empty() \
				or (cur.role == "grenadier" and cur.breach_ammo > 0)):
		return cur                                        # (still able to open it: else choose again)
	var best: Node = null
	var bs := -1
	for m in alive():
		if m == leader_player():
			continue
		var sc := 0
		if stack_door.get("kind", "door") == "door":
			sc = {"heavy": 4, "breacher": 3, "rifleman": 2}.get(m.role, 1)
		elif m.role == "grenadier" and m.breach_ammo > 0:
			sc = 4                                        # a breaching round from range
		elif not m.charges.is_empty():
			sc = 5 if m.role == "breacher" else 3
		if sc > bs:
			bs = sc
			best = m
	if stack_door.get("kind", "door") != "door" and best != null and best.charges.is_empty() \
			and not (best.role == "grenadier" and best.breach_ammo > 0):
		best = null
	stack_door["breacher"] = best
	return best


## The leader if a person is playing them (they don't take AI jobs).
func leader_player() -> Node:
	if leader and is_instance_valid(leader) and (leader == G.possessed or leader.owner_peer != 0):
		return leader
	return null


## A positional order is in force (the AI shouldn't wander off to find cover).
func commanded() -> bool:
	return spacing < 1.0 or not order.is_empty() or not split.is_empty() or not clear.is_empty() or not stack_door.is_empty()
