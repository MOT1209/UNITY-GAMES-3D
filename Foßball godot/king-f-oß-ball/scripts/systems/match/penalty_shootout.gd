class_name PenaltyShootout
extends RefCounted

## Deterministic-with-rng penalty shoot-out: 5 kicks each, then sudden death.
## Scoring chance rises slightly with team rating. Never ends level.


static func resolve(home_rating: int, away_rating: int, rng: RandomNumberGenerator = null) -> Array:
	var r := rng if rng != null else RandomNumberGenerator.new()
	var ph := clampf(0.72 + (home_rating - 60) * 0.002, 0.55, 0.9)
	var pa := clampf(0.72 + (away_rating - 60) * 0.002, 0.55, 0.9)
	var hs := 0
	var as_ := 0
	for i in 5:
		if r.randf() < ph:
			hs += 1
		if r.randf() < pa:
			as_ += 1
	var guard := 0
	while hs == as_ and guard < 200:
		guard += 1
		var h := r.randf() < ph
		var a := r.randf() < pa
		if h:
			hs += 1
		if a:
			as_ += 1
		if h and a:       # both scored: the round does not decide it
			continue
		if h != a:
			break
	if hs == as_:         # astronomically unlikely guard: force a winner
		hs += 1
	return [hs, as_]
