class_name WorldLife
extends RefCounted

## Career phase C5 (what exists without the national-team system): derbies, club reputation that moves over seasons, other clubs'
## managers (hired / sacked), monthly and manager-of-the-season awards, and the Super Cup. Saved with the career.
## NOT here: national teams, international breaks, a World Cup - they need a squad / calendar model that does not exist yet.

const REPUTATION_MAX_STEP := 5               # a club's reputation never moves by more than this in a season
const MANAGER_STYLES: Array[String] = ["attacking", "defensive", "youth", "tactical", "motivator"]

var ai_managers: Dictionary = {}             # club id -> {name, style, since}
var award_log: Array = []                    # [{season, week, kind, id}]  (player_of_month, manager_of_month, manager_of_season)
var super_cups: Array = []                   # [{season, home, away, hg, ag, winner}]
var super_cup_pending: Array = []            # [home, away] to be played in week 1
var _snapshot: Dictionary = {}               # player id -> goals+assists at the last monthly award
var _points_snapshot: Dictionary = {}        # team id -> points at the last monthly award


# --- derbies --------------------------------------------------------------------------------------------

## The rival of a club: same country, paired by a stable hash order (every club in a country with an even/odd partner has one).
static func rival_of(db: Node, club_id: String) -> String:
	var t: TeamData = db.get_team(club_id)
	if t == null:
		return ""
	var peers: Array = db.list_teams(TeamData.Category.CLUB).filter(func(x: TeamData) -> bool: return x.country == t.country)
	peers.sort_custom(func(a: TeamData, b: TeamData) -> bool:
		var ha := hash([a.country, a.id, "derby"])
		var hb := hash([b.country, b.id, "derby"])
		return ha < hb if ha != hb else a.id < b.id)
	var i := -1
	for k in peers.size():
		if (peers[k] as TeamData).id == club_id:
			i = k
	if i < 0 or peers.size() < 2:
		return ""
	var j := i + 1 if i % 2 == 0 else i - 1
	return (peers[j] as TeamData).id if j < peers.size() else ""


static func is_derby(db: Node, a: String, b: String) -> bool:
	return a != b and (rival_of(db, a) == b or rival_of(db, b) == a)


# --- club reputation ------------------------------------------------------------------------------------

## End of season: moves the reputation of every club in the league tables. Champion +3, top third +1, bottom third -1, relegated -2
## (never more than +-5 in a season, always within 1-99). Returns {club: delta}.
func move_reputation(db: Node, league_summaries: Dictionary) -> Dictionary:
	var out := {}
	for k in league_summaries:
		var sm: Dictionary = league_summaries[k]
		var tables: Dictionary = sm.get("tables", {})
		var relegated: Array = sm.get("relegated", [])
		for div_id in tables:
			var order: Array = tables[div_id]
			var n := order.size()
			for i in n:
				var t: TeamData = db.get_team(str(order[i]))
				if t == null:
					continue
				var d := 0
				if i == 0:
					d += 3
				if i < n / 3:
					d += 1
				elif i >= n - n / 3:
					d -= 1
				if relegated.has(order[i]):
					d -= 2
				d = clampi(d, -REPUTATION_MAX_STEP, REPUTATION_MAX_STEP)
				var before := t.reputation
				t.reputation = clampi(t.reputation + d, 1, 99)
				if t.reputation != before:
					out[t.id] = t.reputation - before
	return out


# --- other managers ----------------------------------------------------------------------------------------

func manager_of(db: Node, club_id: String, season: int) -> Dictionary:
	if not ai_managers.has(club_id):
		ai_managers[club_id] = _new_manager(club_id, season, 0)
	return ai_managers[club_id]


static func _new_manager(club_id: String, season: int, n: int) -> Dictionary:
	var h := hash([club_id, season, n, "manager"]) & 0x7fffffff
	return {"name": StaffTeam._name(h), "style": MANAGER_STYLES[h % MANAGER_STYLES.size()], "since": season}


## End of season: a club that finished in the bottom fifth although its squad is in the top half sacks its manager. Returns
## [{club, old, new}] and logs them as news events.
func review_managers(career: CareerState, league_summaries: Dictionary) -> Array:
	var changes: Array = []
	for t: TeamData in career.db.list_teams(TeamData.Category.CLUB):
		manager_of(career.db, t.id, career.season)               # every club has a manager
	for k in league_summaries:
		var tables: Dictionary = (league_summaries[k] as Dictionary).get("tables", {})
		for div_id in tables:
			var order: Array = tables[div_id]
			var n := order.size()
			if n < 5:
				continue
			var by_rating: Array = order.duplicate()
			by_rating.sort_custom(func(a: String, b: String) -> bool:
				var ra: int = career.db.get_team_rating(a)
				var rb: int = career.db.get_team_rating(b)
				return ra > rb if ra != rb else a < b)
			for i in n:
				var id := str(order[i])
				if id == career.club_id:
					continue
				if i >= n - maxi(n / 5, 1) and by_rating.find(id) < n / 2:
					var old := manager_of(career.db, id, career.season)
					var nu := _new_manager(id, career.season + 1, int(hash(old["name"]) % 7) + 1)
					ai_managers[id] = nu
					changes.append({"club": id, "old": old["name"], "new": nu["name"]})
					career.add_event("manager_change", [id, old["name"], nu["name"]])
	return changes


# --- monthly awards -----------------------------------------------------------------------------------------

