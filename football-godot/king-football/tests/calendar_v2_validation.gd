## Phase K (daily calendar with real dates) — K1 time model and K2 weekdays so far:
##   dates of the career clock, translated formatting, day-by-day advancing equal to week-by-week advancing, the save
##   migration (week-based saves load at the end of their week), and the weekday of every fixture of a season in BOTH
##   worlds (fictional and the real pack): league at the weekend (Friday now and then, Wednesday/Thursday for the
##   midweek round of a double-round week), cups Tuesday/Wednesday, continental Tuesday-Thursday, and no club twice
##   within 48 hours.
##   godot --headless --path . res://tests/calendar_v2_validation.tscn
extends Node

var _passed := 0
var _failed := 0
var app: Node


func _check(ok: bool, name: String, detail := "") -> void:
	if ok:
		_passed += 1
		print("[PASS] %s%s" % [name, (" — " + detail) if detail != "" else ""])
	else:
		_failed += 1
		print("[FAIL] %s%s" % [name, (" — " + detail) if detail != "" else ""])


func _ready() -> void:
	await get_tree().process_frame
	print("=== KING FOOTBALL — calendar v2 validation (Phase K) ===")
	app = get_node("/root/AppHub")
	var cfg := ConfigFile.new()
	var had_cfg := cfg.load(TeamDatabase.SETTINGS_PATH) == OK
	var saved_pack: String = str(cfg.get_value("data", "pack", "")) if had_cfg else ""
	_test_dates()
	_test_format()
	app.switch_world("")
	_test_days_equal_weeks()
	_test_migration()
	_test_schedule("fictional world")
	var t0 := Time.get_ticks_msec()
	app.switch_world("real_2025")
	_start_any_real()
	print("  real pack career built in %d ms" % (Time.get_ticks_msec() - t0))
	_test_schedule("real pack")
	_test_day_timing()
	app.switch_world(saved_pack)
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _start_any_real() -> void:
	for t in app.db.list_teams(TeamData.Category.CLUB):
		if app.start_career(t.id) == "":
			print("  real pack career: ", t.id)
			return


# --- K1 dates ----------------------------------------------------------------------------------------

func _test_dates() -> void:
	var w1 := CareerDate.of(1, 1, 0)
	_check(w1["year"] == 2026 and w1["month"] == 8 and w1["day"] == 3 and w1["weekday"] == 0, "season 1, week 1 starts on Monday 3 August 2026", str(w1))
	var sat := CareerDate.of(1, 1, 5)
	_check(sat["day"] == 8 and sat["weekday"] == 5, "day 5 of that week is Saturday 8 August")
	var pre := CareerDate.of(1, 0, 0)
	_check(pre["month"] == 7 and pre["day"] == 1, "week 0 (pre-season) starts on 1 July")
	var last := CareerDate.of(1, CareerState.WEEKS_PER_SEASON, 6)
	_check(last["year"] == 2027 and last["month"] == 6, "week 46 ends in June of the next year (summer break)", str(last))
	var w44 := CareerDate.of(1, 44, 6)
	_check(w44["year"] == 2027 and (w44["month"] == 5 or (w44["month"] == 6 and w44["day"] <= 7)), "the league's last week (44) is at the end of May / first days of June", str(w44))
	var s2 := CareerDate.of(2, 1, 0)
	_check(s2["year"] == 2027 and s2["month"] == 8 and s2["weekday"] == 0 and s2["day"] <= 7, "season 2 starts on the first Monday of August 2027", str(s2))
	var ok := true
	var j0 := CareerDate.jdn(2027, 12, 20)
	for i in 900:
		var d := CareerDate.from_jdn(j0 + i)
		ok = ok and CareerDate.jdn(d["year"], d["month"], d["day"]) == j0 + i
	_check(ok, "date <-> day number round trip over 900 days (incl. 29 Feb 2028)")
	var leap := CareerDate.from_jdn(CareerDate.jdn(2028, 2, 28) + 1)
	_check(leap["month"] == 2 and leap["day"] == 29, "2028 is a leap year")
	var wd := CareerDate.week_day_of(1, CareerDate.jdn_of(1, 20, 3))
	_check(wd["week"] == 20 and wd["day"] == 3, "week/day of a date is the inverse of the date of a week/day")


