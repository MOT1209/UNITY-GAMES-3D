class_name FormationData
extends RefCounted

## Formation definitions (Phase T3). A slot = [position, x, y] with x in
## [-1 (left), 1 (right)] and y in [0 (own goal), 1 (opponent goal)] in
## team-relative pitch space. Slot 0 is always the goalkeeper.

const P := PlayerData.Position

const FORMATIONS := {
	"4-3-3": [[P.GK, 0, .04], [P.LB, -.8, .25], [P.CB, -.3, .22], [P.CB, .3, .22], [P.RB, .8, .25],
			[P.CDM, 0, .40], [P.CM, -.4, .52], [P.CM, .4, .52],
			[P.LW, -.8, .78], [P.ST, 0, .85], [P.RW, .8, .78]],
	"4-4-2": [[P.GK, 0, .04], [P.LB, -.8, .25], [P.CB, -.3, .22], [P.CB, .3, .22], [P.RB, .8, .25],
			[P.LM, -.8, .55], [P.CM, -.3, .50], [P.CM, .3, .50], [P.RM, .8, .55],
			[P.ST, -.25, .82], [P.ST, .25, .82]],
	"4-2-3-1": [[P.GK, 0, .04], [P.LB, -.8, .25], [P.CB, -.3, .22], [P.CB, .3, .22], [P.RB, .8, .25],
			[P.CDM, -.3, .42], [P.CDM, .3, .42],
			[P.LW, -.8, .65], [P.CAM, 0, .65], [P.RW, .8, .65], [P.ST, 0, .86]],
	"3-5-2": [[P.GK, 0, .04], [P.CB, -.5, .22], [P.CB, 0, .20], [P.CB, .5, .22],
			[P.LM, -.9, .52], [P.CM, -.35, .50], [P.CDM, 0, .40], [P.CM, .35, .50], [P.RM, .9, .52],
			[P.ST, -.25, .82], [P.ST, .25, .82]],
	"5-3-2": [[P.GK, 0, .04], [P.LB, -.9, .30], [P.CB, -.5, .20], [P.CB, 0, .18], [P.CB, .5, .20], [P.RB, .9, .30],
			[P.CM, -.4, .50], [P.CM, 0, .46], [P.CM, .4, .50],
			[P.ST, -.25, .82], [P.ST, .25, .82]],
	"4-1-4-1": [[P.GK, 0, .04], [P.LB, -.8, .25], [P.CB, -.3, .22], [P.CB, .3, .22], [P.RB, .8, .25],
			[P.CDM, 0, .38],
			[P.LM, -.8, .58], [P.CM, -.3, .55], [P.CM, .3, .55], [P.RM, .8, .58],
			[P.ST, 0, .85]],
}

## Positions that can cover each other with a small penalty.
const COMPAT := {
	P.GK: [], P.CB: [P.CDM, P.LB, P.RB], P.LB: [P.CB, P.LM], P.RB: [P.CB, P.RM],
	P.CDM: [P.CM, P.CB], P.CM: [P.CDM, P.CAM], P.CAM: [P.CM, P.LW, P.RW, P.ST],
	P.LM: [P.LW, P.LB, P.CM], P.RM: [P.RW, P.RB, P.CM], P.LW: [P.LM, P.CAM, P.ST],
	P.RW: [P.RM, P.CAM, P.ST], P.ST: [P.CAM, P.LW, P.RW],
}


static func ids() -> Array[String]:
	var out: Array[String] = []
	for k in FORMATIONS:
		out.append(k)
	return out


static func is_valid(formation_id: String) -> bool:
	return FORMATIONS.has(formation_id)


static func slots(formation_id: String) -> Array:
	return FORMATIONS.get(formation_id, [])


static func slot_position(formation_id: String, index: int) -> int:
	return int(slots(formation_id)[index][0])


## Fit of a player position to a slot position: 1.0 exact, 0.85 compatible, 0.6 other
## outfield, 0.0 for GK/outfield mismatch.
static func position_fit(player_pos: int, slot_pos: int) -> float:
	if player_pos == slot_pos:
		return 1.0
	if player_pos == P.GK or slot_pos == P.GK:
		return 0.0
	return 0.85 if slot_pos in COMPAT[player_pos] else 0.6
