class_name CareerDate
extends RefCounted

## Real calendar dates for the career (Phase K1). The career clock stays (season, week, day) — `week` is the backbone
## every weekly system already uses — and this class turns it into a date of a European season:
##   * season s is the season FIRST_YEAR + s - 1 / FIRST_YEAR + s (season 1 = 2026/27);
##   * week 0 is the pre-season (it starts on 1 July);
##   * week 1 starts on the first Monday on or after 1 August; weeks 1..46 run to mid June (the league ends in late May,
##     the last weeks hold play-offs, then the summer break);
##   * day 0..6 = Monday..Sunday of the week.
## Dates are plain dictionaries {year, month, day, weekday} (weekday 0 = Monday). All arithmetic goes through a Julian day
## number, so month lengths and leap years are exact.

const FIRST_YEAR := 2026
const DAYS := 7
## Weekday names / month names, translated through Loc (keys DATE_WD_0..6, DATE_MONTH_1..12).
const WEEKDAY_KEYS := ["DATE_WD_0", "DATE_WD_1", "DATE_WD_2", "DATE_WD_3", "DATE_WD_4", "DATE_WD_5", "DATE_WD_6"]


## Julian day number of a Gregorian date.
static func jdn(year: int, month: int, day: int) -> int:
	var a := (14 - month) / 12
	var y := year + 4800 - a
	var m := month + 12 * a - 3
	return day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045


## Gregorian date of a Julian day number: {year, month, day, weekday} (weekday 0 = Monday).
static func from_jdn(j: int) -> Dictionary:
	var a := j + 32044
	var b := (4 * a + 3) / 146097
	var c := a - 146097 * b / 4
	var d := (4 * c + 3) / 1461
	var e := c - 1461 * d / 4
	var m := (5 * e + 2) / 153
	var day := e - (153 * m + 2) / 5 + 1
	var month := m + 3 - 12 * (m / 10)
	var year := 100 * b + d - 4800 + m / 10
	return {"year": year, "month": month, "day": day, "weekday": posmod(j, 7)}      # JDN mod 7: 0 = Monday


## Calendar year in which `season` starts (its first half).
static func season_year(season: int) -> int:
	return FIRST_YEAR + maxi(season, 1) - 1


## Julian day of the Monday that starts `week` of `season` (week 0 = the pre-season, which starts on 1 July).
static func week_start_jdn(season: int, week: int) -> int:
	var y := season_year(season)
	var aug1 := jdn(y, 8, 1)
	var first_monday := aug1 + posmod(7 - posmod(aug1, 7), 7)          # the first Monday on or after 1 August
	if week <= 0:
		return jdn(y, 7, 1)
	return first_monday + (week - 1) * DAYS


static func jdn_of(season: int, week: int, day: int) -> int:
	return week_start_jdn(season, week) + clampi(day, 0, DAYS - 1) if week > 0 else jdn(season_year(season), 7, 1) + maxi(day, 0)


## The date of (season, week, day).
static func of(season: int, week: int, day: int) -> Dictionary:
	return from_jdn(jdn_of(season, week, day))


## (week, day) of a Julian day inside `season` ({"week": 0..46, "day": 0..6}); dates before week 1 are week 0.
static func week_day_of(season: int, j: int) -> Dictionary:
	var w1 := week_start_jdn(season, 1)
	if j < w1:
		return {"week": 0, "day": maxi(j - jdn(season_year(season), 7, 1), 0)}
	var off := j - w1
	return {"week": off / DAYS + 1, "day": off % DAYS}


## Days from (season, week, day) a to b (positive when b is later).
static func days_between(season: int, wa: int, da: int, wb: int, db: int) -> int:
	return jdn_of(season, wb, db) - jdn_of(season, wa, da)


## "Sat 15 Aug 2026" in the active language (Western digits; the caller's RTL layout mirrors the text). `short` drops the year.
static func format(d: Dictionary, short := false) -> String:
	var wd := Loc.t(WEEKDAY_KEYS[int(d["weekday"])])
	var mon := Loc.t("DATE_MONTH_%d" % int(d["month"]))
	if short:
		return "%s %d %s" % [wd, int(d["day"]), mon]
	return "%s %d %s %d" % [wd, int(d["day"]), mon, int(d["year"])]


## Name of a month in the active language.
static func month_name(month: int) -> String:
	return Loc.t("DATE_MONTH_%d" % clampi(month, 1, 12))
