class_name SeasonStats
extends RefCounted

## Per-season player statistics of the whole football world (Phase 10), the data the season awards are computed from.
## Two honest sources:
##   * matches played in the 3D engine: the real `MatchReport` rows (goals, assists, rating, clean sheets);
##   * matches simulated without the engine: a statistical MODEL - the starting XI is the best available eleven, every goal goes to
##     an outfielder with a weight from his position and shooting (assists from passing), ratings are 6.0 plus the contributions.
##     These numbers are model output (deterministic per match), not measured play, and are labelled so in the documentation.
## Stats are keyed by player id: {apps, goals, assists, clean_sheets, rating_sum} are the TOTALS (what awards rank), and
## {est_apps, est_goals, est_assists, est_clean_sheets, est_rating_sum} are the part of those totals that is MODEL output.
## `real = total - est`. Nothing of the model is ever written to `player_stats` / `season_stats`, which hold engine reports only.

const POSITION_GOAL_WEIGHT := {"ST": 3.0, "LW": 2.0, "RW": 2.0, "CAM": 2.0, "LM": 1.4, "RM": 1.4, "CM": 1.0, "CDM": 0.5, "LB": 0.4, "RB": 0.4, "CB": 0.3, "GK": 0.0}


const COUNTERS: Array[String] = ["apps", "goals", "assists", "clean_sheets"]


static func empty_row() -> Dictionary:
	return {"apps": 0, "goals": 0, "assists": 0, "clean_sheets": 0, "rating_sum": 0.0,
			"est_apps": 0, "est_goals": 0, "est_assists": 0, "est_clean_sheets": 0, "est_rating_sum": 0.0,
			"minutes": 0, "est_minutes": 0}


## A row restored from a save (any age): missing fields become 0, the estimated part is only kept when the save had it.
static func restore_row(r: Dictionary) -> Dictionary:
	var out := {"apps": int(r.get("apps", 0)), "goals": int(r.get("goals", 0)), "assists": int(r.get("assists", 0)),
			"clean_sheets": int(r.get("clean_sheets", 0)), "rating_sum": float(r.get("rating_sum", 0.0))}
	for k in ["est_apps", "est_goals", "est_assists", "est_clean_sheets"]:
		out[k] = clampi(int(r.get(k, 0)), 0, int(out[k.substr(4)]))
	out["est_rating_sum"] = float(r.get("est_rating_sum", 0.0))
	out["minutes"] = maxi(int(r.get("minutes", 0)), 0)                      # real minutes (engine) + model minutes (est_minutes)
	out["est_minutes"] = clampi(int(r.get("est_minutes", 0)), 0, int(out["minutes"]))
	return out


## Share (0..1) of a row's appearances that come from the statistical model; 0 = everything was played in the engine.
static func estimated_share(row: Dictionary) -> float:
	var apps := int(row.get("apps", 0))
	return float(int(row.get("est_apps", 0))) / float(apps) if apps > 0 else 0.0


static func _row(stats: Dictionary, pid: String) -> Dictionary:
	if not stats.has(pid):
		stats[pid] = empty_row()
	return stats[pid]


## From a real engine report.
static func record_report(career: CareerState, report: Dictionary) -> void:
	for p in report.get("players", []):
		var pid: String = p["player_id"]
		var r := _row(career.world_stats, pid)
		r["apps"] += 1
		r["goals"] += int(p["goals"])
		r["assists"] += int(p["assists"])
		r["rating_sum"] += float(p["rating"])
		r["minutes"] = int(r.get("minutes", 0)) + int(p.get("minutes", 0))       # measured: from the substitution / red card events
		var pdata: PlayerData = career.db.get_player(pid)
		if pdata != null and pdata.position == PlayerData.Position.GK:
			var conceded: int = int(report["away_goals"]) if p["side"] == "home" else int(report["home_goals"])
			if conceded == 0:
				r["clean_sheets"] += 1


## The model's view of a club for the current calendar week, cached per club (squads change only between weeks):
## {"xi": best available eleven, "outfield": its outfield players, "w_shooting"/"w_passing": goal-pick weights of `outfield`}.
static func _eleven(career: CareerState, team_id: String) -> Dictionary:
	var stamp := (career.season * 100 + career.week) * 10 + career.day       # Phase K3: fitness changes daily
	if career._xi_stamp != stamp:
		career._xi_stamp = stamp
		career._xi_cache.clear()
	if not career._xi_cache.has(team_id):
		career._xi_cache[team_id] = _prepare(_build_eleven(career.db, team_id, team_id != career.club_id))
	return career._xi_cache[team_id]


static func _prepare(xi: Array[PlayerData]) -> Dictionary:
	var outfield: Array[PlayerData] = []
	var w_shoot: Array[float] = []
	var w_pass: Array[float] = []
	for p in xi:
		if p.position == PlayerData.Position.GK:
			continue
		outfield.append(p)
		var base := float(POSITION_GOAL_WEIGHT.get(_position_keys[p.position], 1.0))
		w_shoot.append(base * float(p.shooting))
		w_pass.append(base * float(p.passing))
	return {"xi": xi, "outfield": outfield, "w_shooting": w_shoot, "w_passing": w_pass}


## Phase K3 rotation (AI clubs, `rotate`): the eleven is picked by overall x freshness — a tired regular (fitness under
## ROTATE_BELOW) drops behind a fresh team-mate, so 18-24 players get minutes over a season instead of the same 12.
const ROTATE_BELOW := 78


