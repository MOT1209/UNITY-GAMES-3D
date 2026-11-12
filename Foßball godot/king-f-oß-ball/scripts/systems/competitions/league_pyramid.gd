class_name LeaguePyramid
extends RefCounted

## One country's league system during a career: the divisions with their CURRENT members,
## one league `Competition` per division, the domestic cup, play-offs, the weekly calendar
## and the season rollover with promotion / relegation.
##
## Calendar (career weeks 1..CareerState.WEEKS_PER_SEASON = 46):
##   * league rounds are spread over weeks 1..LEAGUE_LAST_WEEK (44). Divisions with more rounds
##     than weeks (24 clubs = 46 rounds) play some midweek double rounds;
##   * cup round k is played in CUP_WEEKS[k - 1];
##   * play-offs (semi-finals, final) in weeks 45 and 46.
## Every fixture that does not involve the user's club is simulated in the week it is due
## (`MatchSimulator`). The user's own fixture stays pending during its week (play it in 3D or
## quick-sim it); if the week passes without it, it is simulated so the season never stalls.
## Rules: reserve teams can never be promoted into their parent club's division.

const LEAGUE_LAST_WEEK := 44
const PLAYOFF_WEEKS: Array[int] = [45, 46]
const CUP_WEEKS: Array[int] = [5, 11, 17, 23, 29, 35, 41, 43]
## Prize money per final league position: [tier1 first, tier1 step, tier2 first, tier2 step].
const PRIZE := {1: [40_000_000, 1_500_000], 2: [6_000_000, 200_000]}
const PARACHUTE := 20_000_000
const MIN_PRIZE := 500_000

var key := ""
var country := ""
var display_name := ""
var season := 1
var divisions: Array = []          # [{id, name, tier, promote, relegate, playoff, team_ids}]
var reserves: Dictionary = {}
var cup_def: Dictionary = {}
var comp: Dictionary = {}          # role -> competition id; roles: division id, "cup", "po:<division id>"
var history: Array = []            # one summary per finished season


static func create(def: LeagueDef, p_season: int = 1) -> LeaguePyramid:
	var p := LeaguePyramid.new()
	p.key = def.key
	p.country = def.country
	p.display_name = def.display_name
	p.season = p_season
	p.divisions = def.divisions.duplicate(true)
	p.reserves = def.reserves.duplicate()
	p.cup_def = def.cup.duplicate()
	return p


## Creates this season's competitions and adds them to `competitions` (id -> Competition).
func build_season(competitions: Dictionary, db: Node) -> void:
	comp.clear()
	for d in divisions:
		var cid := "%s_s%d" % [d["id"], season]
		var c := Competition.create_league(cid, "%s %d" % [d["name"], season], d["team_ids"], true)
		c.season = season
		competitions[cid] = c
		comp[d["id"]] = cid
	if not cup_def.is_empty():
		var cup_id := "%s_s%d" % [cup_def.get("id", key + "_cup"), season]
		var c := Competition.create_knockout(cup_id, "%s %d" % [cup_def.get("name", "Cup"), season], cup_seeding(db), false)
		c.season = season
		competitions[cup_id] = c
		comp["cup"] = cup_id


## Cup entrants strongest first (top tier, then reputation): `Competition` gives the byes
## of the first round to the first teams in the list.
func cup_seeding(db: Node) -> Array:
	var out: Array = []
	for d in divisions:
		var ids: Array = (d["team_ids"] as Array).duplicate()
		ids.sort_custom(func(a: String, b: String) -> bool:
			var ra: int = db.get_team(a).reputation if db.get_team(a) != null else 0
			var rb: int = db.get_team(b).reputation if db.get_team(b) != null else 0
			return ra > rb if ra != rb else a < b)
		out.append_array(ids)
	return out


func division_of(team_id: String) -> Dictionary:
	for d in divisions:
		if team_id in d["team_ids"]:
			return d
	return {}


func competition_ids() -> Array:
	return comp.values()


# --- calendar --------------------------------------------------------------------------------------

## Career week in which fixture `f` of the competition playing `role` is due.
func week_of(role: String, c: Competition, f: Dictionary) -> int:
	var rnd := int(f["round"])
	if role == "cup":
		return CUP_WEEKS[mini(rnd, CUP_WEEKS.size()) - 1]
	if role.begins_with("po:"):
		return PLAYOFF_WEEKS[mini(rnd, PLAYOFF_WEEKS.size()) - 1]
	var total := 1
	for x in c.fixtures:
		total = maxi(total, int(x["round"]))
	if total <= 1:
		return 1
	return 1 + int(floor(float(rnd - 1) * float(LEAGUE_LAST_WEEK - 1) / float(total - 1)))


