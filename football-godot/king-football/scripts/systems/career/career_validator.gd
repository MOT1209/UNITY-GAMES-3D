class_name CareerValidator
extends RefCounted

## Integrity rules of a career (P1). Two layers:
##   * `check_shape(dict)`: pure-dictionary type check of a saved career block. It guarantees that `CareerState.from_dict` cannot
##     crash on a damaged file (GDScript has no try / catch), so a bad save is refused with a message instead.
##   * `validate(career)`: semantic rules over the live state - unique ids, club / player relations, contracts, transfers, ledgers,
##     competitions, league tables recomputed from their results, the calendar, statistics.
## Both return {"errors": [...], "warnings": [...]}. Errors are defects that can crash play or corrupt the season (a competition
## that can never finish, a table that disagrees with its results); warnings are inconsistencies that do not stop play
## (a counter that disagrees with another counter). Loading refuses errors and reports warnings; the tests accept neither.
## `PlayerData` and `ClubData` (`TeamData`) stay the only sources of truth: nothing here stores a copy of them.

const NUM := "num"
const STR := "str"
const BOOL := "bool"
const ARR := "arr"
const DICT := "dict"

const _LEDGER := {"entries": ["arr_of", {"id": NUM, "week": NUM, "category": STR, "amount": NUM, "balance_after": NUM}],
		"opening": NUM, "balance": NUM, "transfer_budget": NUM, "wage_budget": NUM, "next_id": NUM}
const _FIXTURE := {"match_id": STR, "stage": STR, "round": NUM, "home": STR, "away": STR, "played": BOOL}
const _ROW := {"team_id": STR, "played": NUM, "won": NUM, "drawn": NUM, "lost": NUM, "gf": NUM, "ga": NUM, "gd": NUM, "points": NUM}
const _COMPETITION := {"id": STR, "name": STR, "type": STR, "teams": ["arr_of", STR], "rules": DICT,
		"fixtures": ["arr_of", _FIXTURE],
		"results": ["dict_of", {"match_id": STR, "home": STR, "away": STR, "hg": NUM, "ag": NUM}],
		"tables": ["dict_of", {"win": NUM, "draw": NUM, "rows": ["dict_of", _ROW], "processed": ["arr_of", STR]}],
		"groups": DICT, "ko_round": NUM, "ko_teams": ARR, "stage": STR, "champion": STR, "runner_up": STR, "third": STR,
		"history": ["arr_of", DICT], "season": NUM}
const _DIVISION := {"id": STR, "name": STR, "tier": NUM, "promote": NUM, "relegate": NUM, "team_ids": ["arr_of", STR], "playoff": DICT}
const _PYRAMID := {"key": STR, "country": STR, "season": NUM, "divisions": ["arr_of", _DIVISION], "reserves": DICT, "cup": DICT,
		"comp": DICT, "history": ["arr_of", DICT]}
const _SHAPE := {"club_id": STR, "season": NUM, "week": NUM,
		"ledgers": ["dict_of", _LEDGER], "competitions": ["dict_of", _COMPETITION], "pyramids": ["dict_of", _PYRAMID],
		"market": {"history": ["arr_of", {"id": NUM, "week": NUM, "fee": NUM, "salary": NUM, "years": NUM}], "next_id": NUM},
		"club_history": ["arr_of", DICT], "released": ARR, "match_log": ["arr_of", DICT],
		"player_stats": ["dict_of", DICT], "season_stats": ["dict_of", ["dict_of", DICT]], "world_stats": ["dict_of", DICT],
		"world_stats_legacy": BOOL, "club_levels": ["dict_of", NUM], "yellow_counts": ["dict_of", NUM], "events": ["arr_of", DICT], "award_history": ["arr_of", DICT],
		"manager": {"history": ["arr_of", DICT], "objective": DICT}, "continental": DICT}


# --- layer 1: the shape of a saved career block -----------------------------------------------------

