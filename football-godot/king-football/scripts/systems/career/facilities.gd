class_name Facilities
extends RefCounted

## Career phase C2.5: the managed club's facilities, levels 1-5, built over weeks, paid through the FinanceLedger, with weekly
## upkeep. Effects are small and fixed: clinic = fewer / shorter injuries, training = faster development, stadium = matchday income,
## academy = better intakes (read by the academy code later), scouting = scouting accuracy. AI clubs use `ai_develop` with the
## same costs and the same upgrade rule.

const KINDS: Array[String] = ["stadium", "training", "clinic", "academy", "scouting"]
const MAX_LEVEL := 5
const BASE_COST := 200_000
const UPKEEP_PER_LEVEL := 2_000
const BOARD_APPROVAL_SHARE := 0.30          # an upgrade costing more than this share of the balance needs board approval

var levels: Dictionary = {}                 # kind -> int (1-5)
var queue: Array = []                       # [{kind, weeks_left, cost}]


func _init() -> void:
	for k in KINDS:
		levels[k] = 1


func level(kind: String) -> int:
	return int(levels.get(kind, 1))


static func cost_of(next_level: int) -> int:
	return BASE_COST * next_level * next_level


static func build_weeks(next_level: int) -> int:
	return 4 * next_level


func is_building(kind: String) -> bool:
	return queue.any(func(q: Dictionary) -> bool: return q["kind"] == kind)


## Starts an upgrade. `approved` = the board said yes (needed above the share). Returns "" or an error translation key.
func upgrade(ledger: FinanceLedger, kind: String, week: int, board_confidence: int, approved := false) -> String:
	if not KINDS.has(kind):
		return "FAC_ERR_UNKNOWN"
	if level(kind) >= MAX_LEVEL:
		return "FAC_ERR_MAX"
	if is_building(kind):
		return "FAC_ERR_BUSY"
	var next := level(kind) + 1
	var cost := cost_of(next)
	if cost > int(float(maxi(ledger.balance, 0)) * BOARD_APPROVAL_SHARE) and not approved and board_confidence < 60:
		return "FAC_ERR_BOARD"
	if not ledger.can_afford(-cost, "facilities"):
		return "FAC_ERR_MONEY"
	var err := ledger.record("facilities", -cost, "Facility upgrade: " + kind, week, "FIN_FACILITY_UPGRADE")
	if err != "":
		return "FAC_ERR_MONEY"
	queue.append({"kind": kind, "weeks_left": build_weeks(next), "cost": cost})
	return ""


## Once a week: progress the builds and pay the upkeep. Returns the kinds finished this week.
func weekly(ledger: FinanceLedger, week: int) -> Array:
	var done: Array = []
	for q in queue.duplicate():
		q["weeks_left"] = int(q["weeks_left"]) - 1
		if int(q["weeks_left"]) <= 0:
			levels[q["kind"]] = mini(level(str(q["kind"])) + 1, MAX_LEVEL)
			queue.erase(q)
			done.append(q["kind"])
	var upkeep := 0
	for k in KINDS:
		upkeep += UPKEEP_PER_LEVEL * (level(k) - 1)
	if upkeep > 0 and ledger != null:
		ledger.record("maintenance", -upkeep, "Facility upkeep", week, "FIN_FACILITY_UPKEEP")
	return done


func injury_factor() -> float:
	return 1.0 - 0.05 * float(level("clinic") - 1)


func recovery_factor() -> float:
	return 1.0 - 0.04 * float(level("clinic") - 1)


func development_factor() -> float:
	return 1.0 + 0.03 * float(level("training") - 1)


func matchday_factor() -> float:
	return 1.0 + 0.10 * float(level("stadium") - 1)


func scouting_accuracy() -> float:
	return clampf(0.5 + 0.1 * float(level("scouting") - 1), 0.0, 1.0)


## AI clubs: at most one upgrade at a time, only when it costs under 15% of their balance (same costs as the user).
static func ai_develop(f: Facilities, ledger: FinanceLedger, week: int, seed_value: int) -> String:
	if not f.queue.is_empty():
		return ""
	var kind: String = KINDS[abs(seed_value) % KINDS.size()]
	if level_ok(f, kind) and cost_of(f.level(kind) + 1) < int(float(maxi(ledger.balance, 0)) * 0.15):
		return kind if f.upgrade(ledger, kind, week, 100, true) == "" else ""
	return ""


static func level_ok(f: Facilities, kind: String) -> bool:
	return f.level(kind) < MAX_LEVEL


func to_dict() -> Dictionary:
	return {"levels": levels.duplicate(), "queue": queue.duplicate(true)}


static func from_dict(d: Dictionary) -> Facilities:
	var f := Facilities.new()
	for k in (d.get("levels", {}) as Dictionary):
		if KINDS.has(str(k)):
			f.levels[str(k)] = clampi(int(d["levels"][k]), 1, MAX_LEVEL)
	for q in d.get("queue", []):
		if typeof(q) == TYPE_DICTIONARY and KINDS.has(str(q.get("kind", ""))):
			f.queue.append({"kind": str(q["kind"]), "weeks_left": maxi(int(q.get("weeks_left", 1)), 1), "cost": int(q.get("cost", 0))})
	return f
