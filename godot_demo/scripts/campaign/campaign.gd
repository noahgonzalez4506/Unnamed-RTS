extends RefCounted
## The single-player campaign's state: everything that outlives one visit to a system.
## Saved to user://campaign.json as plain JSON (Vector3s as [x, y, z]).
##
##   The galaxy is regenerated from its seed; only what changed is stored: the player's
##   fleet, stations, credits and stores, standings, market stock, jobs, and which NPC
##   stations were taken or destroyed.

const GALAXY := preload("res://scripts/campaign/galaxy.gd")
const SAVE_PATH := "user://campaign.json"
const CARGO_CAP := {"SMALL_FRIGATE": 60, "SMALL_SUPPORT": 260, "SMALL_DROP_FRIGATE": 40, "MEDIUM": 140, "LARGE": 220, "XL": 320}

var seed := 0
var galaxy := {}
var current := 0                    # the system we're in
var company := "Free Company"
var credits := 2500
var day := 0.0                      # campaign clock (seconds played)
var fleet: Array = []               # {id, cls, name, variant, system, pos [x,z], yaw, hull, troops, supplies, cargo {}}
var miners: Array = []              # {id, system, station}
var stations: Array = []            # the player's own: {key, system, cls, name, pos [x,z], ore, supplies, reserve}
var stores := {"alloys": 1200.0, "circuitry": 300.0, "cores": 12.0, "fuel": 200.0, "ore": 0.0, "tritium": 120.0}
var standing := {2: -10.0, 5: 30.0, 6: 20.0, 7: 5.0}
var markets := {}                   # station key -> {good: stock}
var offers := {}                    # station key -> {"day": made at, "jobs": [...]}
var jobs: Array = []                # accepted jobs
var world := {}                     # NPC station key -> {"team": t, "destroyed": bool}
var visited: Array = []
var arrive_from := -1               # the system we jumped in from (-1: not by jump)
var surface := {}                   # down on a world: {"planet": i, "site": j}; empty in space
var research := {}                  # the player's unlocked techs {id: true} (G.research[1] is this dict)
var researching: Array = []         # the tech in progress: [id, seconds left], or []
var _next_id := 1


static func new_game(seed_: int, company_: String) -> RefCounted:
	var c = load("res://scripts/campaign/campaign.gd").new()
	c.seed = seed_
	c.company = company_ if company_.strip_edges() != "" else "Free Company"
	c.galaxy = GALAXY.generate(seed_)
	c.current = int(c.galaxy["home"])
	c.visited = [c.current]
	var L: Dictionary = GALAXY.sector(c.galaxy, c.current)
	var hp: Vector3 = L["home_spot"]
	c.stations.append({"key": "player_home", "system": c.current, "cls": "STATION_STARTER", "name": "%s Station" % c.company.get_slice(" ", 0),
		"pos": [hp.x, hp.z], "supplies": 200.0, "reserve": 8})
	var out: Vector3 = hp + (Vector3.ZERO - hp).normalized() * 420.0 + Vector3(0, 0, 160)
	c.fleet.append({"id": c.new_id(), "cls": "SMALL_FRIGATE", "name": "%s Venture" % c.company.get_slice(" ", 0), "variant": 1,
		"system": c.current, "pos": [out.x, out.z], "yaw": 0.0, "hull": 1.0, "troops": 12, "supplies": 120.0, "cargo": {}})
	for i in 2:
		c.miners.append({"id": c.new_id(), "system": c.current, "station": "player_home"})
	return c


func new_id() -> int:
	_next_id += 1
	return _next_id


# ------------------------------------------------------------------ save / load

static func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save() -> bool:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict(), "\t"))
	return true


static func load_game() -> RefCounted:
	if not FileAccess.file_exists(SAVE_PATH):
		return null
	var txt := FileAccess.get_file_as_string(SAVE_PATH)
	var d = JSON.parse_string(txt)
	if typeof(d) != TYPE_DICTIONARY:
		return null
	var c = load("res://scripts/campaign/campaign.gd").new()
	c.from_dict(d)
	return c


