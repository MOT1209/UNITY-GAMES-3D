class_name Competition
extends RefCounted

## One competition (Phase T8): league, knockout cup, or groups → knockout.
## Results come only from `MatchResult`s for fixtures this competition
## generated; each fixture can be played once. Knockout rounds are created
## automatically when the previous round is complete.

enum Type { LEAGUE, KNOCKOUT, GROUP_KNOCKOUT }

var id: String = ""
var comp_name: String = ""
var type: Type = Type.LEAGUE
var team_ids: Array = []
var rules: Dictionary = {"win": 3, "draw": 1, "third_place": false, "double": true, "groups": 0}
var fixtures: Array = []          # {match_id, stage, round, home, away, played}
var results: Dictionary = {}      # match_id -> MatchResult dict
var tables: Dictionary = {}       # "main" or "A","B",.. -> LeagueTable
var groups: Dictionary = {}       # group name -> [team ids]
var ko_round: int = 0
var ko_teams: Array = []          # participants of the current knockout round
var stage: String = "league"      # league | groups | knockout | finished
var champion_id: String = ""
var runner_up_id: String = ""
var third_id: String = ""
var history: Array = []           # [{season, champion, runner_up}]
var season: int = 1
## Derived lookup data over `fixtures` (never saved, rebuilt on demand): fixture by match id, number of unplayed fixtures
## per stage and per stage+round, the first index that may still be unplayed and the highest round number. `fixtures`
## is append-only and `played` only changes in `submit_result`, so a changed fixture count is the only reason to rebuild.
var _index: Dictionary = {}
var _unplayed_stage: Dictionary = {}
var _unplayed_round: Dictionary = {}
var _indexed_count: int = -1
var _cursor: int = 0
var _max_round: int = 1


# --- factories --------------------------------------------------------------------

static func create_league(p_id: String, p_name: String, teams: Array, double_round: bool = true, cycles: int = 0) -> Competition:
	var c := Competition.new()
	c.id = p_id
	c.comp_name = p_name
	c.type = Type.LEAGUE
	c.team_ids = teams.duplicate()
	c.rules["double"] = double_round
	c.rules["cycles"] = cycles if cycles > 0 else (2 if double_round else 1)
	c.stage = "league"
	c.tables["main"] = LeagueTable.new(teams, c.rules["win"], c.rules["draw"])
	c._add_round_robin("league", "main", teams, double_round)
	return c


static func create_knockout(p_id: String, p_name: String, teams: Array, third_place: bool = false) -> Competition:
	var c := Competition.new()
	c.id = p_id
	c.comp_name = p_name
	c.type = Type.KNOCKOUT
	c.team_ids = teams.duplicate()
	c.rules["third_place"] = third_place
	c.stage = "knockout"
	c._start_knockout(teams)
	return c


## `group_count` must be even and divide the team count; the top 2 of each
## group advance (crossing groups: A1-B2, B1-A2, C1-D2, ...).
static func create_group_knockout(p_id: String, p_name: String, teams: Array,
		group_count: int, third_place: bool = false) -> Competition:
	var c := Competition.new()
	c.id = p_id
	c.comp_name = p_name
	c.type = Type.GROUP_KNOCKOUT
	c.team_ids = teams.duplicate()
	c.rules["third_place"] = third_place
	c.rules["groups"] = group_count
	c.stage = "groups"
	var names := "ABCDEFGH"
	for g in group_count:
		c.groups[names[g]] = []
	for i in teams.size():
		c.groups[names[i % group_count]].append(teams[i])
	for gname in c.groups:
		c.tables[gname] = LeagueTable.new(c.groups[gname], c.rules["win"], c.rules["draw"])
		c._add_round_robin("group", gname, c.groups[gname], false)
	return c


## Returns "" when the parameters make a valid competition.
static func validate_setup(type_id: Type, teams: Array, group_count: int = 0) -> String:
	var unique := {}
	for t in teams:
		if unique.has(t):
			return "team '%s' registered twice" % t
		unique[t] = true
	if teams.size() < 2:
		return "at least 2 teams are required"
	if type_id == Type.GROUP_KNOCKOUT:
		if group_count < 2 or group_count > 8 or group_count % 2 != 0:
			return "group count must be an even number from 2 to 8"
		if teams.size() % group_count != 0 or teams.size() / group_count < 3:
			return "teams must split evenly into groups of at least 3"
		var advancers := group_count * 2
		if advancers & (advancers - 1) != 0:
			return "number of qualifiers must be a power of two"
	return ""


