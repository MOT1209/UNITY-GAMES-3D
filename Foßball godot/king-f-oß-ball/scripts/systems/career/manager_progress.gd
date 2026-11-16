class_name ManagerProgress
extends RefCounted

## Career phase C8: manager experience and levels, the skill tree (5 branches x 4 levels, each branch at most +-10% in total),
## achievements (awarded once, saved) and optional challenges. Effects are small and fixed; every one is read by real code:
##   negotiation -> `TransferMarket.negotiate` (the user's buy price), youth -> academy development (`dev_bonus`),
##   tactics -> opponent report detail, management -> slower confidence loss, fitness -> injury chance.

const BRANCHES: Array[String] = ["negotiation", "youth", "tactics", "management", "fitness"]
const BRANCH_MAX := 4
const XP_PER_LEVEL := 100
const MAX_LEVEL := 30
const PER_LEVEL_EFFECT := 0.025                 # 4 levels = 10%

var xp := 0
var spent_points := 0
var branch_levels: Dictionary = {}              # branch -> 0..4
var unlocked: Array = []                        # achievement ids
var challenges: Array = []                      # [{id, goal, progress, done, reward}]


func _init() -> void:
	for b in BRANCHES:
		branch_levels[b] = 0


func level() -> int:
	return mini(1 + xp / XP_PER_LEVEL, MAX_LEVEL)


func points_available() -> int:
	return (level() - 1) - spent_points


func add_xp(amount: int) -> int:
	var before := level()
	xp += maxi(amount, 0)
	return level() - before


func spend(branch: String) -> String:
	if not BRANCHES.has(branch):
		return "SKILL_ERR_UNKNOWN"
	if int(branch_levels[branch]) >= BRANCH_MAX:
		return "SKILL_ERR_MAX"
	if points_available() <= 0:
		return "SKILL_ERR_POINTS"
	branch_levels[branch] = int(branch_levels[branch]) + 1
	spent_points += 1
	return ""


func effect(branch: String) -> float:
	return PER_LEVEL_EFFECT * float(int(branch_levels.get(branch, 0)))


# --- xp sources -----------------------------------------------------------------------------------------

static func xp_for_match(result: String) -> int:
	return {"win": 10, "draw": 4, "loss": 1}.get(result, 0)


static func xp_for_season(champion: bool, objective_met: bool, promoted: bool) -> int:
	return (80 if champion else 0) + (40 if objective_met else 0) + (50 if promoted else 0)


# --- achievements -----------------------------------------------------------------------------------------

## id -> [translation key suffix, check Callable(career) -> bool]. Checks read only saved state, so they are repeatable.
static func definitions() -> Array:
	return [
		{"id": "first_win", "check": func(c: CareerState) -> bool: return c.manager.history.size() >= 0 and c.progress.wins >= 1},
		{"id": "ten_wins", "check": func(c: CareerState) -> bool: return c.progress.wins >= 10},
		{"id": "fifty_wins", "check": func(c: CareerState) -> bool: return c.progress.wins >= 50},
		{"id": "first_trophy", "check": func(c: CareerState) -> bool: return c.manager.trophies >= 1},
		{"id": "three_trophies", "check": func(c: CareerState) -> bool: return c.manager.trophies >= 3},
		{"id": "survivor", "check": func(c: CareerState) -> bool: return c.manager.history.size() >= 3},
		{"id": "veteran", "check": func(c: CareerState) -> bool: return c.manager.history.size() >= 10},
		{"id": "respected", "check": func(c: CareerState) -> bool: return c.manager.reputation >= 70},
		{"id": "legend", "check": func(c: CareerState) -> bool: return c.manager.reputation >= 90},
		{"id": "rich", "check": func(c: CareerState) -> bool: return c.ledger().balance >= 50_000_000},
		{"id": "builder", "check": func(c: CareerState) -> bool: return c.facilities.levels.values().any(func(v: int) -> bool: return v >= 3)},
		{"id": "full_staff", "check": func(c: CareerState) -> bool: return c.staff.members.size() >= 5},
		{"id": "skilled", "check": func(c: CareerState) -> bool: return c.progress.level() >= 5},
		{"id": "master", "check": func(c: CareerState) -> bool: return c.progress.branch_levels.values().any(func(v: int) -> bool: return v >= 4)},
		{"id": "promoted", "check": func(c: CareerState) -> bool: return c.progress.promotions >= 1},
		{"id": "from_scratch", "check": func(c: CareerState) -> bool: return c.manager.background == "unknown" and c.manager.trophies >= 1},
		{"id": "unbeaten_streak", "check": func(c: CareerState) -> bool: return c.progress.best_streak >= 5},
		{"id": "ten_streak", "check": func(c: CareerState) -> bool: return c.progress.best_streak >= 10},
		{"id": "promise_keeper", "check": func(c: CareerState) -> bool: return c.board.promises.filter(func(p: Dictionary) -> bool: return p["status"] == "kept").size() >= 2},
		{"id": "loyal", "check": func(c: CareerState) -> bool: return c.manager.history.size() >= 5 and c.manager.history.all(func(h: Dictionary) -> bool: return h.get("club", "") == c.club_id)},
	]