func to_dict() -> Dictionary:
	# mini dropships out (and followers on their way) are saved as docked, with their loads aboard
	var fl: Array = fleet.duplicate(true)
	for e in fl:
		if int(e.get("minidrops_following", 0)) > 0:
			e["minidrops"] = int(e.get("minidrops", 0)) + int(e["minidrops_following"])
			e.erase("minidrops_following")
	for p in G.pods:
		if is_instance_valid(p) and p.get("_camp") == self and not p.get("_back"):
			for e in fl:
				if int(e["id"]) == int(p.get("_fleet_id")):
					p.owed_to(e)
	return {"version": 1, "seed": seed, "current": current, "company": company, "credits": credits, "day": day,
		"fleet": fl, "miners": miners, "stations": stations, "stores": stores, "standing": _int_keys_out(standing),
		"markets": markets, "offers": offers, "jobs": jobs, "world": world, "visited": visited,
		"arrive_from": arrive_from, "next_id": _next_id, "surface": surface,
		"research": research, "researching": researching}


func from_dict(d: Dictionary) -> void:
	seed = int(d["seed"])
	galaxy = GALAXY.generate(seed)
	current = int(d["current"])
	company = d.get("company", "Free Company")
	credits = int(d.get("credits", 0))
	day = float(d.get("day", 0.0))
	fleet = d.get("fleet", [])
	miners = d.get("miners", [])
	stations = d.get("stations", [])
	stores = d.get("stores", {})
	if not stores.has("tritium"):
		stores["tritium"] = 120.0
	standing = {}
	for k in d.get("standing", {}):
		standing[int(k)] = float(d["standing"][k])
	markets = d.get("markets", {})
	offers = d.get("offers", {})
	jobs = d.get("jobs", [])
	world = d.get("world", {})
	visited = d.get("visited", [])
	arrive_from = int(d.get("arrive_from", -1))
	surface = d.get("surface", {})
	research = d.get("research", {})
	researching = d.get("researching", [])
	if researching.size() == 2:
		researching = [String(researching[0]), float(researching[1])]
	else:
		researching = []
	_next_id = int(d.get("next_id", 100))
	# JSON numbers come back as floats
	for e in fleet:
		e["id"] = int(e["id"])
		e["system"] = int(e["system"])
		e["variant"] = int(e.get("variant", 1))
		e["troops"] = int(e.get("troops", 0))
	for m in miners:
		m["id"] = int(m["id"])
		m["system"] = int(m["system"])
	for s in stations:
		s["system"] = int(s["system"])
	for i in visited.size():
		visited[i] = int(visited[i])


func _int_keys_out(d: Dictionary) -> Dictionary:
	var o := {}
	for k in d:
		o[str(k)] = d[k]
	return o


# ------------------------------------------------------------------ the map

func system() -> Dictionary:
	return GALAXY.system_of(galaxy, current)


func system_of(id: int) -> Dictionary:
	return GALAXY.system_of(galaxy, id)


func neighbours() -> Array:
	return system()["lanes"]


## The NPC stations of a system as they stand now (taken, destroyed or as generated).
func stations_in(id: int) -> Array:
	var out: Array = []
	for st in system_of(id)["stations"]:
		var w: Dictionary = world.get(st["key"], {})
		if w.get("destroyed", false):
			continue
		var d: Dictionary = st.duplicate()
		d["team"] = int(w.get("team", st["team"]))
		out.append(d)
	return out


# ------------------------------------------------------------------ markets

func _station_info(key: String) -> Dictionary:
	return GALAXY.station_def(galaxy, key)


func has_market(key: String) -> bool:
	var st := _station_info(key)
	return not st.is_empty() and st.get("economy", "") != ""


## Stock of each good at a station; generated on first visit, drifting back toward normal.
func market(key: String) -> Dictionary:
	if not markets.has(key):
		var st := _station_info(key)
		var e: Dictionary = GALAXY.ECONOMIES.get(st.get("economy", "hub"), GALAXY.ECONOMIES["hub"])
		var m := {}
		for g in GALAXY.GOODS:
			m[g] = 160.0 if g in e["make"] else (20.0 if g in e["need"] else 70.0)
		markets[key] = m
	return markets[key]


