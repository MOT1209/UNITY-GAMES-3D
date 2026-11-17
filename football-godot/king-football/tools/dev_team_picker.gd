## Developer helper: picks two playable clubs from the team database that is actually loaded.
##
## The tools used to hard-code `club_royal_harbor` / `club_northgate_utd`. Those ids only exist in
## the default world (data/clubs), NOT in the shipped data packs (data/packs/real_2025), so
## `MatchSetup.validate()` failed, `MatchManager.begin()` returned an error string that the tools
## ignored, and the tools then waited forever on a null match state.
##
## Picking the pair from the live database makes every tool work with every world.
extends RefCounted


## Two club ids that can play a match: same league first, squads first, deterministic order.
## Empty array when the database holds fewer than two clubs.
static func pick_pair(db: Node) -> Array:
	if db == null:
		return []
	var clubs: Array = []
	for id in db.teams.keys():
		var t: TeamData = db.get_team(id)
		if t == null or t.category != TeamData.Category.CLUB:
			continue
		clubs.append(id)
	if clubs.size() < 2:
		return []
	clubs.sort()                                   # deterministic across runs

	# Group by league ("" = the legacy default world has no league ids).
	var by_league := {}
	for id in clubs:
		var t: TeamData = db.get_team(id)
		var key: String = t.league_id if t.league_id != "" else "-"
		if not by_league.has(key):
			by_league[key] = []
		by_league[key].append(id)

	# Prefer the biggest league, then the clubs that actually have a squad.
	var leagues: Array = by_league.keys()
	leagues.sort_custom(func(a: String, b: String) -> bool:
		return by_league[a].size() > by_league[b].size())
	for lid in leagues:
		var ids: Array = by_league[lid]
		if ids.size() < 2:
			continue
		var with_squad: Array = []
		for id in ids:
			var t: TeamData = db.get_team(id)
			if t != null and not t.squad_ids.is_empty():
				with_squad.append(id)
		if with_squad.size() >= 2:
			return [with_squad[0], with_squad[1]]
		return [ids[0], ids[1]]

	# No league with two clubs: use any two clubs that have a squad.
	var with_squad: Array = []
	for id in clubs:
		var t: TeamData = db.get_team(id)
		if t != null and not t.squad_ids.is_empty():
			with_squad.append(id)
	if with_squad.size() >= 2:
		return [with_squad[0], with_squad[1]]
	return [clubs[0], clubs[1]]


## Fills a MatchSetup with a valid pair and returns an error string ("" = ok).
static func fill_setup(setup: MatchSetup, db: Node) -> String:
	var pair := pick_pair(db)
	if pair.size() < 2:
		return "no league with two playable clubs found in the loaded data"
	setup.home_id = pair[0]
	setup.away_id = pair[1]
	return ""
