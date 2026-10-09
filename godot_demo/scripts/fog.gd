extends Node
## Fog of war and radar. What a side can see comes from its own ships, stations, fighters and
## craft, and on a world from its troops, vehicles and outposts:
##   sensors  everything inside is shown normally
##   radar    (twice the sensor range for ships and stations; vehicles, outposts and landed
##            ships have a ground radar ring) an unknown contact: a grey blip on the minimap
##            and an "UNKNOWN CONTACT" marker, nothing more
##   beyond   hidden
## Stations and ground installations, once seen, stay on the map as they were last seen
## (ghost_of): their side, state and strength update only while someone's looking.
## Inside a ship, enemy crew show only while one of your people aboard has a line of sight
## to them (or it's your own vessel, whose internal sensors see everyone); when they drop out
## of sight a "?" marks where they were for a few seconds.
## The AI sides are fogged the same way for their decisions (sees): the rival commander, the
## pirates and the sandbox AI only go after what their own sensors and radar have found.
## Off with G.settings["fog"] = false.

const SENSOR := {"SMALL": 2400.0, "MEDIUM": 3000.0, "LARGE": 3800.0, "XL": 4200.0}
const STATION_SENSOR := 4200.0
const RADAR_MULT := 2.0
const GROUND_SHIP := 700.0         # down on a world the horizon is close
const MARK_LIFE := 6.0             # seconds a "last seen here" marker stays

var state := {}                    # node -> "vis" / "radar" / "" (hidden), for the player's side
var known := {}                    # stations / installations the player has seen at least once
var ghost := {}                    # known node -> {team, hull, max, shields, destroyed, modules, t}: as last seen
var eyes: Array = []               # the player's: [pos, sensor, radar]
var team_state := {}               # AI team -> {node: "vis" / "radar"}
var team_known := {}               # AI team -> {station / installation: true}
var _seen_in := {}                 # enemy character aboard a vessel -> seen last pass
var _marks: Array = []             # [Label3D, until]
var _t := 0.0
var _ai_t := 0.0


func enabled() -> bool:
	return bool(G.settings.get("fog", true))


func state_of(n: Node) -> String:
	if not enabled() or n == null:
		return "vis"
	if n.get("team") == G.player_team:
		return "vis"
	return state.get(n, "vis")


## Whether side `team` knows about `n` (a vessel, vehicle, craft or installation): in its
## sensors or on its radar now, or (stations, installations) seen before.
func sees(team: int, n: Node) -> bool:
	if not enabled() or n == null or not is_instance_valid(n):
		return true
	var nt = n.get("team")
	if nt == null or int(nt) == team:
		return true
	if team == G.player_team:
		return state_of(n) != "" or known.has(n)
	if not team_state.has(team):
		return true                                  # (not looked yet: don't blind it on the first frame)
	return (team_state[team] as Dictionary).get(n, "") != "" or (team_known.get(team, {}) as Dictionary).has(n)


## How a known station or installation looked when the player last saw it ({} while in sight).
func ghost_of(n: Node) -> Dictionary:
	if not enabled() or n == null or state.get(n, "vis") == "vis":
		return {}
	return ghost.get(n, {})


