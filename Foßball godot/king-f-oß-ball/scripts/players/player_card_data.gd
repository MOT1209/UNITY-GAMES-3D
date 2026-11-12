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
	return c


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