## The price per unit: what the station sells at (buying=true) or pays (buying=false).
func price(key: String, good: String, buying: bool) -> int:
	var st := _station_info(key)
	var e: Dictionary = GALAXY.ECONOMIES.get(st.get("economy", "hub"), GALAXY.ECONOMIES["hub"])
	var base: float = GALAXY.GOODS[good]
	var mult := 1.0
	if good in e["make"]:
		mult = 0.62
	elif good in e["need"]:
		mult = 1.45
	var stock: float = market(key)[good]
	mult *= clampf(1.35 - stock / 300.0, 0.7, 1.35)          # scarce goods cost more
	var h: float = float(hash(key + good) % 21 - 10) / 100.0  # each station's own quirks, +-10%
	mult *= 1.0 + h
	var p: float = base * mult
	return maxi(1, int(round(p * (1.08 if buying else 0.92))))


func cargo_cap(e: Dictionary) -> int:
	return int(CARGO_CAP.get(e["cls"], 60))


func cargo_used(e: Dictionary) -> int:
	var n := 0
	for g in e.get("cargo", {}):
		n += int(e["cargo"][g])
	return n


## Buy n of a good into fleet entry e. Returns a message.
func buy(key: String, e: Dictionary, good: String, n: int) -> String:
	var m := market(key)
	n = mini(n, int(m[good]))
	n = mini(n, cargo_cap(e) - cargo_used(e))
	var p := price(key, good, true)
	n = mini(n, int(credits / max(1, p)))
	if n <= 0:
		return "Can't buy %s: no room, no stock or no credits" % good
	credits -= n * p
	m[good] -= n
	var c: Dictionary = e.get("cargo", {})
	c[good] = int(c.get(good, 0)) + n
	e["cargo"] = c
	G.stat("bought", n)
	return "Bought %d %s for %d cr" % [n, good, n * p]


func sell(key: String, e: Dictionary, good: String, n: int) -> String:
	var c: Dictionary = e.get("cargo", {})
	n = mini(n, int(c.get(good, 0)))
	if n <= 0:
		return "No %s aboard" % good
	var p := price(key, good, false)
	credits += n * p
	market(key)[good] += n
	c[good] = int(c[good]) - n
	if c[good] <= 0:
		c.erase(good)
	G.stat("sold", n)
	return "Sold %d %s for %d cr" % [n, good, n * p]     # (deliveries are handed over when SERVICES opens)


func tick_markets(dt: float) -> void:
	for key in markets:
		var st := _station_info(key)
		var e: Dictionary = GALAXY.ECONOMIES.get(st.get("economy", "hub"), GALAXY.ECONOMIES["hub"])
		for g in markets[key]:
			var target := 160.0 if g in e["make"] else (20.0 if g in e["need"] else 70.0)
			markets[key][g] = move_toward(float(markets[key][g]), target, dt * 0.05)


# ------------------------------------------------------------------ jobs

## The jobs on offer at a station (fresh ones every ten minutes of play).
func offers_at(key: String) -> Array:
	var o: Dictionary = offers.get(key, {})
	if o.is_empty() or day - float(o.get("day", 0.0)) > 600.0:
		o = {"day": day, "jobs": _make_jobs(key)}
		offers[key] = o
	return o["jobs"]


func _make_jobs(key: String) -> Array:
	var st := _station_info(key)
	var r := RandomNumberGenerator.new()
	r.seed = hash(key) + int(day / 600.0) * 7919 + seed
	var out: Array = []
	var team: int = int(st.get("team", 6))
	if team in [3, 4]:
		return out
	var sys_id: int = int(key.get_slice("_", 0))
	var here := system_of(sys_id)
	var near: Array = [sys_id] + here["lanes"]
	for i in 2 + r.randi() % 2:
		var kind: String = ["deliver", "deliver", "bounty", "salvage", "patrol"][r.randi() % 5]
		var job := {"id": new_id(), "kind": kind, "giver": key, "team": team, "system": sys_id}
		match kind:
			"deliver":
				# carry goods somewhere: to another station with a market, a jump or two away
				var dests: Array = []
				for sid in near:
					for d in system_of(sid)["stations"]:
						if d["key"] != key and d["team"] in [5, 6, 7, 2] and d.get("economy", "") != "":
							dests.append(d)
				if dests.is_empty():
					continue
				var d: Dictionary = dests[r.randi() % dests.size()]
				var good: String = GALAXY.GOODS.keys()[r.randi() % GALAXY.GOODS.size()]
				var n: int = [10, 15, 20, 30][r.randi() % 4]
				job["to"] = d["key"]
				job["good"] = good
				job["n"] = n
				job["reward"] = int(n * GALAXY.GOODS[good] * 0.6 + 300 + (0 if int(d["key"].get_slice("_", 0)) == sys_id else 400))
				job["title"] = "Deliver %d %s to %s" % [n, good, d["name"]]
			"bounty":
				var sid: int = near[r.randi() % near.size()]
				job["target_system"] = sid
				job["target_name"] = "%s %s" % [["Captain", "Butcher", "Old", "Mad"][r.randi() % 4], ["Varn", "Sully", "Kade", "Moss", "Rook"][r.randi() % 5]]
				job["cls"] = "SMALL_FRIGATE" if r.randf() < 0.7 else "MEDIUM"
				job["reward"] = 1400 if job["cls"] == "SMALL_FRIGATE" else 2600
				job["title"] = "Bounty: destroy or take %s's %s in %s" % [job["target_name"], "frigate" if job["cls"] == "SMALL_FRIGATE" else "raider", system_of(sid)["name"]]
			"salvage":
				var sid2: int = near[r.randi() % near.size()]
				job["target_system"] = sid2
				job["reward"] = 2200
				job["title"] = "Salvage: board and take the derelict drifting in %s" % system_of(sid2)["name"]
			"patrol":
				var sid3: int = near[r.randi() % near.size()]
				job["target_system"] = sid3
				job["kills"] = 2
				job["got"] = 0
				job["reward"] = 1100
				job["title"] = "Clear pirates: destroy %d pirate ships in %s" % [2, system_of(sid3)["name"]]
		out.append(job)
	return out


