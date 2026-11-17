class_name TrainingPlan
extends RefCounted

## Phase K3: the managed club's daily training. The assistant plans every day automatically around the fixtures —
## match day, rest the day after, light training the day before, intense on free days (medium two days before) — and the
## user can set any day himself (intensity rest / light / medium / intense, focus tactics / fitness / technique /
## set pieces). Overrides are kept per Julian day. The week's mix of intensities scales the weekly youth / first-team
## development (`development_factor`), and intensity changes daily recovery (`recovery_mod`).

const INTENSITIES: Array[String] = ["rest", "light", "medium", "intense"]
const FOCUSES: Array[String] = ["tactics", "fitness", "technique", "set_pieces"]
const RECOVERY := {"rest": 4.0, "light": 2.0, "medium": 0.0, "intense": -3.0, "match": -1.0}
const DEVELOPMENT := {"rest": 0.0, "light": 0.5, "medium": 1.0, "intense": 1.5, "match": 0.8}

var overrides: Dictionary = {}          # str(jdn) -> {intensity, focus}
var _match_key := ""
var _match_cache: Dictionary = {}
var _week_load: Array = []              # intensities of the days lived this week


static func recovery_mod(intensity: String) -> float:
	return float(RECOVERY.get(intensity, 0.0))


## Julian days of the managed club's fixtures this season (cached per call site).
static func match_days(career: CareerState) -> Dictionary:
	var out := {}
	for e in CareerCalendar.season_days(career):
		out[int(e["jdn"])] = true
	return out


## The plan for `jdn`: the user's override, else the assistant's: {intensity, focus, auto: bool, match: bool}.
func day_plan(career: CareerState, jdn: int, matches: Dictionary = {}) -> Dictionary:
	if matches.is_empty():
		var key := "%d_%d_%d" % [career.season, career.week, career.competitions.size()]
		if key != _match_key:                    # the season's match days are computed once per week (it walks every fixture)
			_match_key = key
			_match_cache = match_days(career)
		matches = _match_cache
	if matches.has(jdn):
		return {"intensity": "match", "focus": "tactics", "auto": true, "match": true}
	var o: Dictionary = overrides.get(str(jdn), {})
	if not o.is_empty():
		return {"intensity": str(o.get("intensity", "medium")), "focus": str(o.get("focus", "tactics")), "auto": false, "match": false}
	var intensity := "intense"
	if matches.has(jdn - 1):
		intensity = "rest"
	elif matches.has(jdn + 1):
		intensity = "light"
	elif matches.has(jdn + 2):
		intensity = "medium"
	var focus: String = FOCUSES[posmod(jdn, FOCUSES.size())]
	if intensity == "light":
		focus = "set_pieces"
	return {"intensity": intensity, "focus": focus, "auto": true, "match": false}


## The user sets a day ("" intensity clears the override: the assistant plans it again).
func set_day(jdn: int, intensity: String, focus: String = "tactics") -> String:
	if intensity == "":
		overrides.erase(str(jdn))
		return ""
	if not (intensity in INTENSITIES) or not (focus in FOCUSES):
		return "bad training value"
	overrides[str(jdn)] = {"intensity": intensity, "focus": focus}
	return ""


func note_day(intensity: String) -> void:
	_week_load.append(intensity)
	if _week_load.size() > 7:
		_week_load.pop_front()


## Development multiplier from the last 7 days (0.85 when only resting .. 1.15 when training hard).
func development_factor() -> float:
	if _week_load.is_empty():
		return 1.0
	var s := 0.0
	for i in _week_load:
		s += float(DEVELOPMENT.get(i, 1.0))
	return clampf(0.85 + 0.3 * (s / _week_load.size()) / 1.5, 0.85, 1.15)


func to_dict() -> Dictionary:
	return {"overrides": overrides.duplicate(true), "week_load": _week_load.duplicate()}


static func from_dict(d: Dictionary) -> TrainingPlan:
	var t := TrainingPlan.new()
	t.overrides = (d.get("overrides", {}) as Dictionary).duplicate(true)
	t._week_load = (d.get("week_load", []) as Array).duplicate()
	return t
