class_name FixtureGenerator
extends RefCounted

## Round-robin fixtures by the circle method. Each round = Array of
## {"home": id, "away": id}. Odd team counts get a bye (no fixture).
## Double round robin = second half with home/away swapped.


static func round_robin(team_ids: Array, double_round: bool = true) -> Array:
	var teams: Array = team_ids.duplicate()
	if teams.size() < 2:
		return []
	if teams.size() % 2 == 1:
		teams.append("")          # bye
	var n := teams.size()
	var rounds: Array = []
	for r in n - 1:
		var matches: Array = []
		for i in n / 2:
			var a: String = teams[i]
			var b: String = teams[n - 1 - i]
			if a == "" or b == "":
				continue
			# Home/away pattern that keeps every team's streak ≤ 3 (verified for 4–20 teams).
			var flip := (r % 2 == 1) if i == 0 else (i % 2 == 1)
			matches.append({"home": b if flip else a, "away": a if flip else b})
		rounds.append(matches)
		# rotate all but the first element
		teams.insert(1, teams.pop_back())
	if double_round:
		var first_half := rounds.size()
		for r in first_half:
			var mirrored: Array = []
			for m in rounds[r]:
				mirrored.append({"home": m["away"], "away": m["home"]})
			rounds.append(mirrored)
	return rounds