## Type-checks a career dictionary as written by `CareerState.to_dict()`. Absent fields are fine (old saves); a field that is
## present with the wrong type, or a record missing a field `from_dict` reads directly, is an error.
static func check_shape(d: Variant) -> Array[String]:
	var errors: Array[String] = []
	if typeof(d) != TYPE_DICTIONARY:
		errors.append("career block is not an object")
		return errors
	_shape(d, _SHAPE, "career", errors)
	return errors


static func _type_ok(v: Variant, kind: String) -> bool:
	match kind:
		NUM:
			return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT
		STR:
			return typeof(v) == TYPE_STRING or typeof(v) == TYPE_STRING_NAME
		BOOL:
			return typeof(v) == TYPE_BOOL
		ARR:
			return typeof(v) == TYPE_ARRAY
		DICT:
			return typeof(v) == TYPE_DICTIONARY
	return true


## Checks `v` against a schema node: a kind string, ["arr_of" | "dict_of", node], or a dictionary of field -> node.
static func _node(v: Variant, node: Variant, path: String, errors: Array[String]) -> void:
	if errors.size() >= 20:
		return
	if node is String:
		if not _type_ok(v, node):
			errors.append("%s should be %s" % [path, node])
	elif node is Array:
		if node[0] == "arr_of":
			if typeof(v) != TYPE_ARRAY:
				errors.append("%s should be a list" % path)
				return
			for i in (v as Array).size():
				_node(v[i], node[1], "%s[%d]" % [path, i], errors)
				if errors.size() >= 20:
					return
		else:
			if typeof(v) != TYPE_DICTIONARY:
				errors.append("%s should be an object" % path)
				return
			for k in (v as Dictionary):
				_node(v[k], node[1], "%s/%s" % [path, str(k)], errors)
				if errors.size() >= 20:
					return
	elif node is Dictionary:
		if typeof(v) != TYPE_DICTIONARY:
			errors.append("%s should be an object" % path)
			return
		_shape(v, node, path, errors)


## Fields named in `schema` are optional at the top level of a block but REQUIRED inside list / map records.
static func _shape(d: Dictionary, schema: Dictionary, path: String, errors: Array[String]) -> void:
	var top := path == "career"
	for field in schema:
		if not d.has(field):
			if not top and not (field in ["name", "history", "groups", "rules", "playoff", "reserves", "cup", "comp", "description",
					"ko_round", "ko_teams", "stage", "champion", "runner_up", "third", "season", "processed", "win", "draw", "next_id",
					"opening", "balance", "transfer_budget", "wage_budget", "club_history"]):
				errors.append("%s is missing '%s'" % [path, field])
			continue
		_node(d[field], schema[field], "%s/%s" % [path, field], errors)


# --- layer 2: the semantics of a live career ---------------------------------------------------------

static func _new() -> Dictionary:
	return {"errors": [] as Array[String], "warnings": [] as Array[String]}


static func _err(r: Dictionary, msg: String) -> void:
	if (r["errors"] as Array).size() < 60:
		(r["errors"] as Array).append(msg)


static func _warn(r: Dictionary, msg: String) -> void:
	if (r["warnings"] as Array).size() < 60:
		(r["warnings"] as Array).append(msg)


## Full audit of `c` against its database. `deep` also validates every player record (slower, ~100 ms for 8000 players).
static func validate(c: CareerState, deep: bool = true) -> Dictionary:
	var r := _new()
	var db: Node = c.db
	_check_world(c, db, r, deep)
	_check_ledgers(c, db, r)
	_check_market(c, db, r)
	for cid in c.competitions:
		_check_competition(c.competitions[cid] as Competition, str(cid), db, r)
	_check_pyramids(c, db, r)
	_check_stale(c, r)
	_check_calendar(c, r)
	_check_stats(c, db, r)
	_check_misc(c, db, r)
	return r