static func _build_eleven(db: Node, team_id: String, rotate: bool = false) -> Array[PlayerData]:
	var t: TeamData = db.get_team(team_id)
	var keyed: Array = []                                  # [score, id, player]
	if t != null:
		for pid in t.squad_ids:
			var p: PlayerData = db.players.get(pid)
			if p != null and p.status == PlayerData.Status.ACTIVE:
				var score := float(p.get_overall())
				if rotate and p.fitness < ROTATE_BELOW:
					score -= float(ROTATE_BELOW - p.fitness) * 0.6
				keyed.append([score, p.id, p])
	keyed.sort_custom(func(a: Array, b: Array) -> bool:
		return a[0] > b[0] if a[0] != b[0] else a[1] < b[1])
	var out: Array[PlayerData] = []
	for e in keyed:
		if (e[2] as PlayerData).position == PlayerData.Position.GK:
			out.append(e[2])
			break
	for e in keyed:
		if out.size() >= 11:
			break
		if (e[2] as PlayerData).position != PlayerData.Position.GK:
			out.append(e[2])
	return out


static var _position_keys: Array = PlayerData.Position.keys()


## Weighted pick among `players` with the precomputed `weights`; the player at index `exclude` (-1 = nobody) has weight 0.
static func _pick(rng: RandomNumberGenerator, players: Array[PlayerData], weights: Array[float], exclude: int = -1) -> int:
	var total := 0.0
	for i in weights.size():
		total += 0.0 if i == exclude else weights[i]
	if total <= 0.0:
		return -1
	var roll := rng.randf() * total
	for i in players.size():
		var w := 0.0 if i == exclude else weights[i]
		roll -= w
		if roll <= 0.0 and w > 0.0:
			return i
	return players.size() - 1


## From a result produced by `MatchSimulator` (no engine report exists for this match). Everything written here is also
## counted in the `est_*` fields.
static func record_simulated(career: CareerState, r: MatchResult, competition_id: String = "") -> void:
	# Phase S1: the match record comes from the event engine (same score, scorers = goals, assists, cards, ratings).
	var det: Dictionary = career.live_records.get(r.match_id, {})          # played in the live simulation: its own record
	career.live_records.erase(r.match_id)
	if det.is_empty():
		det = MatchEventEngine.distribute(career.db, r.home_id, r.away_id, r.home_goals, r.away_goals, r.match_id,
				r.home_id != career.club_id, r.away_id != career.club_id, _eleven(career, r.home_id)["xi"], _eleven(career, r.away_id)["xi"],
				r.home_id != career.club_id and r.away_id != career.club_id)
	var by_side := {"home": [], "away": []}
	for ev in det["events"]:
		(by_side[ev["side"]] as Array).append(ev)
	var key := "%d:%s" % [career.season, competition_id if competition_id != "" else "friendly"]
	for side_i in 2:
		var side := "home" if side_i == 0 else "away"
		var team_id := r.home_id if side_i == 0 else r.away_id
		var conceded := r.away_goals if side_i == 0 else r.home_goals
		var ids: Array = det["lineups"][side]
		var mine_side := team_id == career.club_id          # the team centre only shows the managed club: per-competition rows for it alone
		var yellows := {}
		var reds := {}
		for ev in by_side[side]:
			var t := str(ev["type"])
			if t == "goal":
				var srow := _row(career.world_stats, str(ev["player_id"]))
				srow["goals"] += 1
				srow["est_goals"] += 1
				if mine_side:
					_comp_row(career, str(ev["player_id"]), key)["goals"] += 1
				if str(ev["assist_id"]) != "":
					var arow := _row(career.world_stats, str(ev["assist_id"]))
					arow["assists"] += 1
					arow["est_assists"] += 1
					if mine_side:
						_comp_row(career, str(ev["assist_id"]), key)["assists"] += 1
			elif t == "yellow":
				yellows[str(ev["player_id"])] = true
			elif t == "red":
				reds[str(ev["player_id"])] = true
		for pid in ids:
			var p: PlayerData = career.db.get_player(str(pid))
			if p == null:
				continue
			if team_id != career.club_id:
				p.fitness = clampi(p.fitness - DailyLife.match_fatigue(_position_keys[p.position]), 30, 100)      # K3
			var row := _row(career.world_stats, p.id)
			row["apps"] += 1
			row["est_apps"] += 1
			row["minutes"] = int(row.get("minutes", 0)) + 90               # model matches have no substitutions: the eleven plays 90 (an ESTIMATE)
			row["est_minutes"] = int(row.get("est_minutes", 0)) + 90
			var shown: float = float(det["ratings"].get(p.id, 6.0))
			var clean := conceded == 0 and p.position in [PlayerData.Position.GK, PlayerData.Position.CB, PlayerData.Position.LB, PlayerData.Position.RB]
			if p.position == PlayerData.Position.GK and conceded == 0:
				row["clean_sheets"] += 1
				row["est_clean_sheets"] += 1
			row["rating_sum"] += shown
			row["est_rating_sum"] += shown
			if mine_side:
				var crow := _comp_row(career, p.id, key)
				crow["apps"] += 1
				crow["rating_sum"] += shown
				crow["yellow"] += 1 if yellows.has(p.id) else 0
				crow["red"] += 1 if reds.has(p.id) else 0
				crow["clean_sheets"] += 1 if clean else 0


## Per-competition row of the model-played matches (`CareerState.sim_comp_stats`: player -> "season:competition" -> row).
static func _comp_row(career: CareerState, pid: String, key: String) -> Dictionary:
	if not career.sim_comp_stats.has(pid):
		career.sim_comp_stats[pid] = {}
	if not career.sim_comp_stats[pid].has(key):
		career.sim_comp_stats[pid][key] = {"apps": 0, "goals": 0, "assists": 0, "saves": 0, "rating_sum": 0.0, "motm": 0, "yellow": 0, "red": 0, "clean_sheets": 0}
	return career.sim_comp_stats[pid][key]
