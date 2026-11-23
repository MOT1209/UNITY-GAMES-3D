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

## Coaching style (C1.2): a small, fixed edge. attack / defence multiply the expected goals in simulated matches of the managed club
## (atk on goals scored, def on goals conceded), youth multiplies the development of academy youngsters, morale the weekly
## morale recovery, intel the detail of the pre-match opponent report. Values are the ones promised to the player.
const STYLES := {
	"attacking": {"atk": 1.05, "def": 1.0, "youth": 1.0, "morale": 1.0, "intel": 1.0},
	"defensive": {"atk": 1.0, "def": 0.95, "youth": 1.0, "morale": 1.0, "intel": 1.0},
	"youth": {"atk": 1.0, "def": 1.0, "youth": 1.10, "morale": 1.0, "intel": 1.0},
	"tactical": {"atk": 1.0, "def": 1.0, "youth": 1.0, "morale": 1.0, "intel": 1.25},
	"motivator": {"atk": 1.0, "def": 1.0, "youth": 1.0, "morale": 1.25, "intel": 1.0},
}
const DEFAULT_STYLE := "tactical"
## Starting reputation by background: unknown / known / former star (decides which clubs will hire you).
const START_TIERS := {"unknown": 20, "known": 40, "former_star": 60}

var manager_name: String = "Manager"
var nationality_id: String = ""
var age: int = 40
var style: String = DEFAULT_STYLE
var background: String = "unknown"
var avatar_seed: int = 0
var reputation: int = START_REPUTATION
var confidence: int = START_CONFIDENCE
var contract_years: int = CONTRACT_YEARS
var unemployed: bool = false
var trophies: int = 0
var objective: Dictionary = {}            # current season's board objective (see BoardObjectives.for_club)
var history: Array = []                   # [{season, club, objective_rank, rank, result, reputation, confidence, event}]
## Phase 4 identity. `source`: "custom" (created in the wizard) or "club" (the club's own manager from the database, taken
## over as he is). `manager_id` is unique per career; `origin_club_id` is the club whose manager it was ("" for a custom
## one). A club manager's unknown age is 0 and his unknown nationality "" (the database stores only his name).
var source: String = "custom"
var manager_id: String = ""
var origin_club_id: String = ""


func style_effects() -> Dictionary:
	return STYLES[style] if STYLES.has(style) else STYLES[DEFAULT_STYLE]


## Applies the chosen profile (name, nationality, age, style, background); the starting reputation follows the background.
func set_profile(p_name: String, p_nationality_id: String, p_age: int, p_style: String, p_background: String, p_avatar_seed: int = 0) -> void:
	manager_name = p_name.strip_edges() if p_name.strip_edges() != "" else "Manager"
	nationality_id = p_nationality_id
	age = clampi(p_age, 30, 75)
	style = p_style if STYLES.has(p_style) else DEFAULT_STYLE
	background = p_background if START_TIERS.has(p_background) else "unknown"
	avatar_seed = p_avatar_seed
	reputation = int(START_TIERS[background])
	source = "custom"
	origin_club_id = ""
	manager_id = "mgr_%d" % (absi(hash([manager_name, p_nationality_id, age, p_avatar_seed, Time.get_ticks_usec()])) % 1_000_000_000)


## Takes over the club's own manager (Option A of the wizard): his name and database id as stored, nothing invented. The
## style and background are the user's choices of how he plays (they drive the game rules). Returns "" or an error.
func set_club_manager(team: TeamData, p_style: String, p_background: String) -> String:
	if team == null or team.manager_name.strip_edges() == "":
		return "the club has no manager in the database"
	manager_name = team.manager_name.strip_edges()
	nationality_id = ""
	age = 0
	style = p_style if STYLES.has(p_style) else DEFAULT_STYLE
	background = p_background if START_TIERS.has(p_background) else "unknown"
	avatar_seed = hash(team.id + "_manager") & 0x7fffffff
	reputation = int(START_TIERS[background])
	source = "club"
	origin_club_id = team.id
	manager_id = team.manager_id if team.manager_id != "" else "club_mgr_%s" % team.id
	return ""


func is_club_manager() -> bool:
	return source == "club"


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
	return {"nationality_id": nationality_id, "age": age, "style": style, "background": background, "avatar_seed": avatar_seed,
			"name": manager_name, "reputation": reputation, "confidence": confidence, "contract_years": contract_years,
			"unemployed": unemployed, "trophies": trophies, "objective": objective.duplicate(true), "history": history.duplicate(true),
			"source": source, "manager_id": manager_id, "origin_club_id": origin_club_id}


static func from_dict(d: Dictionary) -> ManagerProfile:
	var m := ManagerProfile.new()
	m.manager_name = str(d.get("name", "Manager"))
	m.nationality_id = str(d.get("nationality_id", ""))
	m.source = "club" if str(d.get("source", "custom")) == "club" else "custom"
	m.manager_id = str(d.get("manager_id", ""))
	m.origin_club_id = str(d.get("origin_club_id", ""))
	# a club manager's age can be unknown (0); a created manager is 30..75
	m.age = maxi(int(d.get("age", 0)), 0) if m.source == "club" else clampi(int(d.get("age", 40)), 30, 75)
	m.style = str(d.get("style", DEFAULT_STYLE)) if STYLES.has(str(d.get("style", DEFAULT_STYLE))) else DEFAULT_STYLE
	m.background = str(d.get("background", "unknown")) if START_TIERS.has(str(d.get("background", "unknown"))) else "unknown"
	m.avatar_seed = int(d.get("avatar_seed", 0))
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
