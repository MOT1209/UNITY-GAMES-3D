class_name MatchResult
extends RefCounted

## Outcome of one played match. Competitions only accept results of fixtures
## they generated (`match_id`), and each match id can be recorded once.

var match_id: String = ""
var home_id: String = ""
var away_id: String = ""
var home_goals: int = 0
var away_goals: int = 0
## Penalty shoot-out score, only for knockout draws (-1 = none).
var home_pens: int = -1
var away_pens: int = -1


static func make(p_match_id: String, p_home: String, p_away: String, hg: int, ag: int,
		hp: int = -1, ap: int = -1) -> MatchResult:
	var r := MatchResult.new()
	r.match_id = p_match_id
	r.home_id = p_home
	r.away_id = p_away
	r.home_goals = hg
	r.away_goals = ag
	r.home_pens = hp
	r.away_pens = ap
	return r


func validate() -> Array[String]:
	var errors: Array[String] = []
	if match_id == "":
		errors.append("result has no match id")
	if home_id == "" or away_id == "" or home_id == away_id:
		errors.append("result needs two different teams")
	if home_goals < 0 or away_goals < 0:
		errors.append("negative goals")
	if (home_pens >= 0) != (away_pens >= 0):
		errors.append("penalty score must be given for both teams")
	if home_pens >= 0 and home_goals != away_goals:
		errors.append("penalties only apply to drawn matches")
	if home_pens >= 0 and home_pens == away_pens:
		errors.append("penalty shoot-out cannot end level")
	return errors


## Winning team id, or "" for a draw without penalties.
func winner_id() -> String:
	if home_goals != away_goals:
		return home_id if home_goals > away_goals else away_id
	if home_pens >= 0 and away_pens >= 0 and home_pens != away_pens:
		return home_id if home_pens > away_pens else away_id
	return ""


func loser_id() -> String:
	var w := winner_id()
	if w == "":
		return ""
	return away_id if w == home_id else home_id


func to_dict() -> Dictionary:
	return {"match_id": match_id, "home": home_id, "away": away_id, "hg": home_goals,
			"ag": away_goals, "hp": home_pens, "ap": away_pens}


static func from_dict(d: Dictionary) -> MatchResult:
	return make(str(d.get("match_id", "")), str(d.get("home", "")), str(d.get("away", "")),
			int(d.get("hg", 0)), int(d.get("ag", 0)), int(d.get("hp", -1)), int(d.get("ap", -1)))