## Plays everything due by `week` except the user's fixtures of this very week.
## Returns {"played": int, "user_fixtures": [{competition_id, match_id, home, away}], "auto_played": [match ids]}.
func play_week(week: int, career: CareerState, user_team_id: String) -> Dictionary:
	var out := {"played": 0, "user_fixtures": [], "auto_played": []}
	_play_due(week, career, user_team_id, out)
	if week >= PLAYOFF_WEEKS[0]:
		if _create_playoffs(career):
			_play_due(week, career, user_team_id, out)
	return out


func _play_due(week: int, career: CareerState, user_team_id: String, out: Dictionary) -> void:
	for role in comp.keys():
		var cid: String = comp[role]
		var c: Competition = career.competitions.get(cid)
		if c == null:
			continue
		for f in c.pending_fixtures():
			var due := week_of(role, c, f)
			if due > week:
				continue
			var mine: bool = user_team_id != "" and (f["home"] == user_team_id or f["away"] == user_team_id)
			if mine and due == week:
				out["user_fixtures"].append({"competition_id": cid, "match_id": f["match_id"],
						"home": f["home"], "away": f["away"]})
				continue
			if career.submit_result(cid, MatchSimulator.result(career.db, f, hash([season, key]))) == "":
				out["played"] += 1
				if mine:
					out["auto_played"].append(f["match_id"])


## Creates the play-off knockouts once a division's league is complete. Returns true if any was created.
func _create_playoffs(career: CareerState) -> bool:
	var created := false
	for d in divisions:
		var po: Dictionary = d["playoff"]
		var role: String = "po:" + d["id"]
		if po.is_empty() or comp.has(role):
			continue
		var league: Competition = career.competitions.get(comp[d["id"]])
		if league == null or not league.is_finished():
			continue
		var teams := _playoff_teams(d, league)
		if teams.size() < 2:
			continue
		var cid := "%s_po_s%d" % [d["id"], season]
		var c := Competition.create_knockout(cid, "%s play-off %d" % [d["name"], season], teams, false)
		c.season = season
		career.competitions[cid] = c
		comp[role] = cid
		created = true
	return created


## Eligible teams in places from..to (reserve teams skipped, next eligible team moves up).
func _playoff_teams(d: Dictionary, league: Competition) -> Array:
	var po: Dictionary = d["playoff"]
	var eligible := _eligible_ranking(d, league)
	var start := int(d["promote"])
	var count := int(po["to"]) - int(po["from"]) + 1
	return eligible.slice(start, start + count)


## Standings of a division without the teams that may not go up (reserves of an upper club).
func _eligible_ranking(d: Dictionary, league: Competition) -> Array:
	var upper := _division_above(d)
	var out: Array = []
	for row in league.standings():
		var t: String = row["team_id"]
		if reserves.has(t) and not upper.is_empty() and reserves[t] in upper["team_ids"]:
			continue
		out.append(t)
	return out


func _division_above(d: Dictionary) -> Dictionary:
	for x in divisions:
		if int(x["tier"]) == int(d["tier"]) - 1:
			return x
	return {}


# --- season end ---------------------------------------------------------------------------------

