class_name MatchSimulator
extends RefCounted

## Quick, engine-free result for a fixture (strength-weighted Poisson goals, home advantage,
## penalties for knockout draws). Shared by the hub's "quick sim" and the league pyramid that
## plays every match the user does not play. Same numbers as the original AppHub version.


## `ratings` (optional) is a team id -> rating cache the caller owns for one batch of matches played in the same moment
## (a calendar week): rating the same club once instead of once per match. It must not outlive squad changes.
## `excluded` (optional): player ids who may not take part (a loanee against his own club): the side they belong to is rated
## without them. Empty = the cached club ratings, exactly as before.
static func result(db: Node, f: Dictionary, seed_value: int = 0, ratings: Dictionary = {}, excluded: Array = []) -> MatchResult:
	var match_id: String = f["match_id"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, match_id])
	var hr: int = (rating_without(db, f["home"], excluded) if not excluded.is_empty() else rating_of(db, f["home"], ratings)) + 4
	var ar: int = rating_without(db, f["away"], excluded) if not excluded.is_empty() else rating_of(db, f["away"], ratings)
	var hg := goals(rng, hr - ar)
	var ag := goals(rng, ar - hr)
	var knockout: bool = f["stage"] == "ko" or f["stage"] == "third"
	if knockout and hg == ag:
		var pens := PenaltyShootout.resolve(hr, ar, rng)
		return MatchResult.make(match_id, f["home"], f["away"], hg, ag, pens[0], pens[1])
	return MatchResult.make(match_id, f["home"], f["away"], hg, ag)


## A result inside a career: loanees with the clause "may not play against his own club" sit this fixture out.
static func career_result(career: CareerState, f: Dictionary, seed_value: int = 0, ratings: Dictionary = {}) -> MatchResult:
	var excluded: Array = []
	if career != null and career.market != null:
		excluded = career.market.blocked_against(f["home"], f["away"]) + career.market.blocked_against(f["away"], f["home"])
	return result(career.db, f, seed_value, ratings, excluded)


## Club rating (the best eleven, as `get_team_rating`) leaving out `excluded` players.
static func rating_without(db: Node, team_id: String, excluded: Array) -> int:
	var overalls: Array[int] = []
	for p in db.get_squad(team_id):
		if not (p.id in excluded):
			overalls.append(p.get_overall())
	if overalls.size() < 11:
		return db.get_team_rating(team_id)
	overalls.sort()
	overalls.reverse()
	var total := 0
	for i in 11:
		total += overalls[i]
	return roundi(total / 11.0)


static func rating_of(db: Node, team_id: String, ratings: Dictionary) -> int:
	if not ratings.has(team_id):
		ratings[team_id] = db.get_team_rating(team_id)
	return ratings[team_id]


static func goals(rng: RandomNumberGenerator, edge: int) -> int:
	var lam := clampf(1.3 + edge * 0.04, 0.2, 3.5)
	var g := 0
	var l := exp(-lam)
	var p := 1.0
	while true:
		p *= rng.randf()
		if p <= l:
			break
		g += 1
		if g > 9:
			break
	return g
