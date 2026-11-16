class_name MatchSimulator
extends RefCounted

## Quick, engine-free result for a fixture (strength-weighted Poisson goals, home advantage,
## penalties for knockout draws). Shared by the hub's "quick sim" and the league pyramid that
## plays every match the user does not play. Same numbers as the original AppHub version.


## `ratings` (optional) is a team id -> rating cache the caller owns for one batch of matches played in the same moment
## (a calendar week): rating the same club once instead of once per match. It must not outlive squad changes.
## `mods` (optional) = CareerState.style_mods(): the managed club's attack / defence multipliers from the coach's style.
static func result(db: Node, f: Dictionary, seed_value: int = 0, ratings: Dictionary = {}, mods: Dictionary = {}) -> MatchResult:
	var match_id: String = f["match_id"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, match_id])
	var hr: int = rating_of(db, f["home"], ratings) + 4
	var ar: int = rating_of(db, f["away"], ratings)
	var hm := 1.0
	var am := 1.0
	if not mods.is_empty():
		if f["home"] == mods["club"]:
			hm = float(mods["atk"])
			am = float(mods["def"])
		elif f["away"] == mods["club"]:
			am = float(mods["atk"])
			hm = float(mods["def"])
	var hg := goals(rng, hr - ar, hm)
	var ag := goals(rng, ar - hr, am)
	var knockout: bool = f["stage"] == "ko" or f["stage"] == "third"
	if knockout and hg == ag:
		var pens := PenaltyShootout.resolve(hr, ar, rng)
		return MatchResult.make(match_id, f["home"], f["away"], hg, ag, pens[0], pens[1])
	return MatchResult.make(match_id, f["home"], f["away"], hg, ag)


static func rating_of(db: Node, team_id: String, ratings: Dictionary) -> int:
	if not ratings.has(team_id):
		ratings[team_id] = db.get_team_rating(team_id)
	return ratings[team_id]


static func goals(rng: RandomNumberGenerator, edge: int, mult: float = 1.0) -> int:
	var lam := clampf(1.3 + edge * 0.04, 0.2, 3.5) * mult
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