## Finishes every open fixture (simulated), applies promotion / relegation, pays prize money,
## stores a summary in `history`, starts the next season. Returns the summary.
func end_season(career: CareerState) -> Dictionary:
	_complete_all(career)
	var summary := {"season": season, "country": country, "key": key, "champions": {}, "tables": {},
			"promoted": [], "relegated": [], "playoff_winners": {}, "cup_winner": ""}
	for d in divisions:
		var league: Competition = career.competitions[comp[d["id"]]]
		var order: Array = league.standings().map(func(r: Dictionary) -> String: return r["team_id"])
		summary["tables"][d["id"]] = order
		summary["champions"][d["id"]] = league.champion_id
		_pay_prizes(career, d, order)
	if comp.has("cup"):
		summary["cup_winner"] = (career.competitions[comp["cup"]] as Competition).champion_id
	# moves between each pair of adjacent tiers
	var moves: Array = []
	for i in range(1, divisions.size()):
		var upper: Dictionary = divisions[i - 1]
		var lower: Dictionary = divisions[i]
		var up_order: Array = summary["tables"][upper["id"]]
		var relegated: Array = up_order.slice(up_order.size() - int(upper["relegate"]))
		var lower_league: Competition = career.competitions[comp[lower["id"]]]
		var eligible := _eligible_ranking(lower, lower_league)
		var promoted: Array = eligible.slice(0, int(lower["promote"]))
		if comp.has("po:" + lower["id"]):
			var winner: String = (career.competitions[comp["po:" + lower["id"]]] as Competition).champion_id
			if winner != "" and not (winner in promoted):
				promoted.append(winner)
				summary["playoff_winners"][lower["id"]] = winner
		# Never break the division sizes: as many go up as come down.
		var n := mini(relegated.size(), promoted.size())
		relegated = relegated.slice(relegated.size() - n)
		promoted = promoted.slice(0, n)
		moves.append([upper, lower, promoted, relegated])
		summary["promoted"].append_array(promoted)
		summary["relegated"].append_array(relegated)
		for t in relegated:
			if int(upper["tier"]) == 1 and career.ledgers.has(t):
				(career.ledgers[t] as FinanceLedger).record("competition_reward", PARACHUTE, "Parachute payment", career.week)
	for m in moves:
		var upper: Dictionary = m[0]
		var lower: Dictionary = m[1]
		upper["team_ids"] = (upper["team_ids"] as Array).filter(func(t: String) -> bool: return not (t in m[3])) + m[2]
		lower["team_ids"] = (lower["team_ids"] as Array).filter(func(t: String) -> bool: return not (t in m[2])) + m[3]
		(upper["team_ids"] as Array).sort()
		(lower["team_ids"] as Array).sort()
	history.append(summary)
	for cid in comp.values():
		career.competitions.erase(cid)
	season += 1
	build_season(career.competitions, career.db)
	return summary


func _complete_all(career: CareerState) -> void:
	for _i in 64:                      # knockouts add rounds as they go; bounded loop
		var left := 0
		_create_playoffs(career)
		for role in comp.keys():
			var c: Competition = career.competitions.get(comp[role])
			if c == null:
				continue
			for f in c.pending_fixtures():
				left += 1
				career.submit_result(comp[role], MatchSimulator.result(career.db, f, hash([season, key, "end"])))
		var open := comp.values().any(func(cid: String) -> bool:
			return career.competitions.has(cid) and not (career.competitions[cid] as Competition).is_finished())
		var po_missing := divisions.any(func(d: Dictionary) -> bool:
			return not (d["playoff"] as Dictionary).is_empty() and not comp.has("po:" + d["id"]))
		if left == 0 and not open and not po_missing:
			return


func _pay_prizes(career: CareerState, d: Dictionary, order: Array) -> void:
	var p: Array = PRIZE.get(int(d["tier"]), [MIN_PRIZE, 0])
	for i in order.size():
		var t: String = order[i]
		if career.ledgers.has(t):
			var amount := maxi(MIN_PRIZE, int(p[0]) - int(p[1]) * i)
			(career.ledgers[t] as FinanceLedger).record("competition_reward", amount,
					"%s: position %d" % [d["name"], i + 1], career.week)


# --- persistence --------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"key": key, "country": country, "name": display_name, "season": season,
			"divisions": divisions.duplicate(true), "reserves": reserves.duplicate(),
			"cup": cup_def.duplicate(), "comp": comp.duplicate(), "history": history.duplicate(true)}


static func from_dict(d: Dictionary) -> LeaguePyramid:
	var p := LeaguePyramid.new()
	p.key = str(d.get("key", ""))
	p.country = str(d.get("country", ""))
	p.display_name = str(d.get("name", p.country))
	p.season = int(d.get("season", 1))
	for dv in d.get("divisions", []):
		var div: Dictionary = (dv as Dictionary).duplicate(true)
		div["tier"] = int(div.get("tier", 0))
		div["promote"] = int(div.get("promote", 0))
		div["relegate"] = int(div.get("relegate", 0))
		div["team_ids"] = (div.get("team_ids", []) as Array).map(func(x: Variant) -> String: return str(x))
		var po: Dictionary = div.get("playoff", {})
		div["playoff"] = {} if po.is_empty() else {"from": int(po["from"]), "to": int(po["to"]), "spots": int(po["spots"])}
		p.divisions.append(div)
	p.reserves = (d.get("reserves", {}) as Dictionary).duplicate()
	p.cup_def = (d.get("cup", {}) as Dictionary).duplicate()
	p.comp = (d.get("comp", {}) as Dictionary).duplicate()
	p.history = (d.get("history", []) as Array).duplicate(true)
	return p
