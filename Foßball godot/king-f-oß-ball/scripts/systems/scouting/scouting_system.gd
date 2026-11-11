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

var scout_seed: int = 1
var next_index: int = 1
var next_mission_id: int = 1
var week: int = 0
var scouts: Dictionary = {}      # id -> {id, name, quality, weekly_cost}
var missions: Array = []         # {id, scout_id, region, weeks_left, weeks_total, cost}
var pool: Array[String] = []
var reports: Dictionary = {}     # player_id -> {estimate, margin, scout_id, week}
var history: Array = []          # {week, scout_id, region, player_id}


func _init(p_seed := 1) -> void:
	scout_seed = p_seed


func add_scout(scout_id: String, scout_name: String, quality: float, weekly_cost: int) -> String:
	if scouts.has(scout_id):
		return "scout '%s' already exists" % scout_id
	if quality < 0.0 or quality > 1.0 or weekly_cost < 0:
		return "invalid scout quality/cost"
	scouts[scout_id] = {"id": scout_id, "name": scout_name, "quality": quality, "weekly_cost": weekly_cost}
	return ""


func is_scout_busy(scout_id: String) -> bool:
	for m in missions:
		if m["scout_id"] == scout_id:
			return true
	return false


## Starts a mission and charges its full cost to the academy budget.
func start_mission(academy: Academy, scout_id: String, region: String, weeks: int) -> String:
	if not scouts.has(scout_id):
		return "unknown scout '%s'" % scout_id
	if not YouthGenerator.NAME_POOLS.has(region):
		return "unknown region '%s'" % region
	if weeks < 1 or weeks > MAX_WEEKS:
		return "mission length must be 1-%d weeks" % MAX_WEEKS
	if is_scout_busy(scout_id):
		return "scout '%s' is already on a mission" % scout_id
	var cost: int = int(scouts[scout_id]["weekly_cost"]) * weeks
	if cost > academy.budget:
		return "insufficient academy budget (%d needed, %d available)" % [cost, academy.budget]
	academy.budget -= cost
	missions.append({"id": next_mission_id, "scout_id": scout_id, "region": region,
			"weeks_left": weeks, "weeks_total": weeks, "cost": cost})
	next_mission_id += 1
	return ""


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
		var p := YouthGenerator.generate(scout_seed, idx, academy.team_id + "_s", m["region"],
				float(scout["quality"]))
		p.team_id = ""
		if not db.register_player(p):
			continue
		pool.append(p.id)
		reports[p.id] = _make_report(p, scout, academy.quality, idx)
		history.append({"week": week, "scout_id": scout["id"], "region": m["region"], "player_id": p.id})
		out.append(p.id)
	return out


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
			"week": week, "scouts": scouts.duplicate(true), "missions": missions.duplicate(true),
			"pool": Array(pool), "reports": reports.duplicate(true), "history": history.duplicate(true)}


static func from_dict(d: Dictionary) -> ScoutingSystem:
	var s := ScoutingSystem.new(int(d.get("seed", 1)))
	s.next_index = int(d.get("next_index", 1))
	s.next_mission_id = int(d.get("next_mission_id", 1))
	s.week = int(d.get("week", 0))
	s.scouts = (d.get("scouts", {}) as Dictionary).duplicate(true)
	s.missions = (d.get("missions", []) as Array).duplicate(true)
	for m in s.missions:   # JSON turns ints into floats
		m["weeks_left"] = int(m["weeks_left"])
		m["weeks_total"] = int(m["weeks_total"])
		m["id"] = int(m["id"])
		m["cost"] = int(m["cost"])
	s.pool.assign((d.get("pool", []) as Array).map(func(x: Variant) -> String: return str(x)))
	s.reports = (d.get("reports", {}) as Dictionary).duplicate(true)
	s.history = (d.get("history", []) as Array).duplicate(true)
	return s
