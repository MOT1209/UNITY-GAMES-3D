class_name MatchSimulator
extends RefCounted

## Quick, engine-free result for a fixture (strength-weighted Poisson goals, home advantage,
## penalties for knockout draws). Shared by the hub's "quick sim" and the league pyramid that
## plays every match the user does not play. Same numbers as the original AppHub version.


## `ratings` (optional) is a team id -> rating cache the caller owns for one batch of matches played in the same moment
## (a calendar week): rating the same club once instead of once per match. It must not outlive squad changes.
static func result(db: Node, f: Dictionary, seed_value: int = 0, ratings: Dictionary = {}) -> MatchResult:
	var match_id: String = f["match_id"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, match_id])
	var hr: int = rating_of(db, f["home"], ratings) + 4
	var ar: int = rating_of(db, f["away"], ratings)
	var hg := goals(rng, hr - ar)
	var ag := goals(rng, ar - hr)
	var knockout: bool = f["stage"] == "ko" or f["stage"] == "third"
	if knockout and hg == ag:
		var pens := PenaltyShootout.resolve(hr, ar, rng)
		return MatchResult.make(match_id, f["home"], f["away"], hg, ag, pens[0], pens[1])
	return MatchResult.make(match_id, f["home"], f["away"], hg, ag)


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
