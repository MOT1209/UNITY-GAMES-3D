class_name ContinentalCup
extends RefCounted

## A continental club cup across the countries of the loaded data pack (Phase 10): 16 clubs, four groups of four (single round-robin,
## three match-days), then quarter-finals, semi-finals and the final. The qualifiers are the best clubs of every country's top division:
## in season 1 by squad rating, afterwards by the previous season's final table. Fictional names only: the competition is called
## "Continental Cup"; no real trophy or sponsor name is used. Needs at least two countries with a top division of 4+ clubs.
## It runs through the ordinary `Competition` machinery and the career calendar: matches the user does not play are simulated
## (`MatchSimulator`), the user's own matches stay pending in their week, results pay the usual competition rewards.

const TEAMS := 16
const PER_COUNTRY := 3
const GROUP_WEEKS: Array[int] = [8, 14, 20]
const KO_WEEKS: Array[int] = [26, 32, 38]          # quarter-final, semi-final, final (domestic cup weeks are 5, 11, 17, 23, 29, 35, 41, 43)

var season := 1
var comp_id := ""
var last_champion := ""


## The qualifiers, strongest first. `last_tables`: pyramid key -> division id -> final order (ids) of the season before, or {}.
static func qualifiers(career: CareerState, last_tables: Dictionary = {}) -> Array:
	var chosen: Array = []
	var rest: Array = []
	for k in career.pyramids:
		var pyr: LeaguePyramid = career.pyramids[k]
		var top: Dictionary = pyr.divisions[0]
		var ids: Array = (top["team_ids"] as Array).duplicate()
		var order: Array = last_tables.get(k, {}).get(top["id"], [])
		if order.is_empty() or order.size() != ids.size():
			ids.sort_custom(func(a: String, b: String) -> bool:
				var ra: int = career.db.get_team_rating(a)
				var rb: int = career.db.get_team_rating(b)
				return ra > rb if ra != rb else a < b)
		else:
			ids = order.duplicate()
		for i in ids.size():
			if i < PER_COUNTRY:
				chosen.append(ids[i])
			else:
				rest.append(ids[i])
	rest.sort_custom(func(a: String, b: String) -> bool:
		var ra: int = career.db.get_team_rating(a)
		var rb: int = career.db.get_team_rating(b)
		return ra > rb if ra != rb else a < b)
	while chosen.size() < TEAMS and not rest.is_empty():
		chosen.append(rest.pop_front())
	if chosen.size() < TEAMS:
		return []
	chosen = chosen.slice(0, TEAMS)
	chosen.sort_custom(func(a: String, b: String) -> bool:
		var ra: int = career.db.get_team_rating(a)
		var rb: int = career.db.get_team_rating(b)
		return ra > rb if ra != rb else a < b)
	return chosen


## Creates this season's competition and registers it. Returns false when the data pack cannot field the cup.
func build(career: CareerState, last_tables: Dictionary = {}) -> bool:
	season = career.season
	comp_id = ""
	var teams := qualifiers(career, last_tables)
	if teams.is_empty():
		return false
	# the strongest four clubs are the group seeds: `Competition` deals the list round-robin into the groups
	var c := Competition.create_group_knockout("continental_s%d" % season, "Continental Cup %d" % season, teams, 4, false)
	c.season = season
	if career.register_competition(c) != "":
		return false
	comp_id = c.id
	return true


func competition(career: CareerState) -> Competition:
	return career.competitions.get(comp_id) if comp_id != "" else null


## Career week in which fixture `f` is due.
func week_of(f: Dictionary) -> int:
	var rnd := int(f["round"])
	if f["stage"] == "group":
		return GROUP_WEEKS[mini(rnd, GROUP_WEEKS.size()) - 1]
	return KO_WEEKS[mini(rnd, KO_WEEKS.size()) - 1]


## Plays everything due by `week` except the user's matches of this very week (same contract as `LeaguePyramid.play_week`).
func play_week(week: int, career: CareerState, user_team_id: String) -> Dictionary:
	var out := {"played": 0, "user_fixtures": [], "auto_played": []}
	var c := competition(career)
	if c == null:
		return out
	for _i in 4:                              # a finished group stage creates the quarter-finals: they may be due at once
		var progressed := false
		for f in c.pending_fixtures():
			var due := week_of(f)
			if due > week:
				continue
			var mine: bool = user_team_id != "" and (f["home"] == user_team_id or f["away"] == user_team_id)
			if mine and due == week:
				out["user_fixtures"].append({"competition_id": comp_id, "match_id": f["match_id"], "home": f["home"], "away": f["away"]})
				continue
			if career.submit_result(comp_id, MatchSimulator.result(career.db, f, hash([season, "continental"]))) == "":
				out["played"] += 1
				progressed = true
				if mine:
					out["auto_played"].append(f["match_id"])
		if not progressed:
			break
	return out


## Season end: everything still open is played out; returns the champion id ("" if there was no cup).
func finish(career: CareerState) -> String:
	var c := competition(career)
	if c == null:
		return ""
	for _guard in 400:
		var pending := c.pending_fixtures()
		if pending.is_empty():
			break
		for f in pending:
			career.submit_result(comp_id, MatchSimulator.result(career.db, f, hash([season, "continental", "end"])))
	last_champion = c.champion_id
	return last_champion


func to_dict() -> Dictionary:
	return {"season": season, "comp_id": comp_id, "last_champion": last_champion}


static func from_dict(d: Dictionary) -> ContinentalCup:
	var c := ContinentalCup.new()
	c.season = int(d.get("season", 1))
	c.comp_id = str(d.get("comp_id", ""))
	c.last_champion = str(d.get("last_champion", ""))
	return c