func _test_format() -> void:
	var d := CareerDate.of(1, 1, 5)
	var keep: String = Loc.language
	Loc.set_language("en", false)
	var en := CareerDate.format(d)
	Loc.set_language("de", false)
	var de := CareerDate.format(d)
	Loc.set_language("ar", false)
	var ar := CareerDate.format(d)
	Loc.set_language(keep, false)
	_check(en == "Sat 8 Aug 2026", "English date", en)
	_check(de.begins_with("Sa 8 Aug") and de.ends_with("2026"), "German date", de)
	_check(ar.find("السبت") >= 0 and ar.find("أغسطس") >= 0 and ar.find("2026") >= 0 and ar.find("8") >= 0, "Arabic date (names translated, Western digits)", ar)


# --- K1 advancing ---------------------------------------------------------------------------------------

func _snapshot(c: CareerState) -> Dictionary:
	var played := {}
	for cid in c.competitions:
		var comp: Competition = c.competitions[cid]
		for mid in comp.results:
			played[mid] = str(comp.results[mid])
	return {"week": c.week, "played": played, "balance": c.ledger().balance}


func _test_days_equal_weeks() -> void:
	app.start_career("club_desert_kings")
	var by_week: Array = []
	for i in 6:
		app.advance_week()
		by_week.append(_snapshot(app.career))
	app.start_career("club_desert_kings")
	var by_day: Array = []
	var stops := 0
	for i in 6:
		for d in 7:
			var info: Dictionary = app.advance_day()
			_check_day_info(info, d)
			if not (info.get("user_fixtures", []) as Array).is_empty():
				stops += 1
		by_day.append(_snapshot(app.career))
	var same_fixtures := true
	var same_balance := true
	for i in 6:
		same_fixtures = same_fixtures and (by_week[i]["played"] as Dictionary).keys().size() == (by_day[i]["played"] as Dictionary).keys().size()
		for k in by_week[i]["played"]:
			same_fixtures = same_fixtures and (by_day[i]["played"] as Dictionary).has(k)
		same_balance = same_balance and by_week[i]["balance"] == by_day[i]["balance"]
	# Results may differ where a squad changed during the week: day by day, Sunday's match already sees Saturday's injuries
	# and suspensions (the whole-week call caches every club's rating once).
	_check(same_fixtures, "6 weeks day by day play exactly the fixtures of 6 weeks week by week")
	_check(same_balance, "the club's balance is identical either way (weekly money on Mondays)")
	_check(app.career.day == 6 and app.career.week == 6, "after 42 days the career is on Sunday of week 6")
	_check(stops > 0, "the user's own fixture is handed over on its day", "%d match days" % stops)
	var first_day_run: Array = by_day
	app.start_career("club_desert_kings")
	var again: Array = []
	for i in 6:
		for d in 7:
			app.advance_day()
		again.append(_snapshot(app.career))
	var det := true
	for i in 6:
		det = det and again[i]["played"] == first_day_run[i]["played"] and again[i]["balance"] == first_day_run[i]["balance"]
	_check(det, "day by day is deterministic (a second run gives every result again)")
	# advance_week from the middle of a week finishes that week
	app.advance_day()
	app.advance_day()
	var w: int = app.career.week
	app.advance_week()
	_check(app.career.week == w and app.career.day == 6, "advance_week in mid-week plays the rest of that week")
	app.advance_week()
	_check(app.career.week == w + 1 and app.career.day == 6, "the next advance_week is a whole new week")


var _day_errors := 0


func _check_day_info(info: Dictionary, expect_day: int) -> void:
	if int(info.get("day", -1)) != expect_day:
		_day_errors += 1


func _test_migration() -> void:
	app.start_career("club_desert_kings")
	app.advance_week()
	app.advance_week()
	var d: Dictionary = app.career.to_dict()
	_check(int(d.get("day", -1)) == 6, "the save holds the day")
	d.erase("day")                                   # a save from before Phase K
	var parsed := CareerState.parse(app.db, JSON.parse_string(JSON.stringify(d)))
	_check(parsed["ok"], "a week-based save (no day) loads", str(parsed["errors"]))
	if parsed["ok"]:
		var c: CareerState = parsed["career"]
		_check(c.week == 2 and c.day == 6, "it is placed at the end of its week (Sunday)")
		var dt := c.date()
		_check(dt["weekday"] == 6 and dt["month"] == 8, "its date is the Sunday of week 2 (August)", str(dt))
	var bad: Dictionary = app.career.to_dict()
	bad["day"] = 9
	var c2 := CareerState.from_dict(app.db, JSON.parse_string(JSON.stringify(bad)))
	_check(c2.day == 6, "a broken day is clamped into 0..6")


