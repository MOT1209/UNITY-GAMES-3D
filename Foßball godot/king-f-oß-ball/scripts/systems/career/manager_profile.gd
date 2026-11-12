class_name ManagerProfile
extends RefCounted

## The user's manager (Phase 4): reputation, board confidence, contract and history. Pure data + rules, no scene access.
## Reputation (0..100) decides which clubs offer a job; board confidence (0..100) decides whether the manager keeps it.
## Everything changes only through `BoardObjectives.evaluate` at the end of a season, or `resign` / `take_job`.

const START_REPUTATION := 30
const START_CONFIDENCE := 60
const CONTRACT_YEARS := 3
const SACK_BELOW := 25
const HISTORY_MAX := 50

var manager_name: String = "Manager"
var reputation: int = START_REPUTATION
var confidence: int = START_CONFIDENCE
var contract_years: int = CONTRACT_YEARS
var unemployed: bool = false
var trophies: int = 0
var objective: Dictionary = {}            # current season's board objective (see BoardObjectives.for_club)
var history: Array = []                   # [{season, club, objective_rank, rank, result, reputation, confidence, event}]


func apply_result(delta_confidence: int, delta_reputation: int) -> void:
	confidence = clampi(confidence + delta_confidence, 0, 100)
	reputation = clampi(reputation + delta_reputation, 0, 100)


func is_sacked() -> bool:
	return confidence < SACK_BELOW


func log_entry(entry: Dictionary) -> void:
	history.append(entry)
	while history.size() > HISTORY_MAX:
		history.pop_front()


func to_dict() -> Dictionary:
	return {"name": manager_name, "reputation": reputation, "confidence": confidence, "contract_years": contract_years,
			"unemployed": unemployed, "trophies": trophies, "objective": objective.duplicate(true), "history": history.duplicate(true)}


static func from_dict(d: Dictionary) -> ManagerProfile:
	var m := ManagerProfile.new()
	m.manager_name = str(d.get("name", "Manager"))
	m.reputation = clampi(int(d.get("reputation", START_REPUTATION)), 0, 100)
	m.confidence = clampi(int(d.get("confidence", START_CONFIDENCE)), 0, 100)
	m.contract_years = int(d.get("contract_years", CONTRACT_YEARS))
	m.unemployed = bool(d.get("unemployed", false))
	m.trophies = int(d.get("trophies", 0))
	var o: Dictionary = d.get("objective", {})
	m.objective = {}
	for k in o:
		m.objective[k] = int(o[k]) if o[k] is float or o[k] is int else o[k]
	for h in d.get("history", []):
		var e: Dictionary = (h as Dictionary).duplicate(true)
		for k in ["season", "objective_rank", "rank", "reputation", "confidence"]:
			if e.has(k):
				e[k] = int(e[k])
		m.history.append(e)
	return m
