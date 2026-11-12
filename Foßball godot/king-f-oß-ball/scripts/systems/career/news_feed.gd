class_name NewsFeed
extends RefCounted

## Football news built ONLY from the real state of the career: the transfer history, the injury / ban / season events and the
## league and manager records. Nothing is invented, so the news can never contradict the game state.
## `build()` returns entries {season, week, key, args} (newest first); `Loc.f(key, args)` renders them in the player's language.


static func _name(db: Node, player_id: String) -> String:
	var p: PlayerData = db.get_player(player_id)
	return p.display_name if p != null else player_id


static func _club(db: Node, team_id: String) -> String:
	var t: TeamData = db.get_team(team_id)
	return t.display_name if t != null else team_id


static func build(career: CareerState, limit: int = 20) -> Array:
	var db: Node = career.db
	var out: Array = []
	for h in career.market.history:
		if h["kind"] != "transfer":
			continue
		var to_club := _club(db, h["to"])
		if h["from"] == "":
			out.append({"season": 0, "week": int(h["week"]), "key": "NEWS_FREE_SIGNING", "args": [_name(db, h["player_id"]), to_club], "order": career.season * 1000 + int(h["week"]), "id": int(h["id"])})
		else:
			out.append({"season": 0, "week": int(h["week"]), "key": "NEWS_TRANSFER",
					"args": [_name(db, h["player_id"]), _club(db, h["from"]), to_club, int(h["fee"])], "order": career.season * 1000 + int(h["week"]), "id": int(h["id"])})
	var n := 0
	for e in career.events:
		n += 1
		var a: Array = e["args"]
		var entry := {"season": int(e["season"]), "week": int(e["week"]), "order": int(e["season"]) * 1000 + int(e["week"]), "id": 1_000_000 + n}
		match e["kind"]:
			"injury":
				entry["key"] = "NEWS_INJURY"
				entry["args"] = [_name(db, a[0]), _club(db, a[1]), int(a[2])]
			"ban":
				entry["key"] = "NEWS_BAN"
				entry["args"] = [_name(db, a[0]), _club(db, a[1])]
			"champion":
				entry["key"] = "NEWS_CHAMPION"
				entry["args"] = [_club(db, a[0])]
			"promoted":
				entry["key"] = "NEWS_PROMOTED"
				entry["args"] = [_club(db, a[0])]
			"relegated":
				entry["key"] = "NEWS_RELEGATED"
				entry["args"] = [_club(db, a[0])]
			"award":
				entry["key"] = "NEWS_AWARD_" + str(a[0]).to_upper()
				entry["args"] = [_name(db, a[1]), int(a[2])] if a[0] == "golden_boot" else [_name(db, a[1])]
			"sacked":
				entry["key"] = "NEWS_SACKED"
				entry["args"] = [_club(db, a[0])]
			_:
				continue
		out.append(entry)
	for entry in out:
		if int(entry["season"]) == 0:
			entry["season"] = career.season          # the transfer history stores only the week: it is shown in the current season
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		return int(x["id"]) > int(y["id"]) if x["order"] == y["order"] else int(x["order"]) > int(y["order"]))
	return out.slice(0, limit)


## Historical records computed from the stored statistics (never stored separately, so they cannot drift).
static func records(career: CareerState) -> Dictionary:
	var top_scorer := {"player_id": "", "goals": 0}
	var most_apps := {"player_id": "", "apps": 0}
	var best_rating := {"player_id": "", "rating": 0.0}
	for pid in career.player_stats:
		var s: Dictionary = career.player_stats[pid]
		if int(s["goals"]) > int(top_scorer["goals"]) or (int(s["goals"]) == int(top_scorer["goals"]) and int(s["goals"]) > 0 and pid < top_scorer["player_id"]):
			top_scorer = {"player_id": pid, "goals": int(s["goals"])}
		if int(s["apps"]) > int(most_apps["apps"]) or (int(s["apps"]) == int(most_apps["apps"]) and int(s["apps"]) > 0 and pid < most_apps["player_id"]):
			most_apps = {"player_id": pid, "apps": int(s["apps"])}
		if int(s["apps"]) >= 5:
			var avg := float(s["rating_sum"]) / float(s["apps"])
			if avg > float(best_rating["rating"]):
				best_rating = {"player_id": pid, "rating": snappedf(avg, 0.01)}
	var champions: Array = []
	for h in career.club_history:
		if str(h.get("key", "")).begins_with("rewards_paid_") and str(h.get("champion", "")) != "":
			champions.append({"season": int(h["season"]), "competition": h["competition"], "champion": h["champion"]})
	return {"top_scorer": top_scorer, "most_appearances": most_apps, "best_average_rating": best_rating, "champions": champions,
			"manager_trophies": career.manager.trophies, "seasons": career.manager.history.size()}
