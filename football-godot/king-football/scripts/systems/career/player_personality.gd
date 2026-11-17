class_name PlayerPersonality
extends RefCounted

## Career phase C3.1: a player's personality, DERIVED from his id (so every old save has one, identical on every machine and
## never stored): seven traits 0..20. They bend, never replace, the existing rules:
##   professionalism - training gain (x0.92 .. x1.08), ambition - how fast he wants more (wage / role), loyalty - how willing he is to stay,
##   temperament - how he takes criticism, leadership - his weight in the dressing room, pressure - big-match form, teamwork.

const TRAITS: Array[String] = ["professionalism", "ambition", "loyalty", "temperament", "leadership", "pressure", "teamwork"]


static func for_player(p: PlayerData) -> Dictionary:
	var out := {}
	for t in TRAITS:
		var h := hash([p.id, t, "personality"]) & 0x7fffffff
		# two dice averaged: most players are average, few are extreme; age adds leadership / professionalism
		var v := (h % 21 + (h / 21) % 21) / 2
		if t == "leadership" or t == "professionalism":
			v += clampi((p.age - 24) / 3, 0, 3)
		out[t] = clampi(v, 0, 20)
	return out


static func trait_value(p: PlayerData, trait_name: String) -> int:
	return int(for_player(p).get(trait_name, 10))


## Multiplier on weekly training gain from professionalism (1.0 at 10).
static func training_factor(p: PlayerData) -> float:
	return 1.0 + (float(trait_value(p, "professionalism")) - 10.0) * 0.008
