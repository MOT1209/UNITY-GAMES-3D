class_name MatchSimulator
extends RefCounted

## Quick, engine-free result for a fixture (strength-weighted Poisson goals, home advantage,
## penalties for knockout draws). Shared by the hub's "quick sim" and the league pyramid that
## plays every match the user does not play. Same numbers as the original AppHub version.


static func result(db: Node, f: Dictionary, seed_value: int = 0) -> MatchResult:
	var match_id: String = f["match_id"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, match_id])
	var hr: int = db.get_team_rating(f["home"]) + 4
	var ar: int = db.get_team_rating(f["away"])
	var hg := goals(rng, hr - ar)
	var ag := goals(rng, ar - hr)
	var knockout: bool = f["stage"] == "ko" or f["stage"] == "third"
	if knockout and hg == ag:
		var pens := PenaltyShootout.resolve(hr, ar, rng)
		return MatchResult.make(match_id, f["home"], f["away"], hg, ag, pens[0], pens[1])
	return MatchResult.make(match_id, f["home"], f["away"], hg, ag)


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
