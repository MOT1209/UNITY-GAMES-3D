class_name ClubGenerator
extends RefCounted

## Deterministic generator of FICTIONAL clubs and their squads (database phase 6).
## Same (world seed, country, index) -> same club, always: every random choice comes from a
## RandomNumberGenerator seeded by hash([seed, country id, index]). Names, places and colours are
## invented (nothing is taken from a real club); names are checked against every name already in
## the world (real clubs and real players included) and rejected when equal or too similar.
## Nothing is generated when a screen opens: `tools/generate_world.tscn` writes the result to data
## files that ship with the pack.

const GENERATOR_VERSION := 1
const SQUAD_SIZE := 28
## 28 positions, goalkeeper first; the shirt number is the index + 1.
const LAYOUT: Array[int] = [
	PlayerData.Position.GK, PlayerData.Position.CB, PlayerData.Position.CB, PlayerData.Position.LB, PlayerData.Position.RB,
	PlayerData.Position.CDM, PlayerData.Position.CM, PlayerData.Position.CM, PlayerData.Position.LW, PlayerData.Position.ST,
	PlayerData.Position.RW, PlayerData.Position.GK, PlayerData.Position.CB, PlayerData.Position.CB, PlayerData.Position.LB,
	PlayerData.Position.RB, PlayerData.Position.CDM, PlayerData.Position.CM, PlayerData.Position.CAM, PlayerData.Position.LM,
	PlayerData.Position.RM, PlayerData.Position.ST, PlayerData.Position.CAM, PlayerData.Position.CM, PlayerData.Position.CB,
	PlayerData.Position.GK, PlayerData.Position.CDM, PlayerData.Position.ST,
]

## country -> {id (3 letters, as in countries.json), place prefixes, place suffixes, club prefixes, club suffixes,
## stadium pattern}. "{p}" = place.
const STYLES := {
	"England": {"cc": "eng", "pre": ["Ash", "Brook", "Cald", "Dun", "Elm", "Fair", "Grey", "Hollow", "Kings", "Lang", "Mill", "North", "Oak", "Pen", "Red", "Stan", "Thorn", "Water", "West", "Wyn", "Black", "Cross", "Hart", "Marsh", "Rush", "Sand", "Whit"],
			"suf": ["bridge", "bury", "by", "field", "ford", "ham", "ley", "mere", "ton", "wick", "worth", "stead", "well", "combe"],
			"club_pre": [], "club_suf": ["Town", "Rovers", "United", "Athletic", "City", "Wanderers", "Albion", "Rangers", "Borough"],
			"stadium": "{p} Park"},
	"Spain": {"cc": "esp", "pre": ["Alto", "Bella", "Campo", "Monte", "Villa", "Valle", "Peña", "Puerto", "Río", "Sierra", "Torre", "Santa", "Nueva", "Fuente", "Casa"],
			"suf": ["nueva", "verde", "blanca", "alta", "baja", "mar", "rey", "seca", "dorada", "grande", "luz", "sol"],
			"club_pre": ["CD", "UD", "CF", "Real", "Racing", "Atlético", "Deportivo"], "club_suf": [],
			"stadium": "Estadio {p}"},
	"Germany": {"cc": "ger", "pre": ["Hohen", "Neu", "Alt", "Wald", "Berg", "Stein", "Linden", "Eichen", "Rhein", "Nord", "Süd", "Ost", "Burg", "Lichten", "Rosen", "Wolfs", "Hirsch", "Falken", "Klein"],
			"suf": ["feld", "burg", "stadt", "hausen", "dorf", "bach", "heim", "au", "tal", "stein", "wald", "berg"],
			"club_pre": ["SV", "FC", "TSV", "VfB", "SC", "Eintracht", "Union", "VfL", "SpVgg"], "club_suf": [],
			"stadium": "{p}-Stadion"},
	"Italy": {"cc": "ita", "pre": ["Castel", "Monte", "Borgo", "Villa", "Ponte", "Torre", "Porto", "Campo", "Val", "Rocca", "Pian", "Casa"],
			"suf": ["vecchio", "alto", "bello", "nuovo", "verde", "mare", "fiore", "rosso", "sole", "grande", "bianco", "longo"],
			"club_pre": ["AC", "US", "SS", "Virtus", "Pro", "AS", "Unione", "Atletico"], "club_suf": [],
			"stadium": "Stadio {p}"},
	"France": {"cc": "fra", "pre": ["Beau", "Mont", "Val", "Ville", "Châ", "Fontaine", "Bois", "Pont", "Roche", "Clair", "Bel", "Haute", "Neuf", "Bourg"],
			"suf": ["marais", "mont", "fort", "vert", "blanche", "pré", "fleur", "val", "champ", "bourg", "lieu", "mer"],
			"club_pre": ["FC", "AS", "US", "Olympique", "Stade", "SC", "Racing", "AC"], "club_suf": [],
			"saints": ["Saint-Aubin", "Saint-Valery", "Saint-Léger", "Saint-Orens", "Saint-Clair", "Saint-Gilles", "Saint-Mathieu"],
			"stadium": "Stade {p}"},
}
## (primary, secondary) shirt colours, club colours of nobody in particular.
const PALETTE: Array[String] = ["c8102e", "003399", "00843d", "f2c500", "6a1b9a", "ef6c00", "00838f", "111111", "ffffff", "8d1b3d", "1e90ff", "2e7d32", "ff69b4", "795548", "607d8b", "b71c1c"]
const SECONDARY: Array[String] = ["ffffff", "111111", "f2c500", "0b2a5b", "c8102e"]