# --- K2 weekdays of every fixture ---------------------------------------------------------------------------

func _test_schedule(world: String) -> void:
	var c: CareerState = app.career
	var by_club := {}                                  # team id -> [julian day]
	var bad_days: Array = []
	var count := 0
	for k in c.pyramids:
		var pyr: LeaguePyramid = c.pyramids[k]
		for role in pyr.comp:
			var comp: Competition = c.competitions.get(pyr.comp[role])
			if comp == null:
				continue
			for f in comp.fixtures:
				var w := pyr.week_of(role, comp, f)
				var dd := pyr.day_of(role, comp, f)
				count += 1
				var allowed: Array = [CareerSchedule.TUE, CareerSchedule.WED] if role == "cup" else [CareerSchedule.FRI, CareerSchedule.SAT, CareerSchedule.SUN, CareerSchedule.WED, CareerSchedule.THU]
				if not (dd in allowed):
					bad_days.append("%s %s day %d" % [role, f["match_id"], dd])
				var j := CareerDate.jdn_of(c.season, w, dd)
				for t in [f["home"], f["away"]]:
					if not by_club.has(t):
						by_club[t] = []
					by_club[t].append(j)
	if c.continental != null:
		var cc: Competition = c.continental.competition(c)
		if cc != null:
			for f in cc.fixtures:
				var dd2 := CareerSchedule.continental_day(str(f["match_id"]))
				if not (dd2 in [CareerSchedule.TUE, CareerSchedule.WED, CareerSchedule.THU]):
					bad_days.append("continental %s" % f["match_id"])
				var j2 := CareerDate.jdn_of(c.season, c.continental.week_of(f), dd2)
				for t in [f["home"], f["away"]]:
					if not by_club.has(t):
						by_club[t] = []
					by_club[t].append(j2)
				count += 1
	_check(bad_days.is_empty(), "%s: every fixture is on its competition's weekday (%d fixtures)" % [world, count], str(bad_days.slice(0, 3)))
	var tight: Array = []
	for t in by_club:
		var days: Array = by_club[t]
		days.sort()
		for i in range(1, days.size()):
			if int(days[i]) - int(days[i - 1]) < 2:
				tight.append("%s %s" % [t, str(CareerDate.from_jdn(days[i]))])
	_check(tight.is_empty(), "%s: no club plays twice within 48 hours" % world, str(tight.slice(0, 3)))
	var weekend := 0
	var league_n := 0
	for k in c.pyramids:
		var pyr: LeaguePyramid = c.pyramids[k]
		for d in pyr.divisions:
			var comp: Competition = c.competitions.get(pyr.comp.get(d["id"], ""))
			if comp == null:
				continue
			for f in comp.fixtures:
				league_n += 1
				if pyr.day_of(d["id"], comp, f) in [CareerSchedule.SAT, CareerSchedule.SUN]:
					weekend += 1
	_check(league_n > 0 and float(weekend) / league_n >= 0.8, "%s: league football is mostly at the weekend" % world, "%.0f %% Sat/Sun" % (100.0 * weekend / maxf(league_n, 1.0)))


## A day in the real pack (the biggest world): the time of one simulated day, against the 150 ms budget.
func _test_day_timing() -> void:
	var worst := 0
	var total := 0
	for i in 21:
		var t0 := Time.get_ticks_usec()
		app.advance_day()
		var dt := Time.get_ticks_usec() - t0
		worst = maxi(worst, dt)
		total += dt
	print("  real pack: 21 days, avg %.1f ms, worst %.1f ms (Mondays carry the weekly systems)" % [total / 21000.0, worst / 1000.0])
	_check(total / 21000.0 <= 150.0, "a day in the real pack averages <= 150 ms", "%.1f ms" % (total / 21000.0))
	_check(_day_errors == 0, "every advance_day reports the day it reached")
