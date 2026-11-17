class_name Valuation
extends RefCounted

## Market value of a player (transfers v2). A pure function of the player and the world, so it is the same for the user
## and the AI and needs no saving: value = base(overall) × age × potential × contract × position × league × form.
## The scale is anchored on the game's historical value (overall² × 400 for a player in his prime) so club budgets,
## wages and AI spending stay balanced; the exponential term makes stars clearly dearer than squad players.

const BASE_PER_POINT := 400
const CURVE := 1.03                    # every overall point above 70 adds 3 % on top of the quadratic base
const POSITION := {
	PlayerData.Position.GK: 0.8, PlayerData.Position.CB: 0.95, PlayerData.Position.LB: 0.9, PlayerData.Position.RB: 0.9,
	PlayerData.Position.CDM: 0.95, PlayerData.Position.CM: 1.0, PlayerData.Position.CAM: 1.05, PlayerData.Position.LM: 0.95,
	PlayerData.Position.RM: 0.95, PlayerData.Position.LW: 1.05, PlayerData.Position.RW: 1.05, PlayerData.Position.ST: 1.1,
}
const HISTORY_LEN := 10


static func base(overall: int) -> float:
	return float(BASE_PER_POINT * overall * overall) * pow(CURVE, overall - 70)


## Peak 24-28; young players are bought for their future (see `potential_factor`), veterans lose value fast.
static func age_factor(age: int) -> float:
	if age <= 17:
		return 0.6
	if age <= 20:
		return 0.7 + 0.08 * (age - 18)
	if age <= 23:
		return 0.9 + 0.03 * (age - 21)
	if age <= 28:
		return 1.0
	return maxf(0.3, 1.0 - 0.1 * (age - 28))


## Players up to 23 are worth more the more they can still grow (up to +50 %).
static func potential_factor(p: PlayerData) -> float:
	if p.age > 23:
		return 1.0
	var gap := maxi(0, p.potential - p.get_overall())
	return 1.0 + minf(0.5, gap * 0.02) * clampf((24 - p.age) / 6.0, 0.0, 1.0)


## Contract seasons left: three or more = full value, the last season = -30 %, expired = free (no fee).
static func contract_factor(p: PlayerData) -> float:
	if p.team_id == "":
		return 1.0                          # a free agent costs no fee, but his worth still shows
	if p.contract_years <= 0:
		return 0.0
	if p.contract_years == 1:
		return 0.7
	if p.contract_years == 2:
		return 0.9
	return 1.0


## Reputation of the club (and so of its league): 0.85 at the bottom, ~1.15 at the top.
static func league_factor(db: Node, p: PlayerData) -> float:
	var t: TeamData = db.get_team(p.team_id) if db != null and p.team_id != "" else null
	var rep := t.reputation if t != null else 50
	return 0.85 + clampi(rep, 1, 99) * 0.003


## Form over the current season (average match rating, at least three games): ±10 %.
static func form_factor(p: PlayerData, career: CareerState) -> float:
	if career == null or not career.world_stats.has(p.id):
		return 1.0
	var row: Dictionary = career.world_stats[p.id]
	var apps := int(row.get("apps", 0))
	if apps < 3:
		return 1.0
	var avg := float(row.get("rating_sum", 0.0)) / apps
	return 1.0 + clampf((avg - 6.5) * 0.1, -0.1, 0.1)


static func value(p: PlayerData, db: Node, career: CareerState = null) -> int:
	if p == null or p.status == PlayerData.Status.RETIRED:
		return 0
	var v := base(p.get_overall()) * age_factor(p.age) * potential_factor(p) * contract_factor(p) \
			* float(POSITION.get(p.position, 1.0)) * league_factor(db, p) * form_factor(p, career)
	return round_value(v)


## Values are shown rounded: to 10 000 above 100 000, to 1 000 below.
static func round_value(v: float) -> int:
	if v >= 100_000.0:
		return int(roundf(v / 10_000.0)) * 10_000
	return int(roundf(v / 1000.0)) * 1000