static func _check_world(c: CareerState, db: Node, r: Dictionary, deep: bool) -> void:
	for pid in db.players:
		var p: PlayerData = db.players[pid]
		if p.id != pid:
			_err(r, "player stored under '%s' has id '%s'" % [pid, p.id])
		if deep:
			for e in p.validate():
				_err(r, "player: " + e)
	var seen := {}                                       # player id -> club id: a player is in exactly one squad
	for tid in db.teams:
		var t: TeamData = db.teams[tid]
		if t.id != tid:
			_err(r, "club stored under '%s' has id '%s'" % [tid, t.id])
		var names := {}
		for pid in t.squad_ids:
			if names.has(pid):
				_err(r, "club '%s' lists player '%s' twice" % [tid, pid])
			names[pid] = true
			var p: PlayerData = db.players.get(pid)
			if p == null:
				_err(r, "club '%s' squad references missing player '%s'" % [tid, pid])
				continue
			if seen.has(pid):
				_err(r, "player '%s' is in two squads ('%s' and '%s')" % [pid, seen[pid], tid])
			seen[pid] = tid
			if p.team_id != tid:
				_err(r, "player '%s' is in the squad of '%s' but says team '%s'" % [pid, tid, p.team_id])
			if p.status == PlayerData.Status.RETIRED:
				_err(r, "retired player '%s' still holds a place at '%s'" % [pid, tid])
			if p.loan_parent != "":
				if not db.teams.has(p.loan_parent):
					_err(r, "player '%s' is on loan from unknown club '%s'" % [pid, p.loan_parent])
				elif p.loan_parent == tid:
					_err(r, "player '%s' is on loan to his own club" % pid)
				elif (db.teams[p.loan_parent] as TeamData).squad_ids.has(pid):
					_err(r, "loaned player '%s' is in the squads of both clubs" % pid)
			elif p.contract_years < 1:
				_warn(r, "player '%s' of '%s' has contract_years %d" % [pid, tid, p.contract_years])
			if p.salary < 0 or p.transfer_value < 0:
				_err(r, "player '%s' has a negative salary or value" % pid)
	for pid in db.players:
		var p: PlayerData = db.players[pid]
		if p.team_id != "" and not seen.has(pid) and p.status != PlayerData.Status.YOUTH and p.status != PlayerData.Status.RETIRED:
			_warn(r, "player '%s' says team '%s' but is in no first-team squad" % [pid, p.team_id])
	if c.club_id != "" and (db.teams.get(c.club_id) == null or (db.teams[c.club_id] as TeamData).category != TeamData.Category.CLUB):
		_err(r, "the managed club '%s' does not exist" % c.club_id)


static func _check_ledgers(c: CareerState, db: Node, r: Dictionary) -> void:
	for tid in c.ledgers:
		var l: FinanceLedger = c.ledgers[tid]
		if not db.teams.has(tid):
			_err(r, "ledger for unknown club '%s'" % tid)
		if l.team_id != tid:
			_err(r, "ledger stored under '%s' belongs to '%s'" % [tid, l.team_id])
		if not l.is_consistent():                      # play continues (the finance screen shows "audit mismatch"): a warning
			_warn(r, "ledger of '%s' does not add up (opening + entries != balance)" % tid)
		var ids := {}
		for e in l.entries:
			if ids.has(e["id"]):
				_err(r, "ledger of '%s' has entry id %d twice" % [tid, e["id"]])
				break
			ids[e["id"]] = true
		if l.next_entry_id <= (ids.keys().max() if not ids.is_empty() else 0):
			_err(r, "ledger of '%s' would reuse an entry id" % tid)
	if c.club_id != "" and not c.ledgers.has(c.club_id):
		_err(r, "the managed club has no ledger")
	for t: TeamData in db.list_teams(TeamData.Category.CLUB):
		if not c.ledgers.has(t.id):
			_warn(r, "club '%s' has no ledger" % t.id)


static func _check_market(c: CareerState, db: Node, r: Dictionary) -> void:
	var ids := {}
	var top := 0
	for h in c.market.history:
		if ids.has(h["id"]):
			_err(r, "transfer history has id %d twice" % h["id"])
		ids[h["id"]] = true
		top = maxi(top, int(h["id"]))
		if not db.players.has(h.get("player_id", "")):
			_warn(r, "transfer %d is about unknown player '%s'" % [h["id"], h.get("player_id", "")])
		for side in ["from", "to"]:
			var tid := str(h.get(side, ""))
			if tid != "" and not db.teams.has(tid) and not (TransferMarket.is_external(tid) and c.market.externals.has(tid)):
				_warn(r, "transfer %d names unknown club '%s'" % [h["id"], tid])
		if int(h["fee"]) < 0 or int(h["salary"]) < 0:
			_err(r, "transfer %d has a negative fee or salary" % h["id"])
	if c.market.next_history_id <= top:
		_err(r, "transfer history would reuse an id")


