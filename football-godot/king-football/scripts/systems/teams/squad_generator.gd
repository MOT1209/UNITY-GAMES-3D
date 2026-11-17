class_name SquadGenerator
extends RefCounted

## Deterministic first-team squad generation for NEW fictional clubs (Phase T7).
## Not a manual player editor: users choose a strength level, the generator
## produces believable players (same approach as the seed data).

const LAYOUT: Array[int] = [
	PlayerData.Position.GK, PlayerData.Position.GK, PlayerData.Position.CB, PlayerData.Position.CB,
	PlayerData.Position.CB, PlayerData.Position.CB, PlayerData.Position.LB, PlayerData.Position.RB,
	PlayerData.Position.CDM, PlayerData.Position.CDM, PlayerData.Position.CM, PlayerData.Position.CM,
	PlayerData.Position.CM, PlayerData.Position.CAM, PlayerData.Position.LW, PlayerData.Position.RW,
	PlayerData.Position.LW, PlayerData.Position.RW, PlayerData.Position.ST, PlayerData.Position.ST,
	PlayerData.Position.ST, PlayerData.Position.CB, PlayerData.Position.CM,
]


static func generate(team_id: String, country: String, strength: int, gen_seed: int) -> Array[PlayerData]:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([gen_seed, team_id])
	var pool: Dictionary = YouthGenerator.pool_for(country)
	var out: Array[PlayerData] = []
	var used_names := {}
	for i in LAYOUT.size():
		var pos: int = LAYOUT[i]
		var p := PlayerData.new()
		p.id = "plr_%s_%02d" % [team_id, i + 1]
		p.team_id = team_id
		p.nationality = country
		p.position = pos as PlayerData.Position
		p.shirt_number = i + 1
		p.age = rng.randi_range(19, 35)
		p.preferred_foot = [PlayerData.Foot.RIGHT, PlayerData.Foot.RIGHT, PlayerData.Foot.LEFT,
				PlayerData.Foot.BOTH][rng.randi() % 4] as PlayerData.Foot
		var base := 38.0 + strength * 0.42 + rng.randf_range(-7.0, 7.0) - (6.0 if i >= 11 else 0.0)
		for attr in YouthGenerator.OUTFIELD_ATTRS:
			var bias: int = YouthGenerator.BIAS.get(pos, {}).get(attr, 0)
			p.set(attr, clampi(roundi(base + bias + rng.randf_range(-5.0, 5.0)), 1, 99))
		if pos == PlayerData.Position.GK:
			p.goalkeeping = clampi(roundi(base + 40.0 + rng.randf_range(-5.0, 5.0)), 1, 99)
			p.shooting = mini(p.shooting, 35)
			p.dribbling = mini(p.dribbling, 40)
		else:
			p.goalkeeping = rng.randi_range(5, 18)
		var ov := p.get_overall()
		p.potential = clampi(ov + (rng.randi_range(0, 12) if p.age < 26 else rng.randi_range(0, 3)), ov, 99)
		p.experience = rng.randi_range(0, 300)
		p.contract_years = rng.randi_range(1, 5)
		p.salary = ov * ov / 4
		p.transfer_value = ov * ov * 400
		# unique display name inside the squad
		var tries := 0
		var nm := ""
		while tries < 30:
			nm = "%s %s" % [(pool["first"] as Array)[rng.randi() % (pool["first"] as Array).size()],
					(pool["last"] as Array)[rng.randi() % (pool["last"] as Array).size()]]
			if not used_names.has(nm):
				break
			tries += 1
		used_names[nm] = true
		p.display_name = nm
		out.append(p)
	return out