# --- fixture creation ----------------------------------------------------------------

func _add_round_robin(stage_name: String, group: String, teams: Array, double_round: bool) -> void:
	var rounds := FixtureGenerator.round_robin(teams, double_round)
	# Phase K2: a small league can play its double round robin twice (4 meetings: 8 clubs -> 28 rounds) so a 46-week
	# season has no long empty stretches.
	if int(rules.get("cycles", 2)) >= 4 and double_round:
		rounds = rounds + FixtureGenerator.round_robin(teams, true)
	for r in rounds.size():
		for m in rounds[r].size():
			fixtures.append({"match_id": "%s_%s%s_r%02d_m%02d" % [id, stage_name, group if group != "main" else "", r + 1, m + 1],
					"stage": stage_name, "group": group, "round": r + 1,
					"home": rounds[r][m]["home"], "away": rounds[r][m]["away"], "played": false})


func _add_ko_fixture(kind: String, home: String, away: String, index: int) -> void:
	fixtures.append({"match_id": "%s_ko%02d_%s%02d" % [id, ko_round, kind, index],
			"stage": kind, "group": "", "round": ko_round, "home": home, "away": away, "played": false})


func _start_knockout(teams: Array) -> void:
	ko_round = 1
	var n := teams.size()
	var size := 1
	while size < n:
		size *= 2
	var byes := size - n
	var bye_teams := teams.slice(0, byes)
	var playing := teams.slice(byes)
	ko_teams = bye_teams.duplicate()     # these already count as round-1 winners
	var count := playing.size() / 2
	for i in count:
		_add_ko_fixture("ko", playing[i], playing[playing.size() - 1 - i], i + 1)


func _start_knockout_pairs(pairs: Array) -> void:
	ko_round = 1
	ko_teams = []
	for i in pairs.size():
		_add_ko_fixture("ko", pairs[i][0], pairs[i][1], i + 1)


# --- results --------------------------------------------------------------------------

func _ensure_index() -> void:
	if _indexed_count == fixtures.size():
		return
	_index.clear()
	_unplayed_stage.clear()
	_unplayed_round.clear()
	_cursor = 0
	_max_round = 1
	for f: Dictionary in fixtures:
		if not _index.has(f["match_id"]):        # a duplicated id resolves to its first fixture, as the old linear search did
			_index[f["match_id"]] = f
		_max_round = maxi(_max_round, int(f["round"]))
		if not f["played"]:
			_unplayed_stage[f["stage"]] = int(_unplayed_stage.get(f["stage"], 0)) + 1
			var rk := "%s|%d" % [f["stage"], int(f["round"])]
			_unplayed_round[rk] = int(_unplayed_round.get(rk, 0)) + 1
	_indexed_count = fixtures.size()


func get_fixture(match_id: String) -> Dictionary:
	_ensure_index()
	return _index.get(match_id, {})


## Highest round number of any fixture (the number of rounds of a league).
func max_round() -> int:
	_ensure_index()
	return _max_round


## Unplayed fixtures of the current stage (what the game should play next), in fixture order.
func pending_fixtures() -> Array:
	_ensure_index()
	while _cursor < fixtures.size() and fixtures[_cursor]["played"]:
		_cursor += 1                                  # `played` never goes back to false, so everything before is done
	var out: Array = []
	for i in range(_cursor, fixtures.size()):
		var f: Dictionary = fixtures[i]
		if not f["played"]:
			out.append(f)
	return out


func is_finished() -> bool:
	return stage == "finished"


