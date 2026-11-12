class_name YouthGenerator
extends RefCounted

## Procedural youth prospect generator (Phase T4). Fully deterministic: each
## prospect is derived from (academy_seed, index) only, so reloading a save
## can never regenerate or duplicate players.

const NAME_POOLS := {
	"Aldoria": {"first": ["Adam", "Luca", "Marco", "Felix", "Hugo", "Leon", "Nico", "Anton"],
			"last": ["Vale", "Brandt", "Santoro", "Hartmann", "Costa", "Rossi", "Moreau", "Olsen"]},
	"Zamoria": {"first": ["Karim", "Tariq", "Omar", "Idris", "Sami", "Yusuf", "Rami", "Zaid"],
			"last": ["Haddad", "Kaya", "Zaman", "Okoro", "Mansour", "Farouk", "Nasser", "Rahim"]},
	"Norvland": {"first": ["Jonas", "Elias", "Noah", "Viktor", "Erik", "Axel", "Anders", "Sven"],
			"last": ["Lindqvist", "Olsen", "Petrov", "Novak", "Bergström", "Haugen", "Dahl", "Strand"]},
	"Solmara": {"first": ["Mateo", "Rafael", "Dario", "Bruno", "Diego", "Joao", "Pablo", "Tiago"],
			"last": ["Duarte", "Ferrer", "Silva", "Reyes", "Mbeki", "Navarro", "Pereira", "Lopes"]},
}
## Real-world countries of the data packs (random first + last combinations, fictional people).
const REAL_POOLS := {
	"England": {"first": ["Jack", "Harry", "Oliver", "George", "Charlie", "Alfie", "Jacob", "Thomas", "James", "Callum", "Ryan", "Lewis"],
			"last": ["Walker", "Hughes", "Barnes", "Holt", "Pearce", "Whitfield", "Marsh", "Cartwright", "Doyle", "Fletcher", "Haines", "Kirby"]},
	"Spain": {"first": ["Pablo", "Álvaro", "Javier", "Sergio", "Diego", "Adrián", "Rubén", "Iván", "Hugo", "Mario", "Raúl", "Óscar"],
			"last": ["Moreno", "Navarro", "Iglesias", "Ortega", "Delgado", "Castro", "Vidal", "Serrano", "Molina", "Gil", "Rubio", "Marín"]},
	"Germany": {"first": ["Lukas", "Jonas", "Leon", "Felix", "Tim", "Niklas", "Moritz", "Paul", "Jan", "Fabian", "Tobias", "Florian"],
			"last": ["Becker", "Schröder", "Neumann", "Krüger", "Hofmann", "Wolf", "Lange", "Brandt", "Zimmermann", "Kraus", "Vogt", "Busch"]},
	"Italy": {"first": ["Lorenzo", "Matteo", "Alessandro", "Davide", "Simone", "Federico", "Riccardo", "Andrea", "Luca", "Gabriele", "Tommaso", "Nicolò"],
			"last": ["Ferrara", "Galli", "Conti", "Marchetti", "Fontana", "Barbieri", "Rinaldi", "Caruso", "Mancini", "Lombardi", "Moretti", "Testa"]},
	"France": {"first": ["Lucas", "Hugo", "Théo", "Mathis", "Nathan", "Enzo", "Louis", "Maxime", "Antoine", "Clément", "Romain", "Baptiste"],
			"last": ["Lefèvre", "Moreau", "Girard", "Bonnet", "Dupont", "Lambert", "Fontaine", "Rousseau", "Vincent", "Muller", "Faure", "Mercier"]},
}
const DEFAULT_POOL := "Aldoria"

## Position-specific attribute bias (added to the base rating).
const BIAS := {
	PlayerData.Position.CB: {"defending": 12, "physical": 10, "shooting": -14, "dribbling": -8},
	PlayerData.Position.LB: {"pace": 8, "defending": 7, "shooting": -10},
	PlayerData.Position.RB: {"pace": 8, "defending": 7, "shooting": -10},
	PlayerData.Position.CDM: {"defending": 9, "passing": 5, "shooting": -8},
	PlayerData.Position.CM: {"passing": 7, "dribbling": 4},
	PlayerData.Position.CAM: {"passing": 9, "dribbling": 9, "shooting": 4, "defending": -14},
	PlayerData.Position.LM: {"pace": 8, "dribbling": 7, "defending": -8},
	PlayerData.Position.RM: {"pace": 8, "dribbling": 7, "defending": -8},
	PlayerData.Position.LW: {"pace": 11, "dribbling": 11, "defending": -16},
	PlayerData.Position.RW: {"pace": 11, "dribbling": 11, "defending": -16},
	PlayerData.Position.ST: {"shooting": 13, "pace": 5, "physical": 5, "defending": -18},
}