func accept(job: Dictionary) -> String:
	for j in jobs:
		if j["id"] == job["id"]:
			return "Already taken"
	if jobs.size() >= 6:
		return "Too many jobs: finish or drop one first"
	jobs.append(job)
	var o: Dictionary = offers.get(job["giver"], {})
	if o.has("jobs"):
		o["jobs"] = o["jobs"].filter(func(x): return x["id"] != job["id"])
	G.stat("jobs_taken")
	# the target is right here: it shows up now, not on the next visit
	if int(job.get("target_system", -1)) == current and G.match_node and G.match_node.get("campaign_mode"):
		load("res://scripts/campaign/sector.gd").spawn_job(G.match_node, job, true)
	return "Job taken: %s" % job["title"]


func drop_job(job: Dictionary) -> void:
	jobs.erase(job)
	G.change_standing(int(job["team"]), -3.0)


func _pay(job: Dictionary) -> String:
	credits += int(job["reward"])
	jobs.erase(job)
	G.change_standing(int(job["team"]), 6.0)
	G.stat("jobs_done")
	var msg := "JOB DONE: %s  (+%d cr)" % [job["title"], job["reward"]]
	G.say(msg, 1)
	return msg


## Hand over the goods for delivery jobs bound for this station, from fleet entry e.
func deliver(key: String, e: Dictionary) -> String:
	var out := ""
	for j in jobs.duplicate():
		if j["kind"] != "deliver" or j["to"] != key:
			continue
		var c: Dictionary = e.get("cargo", {})
		if int(c.get(j["good"], 0)) >= int(j["n"]):
			c[j["good"]] = int(c[j["good"]]) - int(j["n"])
			if c[j["good"]] <= 0:
				c.erase(j["good"])
			out += "\n" + _pay(j)
	return out


## Something happened in the world that might finish a job.
func on_vessel_gone(v: Node, by_team: int) -> void:
	for j in jobs.duplicate():
		if j["kind"] == "bounty" and v.get_meta("job", -1) == j["id"] and by_team == 1:
			_pay(j)
		elif j["kind"] == "salvage" and v.get_meta("job", -1) == j["id"] and by_team == 1:
			_pay(j)
		elif j["kind"] == "patrol" and v.team == 3 and v.kind == "ship" and current == int(j["target_system"]):
			j["got"] = int(j.get("got", 0)) + 1
			if j["got"] >= int(j["kills"]):
				_pay(j)


# ------------------------------------------------------------------ the fleet in the scene

func fleet_entry(id: int) -> Dictionary:
	for e in fleet:
		if e["id"] == id:
			return e
	return {}