## Name, place, id and basic data of the `index`-th fictional club of `country`.
## `used` = {"names": NameIndex (clubs), "places": {place: true}, "shorts": {code: true}, "ids": {id: true}}.
static func generate_club(world_seed: int, country: String, index: int, tier: int, division_id: String, used: Dictionary,
		cup_id: String) -> Dictionary:
	var style: Dictionary = STYLES[country]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, style["cc"], tier, index])
	var place := ""
	var name := ""
	for attempt in 60:
		place = _place(rng, style)
		if used["places"].has(place.to_lower()):
			continue
		name = _club_name(rng, style, place)
		if (used["names"] as NameIndex).check(name) == "":
			break
		name = ""
	if name == "":                              # extremely unlikely: make the place unique with a numeral
		place = "%s %d" % [_place(rng, style), index + 2]
		name = _club_name(rng, style, place)
	used["places"][place.to_lower()] = true
	(used["names"] as NameIndex).add(name)
	var slug := NameIndex.normalize(name).replace(" ", "_")
	var id := "fic_%s_%s" % [style["cc"], slug]
	var n := 2
	while used["ids"].has(id):
		id = "fic_%s_%s_%d" % [style["cc"], slug, n]
		n += 1
	used["ids"][id] = true
	var rep := clampi(roundi(rng.randfn(45.0, 4.0)), 36, 54)
	var primary_hex: String = PALETTE[rng.randi() % PALETTE.size()]
	var secondary_hex := primary_hex
	while secondary_hex == primary_hex:
		secondary_hex = SECONDARY[rng.randi() % SECONDARY.size()] if rng.randf() < 0.8 else PALETTE[rng.randi() % PALETTE.size()]
	return {"id": id, "name": name, "place": place, "country": country, "reputation": rep,
			"short_name": _short(place, used["shorts"]), "primary": primary_hex, "secondary": secondary_hex,
			"stadium_name": String(style["stadium"]).replace("{p}", place), "division_id": division_id, "tier": tier,
			"cup_id": cup_id, "rng_seed": rng.randi()}


static func _place(rng: RandomNumberGenerator, style: Dictionary) -> String:
	if style.has("saints") and rng.randf() < 0.18:
		return (style["saints"] as Array)[rng.randi() % (style["saints"] as Array).size()]
	var pre: String = (style["pre"] as Array)[rng.randi() % (style["pre"] as Array).size()]
	var suf: String = (style["suf"] as Array)[rng.randi() % (style["suf"] as Array).size()]
	return pre + suf


static func _club_name(rng: RandomNumberGenerator, style: Dictionary, place: String) -> String:
	var pre: Array = style["club_pre"]
	var suf: Array = style["club_suf"]
	if not suf.is_empty():
		return "%s %s" % [place, suf[rng.randi() % suf.size()]]
	return "%s %s" % [pre[rng.randi() % pre.size()], place]


## Unique 3-letter code from the place name (letters first, then other letters, then a digit).
static func _short(place: String, taken: Dictionary) -> String:
	var letters := NameIndex.normalize(place).replace(" ", "").to_upper()
	var tries: Array[String] = [letters.substr(0, 3)]
	for i in range(1, maxi(letters.length() - 2, 1)):
		tries.append(letters.substr(0, 1) + letters.substr(i, 2))
	for c in tries:
		if c.length() == 3 and not taken.has(c):
			taken[c] = true
			return c
	var n := 1
	while taken.has("%s%d" % [letters.substr(0, 2), n]):
		n += 1
	var code := "%s%d" % [letters.substr(0, 2), n]
	taken[code] = true
	return code


# --- squads ---------------------------------------------------------------------------------------