static func _check_competition(comp: Competition, key: String, db: Node, r: Dictionary) -> void:
	var tag := "competition '%s'" % key
	if comp.id != key:
		_err(r, "%s is stored under another id ('%s')" % [tag, comp.id])
	var members := {}
	for t in comp.team_ids:
		if members.has(t):
			_err(r, "%s registers team '%s' twice" % [tag, t])
		members[t] = true
		if not db.teams.has(t):
			_err(r, "%s has unknown team '%s'" % [tag, t])
	var by_id := {}
	var played := 0
	var pairs := {}
	for f: Dictionary in comp.fixtures:
		var mid: String = f["match_id"]
		if by_id.has(mid):
			_err(r, "%s has match id '%s' twice" % [tag, mid])
			continue
		by_id[mid] = f
		if f["home"] == f["away"]:
			_err(r, "%s: '%s' pairs a team with itself" % [tag, mid])
		if not members.has(f["home"]) or not members.has(f["away"]):
			_err(r, "%s: '%s' uses a team that is not entered" % [tag, mid])
		if f["played"]:
			played += 1
			if not comp.results.has(mid):
				_err(r, "%s: '%s' is marked played but has no result" % [tag, mid])
		elif comp.results.has(mid):
			_err(r, "%s: '%s' has a result but is not marked played" % [tag, mid])
		if comp.type == Competition.Type.LEAGUE:
			var pk := "%s>%s" % [f["home"], f["away"]]
			if pairs.has(pk):
				_err(r, "%s: %s is played twice at the same ground" % [tag, pk])
			pairs[pk] = true
	for mid in comp.results:
		var f: Dictionary = by_id.get(mid, {})
		if f.is_empty():
			_err(r, "%s has a result for unknown match '%s'" % [tag, mid])
			continue
		var res := MatchResult.from_dict(comp.results[mid])
		for e in res.validate():
			_err(r, "%s: result '%s': %s" % [tag, mid, e])
		if res.home_id != f["home"] or res.away_id != f["away"]:
			_err(r, "%s: result '%s' is for other teams than its fixture" % [tag, mid])
		if (f["stage"] == "ko" or f["stage"] == "third") and res.winner_id() == "":
			_err(r, "%s: knockout result '%s' has no winner" % [tag, mid])
	if played != comp.results.size():
		_err(r, "%s: %d played fixtures but %d results" % [tag, played, comp.results.size()])
	match comp.type:
		Competition.Type.LEAGUE:
			var n := comp.team_ids.size()
			var expected := n * (n - 1) if bool(comp.rules.get("double", true)) else n * (n - 1) / 2
			if comp.fixtures.size() != expected:
				_err(r, "%s has %d fixtures, a %d-team league needs %d" % [tag, comp.fixtures.size(), n, expected])
			if comp.stage == "finished" and played != comp.fixtures.size():
				_err(r, "%s is finished with %d unplayed fixtures" % [tag, comp.fixtures.size() - played])
			if comp.stage != "finished" and played == comp.fixtures.size() and not comp.fixtures.is_empty():
				_err(r, "%s has played everything but is not finished" % tag)
		_:
			if comp.stage == "finished" and comp.champion_id == "":
				_err(r, "%s is finished without a champion" % tag)
	if comp.stage == "finished" and comp.champion_id != "" and not members.has(comp.champion_id):
		_err(r, "%s: the champion '%s' is not an entrant" % [tag, comp.champion_id])
	_check_tables(comp, by_id, tag, r)