## Write the scene's player ships and stations back into the records (before a save or a jump).
func snapshot() -> void:
	if G.match_node == null:
		return
	if not surface.is_empty() and G.match_node.has_method("save_ground_units"):
		G.match_node.save_ground_units()
	for v in G.vessels:
		if not is_instance_valid(v):
			continue
		var id: int = int(v.get_meta("fleet_id", -1))
		if v.kind == "ship" and id >= 0:
			var e := fleet_entry(id)
			if e.is_empty():
				continue
			if v.destroyed or v.team != 1:
				fleet.erase(e)                       # lost (or taken)
				continue
			if surface.is_empty():
				e["pos"] = [v.global_position.x, v.global_position.z]
				e["yaw"] = v.rotation.y
			e["hull"] = clampf(v.hull / maxf(1.0, v.max_hull), 0.05, 1.0)
			e["troops"] = v.troops
			# the infection aboard comes along wherever the ship goes
			var inf_n := 0
			for o in v.occupants:
				if is_instance_valid(o) and o.team == 4 and o.state == "alive":
					inf_n += 1
			var inf_z: Array = []
			for zi in v.zones.size():
				if v.zones[zi]["infected"]:
					inf_z.append([zi, float(v.zones[zi].get("growth", 0.5))])
			e["infected"] = inf_n
			e["infected_zones"] = inf_z
			e["supplies"] = v.supplies
			e["system"] = current
			e["variant"] = v.variant
			# the hangar: craft parked on the pads, and this carrier's fighters still out flying
			var hangar: Array = []
			for p in v.pads:
				if p["parked"] != null:
					hangar.append(p.get("model", "FIGHTER"))
			for f in G.fighters:
				if is_instance_valid(f) and f.carrier == v:
					hangar.append("FIGHTER")
			e["hangar"] = hangar.slice(0, v.pads.size())
		elif v.kind == "ship" and id < 0 and v.team == 1 and not v.destroyed and v.get_meta("prize", false):
			# a ship we captured: it joins the fleet
			fleet.append({"id": new_id(), "cls": v.cls, "name": v.display_name, "variant": v.variant, "system": current,
				"pos": [v.global_position.x, v.global_position.z], "yaw": v.rotation.y,
				"hull": clampf(v.hull / maxf(1.0, v.max_hull), 0.05, 1.0), "troops": v.troops, "supplies": v.supplies,
				"cargo": {}, "fac": v.faction})
			v.set_meta("fleet_id", fleet[-1]["id"])
		elif v.kind == "ship" and v.has_meta("derelict_rec") and (v.destroyed or v.team != 4):
			# a derelict cleared (or taken): it stays gone
			var dr: PackedStringArray = String(v.get_meta("derelict_rec")).split("/")
			var dl: Array = world.get(dr[0], [])
			if int(dr[1]) < dl.size():
				dl[int(dr[1])]["cleared"] = true
		elif v.kind == "station":
			var key: String = v.get_meta("key", "")
			if key == "":
				continue
			var mine := stations.filter(func(s): return s["key"] == key)
			if not mine.is_empty():
				mine[0]["supplies"] = v.supplies
				mine[0]["reserve"] = v.reserve
				if v.destroyed or v.team != 1:
					stations.erase(mine[0])
					miners = miners.filter(func(mn): return mn.get("station", "") != key)   # (its miners go with it)
			elif v.destroyed or v.team != int(v.get_meta("spawn_team", _station_info(key).get("team", v.team))):
				var rec: Dictionary = world.get(key, {})        # (keep whatever else the site records)
				rec["team"] = v.team
				rec["destroyed"] = v.destroyed
				world[key] = rec
	stores = G.resources.get(1, stores)          # (the same dictionary: everything reads and spends the one store)
	research = G.research.get(1, research)
	researching = (G.researching.get(1, []) as Array).duplicate()


## Jump: the ships go through the gate to system `to`.
func jump(to: int, ship_ids: Array) -> void:
	snapshot()
	for e in fleet:
		if e["id"] in ship_ids:
			e["system"] = to
			e["arrive"] = true
	arrive_from = current
	current = to
	if not visited.has(to):
		visited.append(to)
	save()


## Ships go down to a landing zone on planet `pl`, site `site`.
func land(pl: int, site: int, ship_ids: Array) -> void:
	snapshot()
	for e in fleet:
		if e["id"] in ship_ids:
			e["landed"] = true
			e["at"] = [current, pl, site]
	surface = {"planet": pl, "site": site}
	world["seen_%d_%d_%d" % [current, pl, site]] = true
	save()


