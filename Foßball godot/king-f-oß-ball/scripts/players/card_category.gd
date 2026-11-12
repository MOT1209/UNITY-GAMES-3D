class_name CardCategory
extends RefCounted

## Visual card classes (Phase V5). Pure presentation: the class is DERIVED from
## the player's current overall rating on every read, so a card can never show
## an outdated class. No packs, no randomness, no monetisation.
##
## One theme table drives ONE card implementation (`PlayerCard`) — there are not
## five separate cards. Brand palette: Black #111111, Gold #D4AF37, Dark Gold
## #A8862D, Royal Red #A51E2B, Ivory #E7E3D8, Steel #343A40.

enum Kind { BRONZE, SILVER, GOLD, ELITE, LEGENDARY }

const BLACK := Color("#111111")
const GOLD := Color("#D4AF37")
const DARK_GOLD := Color("#A8862D")
const ROYAL_RED := Color("#A51E2B")
const IVORY := Color("#E7E3D8")
const STEEL := Color("#343A40")

## Minimum overall for each class (ascending). Legendary = 90+.
const THRESHOLDS := {Kind.BRONZE: 0, Kind.SILVER: 65, Kind.GOLD: 75, Kind.ELITE: 85, Kind.LEGENDARY: 90}

## Per-class presentation. `bg_top/bg_bottom` gradient, `frame` + `frame_dark`
## metal colours, `text` main text, `accent` secondary details, `border` px,
## `shine` 0..1 strength of the (single, subtle) metallic sheen,
## `corner` decoration style, `red` true only for Legendary's controlled accent.
const THEMES := {
	Kind.BRONZE: {"key": "bronze", "bg_top": Color("#3b2a1e"), "bg_bottom": Color("#171210"),
		"frame": Color("#B0763F"), "frame_dark": Color("#6e4521"), "text": IVORY, "accent": Color("#CD8B4F"),
		"border": 3, "shine": 0.10, "ornament": 0, "red": false},
	Kind.SILVER: {"key": "silver", "bg_top": Color("#3d4349"), "bg_bottom": Color("#15181b"),
		"frame": Color("#C4CBD2"), "frame_dark": Color("#7b848c"), "text": IVORY, "accent": Color("#DDE3E8"),
		"border": 4, "shine": 0.16, "ornament": 1, "red": false},
	Kind.GOLD: {"key": "gold", "bg_top": Color("#4a3b12"), "bg_bottom": Color("#16120a"),
		"frame": GOLD, "frame_dark": DARK_GOLD, "text": IVORY, "accent": GOLD,
		"border": 5, "shine": 0.22, "ornament": 2, "red": false},
	Kind.ELITE: {"key": "elite", "bg_top": Color("#26221a"), "bg_bottom": BLACK,
		"frame": GOLD, "frame_dark": DARK_GOLD, "text": IVORY, "accent": GOLD,
		"border": 6, "shine": 0.30, "ornament": 3, "red": false},
	Kind.LEGENDARY: {"key": "legendary", "bg_top": Color("#2a0f14"), "bg_bottom": BLACK,
		"frame": GOLD, "frame_dark": ROYAL_RED, "text": IVORY, "accent": ROYAL_RED,
		"border": 7, "shine": 0.38, "ornament": 4, "red": true},
}


## Class for an overall rating (1..99).
static func for_overall(overall: int) -> Kind:
	var result := Kind.BRONZE
	for k in THRESHOLDS:
		if overall >= int(THRESHOLDS[k]):
			result = k
	return result


static func for_player(p: PlayerData) -> Kind:
	return for_overall(p.get_overall()) if p != null else Kind.BRONZE


static func theme(kind: int) -> Dictionary:
	return THEMES.get(kind, THEMES[Kind.BRONZE])


static func key(kind: int) -> String:
	return str(theme(kind)["key"])


## Translation key suffix, e.g. CARD_CAT_GOLD.
static func loc_key(kind: int) -> String:
	return "CARD_CAT_" + key(kind).to_upper()


static func all_kinds() -> Array:
	return [Kind.BRONZE, Kind.SILVER, Kind.GOLD, Kind.ELITE, Kind.LEGENDARY]
