class_name FormationData
extends RefCounted

## Formation definitions (Phase T3). A slot = [position, x, y] with x in
## [-1 (left), 1 (right)] and y in [0 (own goal), 1 (opponent goal)] in
## team-relative pitch space. Slot 0 is always the goalkeeper.

const FORMATIONS := {
	"4-3-3": [[PlayerData.Position.GK, 0, .04], [PlayerData.Position.LB, -.8, .25], [PlayerData.Position.CB, -.3, .22], [PlayerData.Position.CB, .3, .22], [PlayerData.Position.RB, .8, .25],
			[PlayerData.Position.CDM, 0, .40], [PlayerData.Position.CM, -.4, .52], [PlayerData.Position.CM, .4, .52],
			[PlayerData.Position.LW, -.8, .78], [PlayerData.Position.ST, 0, .85], [PlayerData.Position.RW, .8, .78]],
	"4-4-2": [[PlayerData.Position.GK, 0, .04], [PlayerData.Position.LB, -.8, .25], [PlayerData.Position.CB, -.3, .22], [PlayerData.Position.CB, .3, .22], [PlayerData.Position.RB, .8, .25],
			[PlayerData.Position.LM, -.8, .55], [PlayerData.Position.CM, -.3, .50], [PlayerData.Position.CM, .3, .50], [PlayerData.Position.RM, .8, .55],
			[PlayerData.Position.ST, -.25, .82], [PlayerData.Position.ST, .25, .82]],
	"4-2-3-1": [[PlayerData.Position.GK, 0, .04], [PlayerData.Position.LB, -.8, .25], [PlayerData.Position.CB, -.3, .22], [PlayerData.Position.CB, .3, .22], [PlayerData.Position.RB, .8, .25],
			[PlayerData.Position.CDM, -.3, .42], [PlayerData.Position.CDM, .3, .42],
			[PlayerData.Position.LW, -.8, .65], [PlayerData.Position.CAM, 0, .65], [PlayerData.Position.RW, .8, .65], [PlayerData.Position.ST, 0, .86]],
	"3-5-2": [[PlayerData.Position.GK, 0, .04], [PlayerData.Position.CB, -.5, .22], [PlayerData.Position.CB, 0, .20], [PlayerData.Position.CB, .5, .22],
			[PlayerData.Position.LM, -.9, .52], [PlayerData.Position.CM, -.35, .50], [PlayerData.Position.CDM, 0, .40], [PlayerData.Position.CM, .35, .50], [PlayerData.Position.RM, .9, .52],
			[PlayerData.Position.ST, -.25, .82], [PlayerData.Position.ST, .25, .82]],
	"5-3-2": [[PlayerData.Position.GK, 0, .04], [PlayerData.Position.LB, -.9, .30], [PlayerData.Position.CB, -.5, .20], [PlayerData.Position.CB, 0, .18], [PlayerData.Position.CB, .5, .20], [PlayerData.Position.RB, .9, .30],
			[PlayerData.Position.CM, -.4, .50], [PlayerData.Position.CM, 0, .46], [PlayerData.Position.CM, .4, .50],
			[PlayerData.Position.ST, -.25, .82], [PlayerData.Position.ST, .25, .82]],
	"4-1-4-1": [[PlayerData.Position.GK, 0, .04], [PlayerData.Position.LB, -.8, .25], [PlayerData.Position.CB, -.3, .22], [PlayerData.Position.CB, .3, .22], [PlayerData.Position.RB, .8, .25],
			[PlayerData.Position.CDM, 0, .38],
			[PlayerData.Position.LM, -.8, .58], [PlayerData.Position.CM, -.3, .55], [PlayerData.Position.CM, .3, .55], [PlayerData.Position.RM, .8, .58],
			[PlayerData.Position.ST, 0, .85]],
}

## Positions that can cover each other with a small penalty.
const COMPAT := {
	PlayerData.Position.GK: [], PlayerData.Position.CB: [PlayerData.Position.CDM, PlayerData.Position.LB, PlayerData.Position.RB], PlayerData.Position.LB: [PlayerData.Position.CB, PlayerData.Position.LM], PlayerData.Position.RB: [PlayerData.Position.CB, PlayerData.Position.RM],
	PlayerData.Position.CDM: [PlayerData.Position.CM, PlayerData.Position.CB], PlayerData.Position.CM: [PlayerData.Position.CDM, PlayerData.Position.CAM], PlayerData.Position.CAM: [PlayerData.Position.CM, PlayerData.Position.LW, PlayerData.Position.RW, PlayerData.Position.ST],
	PlayerData.Position.LM: [PlayerData.Position.LW, PlayerData.Position.LB, PlayerData.Position.CM], PlayerData.Position.RM: [PlayerData.Position.RW, PlayerData.Position.RB, PlayerData.Position.CM], PlayerData.Position.LW: [PlayerData.Position.LM, PlayerData.Position.CAM, PlayerData.Position.ST],
	PlayerData.Position.RW: [PlayerData.Position.RM, PlayerData.Position.CAM, PlayerData.Position.ST], PlayerData.Position.ST: [PlayerData.Position.CAM, PlayerData.Position.LW, PlayerData.Position.RW],
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
	if player_pos == PlayerData.Position.GK or slot_pos == PlayerData.Position.GK:
		return 0.0
	return 0.85 if slot_pos in COMPAT[player_pos] else 0.6