## Awards every achievement whose condition holds and which is not yet unlocked. Returns the new ids.
func check_achievements(career: CareerState) -> Array:
	var fresh: Array = []
	for d in definitions():
		if not unlocked.has(d["id"]) and bool((d["check"] as Callable).call(career)):
			unlocked.append(d["id"])
			fresh.append(d["id"])
	return fresh


# --- results tracking -----------------------------------------------------------------------------------------

var wins := 0
var draws := 0
var losses := 0
var streak := 0
var best_streak := 0
var promotions := 0


func record_result(result: String) -> void:
	match result:
		"win":
			wins += 1
			streak += 1
		"draw":
			draws += 1
			streak += 1
		"loss":
			losses += 1
			streak = 0
	best_streak = maxi(best_streak, streak)
	add_xp(xp_for_match(result))


# --- challenges (optional, small rewards) ----------------------------------------------------------------------

static func new_challenges(season: int) -> Array:
	return [
		{"id": "win_3", "goal": 3, "progress": 0, "done": false, "reward": {"reputation": 1}},
		{"id": "clean_sheets_2", "goal": 2, "progress": 0, "done": false, "reward": {"budget": 100_000}},
	]


func progress_challenge(id: String, amount: int, career: CareerState) -> bool:
	for c in challenges:
		if c["id"] == id and not c["done"]:
			c["progress"] = int(c["progress"]) + amount
			if int(c["progress"]) >= int(c["goal"]):
				c["done"] = true
				var r: Dictionary = c["reward"]
				if r.has("reputation"):
					career.manager.apply_result(0, int(r["reputation"]))
				if r.has("budget"):
					career.ledger().transfer_budget += int(r["budget"])
				return true
	return false


func to_dict() -> Dictionary:
	return {"xp": xp, "spent": spent_points, "branches": branch_levels.duplicate(), "unlocked": unlocked.duplicate(), "challenges": challenges.duplicate(true),
			"wins": wins, "draws": draws, "losses": losses, "streak": streak, "best_streak": best_streak, "promotions": promotions}


static func from_dict(d: Dictionary) -> ManagerProgress:
	var m := ManagerProgress.new()
	m.xp = maxi(int(d.get("xp", 0)), 0)
	for b in (d.get("branches", {}) as Dictionary):
		if BRANCHES.has(str(b)):
			m.branch_levels[str(b)] = clampi(int(d["branches"][b]), 0, BRANCH_MAX)
	var total := 0
	for b in BRANCHES:
		total += int(m.branch_levels[b])
	m.spent_points = mini(maxi(int(d.get("spent", total)), total), m.level() - 1) if m.level() - 1 >= total else total
	m.unlocked = (d.get("unlocked", []) as Array).map(func(x: Variant) -> String: return str(x))
	m.challenges = PlayerData._restore_ints((d.get("challenges", []) as Array).duplicate(true))
	for k in ["wins", "draws", "losses", "streak", "best_streak", "promotions"]:
		m.set(k, maxi(int(d.get(k, 0)), 0))
	return m