## The table of every league / group is recomputed from the results; it must equal the stored one exactly.
static func _check_tables(comp: Competition, by_id: Dictionary, tag: String, r: Dictionary) -> void:
	for group in comp.tables:
		var table: LeagueTable = comp.tables[group]
		var fresh := LeagueTable.new(table.rows.keys(), table.points_win, table.points_draw)
		var processed := 0
		for mid in comp.results:
			var f: Dictionary = by_id.get(mid, {})
			if f.is_empty() or f["stage"] == "ko" or f["stage"] == "third":
				continue
			if (f["group"] if f["group"] != "" else "main") != group:
				continue
			var res := MatchResult.from_dict(comp.results[mid])
			if fresh.apply_result(res) == "":
				processed += 1
		for tid in table.rows:
			var a: Dictionary = table.rows[tid]
			var b: Dictionary = fresh.rows.get(tid, {})
			for k in ["played", "won", "drawn", "lost", "gf", "ga", "gd", "points"]:
				if int(a.get(k, -1)) != int(b.get(k, -2)):
					_err(r, "%s: table row of '%s' has %s=%s but its results give %s" % [tag, tid, k, str(a.get(k)), str(b.get(k))])
					break
			if int(a["won"]) + int(a["drawn"]) + int(a["lost"]) != int(a["played"]) or int(a["gf"]) - int(a["ga"]) != int(a["gd"]):
				_err(r, "%s: table row of '%s' is not internally consistent" % [tag, tid])
		if table._processed.size() != processed:
			_err(r, "%s: table group '%s' recorded %d matches but the results hold %d" % [tag, group, table._processed.size(), processed])
		var gf := 0
		var ga := 0
		for tid in table.rows:
			gf += int(table.rows[tid]["gf"])
			ga += int(table.rows[tid]["ga"])
		if gf != ga:
			_err(r, "%s: goals for (%d) and against (%d) differ in group '%s'" % [tag, gf, ga, group])


## A competition of an earlier season that nothing refers to any more is a leak (memory and save size grow every season).
static func _check_stale(c: CareerState, r: Dictionary) -> void:
	var referenced := {}
	for k in c.pyramids:
		for cid in (c.pyramids[k] as LeaguePyramid).comp.values():
			referenced[cid] = true
	if c.continental != null:
		referenced[c.continental.comp_id] = true
	var rx := RegEx.new()
	rx.compile("_s(\\d+)$")
	for cid in c.competitions:
		var m := rx.search(str(cid))
		if m != null and int(m.get_string(1)) < c.season and not referenced.has(cid):
			_warn(r, "competition '%s' is from season %s but the career is in season %d and nothing refers to it" % [cid, m.get_string(1), c.season])


static func _check_pyramids(c: CareerState, db: Node, r: Dictionary) -> void:
	var club_home := {}                                      # club id -> pyramid key: one division in one league system
	for k in c.pyramids:
		var pyr: LeaguePyramid = c.pyramids[k]
		var tag := "league system '%s'" % k
		if pyr.season != c.season:
			_err(r, "%s is in season %d but the career is in season %d" % [tag, pyr.season, c.season])
		var div_ids := {}
		var def: LeagueDef = db.leagues.get(k) if db.get("leagues") != null else null
		for d in pyr.divisions:
			if div_ids.has(d["id"]):
				_err(r, "%s has division '%s' twice" % [tag, d["id"]])
			div_ids[d["id"]] = true
			for t in d["team_ids"]:
				if club_home.has(t):
					_err(r, "club '%s' is in two divisions ('%s' and '%s')" % [t, club_home[t], k])
				club_home[t] = k
				if not db.teams.has(t):
					_err(r, "%s division '%s' has unknown club '%s'" % [tag, d["id"], t])
			if def != null and def.division(d["id"]).has("team_ids") and (def.division(d["id"])["team_ids"] as Array).size() != (d["team_ids"] as Array).size():
				_err(r, "%s division '%s' changed size (%d, was %d)" % [tag, d["id"], (d["team_ids"] as Array).size(), (def.division(d["id"])["team_ids"] as Array).size()])
			var cid: String = pyr.comp.get(d["id"], "")
			var league: Competition = c.competitions.get(cid)
			if league == null:
				_err(r, "%s has no competition for division '%s'" % [tag, d["id"]])
				continue
			if league.type != Competition.Type.LEAGUE:
				_err(r, "%s: the competition of division '%s' is not a league" % [tag, d["id"]])
			var a := (d["team_ids"] as Array).duplicate()
			var b := league.team_ids.duplicate()
			a.sort()
			b.sort()
			if a != b and league.stage != "finished":
				_err(r, "%s: division '%s' and its league have different clubs" % [tag, d["id"]])
		for role in pyr.comp:
			if not c.competitions.has(pyr.comp[role]):
				_err(r, "%s role '%s' points at missing competition '%s'" % [tag, role, pyr.comp[role]])
	if not c.pyramids.is_empty() and c.club_id != "" and not club_home.has(c.club_id):
		_warn(r, "the managed club '%s' plays in no division" % c.club_id)


