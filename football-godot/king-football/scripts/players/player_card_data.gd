class_name PlayerCardData
extends RefCounted

## View-model of one player card (Phase V7). Built FROM the live `PlayerData`
## (and its team) every time it is needed and never stored, so a card cannot
## become an independent or outdated copy: attribute growth, position change,
## transfer, promotion and kit changes show up on the next build.
##
## Gameplay data (attributes, position, ovr) stays in `PlayerData`; appearance
## data in `PlayerData.appearance`; kit data in `TeamData.kits`; card class is
## derived from the overall (`CardCategory`). Nothing here is persisted.

## Six core attributes in display order: [short code key, PlayerData attribute].
const CORE := [["PAC", "pace"], ["SHO", "shooting"], ["PAS", "passing"],
		["DRI", "dribbling"], ["DEF", "defending"], ["PHY", "physical"]]

var player_id := ""
var name := ""
var age := 0
var nationality := ""
var club := ""
var club_id := ""
var position := ""
var overall := 0
var category: int = CardCategory.Kind.BRONZE
var stats: Array = []          # [{code, attr, value}] — real attributes, six core
var goalkeeping := -1          # shown additionally for goalkeepers only
var is_goalkeeper := false
var shirt_number := 0
var status := ""
var kit_slot := "home"
var appearance: Dictionary = {}

# --- display data (round 3, task B) -------------------------------------------------------------
var full_name := ""
var last_name := ""
var country_id := ""
var country_name := ""          # translated (Loc.country) at build time
var flag: Texture2D            # never null: FlagService falls back to a neutral flag
var club_crest: Texture2D      # null for a free agent
var club_name := ""
var league_name := ""           # "" outside a league system (fictional default world)
var birth_year := 0
var height_cm := 0
var weight_kg := 0
var preferred_foot := ""        # Foot enum key: RIGHT / LEFT / BOTH
var secondary_positions: Array = []
var potential := 0
var traits: Array = []
var contract_years := 0
var salary := 0
var market_value := 0
var fitness := 0
var morale := 0
var loan_parent := ""
## Badges: set by the caller where it knows (a squad knows its captain).
var is_captain := false
## Last match ratings (newest last), filled by `with_recent_ratings` when a career log exists.
var recent_ratings: Array = []

const YOUTH_AGE := 21
const POTENTIAL_ARROW := 5


## Returns null for an unknown player id (callers show an empty state).
static func from_player(db: Node, player_id_: String, slot: String = "home") -> PlayerCardData:
	var p: PlayerData = db.get_player(player_id_)
	if p == null:
		return null
	return from_data(db, p, slot)


static func from_data(db: Node, p: PlayerData, slot: String = "home") -> PlayerCardData:
	var c := PlayerCardData.new()
	c.player_id = p.id
	c.name = p.display_name
	c.age = p.age
	c.nationality = p.nationality
	c.position = PlayerData.Position.keys()[p.position]
	c.overall = p.get_overall()
	c.category = CardCategory.for_overall(c.overall)
	c.shirt_number = p.shirt_number
	c.status = PlayerData.Status.keys()[p.status]
	c.kit_slot = slot
	c.is_goalkeeper = p.position == PlayerData.Position.GK
	c.goalkeeping = p.goalkeeping if c.is_goalkeeper else -1
	for pair in CORE:
		c.stats.append({"code": pair[0], "attr": pair[1], "value": p.get_attribute(pair[1])})
	var team: TeamData = db.get_team(p.team_id) if p.team_id != "" else null
	c.club_id = p.team_id
	c.club = team.display_name if team != null else ""
	c.appearance = PlayerAppearance.ensure(p).duplicate(true)
	c.full_name = p.display_name
	c.last_name = p.last_name if p.last_name != "" else str(PlayerData.split_name(p.display_name)[1])
	if c.last_name == "":
		c.last_name = p.display_name
	c.country_id = p.nationality_id
	if c.country_id == "" and db.has_method("country_id_for"):
		c.country_id = db.country_id_for(p.nationality)
	c.country_name = Loc.country(p.nationality)
	c.flag = FlagService.texture(c.country_id)
	c.club_name = c.club
	c.club_crest = CrestService.texture(db, p.team_id, "card") if team != null else null
	c.league_name = league_of(db, team)
	c.birth_year = p.birth_year
	c.height_cm = p.get_height_cm()
	c.weight_kg = p.get_weight_kg()
	c.preferred_foot = PlayerData.Foot.keys()[p.preferred_foot]
	c.secondary_positions = p.secondary_positions.duplicate()
	c.potential = p.potential
	c.traits = p.traits.duplicate()
	c.contract_years = p.contract_years
	c.salary = p.salary
	c.market_value = p.transfer_value
	c.fitness = p.fitness
	c.morale = p.morale
	c.loan_parent = p.loan_parent
	return c


## Display name of the division the club plays in ("" when there is no league system).
static func league_of(db: Node, team: TeamData) -> String:
	if team == null or team.league_id == "" or not ("leagues" in db):
		return ""
	for lg: LeagueDef in db.leagues.values():
		var dv := lg.division(team.league_id)
		if not dv.is_empty():
			return LeaguePyramid.label(str(dv.get("name", "")))
	return ""


## Badges shown on the full card, in display order: injured / suspended / loan / captain / youth / potential.
func badges() -> Array:
	var out: Array = []
	if status == "INJURED":
		out.append("injured")
	elif status == "SUSPENDED":
		out.append("suspended")
	if status == "LOANED" or loan_parent != "":
		out.append("loan")
	if is_captain:
		out.append("captain")
	if age > 0 and age < YOUTH_AGE:
		out.append("youth")
	if potential - overall >= POTENTIAL_ARROW:
		out.append("potential")
	return out


## Fills `recent_ratings` with the player's last `n` match ratings from a career match log
## (array of engine reports, oldest first). Returns self for chaining.
func with_recent_ratings(match_log: Array, n: int = 5) -> PlayerCardData:
	recent_ratings.clear()
	for i in range(match_log.size() - 1, -1, -1):
		for e in (match_log[i] as Dictionary).get("players", []):
			if str(e.get("player_id", "")) == player_id:
				recent_ratings.push_front(float(e.get("rating", 0.0)))
				break
		if recent_ratings.size() >= n:
			break
	return self


## Kit colours the portrait should wear: the player's club kit (outfield or
## goalkeeper slot), falling back to the default TeamKit.
func kit(db: Node) -> TeamKit:
	var team: TeamData = db.get_team(club_id) if club_id != "" else null
	if team == null:
		return TeamKit.new()
	var slot_name := "goalkeeper" if is_goalkeeper else kit_slot
	return TeamKit.for_team(db, team, slot_name)


## Stable cache key: changes whenever anything visible in the portrait changes.
func portrait_key(db: Node) -> String:
	var k := kit(db)
	var crest := CrestService.crest_of(db, club_id) if club_id != "" else null
	var crest_key := CrestService.cache_key(crest, "kit", 0) if crest != null else "-"     # the chest badge is part of the picture
	return "%s|%s|%s|%s|%s|%s|%s|%d|%s|%s" % [player_id, PlayerAppearance.signature(appearance),
			k.jersey.to_html(false), k.trim.to_html(false), k.shorts.to_html(false),
			k.socks.to_html(false), "gk" if is_goalkeeper else "of", shirt_number, k.pattern, crest_key]