## Every 4th week: player of the month (goals + assists since the last award, any club of the user's league system) and manager of
## the month (most league points gained by a club since the last award). Returns {player, club} ids ("" when nothing happened).
func monthly_awards(career: CareerState) -> Dictionary:
	var best_player := ""
	var best_v := 0
	for pid in career.world_stats:
		var row: Dictionary = career.world_stats[pid]
		var total := int(row.get("goals", 0)) + int(row.get("assists", 0)) + int(row.get("est_goals", 0)) + int(row.get("est_assists", 0))
		var gain := total - int(_snapshot.get(pid, 0))
		_snapshot[pid] = total
		if gain > best_v or (gain == best_v and gain > 0 and str(pid) < best_player):
			best_v = gain
			best_player = str(pid)
	var best_club := ""
	var best_pts := 0
	var ud := career.user_division()
	if not ud.is_empty():
		var pyr: LeaguePyramid = career.pyramids[ud["pyramid"]]
		var comp: Competition = career.competitions.get(pyr.comp.get(ud["division"]["id"], ""))
		if comp != null:
			for row in comp.standings():
				var tid := str(row["team_id"])
				var gain := int(row["points"]) - int(_points_snapshot.get(tid, 0))
				_points_snapshot[tid] = int(row["points"])
				if gain > best_pts or (gain == best_pts and gain > 0 and tid < best_club):
					best_pts = gain
					best_club = tid
	if best_player != "":
		award_log.append({"season": career.season, "week": career.week, "kind": "player_of_month", "id": best_player})
		career.add_event("award", ["player_of_month", best_player, 0])
	if best_club != "":
		award_log.append({"season": career.season, "week": career.week, "kind": "manager_of_month", "id": best_club})
	while award_log.size() > 120:
		award_log.pop_front()
	return {"player": best_player, "club": best_club}


## End of season: the manager of the season = the club that beat its rating rank by the most places in the user's league.
func manager_of_season(career: CareerState, league_summaries: Dictionary) -> String:
	var best := ""
	var best_gain := -1000
	for k in league_summaries:
		var tables: Dictionary = (league_summaries[k] as Dictionary).get("tables", {})
		for div_id in tables:
			var order: Array = tables[div_id]
			var by_rating: Array = order.duplicate()
			by_rating.sort_custom(func(a: String, b: String) -> bool:
				var ra: int = career.db.get_team_rating(a)
				var rb: int = career.db.get_team_rating(b)
				return ra > rb if ra != rb else a < b)
			for i in order.size():
				var gain: int = by_rating.find(order[i]) - i
				if gain > best_gain:
					best_gain = gain
					best = str(order[i])
	if best != "":
		award_log.append({"season": career.season, "week": career.week, "kind": "manager_of_season", "id": best})
	return best


# --- Super Cup --------------------------------------------------------------------------------------------------

## Called at the season end with the summaries: league champion vs cup winner of the user's league system (the runner-up when the
## champion also won the cup). Played in week 1 of the next season.
func schedule_super_cup(career: CareerState, league_summaries: Dictionary) -> void:
	super_cup_pending = []
	var ud_key := ""
	var ud := career.user_division()
	if not ud.is_empty():
		ud_key = str(ud["pyramid"])
	elif not league_summaries.is_empty():
		ud_key = str(league_summaries.keys()[0])
	if not league_summaries.has(ud_key):
		return
	var sm: Dictionary = league_summaries[ud_key]
	var top_id := ""
	for div_id in sm.get("tables", {}):
		var order: Array = sm["tables"][div_id]
		if not order.is_empty() and (top_id == "" or str(div_id) < top_id):
			top_id = str(div_id)
	if top_id == "":
		return
	var order_top: Array = sm["tables"][top_id]
	var champion := str(order_top[0])
	var cup := str(sm.get("cup_winner", ""))
	if cup == "":
		return
	if cup == champion and order_top.size() > 1:
		cup = str(order_top[1])
	super_cup_pending = [champion, cup]


## Plays the pending Super Cup (a single match, statistical). Returns the record or {}.
func play_super_cup(career: CareerState) -> Dictionary:
	if super_cup_pending.size() != 2:
		return {}
	var home: String = super_cup_pending[0]
	var away: String = super_cup_pending[1]
	super_cup_pending = []
	var f := {"match_id": "supercup_%d" % career.season, "stage": "ko", "home": home, "away": away}
	var r := MatchSimulator.result(career.db, f, hash([career.season, "supercup"]), {}, career.style_mods())
	var winner := home if r.winner_id() == home else away
	var rec := {"season": career.season, "home": home, "away": away, "hg": r.home_goals, "ag": r.away_goals, "winner": winner}
	super_cups.append(rec)
	career.add_event("super_cup", [winner, home, away])
	if winner == career.club_id:
		career.manager.trophies += 1
	return rec


func to_dict() -> Dictionary:
	return {"ai_managers": ai_managers.duplicate(true), "award_log": award_log.duplicate(true), "super_cups": super_cups.duplicate(true),
			"super_cup_pending": super_cup_pending.duplicate(), "snapshot": _snapshot.duplicate(), "points_snapshot": _points_snapshot.duplicate()}


static func from_dict(d: Dictionary) -> WorldLife:
	var w := WorldLife.new()
	w.ai_managers = PlayerData._restore_ints((d.get("ai_managers", {}) as Dictionary).duplicate(true))
	w.award_log = PlayerData._restore_ints((d.get("award_log", []) as Array).duplicate(true))
	w.super_cups = PlayerData._restore_ints((d.get("super_cups", []) as Array).duplicate(true))
	w.super_cup_pending = (d.get("super_cup_pending", []) as Array).map(func(x: Variant) -> String: return str(x))
	for k in (d.get("snapshot", {}) as Dictionary):
		w._snapshot[str(k)] = int(d["snapshot"][k])
	for k in (d.get("points_snapshot", {}) as Dictionary):
		w._points_snapshot[str(k)] = int(d["points_snapshot"][k])
	return w
