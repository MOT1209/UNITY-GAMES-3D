class_name MatchReport
extends RefCounted

## Post-match report built from the REAL match state (events + measured statistics). JSON-safe so
## it can be shown on the results screen, stored in career records and saved with a match.
## `measured` lists the statistics that exist for this report: the UI shows nothing else.
## Matches decided by quick simulation have no events: their report only contains the score.


## `state` = MatchState of a finished (or running) match; `names` optional id -> display name.
static func build(state: MatchState, db: Node = null, human_side: String = "none", result: MatchResult = null) -> Dictionary:
	var hg: int = state.score["home"]
	var ag: int = state.score["away"]
	var outcome := {"home": 0, "away": 0}
	if hg != ag:
		outcome["home" if hg > ag else "away"] = 1
		outcome["away" if hg > ag else "home"] = -1
	elif result != null and result.winner_id() != "":
		outcome["home" if result.winner_id() == state.home_id else "away"] = 1
		outcome["away" if result.winner_id() == state.home_id else "home"] = -1
	var scorers: Array = []
	for e in state.events:
		if e["type"] == "goal":
			scorers.append({"minute": float(e["minute"]), "side": e["side"], "player_id": e["player_id"],
					"assist_id": e.get("assist_id", ""), "own_goal": bool(e.get("own_goal", false))})
	var team_stats := {}
	for side in ["home", "away"]:
		var t: Dictionary = state.stats.teams[side]
		team_stats[side] = {"possession": snappedf(state.stats.possession_pct(side), 0.1), "shots": t["shots"],
				"shots_on_target": t["on_target"], "passes": t["passes"], "passes_ok": t["passes_ok"],
				"pass_accuracy": snappedf(state.stats.pass_accuracy(side), 0.1), "saves": t["saves"], "substitutions": t["subs"],
				"fouls": t["fouls"], "yellows": t["yellows"], "reds": t["reds"],
				"corners": t["corners"], "throw_ins": t["throw_ins"], "goal_kicks": t["goal_kicks"], "offsides": t["offsides"]}
	var rated: Array = []
	var best_id := ""
	var best_key := [-1.0, -1, ""]
	for pid in state.stats.players:
		var p: Dictionary = state.stats.players[pid]
		var played: bool = state.stamina.has(pid) or p["subbed_in"]
		if not played:
			continue
		var r := state.stats.rating(pid, int(outcome[p["side"]]))
		rated.append({"player_id": pid, "side": p["side"], "rating": r, "goals": p["goals"], "assists": p["assists"],
				"shots": p["shots"], "shots_on_target": p["on_target"], "passes": p["passes"], "passes_ok": p["passes_ok"],
				"saves": p["saves"], "own_goals": p["own_goals"], "fouls": p["fouls"], "yellow": p["yellow"], "red": p["red"], "offsides": p["offsides"]})
		var key := [r, int(p["goals"]), pid]
		if _better(key, best_key):
			best_key = key
			best_id = pid
	rated.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["rating"] > b["rating"] if a["rating"] != b["rating"] else a["player_id"] < b["player_id"])
	var human_outcome := ""
	if human_side in ["home", "away"]:
		var o: int = outcome[human_side]
		human_outcome = "win" if o > 0 else ("loss" if o < 0 else "draw")
	var report := {"version": 1, "source": "engine", "match_id": state.match_id, "home_id": state.home_id,
			"away_id": state.away_id, "home_goals": hg, "away_goals": ag, "outcome_home": outcome["home"],
			"outcome_human": human_outcome, "human_side": human_side, "scorers": scorers, "team_stats": team_stats,
			"players": rated, "motm": best_id, "measured": MatchStats.MEASURED.duplicate(),
			"minutes": snappedf(state.display_minute(), 0.1)}
	if result != null and result.home_pens >= 0:
		report["home_pens"] = result.home_pens
		report["away_pens"] = result.away_pens
	return report


static func _better(a: Array, b: Array) -> bool:
	if a[0] != b[0]:
		return a[0] > b[0]
	if a[1] != b[1]:
		return a[1] > b[1]
	return b[2] == "" or str(a[2]) < str(b[2])


## Score-only report for results that did not come from the engine (quick simulation).
static func from_result(result: MatchResult, human_side: String = "none") -> Dictionary:
	var out := 0
	if result.home_goals != result.away_goals:
		out = 1 if result.home_goals > result.away_goals else -1
	elif result.winner_id() != "":
		out = 1 if result.winner_id() == result.home_id else -1
	var hs := ""
	if human_side in ["home", "away"]:
		var o := out if human_side == "home" else -out
		hs = "win" if o > 0 else ("loss" if o < 0 else "draw")
	return {"version": 1, "source": "simulation", "match_id": result.match_id, "home_id": result.home_id,
			"away_id": result.away_id, "home_goals": result.home_goals, "away_goals": result.away_goals,
			"outcome_home": out, "outcome_human": hs, "human_side": human_side, "scorers": [], "team_stats": {},
			"players": [], "motm": "", "measured": ["score"], "minutes": 90.0}