func _process(dt: float) -> void:
	_tick_marks()
	_t -= dt
	_ai_t -= dt
	if _t > 0.0:
		return
	_t = 0.25
	var me: int = G.player_team
	var m: Node = G.match_node
	if m == null:
		return
	if not enabled():
		if not state.is_empty() or not _seen_in.is_empty():
			_reveal_all()
		team_state.clear()
		return
	var surf: bool = m.get("on_surface") == true
	var boarded := {}
	eyes = _eyes_for(me, surf, boarded)
	# vessels
	for v in G.vessels:
		if not is_instance_valid(v) or v.team == me:
			continue
		var st: String = "vis" if boarded.has(v) else _look(eyes, v.global_position)
		if st == "vis" and v.kind == "station":
			known[v] = true
		_remember(v, st)
		state[v] = st
		var show: bool = st == "vis" or known.has(v)
		if v.visible != show:
			v.visible = show
	for list in [G.fighters, G.pods, G.missiles, G.vehicles]:
		for n in list:
			if not is_instance_valid(n) or n.get("team") == me:
				continue
			var st2 := _look(eyes, n.global_position)
			state[n] = st2
			var sh2: bool = st2 == "vis"
			if n.visible != sh2:
				n.visible = sh2
	if m.get("outposts") != null:
		for o in m.outposts:
			if not is_instance_valid(o) or o.team == me:
				continue
			var st3 := _look(eyes, o.global_position)
			if st3 == "vis":
				known[o] = true
			_remember(o, st3)
			state[o] = st3
			var sh3: bool = st3 == "vis" or known.has(o)
			if o.visible != sh3:
				o.visible = sh3
	# salvage caches: hidden until seen, then marked
	if m.get("caches") != null:
		for cache in m.caches:
			if not is_instance_valid(cache):
				continue
			if _look(eyes, cache.global_position) == "vis":
				known[cache] = true
			var sh4: bool = known.has(cache)
			if cache.visible != sh4:
				cache.visible = sh4
	# people: on the open ground by our eyes (radar shows them as contacts); aboard a vessel only
	# while one of ours aboard can see them (our own vessels see everyone inside)
	for c in G.characters:
		if not is_instance_valid(c) or c.team == me or c.vessel == null:
			continue
		var hide := false
		if c.vessel.get("kind") == "ground":
			var stc := _look(eyes, c.global_position)
			state[c] = stc
			hide = stc != "vis"
		elif G.enemies(me, c.team) and c.vessel.team != me:
			var seen: bool = boarded.has(c.vessel) and _sighted(c, me)
			if not seen and _seen_in.get(c, false) and c.state != "dead":
				_mark(c)
			_seen_in[c] = seen
			hide = not seen
		c.fog_hidden = hide
	if _ai_t <= 0.0:
		_ai_t = 0.5
		_ai_fog(me, surf)


## [pos, sensor, radar] for every eye side `team` has. Fills `boarded` with the vessels its
## people are aboard (they see the whole ship from inside).
func _eyes_for(team: int, surf: bool, boarded: Dictionary = {}) -> Array:
	var out: Array = []
	for c in G.characters:
		if is_instance_valid(c) and c.team == team and c.state == "alive" and c.vessel != null:
			boarded[c.vessel] = true
			if c.vessel.get("kind") == "ground":
				out.append([c.global_position, 110.0, 0.0])
	for v in G.vessels:
		if not is_instance_valid(v) or v.destroyed or v.team != team or v.get("kind") == "ground":
			continue
		if v.kind == "station":
			out.append([v.global_position, STATION_SENSOR, STATION_SENSOR * RADAR_MULT])
		else:
			var sz: String = v.size_class(String(v.cls)) if v.has_method("size_class") else "SMALL"
			var r: float = GROUND_SHIP if surf else float(SENSOR.get(sz, 2400.0))
			out.append([v.global_position, r, r * RADAR_MULT])
	for f in G.fighters:
		if is_instance_valid(f) and f.team == team:
			out.append([f.global_position, 1500.0, 0.0])
	for p in G.pods:
		if is_instance_valid(p) and p.get("team") == team:
			out.append([p.global_position, 800.0, 0.0])
	for veh in G.vehicles:
		if is_instance_valid(veh) and veh.team == team:
			out.append([veh.global_position, 260.0, 650.0])          # (a vehicle's ground radar)
	var m: Node = G.match_node
	if m and m.get("outposts") != null:
		for o in m.outposts:
			if is_instance_valid(o) and not o.destroyed and o.team == team:
				out.append([o.global_position, 380.0, 950.0])        # (an outpost's radar mast)
	return out


func _look(ey: Array, p: Vector3) -> String:
	var best := ""
	for e in ey:
		var d: float = (e[0] as Vector3).distance_to(p)
		if d <= float(e[1]):
			return "vis"
		if d <= float(e[2]):
			best = "radar"
	return best


