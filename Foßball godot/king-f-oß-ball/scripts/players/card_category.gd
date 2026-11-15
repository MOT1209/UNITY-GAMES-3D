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

## Per-class presentation (round 3, C4: five clearly different looks). `bg_top/bg_bottom` card gradient,
## `panel_top/panel_bottom` the portrait panel, `frame` + `frame_dark` metal colours, `text` main text,
## `muted` abbreviations / footer / shirt number, `rating` the big rating, `accent` decoration, `border` px,
## `shine` 0..1 static sheen, `shader_shine` true = animated shader gloss (upper classes only),
## `ornament` decoration level, `red` true only for Legendary's controlled accent.
## Every text colour keeps a WCAG AA contrast >= 4.5:1 against every background colour of its class
## (checked by player_card_validation).
const THEMES := {
	Kind.BRONZE: {"key": "bronze", "bg_top": Color("#3b2416"), "bg_bottom": Color("#140c08"),
		"panel_top": Color("#5a3820"), "panel_bottom": Color("#2a190f"),
		"frame": Color("#C27C45"), "frame_dark": Color("#6e3f1c"), "text": IVORY, "muted": Color("#D9B89A"),
		"rating": Color("#E9A66B"), "accent": Color("#CD8B4F"),
		"border": 3, "shine": 0.10, "shader_shine": false, "ornament": 0, "red": false},
	Kind.SILVER: {"key": "silver", "bg_top": Color("#2f363d"), "bg_bottom": Color("#111417"),
		"panel_top": Color("#46505a"), "panel_bottom": Color("#1f2429"),
		"frame": Color("#C9D1D8"), "frame_dark": Color("#6f7a84"), "text": Color("#F2F4F6"), "muted": Color("#C3CCD4"),
		"rating": Color("#E4EAEF"), "accent": Color("#DDE3E8"),
		"border": 4, "shine": 0.16, "shader_shine": false, "ornament": 1, "red": false},
	Kind.GOLD: {"key": "gold", "bg_top": Color("#3f310c"), "bg_bottom": Color("#140f05"),
		"panel_top": Color("#5c4712"), "panel_bottom": Color("#2a2008"),
		"frame": GOLD, "frame_dark": DARK_GOLD, "text": IVORY, "muted": Color("#E2CF95"),
		"rating": Color("#F0CB55"), "accent": GOLD,
		"border": 5, "shine": 0.22, "shader_shine": true, "ornament": 2, "red": false},
	Kind.ELITE: {"key": "elite", "bg_top": Color("#0f2a33"), "bg_bottom": Color("#060d10"),
		"panel_top": Color("#16404c"), "panel_bottom": Color("#0a1c22"),
		"frame": Color("#7FD6E0"), "frame_dark": Color("#2C6E7A"), "text": Color("#EEF8F9"), "muted": Color("#A9D9DF"),
		"rating": Color("#9BE6EE"), "accent": GOLD,
		"border": 6, "shine": 0.30, "shader_shine": true, "ornament": 3, "red": false},
	Kind.LEGENDARY: {"key": "legendary", "bg_top": Color("#2a0f14"), "bg_bottom": BLACK,
		"panel_top": Color("#4a1520"), "panel_bottom": Color("#220a0e"),
		"frame": GOLD, "frame_dark": ROYAL_RED, "text": IVORY, "muted": Color("#E6C9A0"),
		"rating": GOLD, "accent": ROYAL_RED,
		"border": 7, "shine": 0.38, "shader_shine": true, "ornament": 4, "red": true},
}


## WCAG 2.x contrast ratio of two opaque colours (1..21).
static func contrast(a: Color, b: Color) -> float:
	var la := _lum(a)
	var lb := _lum(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func _lum(c: Color) -> float:
	var ch := [c.r, c.g, c.b]
	for i in 3:
		ch[i] = ch[i] / 12.92 if ch[i] <= 0.03928 else pow((ch[i] + 0.055) / 1.055, 2.4)
	return 0.2126 * ch[0] + 0.7152 * ch[1] + 0.0722 * ch[2]


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
