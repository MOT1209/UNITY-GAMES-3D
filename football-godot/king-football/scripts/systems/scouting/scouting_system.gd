class_name ScoutingSystem
extends RefCounted

## Youth scouting (Phase T5): scouts, regional missions, discovered prospects,
## reports with potential estimates whose reliability depends on scout
## quality and academy facilities, costs and discovery history.
## Discovered prospects live in `pool` (registered in the player database with
## an empty team_id) until signed into the academy.

const MAX_POOL := 30
const MAX_WEEKS := 12
const SIGNING_BASE_COST := 5000
## Scout market (Nov 2026): hire / dismiss scouts. A hire costs HIRE_WEEKS weeks of the scout's weekly cost
## (paid from the academy budget); the market offers MARKET_SIZE candidates and refreshes after every hire.
const MAX_SCOUTS := 5
const MARKET_SIZE := 4
const HIRE_WEEKS := 10

var scout_seed: int = 1
var next_index: int = 1
var next_mission_id: int = 1
var week: int = 0
var scouts: Dictionary = {}      # id -> {id, name, quality, weekly_cost}
var missions: Array = []         # {id, scout_id, region, weeks_left, weeks_total, cost}
var pool: Array[String] = []
var reports: Dictionary = {}     # player_id -> {estimate, margin, scout_id, week}
var history: Array = []          # {week, scout_id, region, player_id}
var market_round: int = 0        # bumps after each hire: a new set of candidates
var next_hire_id: int = 1


func _init(p_seed := 1) -> void:
	scout_seed = p_seed


func add_scout(scout_id: String, scout_name: String, quality: float, weekly_cost: int) -> String:
	if scouts.has(scout_id):
		return "scout '%s' already exists" % scout_id
	if quality < 0.0 or quality > 1.0 or weekly_cost < 0:
		return "invalid scout quality/cost"
	scouts[scout_id] = {"id": scout_id, "name": scout_name, "quality": quality, "weekly_cost": weekly_cost}
	return ""


## Scouts on the market: deterministic from the seed and `market_round` (same list after save / load).
func candidates() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([scout_seed, market_round, "scouts"])
	var out: Array = []
	for i in MARKET_SIZE:
		var q := snappedf(rng.randf_range(0.3, 0.95), 0.01)
		var cost := int(snappedf(500.0 + q * q * 5500.0, 50.0))
		out.append({"name": YouthGenerator._name(rng, "Aldoria"), "quality": q, "weekly_cost": cost})
	return out


func hire_fee(candidate: Dictionary) -> int:
	return int(candidate["weekly_cost"]) * HIRE_WEEKS


## Hires market candidate `index`. Returns "" or an error.
func hire(academy: Academy, index: int) -> String:
	var list := candidates()
	if index < 0 or index >= list.size():
		return "unknown candidate"
	if scouts.size() >= MAX_SCOUTS:
		return "at most %d scouts" % MAX_SCOUTS
	var c: Dictionary = list[index]
	var fee := hire_fee(c)
	if fee > academy.budget:
		return "insufficient academy budget (%d needed, %d available)" % [fee, academy.budget]
	var id := "scout_h%d" % next_hire_id
	var err := add_scout(id, str(c["name"]), float(c["quality"]), int(c["weekly_cost"]))
	if err != "":
		return err
	academy.budget -= fee
	next_hire_id += 1
	market_round += 1
	return ""


## Dismisses a scout (not while on a mission; the last scout stays).
func dismiss(scout_id: String) -> String:
	if not scouts.has(scout_id):
		return "unknown scout '%s'" % scout_id
	if is_scout_busy(scout_id):
		return "scout '%s' is on a mission" % scout_id
	if scouts.size() <= 1:
		return "the academy needs at least one scout"
	scouts.erase(scout_id)
	return ""


func is_scout_busy(scout_id: String) -> bool:
	for m in missions:
		if m["scout_id"] == scout_id:
			return true
	return false


## A mission to "worldwide" finds prospects of every nationality in the database.
const WORLDWIDE := "worldwide"


## Every country a scout can be sent to: worldwide first, then the database's countries (fictional regions when the
## database has none), sorted by their localized name.
static func regions(db: Node) -> Array:
	var ids: Array = []
	if db != null and "countries" in db:
		ids = (db.countries as Dictionary).keys()
	if ids.is_empty():
		ids = YouthGenerator.NAME_POOLS.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return Loc.country(a) < Loc.country(b))
	return [WORLDWIDE] + ids


