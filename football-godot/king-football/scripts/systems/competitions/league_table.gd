class_name LeagueTable
extends RefCounted

## Points table. Ranking: points, goal difference, goals scored, then team id
## (fully deterministic). Results are idempotent per match id.

var points_win: int = 3
var points_draw: int = 1
var rows: Dictionary = {}          # team_id -> stats dict
var _processed: Dictionary = {}    # match_id -> true


func _init(team_ids: Array = [], p_win: int = 3, p_draw: int = 1) -> void:
	points_win = p_win
	points_draw = p_draw
	for t in team_ids:
		rows[t] = {"team_id": t, "played": 0, "won": 0, "drawn": 0, "lost": 0,
				"gf": 0, "ga": 0, "gd": 0, "points": 0}


## Returns "" or an error. Duplicate match ids are rejected.
func apply_result(r: MatchResult) -> String:
	if _processed.has(r.match_id):
		return "match '%s' already recorded" % r.match_id
	if not rows.has(r.home_id) or not rows.has(r.away_id):
		return "match '%s' has a team that is not in this table" % r.match_id
	var h: Dictionary = rows[r.home_id]
	var a: Dictionary = rows[r.away_id]
	h["played"] += 1
	a["played"] += 1
	h["gf"] += r.home_goals
	h["ga"] += r.away_goals
	a["gf"] += r.away_goals
	a["ga"] += r.home_goals
	if r.home_goals > r.away_goals:
		h["won"] += 1
		a["lost"] += 1
		h["points"] += points_win
	elif r.home_goals < r.away_goals:
		a["won"] += 1
		h["lost"] += 1
		a["points"] += points_win
	else:
		h["drawn"] += 1
		a["drawn"] += 1
		h["points"] += points_draw
		a["points"] += points_draw
	h["gd"] = h["gf"] - h["ga"]
	a["gd"] = a["gf"] - a["ga"]
	_processed[r.match_id] = true
	return ""


func ranking() -> Array:
	var list: Array = rows.values()
	list.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		if x["points"] != y["points"]:
			return x["points"] > y["points"]
		if x["gd"] != y["gd"]:
			return x["gd"] > y["gd"]
		if x["gf"] != y["gf"]:
			return x["gf"] > y["gf"]
		return str(x["team_id"]) < str(y["team_id"]))
	return list


func position_of(team_id: String) -> int:
	var rk := ranking()
	for i in rk.size():
		if rk[i]["team_id"] == team_id:
			return i + 1
	return -1


func to_dict() -> Dictionary:
	return {"win": points_win, "draw": points_draw, "rows": rows.duplicate(true),
			"processed": _processed.keys()}


static func from_dict(d: Dictionary) -> LeagueTable:
	var t := LeagueTable.new([], int(d.get("win", 3)), int(d.get("draw", 1)))
	t.rows = (d.get("rows", {}) as Dictionary).duplicate(true)
	for k in t.rows:
		for f in ["played", "won", "drawn", "lost", "gf", "ga", "gd", "points"]:
			t.rows[k][f] = int(t.rows[k][f])
	for m in d.get("processed", []):
		t._processed[str(m)] = true
	return t
