class_name SeasonStats
extends RefCounted

## Per-season player statistics of the whole football world (Phase 10), the data the season awards are computed from.
## Two honest sources:
##   * matches played in the 3D engine: the real `MatchReport` rows (goals, assists, rating, clean sheets);
##   * matches simulated without the engine: a statistical MODEL - the starting XI is the best available eleven, every goal goes to
##     an outfielder with a weight from his position and shooting (assists from passing), ratings are 6.0 plus the contributions.
##     These numbers are model output (deterministic per match), not measured play, and are labelled so in the documentation.
## Stats are keyed by player id: {apps, goals, assists, clean_sheets, rating_sum}.

const POSITION_GOAL_WEIGHT := {"ST": 3.0, "LW": 2.0, "RW": 2.0, "CAM": 2.0, "LM": 1.4, "RM": 1.4, "CM": 1.0, "CDM": 0.5, "LB": 0.4, "RB": 0.4, "CB": 0.3, "GK": 0.0}


static func empty_row() -> Dictionary:
	return {"apps": 0, "goals": 0, "assists": 0, "clean_sheets": 0, "rating_sum": 0.0}


static func _row(stats: Dictionary, pid: String) -> Dictionary:
	if not stats.has(pid):
		stats[pid] = empty_row()
	return stats[pid]


## From a real engine report.
static func record_report(career: CareerState, report: Dictionary) -> void:
	for p in report.get("players", []):
		var pid: String = p["player_id"]
		var r := _row(career.season_stats, pid)
		r["apps"] += 1
		r["goals"] += int(p["goals"])
		r["assists"] += int(p["assists"])
		r["rating_sum"] += float(p["rating"])
		var pdata: PlayerData = career.db.get_player(pid)
		if pdata != null and pdata.position == PlayerData.Position.GK:
			var conceded: int = int(report["away_goals"]) if p["side"] == "home" else int(report["home_goals"])
			if conceded == 0:
				r["clean_sheets"] += 1


## The best available eleven of a club, cached per club for the current calendar week (squads change only between weeks).
static func _eleven(career: CareerState, team_id: String) -> Array[PlayerData]:
	var stamp := career.season * 100 + career.week
	if career._xi_stamp != stamp:
		career._xi_stamp = stamp
		career._xi_cache.clear()
	if not career._xi_cache.has(team_id):
		career._xi_cache[team_id] = _build_eleven(career.db, team_id)
	return career._xi_cache[team_id]


static func _build_eleven(db: Node, team_id: String) -> Array[PlayerData]:
	var pool: Array[PlayerData] = []
	for p in db.get_squad(team_id):
		if p.status == PlayerData.Status.ACTIVE:
			pool.append(p)
	pool.sort_custom(func(a: PlayerData, b: PlayerData) -> bool:
		return a.get_overall() > b.get_overall() if a.get_overall() != b.get_overall() else a.id < b.id)
	var out: Array[PlayerData] = []
	for p in pool:
		if p.position == PlayerData.Position.GK:
			out.append(p)
			break
	for p in pool:
		if out.size() >= 11:
			break
		if p.position != PlayerData.Position.GK:
			out.append(p)
	return out


static func _pick(rng: RandomNumberGenerator, players: Array[PlayerData], attr: String, exclude: String = "") -> String:
	var total := 0.0
	var weights: Array[float] = []
	for p in players:
		var w: float = float(POSITION_GOAL_WEIGHT.get(PlayerData.Position.keys()[p.position], 1.0)) * float(p.get_attribute(attr)) if p.id != exclude else 0.0
		weights.append(w)
		total += w
	if total <= 0.0:
		return ""
	var roll := rng.randf() * total
	for i in players.size():
		roll -= weights[i]
		if roll <= 0.0 and weights[i] > 0.0:
			return players[i].id
	return players[players.size() - 1].id


## From a result produced by `MatchSimulator` (no engine report exists for this match).
static func record_simulated(career: CareerState, r: MatchResult) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("sim|" + r.match_id)
	for side in 2:
		var team_id := r.home_id if side == 0 else r.away_id
		var scored := r.home_goals if side == 0 else r.away_goals
		var conceded := r.away_goals if side == 0 else r.home_goals
		var xi := _eleven(career, team_id)
		var outfield: Array[PlayerData] = xi.filter(func(p: PlayerData) -> bool: return p.position != PlayerData.Position.GK)
		var bonus := {}                                   # player id -> rating contribution
		var result_bonus := 0.3 if scored > conceded else (-0.3 if scored < conceded else 0.0)
		for g in scored:
			var scorer := _pick(rng, outfield, "shooting")
			if scorer == "":
				continue
			_row(career.season_stats, scorer)["goals"] += 1
			bonus[scorer] = float(bonus.get(scorer, 0.0)) + 0.9
			if rng.randf() < 0.7:
				var assister := _pick(rng, outfield, "passing", scorer)
				if assister != "":
					_row(career.season_stats, assister)["assists"] += 1
					bonus[assister] = float(bonus.get(assister, 0.0)) + 0.4
		for p in xi:
			var row := _row(career.season_stats, p.id)
			row["apps"] += 1
			var rating := 6.0 + result_bonus + float(bonus.get(p.id, 0.0))
			if p.position == PlayerData.Position.GK:
				if conceded == 0:
					row["clean_sheets"] += 1
					rating += 0.6
				rating -= 0.2 * float(conceded)
			elif p.position in [PlayerData.Position.CB, PlayerData.Position.LB, PlayerData.Position.RB] and conceded == 0:
				rating += 0.3
			row["rating_sum"] += clampf(rating, 3.0, 10.0)
