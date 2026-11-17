class_name CareerSettings
extends RefCounted

## Career phase C1.2: the options chosen in the new-career wizard. Saved with the career and read by real code:
##   difficulty -> the managed club's expected goals in simulated matches (easy +5% / -5% conceded, hard the reverse),
##   market difficulty -> the price factor the user pays in negotiations, start budget -> the opening transfer budget,
##   injuries -> whether injuries happen at all, default match mode and delegation defaults -> pre-selected in the match / assistant UI.

const LEVELS: Array[String] = ["easy", "normal", "hard"]
const BUDGETS: Array[String] = ["low", "default", "high"]
const MATCH_MODES: Array[String] = ["play", "manage", "simulate"]

var match_difficulty := "normal"
var market_difficulty := "normal"
var start_budget := "default"
var injuries := true
var default_match_mode := "play"
var delegate_academy := false
var delegate_renewals := false


func match_factors() -> Dictionary:
	match match_difficulty:
		"easy":
			return {"atk": 1.05, "def": 0.95}
		"hard":
			return {"atk": 0.95, "def": 1.05}
	return {"atk": 1.0, "def": 1.0}


func market_price_factor() -> float:
	return {"easy": 0.95, "normal": 1.0, "hard": 1.08}.get(market_difficulty, 1.0)


func budget_factor() -> float:
	return {"low": 0.7, "default": 1.0, "high": 1.4}.get(start_budget, 1.0)


func to_dict() -> Dictionary:
	return {"match_difficulty": match_difficulty, "market_difficulty": market_difficulty, "start_budget": start_budget, "injuries": injuries,
			"default_match_mode": default_match_mode, "delegate_academy": delegate_academy, "delegate_renewals": delegate_renewals}


static func from_dict(d: Dictionary) -> CareerSettings:
	var s := CareerSettings.new()
	s.match_difficulty = str(d.get("match_difficulty", "normal")) if LEVELS.has(str(d.get("match_difficulty", "normal"))) else "normal"
	s.market_difficulty = str(d.get("market_difficulty", "normal")) if LEVELS.has(str(d.get("market_difficulty", "normal"))) else "normal"
	s.start_budget = str(d.get("start_budget", "default")) if BUDGETS.has(str(d.get("start_budget", "default"))) else "default"
	s.injuries = bool(d.get("injuries", true))
	s.default_match_mode = str(d.get("default_match_mode", "play")) if MATCH_MODES.has(str(d.get("default_match_mode", "play"))) else "play"
	s.delegate_academy = bool(d.get("delegate_academy", false))
	s.delegate_renewals = bool(d.get("delegate_renewals", false))
	return s


## Applies the start-of-career effects (budget, delegation defaults). Everything else is read live.
func apply_to(career: CareerState) -> void:
	var l := career.ledger()
	l.transfer_budget = int(float(l.transfer_budget) * budget_factor())
	career.delegation.set_domain("academy", Delegation.ASSISTANT if delegate_academy else Delegation.ME)
	career.delegation.set_domain("renewals", Delegation.ASSISTANT if delegate_renewals else Delegation.ME)