const OUTFIELD_ATTRS: Array[String] = ["pace", "shooting", "passing", "dribbling", "defending", "physical"]


## Generates prospect number `index` for an academy. `quality` (0..1, facilities
## + scouting) shifts potential upward a little but never guarantees it.
static func generate(academy_seed: int, index: int, team_id: String,
		country: String, quality: float = 0.5, forced_age: int = -1) -> PlayerData:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([academy_seed, index])
	var min_age: int = AcademyConfig.AGE_GROUPS[0]["min_age"]
	var max_age: int = AcademyConfig.AGE_GROUPS[AcademyConfig.AGE_GROUPS.size() - 1]["max_age"]
	var age := forced_age if forced_age > 0 else rng.randi_range(min_age, max_age)

	var is_gk := rng.randf() < 0.09
	var pos: int = PlayerData.Position.GK if is_gk else \
			AcademyConfig.OUTFIELD_POSITIONS[rng.randi() % AcademyConfig.OUTFIELD_POSITIONS.size()]

	# Current ability grows with age; wide per-player spread.
	var current_target := 26.0 + (age - min_age) * 3.4 + rng.randfn(0.0, 5.0)
	var p := PlayerData.new()
	p.id = "yth_%s_%05d" % [team_id, index]
	p.age = age
	p.position = pos as PlayerData.Position
	p.team_id = team_id
	p.nationality = country
	p.status = PlayerData.Status.YOUTH
	p.preferred_foot = [PlayerData.Foot.RIGHT, PlayerData.Foot.RIGHT, PlayerData.Foot.LEFT,
			PlayerData.Foot.BOTH][rng.randi() % 4] as PlayerData.Foot
	for attr in OUTFIELD_ATTRS:
		var bias: int = BIAS.get(pos, {}).get(attr, 0)
		p.set(attr, clampi(roundi(current_target + bias + rng.randfn(0.0, 4.5)), 5, 80))
	if is_gk:
		p.goalkeeping = clampi(roundi(current_target + 30.0 + rng.randfn(0.0, 4.0)), 20, 85)
		p.shooting = mini(p.shooting, 30)
		p.dribbling = mini(p.dribbling, 35)
	else:
		p.goalkeeping = rng.randi_range(3, 15)

	# Potential is independent of current ability: gap shrinks with age.
	var overall := p.get_overall()
	var gap_max := lerpf(38.0, 10.0, float(age - min_age) / float(max_age - min_age))
	var gap := rng.randf_range(2.0, gap_max) + (quality - 0.5) * 8.0
	p.potential = clampi(roundi(overall + maxf(gap, 1.0)), overall, 95)

	p.fitness = 100
	p.stamina = 100
	p.morale = rng.randi_range(60, 85)
	p.experience = 0
	p.contract_years = 3
	p.salary = 0
	p.transfer_value = overall * overall * 100
	var trait_count := 1 if rng.randf() < 0.7 else 2
	var pool := AcademyConfig.TRAITS.duplicate()
	for i in trait_count:
		var t: String = pool.pop_at(rng.randi() % pool.size())
		p.traits.append(t)
	p.display_name = _name(rng, country)
	p.development_history = [{"event": "generated", "age": age, "overall": overall,
			"potential": p.potential}]
	return p


static func _name(rng: RandomNumberGenerator, country: String) -> String:
	var pool: Dictionary = pool_for(country)
	var first: Array = pool["first"]
	var last: Array = pool["last"]
	return "%s %s" % [first[rng.randi() % first.size()], last[rng.randi() % last.size()]]


## Name pool for a country: fictional regions first, then the real-world countries of the
## data packs, else the default pool.
static func pool_for(country: String) -> Dictionary:
	if NAME_POOLS.has(country):
		return NAME_POOLS[country]
	return REAL_POOLS.get(country, NAME_POOLS[DEFAULT_POOL])