static func _known_region(region: String) -> bool:
	if region == WORLDWIDE or YouthGenerator.NAME_POOLS.has(region) or YouthGenerator.REAL_POOLS.has(region) or NameBank.has_pool(region):
		return true
	var tree := Engine.get_main_loop() as SceneTree
	var db: Node = tree.root.get_node_or_null("TeamDB") if tree != null else null
	return db != null and (db.countries as Dictionary).has(region)


func _random_country(db: Node, idx: int) -> String:
	var ids: Array = (db.countries as Dictionary).keys() if db != null and "countries" in db else []
	if ids.is_empty():
		ids = YouthGenerator.NAME_POOLS.keys()
	ids.sort()
	return str(ids[absi(hash([scout_seed, idx, "country"])) % ids.size()])


## Starts a mission and charges its full cost to the academy budget.
## Mission objectives: what the scout looks for among the players he sees.
const OBJECTIVES: Array[String] = ["balanced", "potential", "ready"]


## `position` ("" = any, else a PlayerData.Position name) and `objective` (see OBJECTIVES) steer the discovery: a better scout sees more
## players per slot and so finds a better match; reports stay as (un)reliable as the scout is.
func start_mission(academy: Academy, scout_id: String, region: String, weeks: int, position: String = "", objective: String = "balanced") -> String:
	if position != "" and not (position in PlayerData.Position.keys()):
		return "unknown position '%s'" % position
	if not (objective in OBJECTIVES):
		return "unknown objective '%s'" % objective
	if not scouts.has(scout_id):
		return "unknown scout '%s'" % scout_id
	if not _known_region(region):
		return "unknown region '%s'" % region          # any country of the database (or WORLDWIDE) can be scouted
	if weeks < 1 or weeks > MAX_WEEKS:
		return "mission length must be 1-%d weeks" % MAX_WEEKS
	if is_scout_busy(scout_id):
		return "scout '%s' is already on a mission" % scout_id
	var cost: int = int(scouts[scout_id]["weekly_cost"]) * weeks
	if cost > academy.budget:
		return "insufficient academy budget (%d needed, %d available)" % [cost, academy.budget]
	academy.budget -= cost
	missions.append({"id": next_mission_id, "scout_id": scout_id, "region": region,
			"weeks_left": weeks, "weeks_total": weeks, "cost": cost, "position": position, "objective": objective})
	next_mission_id += 1
	return ""


## Absolute career week last processed (-1 = never synced); see TrainingSystem.
var calendar_week: int = -1


## Runs the scouting weeks owed up to the career's `absolute_week`. Idempotent
## per week. Returns the player ids discovered.
func sync_to_calendar(db: Node, academy: Academy, absolute_week: int) -> Array[String]:
	if calendar_week < 0:
		calendar_week = absolute_week - 1
	var found: Array[String] = []
	if absolute_week <= calendar_week:
		return found
	var owed := mini(absolute_week - calendar_week, DevConfig.YOUTH_CATCH_UP_MAX_WEEKS)     # was 4: longer jumps lost scouting weeks
	calendar_week = absolute_week
	for i in owed:
		found.append_array(advance_week(db, academy))
	return found


## Advances one week. Returns player ids discovered this week.
func advance_week(db: Node, academy: Academy) -> Array[String]:
	week += 1
	var found: Array[String] = []
	var remaining: Array = []
	for m in missions:
		m["weeks_left"] -= 1
		if m["weeks_left"] > 0:
			remaining.append(m)
			continue
		found.append_array(_complete(db, academy, m))
	missions = remaining
	return found


func _complete(db: Node, academy: Academy, m: Dictionary) -> Array[String]:
	var scout: Dictionary = scouts[m["scout_id"]]
	var count := clampi(roundi(m["weeks_total"] * (0.5 + float(scout["quality"]))), 1, 6)
	var out: Array[String] = []
	for i in count:
		if pool.size() >= MAX_POOL:
			break
		var idx := next_index
		next_index += 1
		var country: String = m["region"]
		if country == WORLDWIDE:
			country = _random_country(db, idx)            # worldwide: every prospect from any country of the database
		var p := _best_candidate(academy, scout, country, idx, str(m.get("position", "")), str(m.get("objective", "balanced")))
		p.team_id = ""
		if not db.register_player(p):
			continue
		pool.append(p.id)
		reports[p.id] = _make_report(p, scout, academy.quality, idx)
		history.append({"week": week, "scout_id": scout["id"], "region": m["region"], "player_id": p.id})
		out.append(p.id)
	return out