## Squad of `SQUAD_SIZE` players for a club: deterministic from the club data, names unique in
## `names` (a NameIndex shared by the whole world). ~80 % of the players have the club's nationality,
## the rest one of the other four countries; names always come from the player's own nationality.
static func generate_squad(club: Dictionary, names: NameIndex) -> Array[PlayerData]:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(club["rng_seed"]) ^ 0x5bd1e995
	var out: Array[PlayerData] = []
	var rep: int = club["reputation"]
	for i in SQUAD_SIZE:
		var pos: int = LAYOUT[i]
		var p := PlayerData.new()
		p.id = "gen_%s_%02d" % [club["id"], i + 1]
		p.team_id = club["id"]
		p.nationality = club["country"] if rng.randf() < 0.8 else NameBank.COUNTRIES[rng.randi() % NameBank.COUNTRIES.size()]
		p.display_name = NameBank.unique_name(rng, p.nationality, names)
		var parts := PlayerData.split_name(p.display_name)
		p.first_name = parts[0]
		p.last_name = parts[1]
		p.player_type = PlayerData.PlayerType.GENERATED
		p.position = pos as PlayerData.Position
		p.shirt_number = i + 1
		p.age = _age(rng)
		p.preferred_foot = [PlayerData.Foot.RIGHT, PlayerData.Foot.RIGHT, PlayerData.Foot.RIGHT, PlayerData.Foot.LEFT, PlayerData.Foot.BOTH][rng.randi() % 5] as PlayerData.Foot
		var base := 27.0 + rep * 0.42 + rng.randf_range(-5.0, 5.0) - (4.0 if i >= 15 else 0.0)
		for attr in YouthGenerator.OUTFIELD_ATTRS:
			var bias: int = YouthGenerator.BIAS.get(pos, {}).get(attr, 0)
			p.set(attr, clampi(roundi(base + bias + rng.randf_range(-5.0, 5.0)), 5, 85))
		if pos == PlayerData.Position.GK:
			p.goalkeeping = clampi(roundi(base + 38.0 + rng.randf_range(-5.0, 5.0)), 20, 85)
			p.shooting = mini(p.shooting, 35)
			p.dribbling = mini(p.dribbling, 40)
		else:
			p.goalkeeping = rng.randi_range(5, 16)
		var ov := p.get_overall()
		var room := rng.randi_range(0, 14) if p.age < 23 else (rng.randi_range(0, 8) if p.age < 27 else rng.randi_range(0, 3))
		p.potential = clampi(ov + room, ov, 92)
		p.experience = clampi((p.age - 17) * 14 + rng.randi_range(0, 60), 0, 400)
		p.contract_years = rng.randi_range(1, 4)
		p.salary = maxi(ov * ov / 5, 200)
		p.transfer_value = ov * ov * 300
		p.morale = rng.randi_range(60, 85)
		out.append(p)
	return out


static func _age(rng: RandomNumberGenerator) -> int:
	var r := rng.randf()
	if r < 0.25:
		return rng.randi_range(17, 21)
	if r < 0.70:
		return rng.randi_range(22, 27)
	if r < 0.95:
		return rng.randi_range(28, 33)
	return rng.randi_range(34, 36)


# --- team record ------------------------------------------------------------------------------------

## TeamData for a generated club (all supported optional fields filled; this is fictional data).
static func make_team(club: Dictionary, squad: Array[PlayerData], rival_ids: Array, world_seed: int) -> TeamData:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(club["rng_seed"]) ^ 0x2545f491
	var t := TeamData.new()
	t.id = club["id"]
	t.display_name = club["name"]
	t.full_name = club["name"]
	t.short_name = club["short_name"]
	t.category = TeamData.Category.CLUB
	t.is_real = false
	t.club_type = TeamData.ClubType.FICTIONAL
	t.country = club["country"]
	t.city = club["place"]
	t.founding_year = rng.randi_range(1885, 1995)
	t.description = "Fictional club generated for the %s third division (seed %d)." % [club["country"], world_seed]
	t.primary_color = Color.from_string(club["primary"], Color.WHITE)
	t.secondary_color = Color.from_string(club["secondary"], Color.BLACK)
	t.kits = KitEditor.default_kits(t.primary_color, t.secondary_color)
	t.reputation = club["reputation"]
	t.budget = 1_000_000 + (t.reputation - 35) * 60_000
	var wages := 0
	for p in squad:
		wages += p.salary
	t.transfer_budget = int(t.budget * 0.4)
	t.wage_budget = int(wages * 1.3)
	t.current_balance = t.budget
	t.weekly_expenses = wages
	t.sponsorship_income = t.reputation * 2000
	t.stadium_id = "std_" + t.id
	t.stadium_name = club["stadium_name"]
	t.stadium_capacity = 2500 + (t.reputation - 35) * 450 + rng.randi_range(0, 1500)
	t.stadium_level = 1 if t.reputation < 46 else 2
	t.rival_club_ids = PackedStringArray(rival_ids)
	t.competition_ids = PackedStringArray([club["division_id"], club["cup_id"]])
	t.squad_ids = PackedStringArray(squad.map(func(p: PlayerData) -> String: return p.id))
	return t
