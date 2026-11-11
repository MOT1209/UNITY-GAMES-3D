class_name Formation
extends RefCounted

## Kick-off formations. Each slot: [role, depth, lateral]
##   depth   0 = own goal line .. 0.5 = halfway line (kick-off positions stay
##           in the own half)
##   lateral -1 = left touchline .. +1 = right touchline (from the team's
##           own point of view — the mirror is applied in `home_position`)
## Slot 0 is always the goalkeeper. Roles: GK, LB, CB, RB, LWB, RWB, DM, CM,
## AM, LM, RM, LW, RW, ST.
##
## The pitch dimensions come from `FootballPitch` so the slots can never drift
## away from the pitch they are placed on.
##
## `resources/formations/formations.json` is the exported mirror of this
## table (used to draw the formation sheets). The Phase 5 suite compares the
## two, so they cannot drift apart silently.

const FORMATIONS := {
	"4-4-2": [["GK", .05, 0.0], ["LB", .17, -.80], ["CB", .15, -.27], ["CB", .15, .27], ["RB", .17, .80],
		["LM", .32, -.80], ["CM", .29, -.25], ["CM", .29, .25], ["RM", .32, .80], ["ST", .44, -.18], ["ST", .44, .18]],
	"4-3-3": [["GK", .05, 0.0], ["LB", .17, -.80], ["CB", .15, -.27], ["CB", .15, .27], ["RB", .17, .80],
		["CM", .27, -.45], ["DM", .24, 0.0], ["CM", .27, .45], ["LW", .42, -.72], ["ST", .46, 0.0], ["RW", .42, .72]],
	"3-5-2": [["GK", .05, 0.0], ["CB", .15, -.45], ["CB", .13, 0.0], ["CB", .15, .45],
		["LWB", .30, -.90], ["CM", .28, -.35], ["DM", .24, 0.0], ["CM", .28, .35], ["RWB", .30, .90],
		["ST", .44, -.18], ["ST", .44, .18]],
	"4-2-3-1": [["GK", .05, 0.0], ["LB", .17, -.80], ["CB", .15, -.27], ["CB", .15, .27], ["RB", .17, .80],
		["DM", .25, -.25], ["DM", .25, .25], ["LM", .36, -.70], ["AM", .37, 0.0], ["RM", .36, .70], ["ST", .46, 0.0]],
}

## Roles used by the table above.
const ROLES := ["GK", "LB", "CB", "RB", "LWB", "RWB", "DM", "CM", "AM", "LM", "RM", "LW", "RW", "ST"]

## All formation ids, in a stable order.
static func names() -> Array:
	return ["4-4-2", "4-3-3", "3-5-2", "4-2-3-1"]


## The slots of a formation; falls back to 4-4-2 for an unknown id.
static func slots(id: String) -> Array:
	return FORMATIONS.get(id, FORMATIONS["4-4-2"])


## World position of a slot. `attack_dir_z` = -1 when the team attacks toward
## -Z (own goal at +Z), +1 otherwise.
static func home_position(slot: Array, attack_dir_z: float) -> Vector3:
	var z_from_own: float = slot[1] * FootballPitch.PITCH_LENGTH
	var own_goal_z := -attack_dir_z * FootballPitch.PITCH_LENGTH * 0.5
	var z := own_goal_z + attack_dir_z * z_from_own
	# Lateral is the team's own left/right: facing -Z the right hand is +X,
	# facing +Z it is -X.
	var x: float = slot[2] * (FootballPitch.PITCH_WIDTH * 0.5 - 3.0) * (-attack_dir_z)
	return Vector3(x, 0.0, z)