## No match may be forgotten by the calendar: everything due before this week, and everything due this week that does not
## involve the managed club, has been played.
static func _check_calendar(c: CareerState, r: Dictionary) -> void:
	if c.week < 0 or c.week > CareerState.WEEKS_PER_SEASON:
		_err(r, "week %d is outside 0..%d" % [c.week, CareerState.WEEKS_PER_SEASON])
	if c.day < 0 or c.day > 6:
		_err(r, "day %d is outside 0..6" % c.day)
	if c.season < 1:
		_err(r, "season %d is below 1" % c.season)
	for k in c.pyramids:
		var pyr: LeaguePyramid = c.pyramids[k]
		for role in pyr.comp:
			var comp: Competition = c.competitions.get(pyr.comp[role])
			if comp == null:
				continue
			for f in comp.pending_fixtures():
				var due := pyr.week_of(role, comp, f)
				var mine: bool = f["home"] == c.club_id or f["away"] == c.club_id
				if due < c.week or (due == c.week and not mine):
					_err(r, "match '%s' was due in week %d but is still unplayed in week %d" % [f["match_id"], due, c.week])
					break
	if c.continental != null:
		var cc: Competition = c.continental.competition(c)
		if cc == null:
			_err(r, "the continental cup points at a missing competition")
		else:
			for f in cc.pending_fixtures():
				var due := c.continental.week_of(f)
				var mine: bool = f["home"] == c.club_id or f["away"] == c.club_id
				if due < c.week or (due == c.week and not mine):
					_err(r, "continental match '%s' was due in week %d but is unplayed in week %d" % [f["match_id"], due, c.week])
					break


const _COUNTERS: Array[String] = ["apps", "goals", "assists", "saves", "motm", "yellow", "red", "clean_sheets"]