## Records a result. Returns "" or an error text; invalid/duplicate results
## change nothing.
func submit_result(r: MatchResult) -> String:
	var problems := r.validate()
	if not problems.is_empty():
		return problems[0]
	var f := get_fixture(r.match_id)
	if f.is_empty():
		return "unknown match '%s'" % r.match_id
	if f["played"]:
		return "match '%s' already played" % r.match_id
	if f["home"] != r.home_id or f["away"] != r.away_id:
		return "result teams do not match fixture '%s'" % r.match_id
	var is_ko: bool = f["stage"] == "ko" or f["stage"] == "third"
	if is_ko and r.winner_id() == "":
		return "knockout match needs a winner (penalties after a draw)"
	if not is_ko:
		var key: String = f["group"] if f["group"] != "" else "main"
		var err := (tables[key] as LeagueTable).apply_result(r)
		if err != "":
			return err
	f["played"] = true
	_unplayed_stage[f["stage"]] = int(_unplayed_stage.get(f["stage"], 1)) - 1
	var rk := "%s|%d" % [f["stage"], int(f["round"])]
	_unplayed_round[rk] = int(_unplayed_round.get(rk, 1)) - 1
	results[r.match_id] = r.to_dict()
	_advance()
	return ""


func _stage_done(stage_name: String, round_no: int = -1) -> bool:
	_ensure_index()
	if round_no < 0:
		return int(_unplayed_stage.get(stage_name, 0)) == 0
	return int(_unplayed_round.get("%s|%d" % [stage_name, round_no], 0)) == 0


func _advance() -> void:
	match stage:
		"league":
			if _stage_done("league"):
				var rk := (tables["main"] as LeagueTable).ranking()
				champion_id = rk[0]["team_id"]
				runner_up_id = rk[1]["team_id"] if rk.size() > 1 else ""
				_finish()
		"groups":
			if _stage_done("group"):
				_start_knockout_from_groups()
		"knockout":
			_advance_knockout()


func _start_knockout_from_groups() -> void:
	stage = "knockout"
	var names: Array = groups.keys()
	names.sort()
	var firsts := {}
	var seconds := {}
	for g in names:
		var rk := (tables[g] as LeagueTable).ranking()
		firsts[g] = rk[0]["team_id"]
		seconds[g] = rk[1]["team_id"]
	var pairs: Array = []
	for i in range(0, names.size(), 2):
		pairs.append([firsts[names[i]], seconds[names[i + 1]]])
		pairs.append([firsts[names[i + 1]], seconds[names[i]]])
	_start_knockout_pairs(pairs)


func _round_fixtures(kind_filter: Array) -> Array:
	return fixtures.filter(func(f: Dictionary) -> bool: return f["round"] == ko_round and f["stage"] in kind_filter)


func _advance_knockout() -> void:
	if not _stage_done("ko", ko_round) or not _stage_done("third", ko_round):
		return
	var matches := _round_fixtures(["ko"])
	var winners: Array = ko_teams.duplicate()
	var losers: Array = []
	for f in matches:
		var res := MatchResult.from_dict(results[f["match_id"]])
		winners.append(res.winner_id())
		losers.append(res.loser_id())
	var was_final: bool = winners.size() == 1 and matches.size() == 1
	if was_final:
		champion_id = winners[0]
		runner_up_id = losers[0]
		for f in _round_fixtures(["third"]):
			third_id = MatchResult.from_dict(results[f["match_id"]]).winner_id()
		_finish()
		return
	_next_knockout_round(winners, losers)


func _next_knockout_round(winners: Array, losers: Array = []) -> void:
	ko_round += 1
	ko_teams = []
	var list := winners
	var n := list.size()
	var count := n / 2
	for i in count:
		_add_ko_fixture("ko", list[i], list[n - 1 - i], i + 1)
	# Third-place match when the next round is the final and two semi-final losers exist.
	if n == 2 and bool(rules["third_place"]) and losers.size() == 2:
		_add_ko_fixture("third", losers[0], losers[1], 1)


func _finish() -> void:
	stage = "finished"
	history.append({"season": season, "champion": champion_id, "runner_up": runner_up_id,
			"third": third_id})


# --- queries ----------------------------------------------------------------------------

func standings(group: String = "main") -> Array:
	if not tables.has(group):
		return []
	return (tables[group] as LeagueTable).ranking()


