class_name AttributeDetail
extends RefCounted

## Detailed football attributes (database phase 3), DERIVED from the 7 core attributes.
##
## The match engine, cards, overall formula and training all run on the 7 core attributes
## (see PlayerData.ATTRIBUTES), so those stay the single source of truth. The finer
## attributes of the data specification are computed here: parent value(s) plus a small
## deterministic per-player offset (+-OFFSET, from the player id), clamped to 1..99.
## Nothing here is stored or feeds back into `get_overall()`, so it can neither drift nor
## change match results. Reproducible: same player + same core values = same output.

const OFFSET := 6
## attribute -> parent core attributes (averaged).
const PARENTS := {
	"acceleration": ["pace"], "sprint_speed": ["pace"], "agility": ["pace", "dribbling"],
	"finishing": ["shooting"], "vision": ["passing"], "ball_control": ["dribbling"],
	"tackling": ["defending"], "stamina": ["physical"], "balance": ["physical", "dribbling"],
	"composure": ["passing", "dribbling", "shooting"], "reactions": ["pace", "passing", "defending"],
}
## Names of the specification, in display order. Core ones are passed through unchanged.
const ORDER: Array[String] = [
	"pace", "acceleration", "sprint_speed", "shooting", "finishing", "passing", "vision",
	"dribbling", "ball_control", "defending", "tackling", "physicality", "stamina", "agility",
	"balance", "reactions", "positioning", "composure",
]


## Every detailed attribute of `p` as {name: value}.
static func for_player(p: PlayerData) -> Dictionary:
	var out := {}
	for name in ORDER:
		out[name] = value(p, name)
	return out


static func value(p: PlayerData, attr_name: String) -> int:
	match attr_name:
		"pace", "shooting", "passing", "dribbling", "defending":
			return p.get_attribute(attr_name)
		"physicality":
			return p.get_attribute("physical")
	var base := _base(p, attr_name)
	return clampi(roundi(base) + _offset(p.id, attr_name), PlayerData.MIN_RATING, PlayerData.MAX_RATING)


static func _base(p: PlayerData, attr_name: String) -> float:
	if attr_name == "positioning":
		return float(_positioning_parent(p))
	if attr_name == "reactions" and p.position == PlayerData.Position.GK:
		return float(p.goalkeeping)
	var parents: Array = PARENTS.get(attr_name, [])
	if parents.is_empty():
		return 0.0
	var total := 0.0
	for a in parents:
		total += float(p.get_attribute(str(a)))
	return total / parents.size()


## Positioning follows the part of the game the position lives in.
static func _positioning_parent(p: PlayerData) -> int:
	match p.position:
		PlayerData.Position.GK:
			return p.goalkeeping
		PlayerData.Position.CB, PlayerData.Position.LB, PlayerData.Position.RB, PlayerData.Position.CDM:
			return p.defending
		PlayerData.Position.CM, PlayerData.Position.CAM, PlayerData.Position.LM, PlayerData.Position.RM:
			return p.passing
		_:
			return p.shooting


## Stable per-player, per-attribute offset in [-OFFSET, +OFFSET] (String.hash is stable).
static func _offset(player_id: String, attr_name: String) -> int:
	return (hash(player_id + ":" + attr_name) & 0x7fffffff) % (OFFSET * 2 + 1) - OFFSET


# --- body (estimates from the stored appearance; real measurements are never invented) ---

static func _appearance_of(p: PlayerData) -> Dictionary:
	if PlayerAppearance.is_valid(p.appearance):
		return p.appearance
	return PlayerAppearance.generate(PlayerAppearance.seed_for(p.id), p.position == PlayerData.Position.GK)


static func estimated_height_cm(p: PlayerData) -> int:
	return clampi(roundi(float(_appearance_of(p).get("height_pm", 1000)) * 0.18), 160, 205)


static func estimated_weight_kg(p: PlayerData) -> int:
	var h := estimated_height_cm(p) / 100.0
	var build := float(_appearance_of(p).get("build_pm", 1000)) / 1000.0
	return clampi(roundi(22.5 * h * h * build), 55, 105)