## Is this landed ship down at the landing zone we're on now?
func landed_here(e: Dictionary) -> bool:
	if not e.get("landed", false) or surface.is_empty():
		return false
	var at: Array = e.get("at", [current, int(surface["planet"]), int(surface["site"])])
	return int(at[0]) == current and int(at[1]) == int(surface["planet"]) and int(at[2]) == int(surface["site"])


static func units_key(sys: int, pl: int, site: int) -> String:
	return "units_%d_%d_%d" % [sys, pl, site]


## Every place we have something: systems with our ships or stations in orbit, landing
## zones with ships set down or troops and vehicles left on the ground.
##   [{system, planet (-1 in space), site, label, ships, troops, vehicles, here}]
func zones() -> Array:
	var out := {}
	var add := func(sys: int, pl: int, site: int) -> Dictionary:
		var k := "%d/%d/%d" % [sys, pl, site]
		if not out.has(k):
			out[k] = {"system": sys, "planet": pl, "site": site, "ships": 0, "troops": 0, "vehicles": 0, "stations": 0}
		return out[k]
	for e in fleet:
		if e.get("landed", false):
			var at: Array = e.get("at", [int(e["system"]), int(surface.get("planet", 0)), int(surface.get("site", 0))])
			var za: Dictionary = add.call(int(at[0]), int(at[1]), int(at[2]))
			za["ships"] = int(za["ships"]) + 1
		else:
			var zb: Dictionary = add.call(int(e["system"]), -1, -1)
			zb["ships"] = int(zb["ships"]) + 1
	for st in stations:
		var zs: Dictionary = add.call(int(st["system"]), -1, -1)
		zs["stations"] = int(zs["stations"]) + 1
	for k in world:
		if String(k).begins_with("units_"):
			var bits: PackedStringArray = String(k).split("_")
			var rec: Dictionary = world[k]
			var nt: int = (rec.get("troops", []) as Array).size()
			var nv: int = (rec.get("vehicles", []) as Array).size()
			if nt + nv > 0:
				var z: Dictionary = add.call(int(bits[1]), int(bits[2]), int(bits[3]))
				z["troops"] = int(z["troops"]) + nt
				z["vehicles"] = int(z["vehicles"]) + nv
	var res: Array = []
	for k in out:
		var z: Dictionary = out[k]
		var sysd: Dictionary = system_of(int(z["system"]))
		var lab: String = sysd.get("name", "system")
		if int(z["planet"]) >= 0:
			var pls: Array = sysd.get("planets", [])
			if int(z["planet"]) < pls.size():
				var pld: Dictionary = pls[int(z["planet"])]
				var sites: Array = pld.get("sites", [])
				var sname: String = "landing zone %d" % (int(z["site"]) + 1)
				if int(z["site"]) < sites.size():
					sname = String((sites[int(z["site"])] as Dictionary).get("name", sname))
				lab = "%s  ·  %s" % [pld.get("name", "planet"), sname]
		else:
			lab += "  ·  orbit"
		z["label"] = lab
		z["here"] = int(z["system"]) == current and ((int(z["planet"]) < 0 and surface.is_empty()) or
			(not surface.is_empty() and int(z["planet"]) == int(surface["planet"]) and int(z["site"]) == int(surface["site"])))
		res.append(z)
	return res


## Switch the view to another zone (the world reloads there; everything else waits).
func goto_zone(z: Dictionary) -> void:
	snapshot()
	current = int(z["system"])
	surface = {} if int(z["planet"]) < 0 else {"planet": int(z["planet"]), "site": int(z["site"])}
	arrive_from = -1
	if not visited.has(current):
		visited.append(current)
	save()


## Everyone on the ground lifts off, back into orbit by the planet.
func take_off() -> void:
	snapshot()
	var pl: Dictionary = system()["planets"][int(surface["planet"])]
	var out: Vector3 = (Vector3.ZERO - (pl["pos"] as Vector3)).normalized()
	var p0: Vector3 = (pl["pos"] as Vector3) + out * (float(pl["radius"]) + 450.0)
	var k := 0
	for e in fleet:
		if e.get("landed", false) and int(e["system"]) == current and landed_here(e):
			e["landed"] = false
			e.erase("at")
			var p: Vector3 = p0 + out.cross(Vector3.UP) * (k * 200.0 - 200.0)
			e["pos"] = [p.x, p.z]
			k += 1
	surface = {}
	arrive_from = -1
	save()