## Knockout bracket for the UI: rounds → [{match_id, home, away, played, winner}].
func bracket() -> Array:
	var rounds: Dictionary = {}
	for f in fixtures:
		if f["stage"] == "ko" or f["stage"] == "third":
			if not rounds.has(f["round"]):
				rounds[f["round"]] = []
			var winner := ""
			if f["played"]:
				winner = MatchResult.from_dict(results[f["match_id"]]).winner_id()
			rounds[f["round"]].append({"match_id": f["match_id"], "home": f["home"],
					"away": f["away"], "played": f["played"], "winner": winner, "kind": f["stage"]})
	var keys: Array = rounds.keys()
	keys.sort()
	return keys.map(func(k: Variant) -> Array: return rounds[k])


func awards() -> Dictionary:
	var out := {"champion": champion_id, "runner_up": runner_up_id}
	if third_id != "":
		out["third"] = third_id
	if type == Type.LEAGUE and stage == "finished":
		var best := ""
		var best_gf := -1
		for row in (tables["main"] as LeagueTable).rows.values():
			if row["gf"] > best_gf or (row["gf"] == best_gf and str(row["team_id"]) < best):
				best_gf = row["gf"]
				best = row["team_id"]
		out["best_attack"] = best
	return out


## Promotion/relegation between two leagues: returns the new team lists.
static func promotion_relegation(upper: Competition, lower: Competition, count: int) -> Dictionary:
	var up_rank := upper.standings()
	var low_rank := lower.standings()
	var n := mini(count, mini(up_rank.size(), low_rank.size()))
	var relegated: Array = []
	var promoted: Array = []
	for i in n:
		relegated.append(up_rank[up_rank.size() - 1 - i]["team_id"])
		promoted.append(low_rank[i]["team_id"])
	var new_upper: Array = upper.team_ids.filter(func(t: String) -> bool: return not (t in relegated))
	new_upper.append_array(promoted)
	var new_lower: Array = lower.team_ids.filter(func(t: String) -> bool: return not (t in promoted))
	new_lower.append_array(relegated)
	return {"promoted": promoted, "relegated": relegated, "upper": new_upper, "lower": new_lower}


# --- persistence --------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var tbl := {}
	for k in tables:
		tbl[k] = (tables[k] as LeagueTable).to_dict()
	return {"id": id, "name": comp_name, "type": Type.keys()[type], "teams": team_ids.duplicate(),
			"rules": rules.duplicate(), "fixtures": fixtures.duplicate(true), "results": results.duplicate(true),
			"tables": tbl, "groups": groups.duplicate(true), "ko_round": ko_round,
			"ko_teams": ko_teams.duplicate(), "stage": stage, "champion": champion_id,
			"runner_up": runner_up_id, "third": third_id, "history": history.duplicate(true), "season": season}


static func from_dict(d: Dictionary) -> Competition:
	var c := Competition.new()
	c.id = str(d.get("id", ""))
	c.comp_name = str(d.get("name", ""))
	var t := str(d.get("type", "LEAGUE"))
	c.type = Type[t] if Type.has(t) else Type.LEAGUE
	c.team_ids = (d.get("teams", []) as Array).duplicate()
	c.rules = PlayerData._restore_ints((d.get("rules", c.rules) as Dictionary).duplicate())
	c.fixtures = (d.get("fixtures", []) as Array).duplicate(true)
	for f in c.fixtures:
		f["round"] = int(f["round"])
	# JSON turns whole numbers into floats; rebuild each result so goals stay ints.
	c.results = {}
	for mid in (d.get("results", {}) as Dictionary):
		c.results[mid] = MatchResult.from_dict(d["results"][mid]).to_dict()
	for k in (d.get("tables", {}) as Dictionary):
		c.tables[k] = LeagueTable.from_dict(d["tables"][k])
	c.groups = (d.get("groups", {}) as Dictionary).duplicate(true)
	c.ko_round = int(d.get("ko_round", 0))
	c.ko_teams = (d.get("ko_teams", []) as Array).duplicate()
	c.stage = str(d.get("stage", "league"))
	c.champion_id = str(d.get("champion", ""))
	c.runner_up_id = str(d.get("runner_up", ""))
	c.third_id = str(d.get("third", ""))
	c.history = PlayerData._restore_ints((d.get("history", []) as Array).duplicate(true))
	c.season = int(d.get("season", 1))
	return c
