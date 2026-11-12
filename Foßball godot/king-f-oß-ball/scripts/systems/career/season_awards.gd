class_name SeasonAwards
extends RefCounted

## Season awards computed from `SeasonStats` of the players of one set of clubs (the top division of a country, or all clubs).
## Nothing is stored here: the same stats always give the same awards (ties break by the player id).
## A player needs MIN_APPS appearances for the rating-based awards. Not implemented: Player of the Month, Manager of the Season
## (only the user's manager is simulated).

const MIN_APPS := 10
const YOUNG_AGE := 21


static func _avg(row: Dictionary) -> float:
	return float(row["rating_sum"]) / float(maxi(int(row["apps"]), 1))


static func _better(a: Array, b: Array) -> bool:
	for i in a.size() - 1:
		if a[i] != b[i]:
			return a[i] > b[i]
	return str(a[a.size() - 1]) < str(b[b.size() - 1])


## Returns {golden_boot, player_of_the_season, best_goalkeeper, best_young_player, team_of_the_season: [ids]} (empty values when nobody qualifies).
static func compute(db: Node, stats: Dictionary, club_ids: Array) -> Dictionary:
	var best := {}
	var ranked: Array = []          # [avg, goals, id] of every qualified player, with position group
	var pool: Array = []
	for pid in stats:
		var p: PlayerData = db.get_player(pid)
		if p == null or not (p.team_id in club_ids):
			continue
		var row: Dictionary = stats[pid]
		pool.append({"id": pid, "p": p, "row": row})
	var boot := ""
	var boot_key: Array = [-1, -1, ""]
	var poty := ""
	var poty_key: Array = [-1.0, -1, ""]
	var gk := ""
	var gk_key: Array = [-1.0, -1, ""]
	var young := ""
	var young_key: Array = [-1.0, -1, ""]
	for e in pool:
		var row: Dictionary = e["row"]
		var p: PlayerData = e["p"]
		var key_boot: Array = [int(row["goals"]), int(row["assists"]), e["id"]]
		if int(row["goals"]) > 0 and _better(key_boot, boot_key):
			boot_key = key_boot
			boot = e["id"]
		if int(row["apps"]) < MIN_APPS:
			continue
		var avg := _avg(row)
		var key: Array = [avg, int(row["goals"]), e["id"]]
		if _better(key, poty_key):
			poty_key = key
			poty = e["id"]
		if p.position == PlayerData.Position.GK:
			var gkey: Array = [avg, int(row["clean_sheets"]), e["id"]]
			if _better(gkey, gk_key):
				gk_key = gkey
				gk = e["id"]
		if p.age <= YOUNG_AGE and _better(key, young_key):
			young_key = key
			young = e["id"]
		ranked.append({"id": e["id"], "avg": avg, "goals": int(row["goals"]), "pos": p.position})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["avg"] > b["avg"] if a["avg"] != b["avg"] else a["id"] < b["id"])
	var wanted := {"GK": 1, "DEF": 4, "MID": 3, "FWD": 3}
	var team: Array = []
	for group in ["GK", "DEF", "MID", "FWD"]:
		var n := 0
		for r in ranked:
			if _group(r["pos"]) == group and n < int(wanted[group]):
				team.append(r["id"])
				n += 1
	best = {"golden_boot": boot, "golden_boot_goals": int(stats[boot]["goals"]) if boot != "" else 0,
			"player_of_the_season": poty, "best_goalkeeper": gk, "best_young_player": young, "team_of_the_season": team}
	return best


static func _group(pos: int) -> String:
	match pos:
		PlayerData.Position.GK:
			return "GK"
		PlayerData.Position.CB, PlayerData.Position.LB, PlayerData.Position.RB:
			return "DEF"
		PlayerData.Position.CDM, PlayerData.Position.CM, PlayerData.Position.CAM, PlayerData.Position.LM, PlayerData.Position.RM:
			return "MID"
	return "FWD"