## A scout looks at 1..4 players per slot (more with higher quality) and keeps the one that best fits the mission.
func _best_candidate(academy: Academy, scout: Dictionary, country: String, idx: int, position: String, objective: String) -> PlayerData:
	var looks := 1 + roundi(float(scout["quality"]) * 3.0) if (position != "" or objective != "balanced") else 1
	var best: PlayerData = null
	var best_score := -1.0e9
	for k in looks:
		var cand := YouthGenerator.generate(scout_seed, idx if k == 0 else 1_000_000 + idx * 10 + k, academy.team_id + "_s", country, float(scout["quality"]))
		var score := 0.0
		if position != "" and PlayerData.Position.keys()[cand.position] == position:
			score += 100.0
		match objective:
			"potential":
				score += cand.potential
			"ready":
				score += cand.get_overall() + cand.age
			_:
				score += cand.potential * 0.5 + cand.get_overall() * 0.5
		if score > best_score:
			best_score = score
			best = cand
	return best


## Reliability = 70 % scout quality + 30 % academy facilities. The estimate is
## the true potential plus noise whose size shrinks with reliability.
func _make_report(p: PlayerData, scout: Dictionary, facility: float, idx: int) -> Dictionary:
	var rel := 0.7 * float(scout["quality"]) + 0.3 * clampf(facility, 0.0, 1.0)
	var margin := lerpf(14.0, 2.0, rel)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([scout_seed, idx, "report"])
	var noise := rng.randfn(0.0, margin / 2.0)
	var estimate := clampi(roundi(p.potential + noise), 1, 99)
	return {"estimate": estimate, "margin": roundi(margin), "scout_id": scout["id"],
			"week": week, "reliability": rel}


func signing_cost(p: PlayerData) -> int:
	return SIGNING_BASE_COST + p.get_overall() * 100


## Moves a discovered prospect into the academy (budget + capacity checked).
func sign_prospect(db: Node, academy: Academy, player_id: String) -> String:
	if not (player_id in pool):
		return "prospect '%s' is not in the scouting pool" % player_id
	var p: PlayerData = db.get_player(player_id)
	if p == null:
		return "unknown player '%s'" % player_id
	var group := AcademyConfig.group_for_age(p.age)
	if not academy.has_room(db, group):
		return "%s group is full" % group
	var cost := signing_cost(p)
	if cost > academy.budget:
		return "insufficient academy budget (%d needed)" % cost
	academy.budget -= cost
	p.team_id = academy.team_id
	pool.erase(player_id)
	academy.roster_ids.append(player_id)
	p.development_history.append({"event": "signed", "week": week, "cost": cost})
	return ""


func to_dict() -> Dictionary:
	return {"seed": scout_seed, "next_index": next_index, "next_mission_id": next_mission_id,
			"week": week, "calendar_week": calendar_week, "scouts": scouts.duplicate(true), "missions": missions.duplicate(true),
			"pool": Array(pool), "reports": reports.duplicate(true), "history": history.duplicate(true),
			"market_round": market_round, "next_hire_id": next_hire_id}


static func from_dict(d: Dictionary) -> ScoutingSystem:
	var s := ScoutingSystem.new(int(d.get("seed", 1)))
	s.next_index = int(d.get("next_index", 1))
	s.next_mission_id = int(d.get("next_mission_id", 1))
	s.week = int(d.get("week", 0))
	s.calendar_week = int(d.get("calendar_week", -1))
	s.scouts = (d.get("scouts", {}) as Dictionary).duplicate(true)
	s.missions = (d.get("missions", []) as Array).duplicate(true)
	for m in s.missions:   # JSON turns ints into floats
		m["weeks_left"] = int(m["weeks_left"])
		m["weeks_total"] = int(m["weeks_total"])
		m["id"] = int(m["id"])
		m["cost"] = int(m["cost"])
		m["position"] = str(m.get("position", ""))
		m["objective"] = str(m.get("objective", "balanced"))
	s.pool.assign((d.get("pool", []) as Array).map(func(x: Variant) -> String: return str(x)))
	s.reports = (d.get("reports", {}) as Dictionary).duplicate(true)
	s.history = (d.get("history", []) as Array).duplicate(true)
	s.market_round = int(d.get("market_round", 0))
	s.next_hire_id = int(d.get("next_hire_id", 1))
	return s