## While a known station or installation is in sight, keep a copy of how it looks.
func _remember(n: Node, st: String) -> void:
	if st != "vis" or not known.has(n):
		return
	var g := {"team": int(n.get("team")), "destroyed": n.get("destroyed") == true, "t": G.time}
	if n.get("hull") != null:
		g["hull"] = float(n.get("hull"))
		g["max"] = float(n.get("max_hull")) if n.get("max_hull") != null else float(n.get("hull"))
	if n.get("hp") != null:
		g["hull"] = float(n.get("hp"))
		g["max"] = float(n.get("max_hp")) if n.get("max_hp") != null else float(n.get("hp"))
	if n.get("shields") != null:
		g["shields"] = float(n.get("shields"))
		g["max_shields"] = float(n.get("max_shields"))
	if n.get("modules") != null and n.has_method("modules_online"):
		g["modules_online"] = int(n.modules_online())
		g["modules"] = (n.get("modules") as Dictionary).size()
	ghost[n] = g


## One of side `me`'s people aboard `c`'s vessel has a line of sight to `c` (nearest few, 45 m).
func _sighted(c: Node, me: int) -> bool:
	var v: Node = c.vessel
	var near: Array = []
	for o in v.near_occupants(c.position, 45.0):
		if is_instance_valid(o) and o.team == me and o.state == "alive" and o.vessel == v:
			var d: float = o.position.distance_to(c.position)
			if d < 45.0:
				near.append([d, o])
	if near.is_empty():
		return false
	near.sort_custom(func(a, b): return a[0] < b[0])
	for k in mini(4, near.size()):
		var o: Node = near[k][1]
		if float(near[k][0]) < 2.0:
			return true                                   # (close enough to hear and touch)
		if G.ray(o.eye(), c.chest(), [o.get_rid(), c.get_rid()], G.LAYER_WORLD | G.LAYER_DOOR).is_empty():
			return true
	return false


## A "?" where an enemy aboard was last seen, fading out over a few seconds.
func _mark(c: Node) -> void:
	var l := Label3D.new()
	l.text = "?"
	l.font_size = 72
	l.pixel_size = 0.01
	l.outline_size = 10
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.modulate = Color(1.0, 0.45, 0.35)
	c.vessel.add_child(l)
	l.position = c.position + Vector3.UP * 1.9
	_marks.append([l, G.time + MARK_LIFE])
	G.stat("fog_last_seen_marks")


func _tick_marks() -> void:
	for i in range(_marks.size() - 1, -1, -1):
		var mk: Array = _marks[i]
		var l: Label3D = mk[0]
		if not is_instance_valid(l) or G.time > float(mk[1]):
			if is_instance_valid(l):
				l.queue_free()
			_marks.remove_at(i)
		else:
			l.modulate.a = clampf((float(mk[1]) - G.time) / 2.0, 0.0, 1.0)


## The same sensor pass for every other side, for its AI's decisions only (nothing is hidden).
func _ai_fog(me: int, surf: bool) -> void:
	var teams := {}
	for v in G.vessels:
		if is_instance_valid(v) and v.team != me and v.get("kind") != "ground":
			teams[int(v.team)] = true
	for veh in G.vehicles:
		if is_instance_valid(veh) and veh.team != me:
			teams[int(veh.team)] = true
	for tm in team_state.keys():
		if not teams.has(tm):
			team_state.erase(tm)
	var m: Node = G.match_node
	for tm in teams:
		var ey := _eyes_for(tm, surf)
		var st := {}
		var kn: Dictionary = team_known.get(tm, {})
		for v in G.vessels:
			if is_instance_valid(v) and v.team != tm:
				var s := _look(ey, v.global_position)
				if s != "":
					st[v] = s
				if s == "vis" and v.kind == "station":
					kn[v] = true
		for list in [G.vehicles, G.fighters, G.pods]:
			for n in list:
				if is_instance_valid(n) and n.get("team") != tm:
					var s2 := _look(ey, n.global_position)
					if s2 != "":
						st[n] = s2
		if m and m.get("outposts") != null:
			for o in m.outposts:
				if is_instance_valid(o) and o.team != tm:
					var s3 := _look(ey, o.global_position)
					if s3 != "":
						st[o] = s3
					if s3 == "vis":
						kn[o] = true
		team_state[tm] = st
		team_known[tm] = kn


func _reveal_all() -> void:
	for n in state:
		if is_instance_valid(n):
			n.visible = true
			if n.get("fog_hidden") != null:
				n.fog_hidden = false
	for c in G.characters:
		if is_instance_valid(c):
			c.fog_hidden = false
	state.clear()
	_seen_in.clear()