static func _check_stats(c: CareerState, db: Node, r: Dictionary) -> void:
	# all-time counters of the user's matches == the sum over every season / competition bucket
	for pid in c.player_stats:
		if not db.players.has(pid):
			_warn(r, "statistics of unknown player '%s'" % pid)
		var s: Dictionary = c.player_stats[pid]
		for k in ["apps", "goals", "assists", "saves", "motm"]:
			if int(s[k]) < 0:
				_err(r, "player '%s' has negative %s" % [pid, k])
		if float(s["rating_sum"]) < 0.0 or float(s["rating_sum"]) > 10.0 * float(s["apps"]) + 0.001:
			_err(r, "player '%s' has a rating sum outside 0..10 per appearance" % pid)
		if c.season_stats.has(pid):
			var sums := {"apps": 0, "goals": 0, "assists": 0, "saves": 0, "motm": 0}
			for key in c.season_stats[pid]:
				for k in sums:
					sums[k] += int(c.season_stats[pid][key].get(k, 0))
			for k in sums:
				if sums[k] != int(s[k]):
					_warn(r, "player '%s': all-time %s=%d but the season buckets add up to %d" % [pid, k, int(s[k]), sums[k]])
					break
	for pid in c.season_stats:
		for key in c.season_stats[pid]:
			for k in _COUNTERS:
				if int(c.season_stats[pid][key].get(k, 0)) < 0:
					_err(r, "player '%s' bucket '%s' has negative %s" % [pid, key, k])
	# the current season of every player of the world: estimated part <= total, nothing negative
	for pid in c.world_stats:
		var w: Dictionary = c.world_stats[pid]
		if not db.players.has(pid):
			_warn(r, "world statistics of unknown player '%s'" % pid)
		for k in SeasonStats.COUNTERS:
			if int(w.get(k, 0)) < 0 or int(w.get("est_" + k, 0)) < 0 or int(w.get("est_" + k, 0)) > int(w.get(k, 0)):
				_err(r, "world statistics of '%s': %s=%d, estimated part %d" % [pid, k, int(w.get(k, 0)), int(w.get("est_" + k, 0))])
		if int(w.get("clean_sheets", 0)) > int(w.get("apps", 0)):
			_err(r, "world statistics of '%s': more clean sheets than appearances" % pid)
		if float(w.get("rating_sum", 0.0)) > 10.0 * float(w.get("apps", 0)) + 0.001 or float(w.get("est_rating_sum", 0.0)) > float(w.get("rating_sum", 0.0)) + 0.001:
			_err(r, "world statistics of '%s': rating sum out of range" % pid)
	# the report log: unique uids, bounded, goals of players do not exceed the score, and never more than the totals say
	if c.match_log.size() > CareerState.MATCH_LOG_MAX:
		_err(r, "match log has %d entries (limit %d)" % [c.match_log.size(), CareerState.MATCH_LOG_MAX])
	var uids := {}
	var from_log := {}
	for rep: Dictionary in c.match_log:
		var uid := CareerState._report_key(rep)
		if uids.has(uid):
			_err(r, "match report '%s' is in the log twice" % uid)
		uids[uid] = true
		var side_goals := {"home": int(rep.get("home_goals", 0)), "away": int(rep.get("away_goals", 0))}
		var scored := {"home": 0, "away": 0}
		for p in rep.get("players", []):
			if p.get("side", "") in scored:
				scored[p["side"]] += int(p.get("goals", 0))
			var t: Dictionary = from_log.get(p["player_id"], {"apps": 0, "goals": 0})
			t["apps"] += 1
			t["goals"] += int(p.get("goals", 0))
			from_log[p["player_id"]] = t
		for side in scored:
			if scored[side] > side_goals[side]:
				_err(r, "report '%s': players of the %s side scored %d but the team scored %d" % [uid, side, scored[side], side_goals[side]])
	for pid in from_log:
		var s: Dictionary = c.player_stats.get(pid, {})
		if int(s.get("apps", 0)) < from_log[pid]["apps"] or int(s.get("goals", 0)) < from_log[pid]["goals"]:
			_warn(r, "player '%s': the log holds more appearances or goals than his totals" % pid)
	for pid in c.yellow_counts:
		if int(c.yellow_counts[pid]) < 0 or int(c.yellow_counts[pid]) >= Availability.YELLOWS_FOR_BAN:
			_warn(r, "player '%s' has %d yellow cards counted" % [pid, int(c.yellow_counts[pid])])


static func _check_misc(c: CareerState, db: Node, r: Dictionary) -> void:
	for tid in c.club_levels:
		if not db.teams.has(tid):
			_warn(r, "club level for unknown club '%s'" % tid)
	if c.events.size() > CareerState.EVENT_LOG_MAX:
		_err(r, "event log has %d entries (limit %d)" % [c.events.size(), CareerState.EVENT_LOG_MAX])
	if c.manager.reputation < 0 or c.manager.reputation > 100 or c.manager.confidence < 0 or c.manager.confidence > 100:
		_err(r, "manager reputation / confidence out of range")
	if c.continental != null and c.continental.comp_id != "" and not c.competitions.has(c.continental.comp_id):
		_err(r, "the continental cup '%s' is not registered" % c.continental.comp_id)
	for a in c.award_history:
		var aw: Dictionary = a.get("awards", {})
		for kind in ["golden_boot", "player_of_the_season", "best_goalkeeper", "best_young_player"]:
			if str(aw.get(kind, "")) != "" and not db.players.has(str(aw[kind])):
				_warn(r, "award '%s' of season %s names unknown player '%s'" % [kind, str(a.get("season")), aw[kind]])
