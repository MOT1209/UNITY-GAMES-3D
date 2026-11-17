class_name CareerSchedule
extends RefCounted

## Weekday of every fixture (Phase K2). The week of a fixture still comes from its competition (`LeaguePyramid.week_of`,
## `ContinentalCup.week_of`); this decides the day inside that week, deterministically from the match id:
##   * league: Saturday or Sunday, now and then Friday (about 1 in 10; never in a continental week: Thursday -> Friday would be
##     24 h). No Monday games: a Sunday -> Monday pair would be 24 h. When a division plays two rounds in one week (24-club
##     leagues), the first of them is midweek: Wednesday, Friday in a cup week (the second is then Sunday);
##   * domestic cup: Tuesday or Wednesday; continental: Tuesday, Wednesday or Thursday;
##   * play-offs: rounds on Wednesday, Wednesday, Friday; relegation play-off on Sunday.
## So no club ever plays twice within 48 hours (`calendar_v2_validation` checks every fixture of a season).
## Days are 0 = Monday .. 6 = Sunday (`CareerDate`).

const MON := 0
const TUE := 1
const WED := 2
const THU := 3
const FRI := 4
const SAT := 5
const SUN := 6


static func _h(match_id: String) -> int:
	return absi(hash("day:" + match_id))


static func league_day(match_id: String, friday_ok: bool = true) -> int:
	var h := _h(match_id) % 20
	if h <= 1 and friday_ok:
		return FRI
	return SAT if h % 2 == 0 else SUN


## The earlier of two rounds a division plays in the same week.
static func midweek_league_day(cup_week: bool) -> int:
	return FRI if cup_week else WED          # a cup week already has Tue/Wed: Friday is 2 days after Wednesday, the other round is Sunday


static func cup_day(match_id: String) -> int:
	return TUE if _h(match_id) % 2 == 0 else WED


static func continental_day(match_id: String) -> int:
	return TUE + _h(match_id) % 3


static func playoff_day(round: int) -> int:
	return [WED, WED, FRI][clampi(round, 1, 3) - 1]


static func relegation_playoff_day() -> int:
	return SUN
