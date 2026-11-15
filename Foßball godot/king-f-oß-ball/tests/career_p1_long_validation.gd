## Career P1 long-term validation and performance measurements: 10 consecutive seasons in BOTH worlds (the fictional default
## world and the real data pack with 298 clubs / ~8000 players), full integrity audit every season, save round trips,
## memory and save-size growth, and the measured cost of `advance_week()`.
##   godot --headless --path . res://tests/career_p1_long_validation.tscn
## The timing budgets below were set from measurements (see docs/P1_CAREER_REPORT.md): the build BEFORE the P1 repairs averaged
## 577 ms per week (46 weeks = 26.5 s) on the same machine and would fail them. The numbers are printed as [INFO] lines.
extends Node

const SEASONS := 10
const REAL_PACK := "real_2025"
const REAL_CLUB := "eng_leicester_city_fc"
const FICTIONAL_CLUB := "club_royal_harbor"

## Budgets (ms). Generous multiples of the measured values so a slower CI machine passes; a regression to the old
## implementation (577 ms average, 889 ms worst, 26.5 s per season) does not.
const BUDGET_AVG_WEEK_MS := 350.0
const BUDGET_WORST_STEP_MS := 450.0
const BUDGET_SEASON_MS := 18000.0
const BUDGET_END_SEASON_MS := 3000.0

var _passed := 0
var _failed := 0
var db: TeamDatabase


func _check(ok: bool, name: String, detail := "") -> void:
	if ok:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s%s" % [name, (" — " + detail) if detail != "" else ""])


func _ready() -> void:
	await get_tree().process_frame
	print("=== KING FOOTBALL — Career P1 long-term validation ===")
	db = get_node("/root/TeamDB")
	_run_world("", FICTIONAL_CLUB, "fictional world", false)
	_run_world(REAL_PACK, REAL_CLUB, "real data pack", true)
	_test_step_blocks()
	db.load_world("")
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _percentile(sorted_values: Array, q: float) -> float:
	return float(sorted_values[mini(int(sorted_values.size() * q), sorted_values.size() - 1)])


func _fingerprint(c: CareerState) -> String:
	var ids: Array = db.players.keys()
	ids.sort()
	var parts: PackedStringArray = []
	for id in ids:
		var p: PlayerData = db.players[id]
		parts.append("%s|%s|%d|%d|%d|%d" % [id, p.team_id, p.age, p.status, p.contract_years, p.salary])
	return JSON.stringify(c.to_dict(), "", true).sha256_text().substr(0, 16) + "/" + "\n".join(parts).sha256_text().substr(0, 16)


## Goals of every result of every competition of the career (shoot-outs excluded).
func _result_goals(c: CareerState) -> int:
	var total := 0
	for cid in c.competitions:
		for mid in (c.competitions[cid] as Competition).results:
			var r: Dictionary = (c.competitions[cid] as Competition).results[mid]
			total += int(r["hg"]) + int(r["ag"])
	return total


func _run_world(pack: String, club: String, label: String, real: bool) -> void:
	print("--- %s: %d seasons ---" % [label, SEASONS])
	db.load_world(pack)
	var clubs := db.list_teams(TeamData.Category.CLUB).size()
	print("[INFO] %s: %d clubs, %d players" % [label, clubs, db.players.size()])
	var c := CareerState.start(db, club)
	if c.pyramids.is_empty():
		c.add_default_league()
	var matches_total := 0
	var week_ms: Array[float] = []
	var season_ms: Array[float] = []
	var end_ms: Array[float] = []
	var mem: Array[float] = []
	var save_kb: Dictionary = {}
	var max_ledger := 0
	var seen_results := {}                                  # match id -> season: a match id never comes back
	var duplicate_matches := 0
	var stats_ok := true
	var audit_ok := true
	var audit_detail := ""
	var start_levels := {}
	for k in c.pyramids:
		for d in (c.pyramids[k] as LeaguePyramid).divisions:
			start_levels[d["id"]] = (d["team_ids"] as Array).size()
	for s in SEASONS:
		var t_season := Time.get_ticks_usec()
		for w in CareerState.WEEKS_PER_SEASON:
			var t := Time.get_ticks_usec()
			c.advance_week()
			week_ms.append((Time.get_ticks_usec() - t) / 1000.0)
		season_ms.append((Time.get_ticks_usec() - t_season) / 1000.0)
		# --- the season is over (week 46): everything must be consistent before the rollover ---
		var audit := CareerValidator.validate(c, true)
		if not (audit["errors"] as Array).is_empty() or not (audit["warnings"] as Array).is_empty():
			audit_ok = false
			audit_detail = "season %d: %s %s" % [s + 1, str((audit["errors"] as Array).slice(0, 2)), str((audit["warnings"] as Array).slice(0, 2))]
		var model_goals := 0
		var est_apps := 0
		for pid in c.world_stats:
			model_goals += int(c.world_stats[pid]["est_goals"])
			est_apps += int(c.world_stats[pid]["est_apps"])
		if model_goals != _result_goals(c):
			stats_ok = false
			audit_detail = "season %d: model goals %d != result goals %d" % [s + 1, model_goals, _result_goals(c)]
		for cid in c.competitions:
			for mid in (c.competitions[cid] as Competition).results:
				if seen_results.has(mid) and seen_results[mid] != s + 1:
					duplicate_matches += 1
				seen_results[mid] = s + 1
				matches_total += 1 if seen_results[mid] == s + 1 else 0
		for tid in c.ledgers:
			max_ledger = maxi(max_ledger, (c.ledgers[tid] as FinanceLedger).entries.size())
		var t_end := Time.get_ticks_usec()
		var res := c.end_season()
		end_ms.append((Time.get_ticks_usec() - t_end) / 1000.0)
		mem.append(OS.get_static_memory_usage() / 1048576.0)
		_check(c.season == s + 2 and c.week == 0 and res["season"] == s + 2, "season %d ends and season %d starts at week 0" % [s + 1, s + 2])
		# the new season is clean at once
		var fresh := CareerValidator.validate(c, false)
		if not (fresh["errors"] as Array).is_empty() or not (fresh["warnings"] as Array).is_empty():
			audit_ok = false
			audit_detail = "start of season %d: %s %s" % [s + 2, str((fresh["errors"] as Array).slice(0, 2)), str((fresh["warnings"] as Array).slice(0, 2))]
		# save / reload at the start of the next season for seasons 1 and 10 (the files are big in the real world; a reload also
		# re-allocates every player, so it is kept out of the middle of the memory measurement)
		if s + 1 in [1, SEASONS]:
			var before := _fingerprint(c)
			var data := SaveManager.capture(db, {}, {}, {}, {}, {"career": c.to_dict(), "user_team_id": club})
			var text := JSON.stringify(data, "", true, true)
			save_kb[s + 1] = text.length() / 1024
			var parsed: Dictionary = JSON.parse_string(text)
			var rs := SaveManager.restore(db, parsed)
			var ok: bool = rs["ok"]
			_check(ok, "%s: the save after season %d validates and restores" % [label, s + 1], str(rs.get("errors", []).slice(0, 2)))
			if ok:
				c = CareerState.from_dict(db, rs["extras"]["career"])
				_check(_fingerprint(c) == before, "%s: the career after save + load (season %d) is identical to before" % [label, s + 1])
		print("[INFO] %s season %d: %.0f ms (avg %.1f/week), end_season %.0f ms, memory %.1f MB, max ledger %d, model apps %d" % [
				label, s + 1, season_ms[s], season_ms[s] / 46.0, end_ms[s], mem[s], max_ledger, est_apps])
	_check(audit_ok, "%s: every season passes the full integrity audit (ids, squads, contracts, tables, calendar, statistics): %d seasons" % [label, SEASONS], audit_detail)
	_check(stats_ok, "%s: statistics are recorded exactly once (model goals == goals of all results, every season)" % label, audit_detail)
	_check(duplicate_matches == 0, "%s: no match id is ever played twice across seasons (%d results checked)" % [label, seen_results.size()], str(duplicate_matches))
	_check(c.season == SEASONS + 1, "%s: %d consecutive seasons completed" % [label, SEASONS])
	_check(c.club_history.filter(func(h: Dictionary) -> bool: return str(h["key"]).begins_with("season_")).size() == SEASONS, "%s: one club-history entry per season" % label)
	_check(c.award_history.size() >= SEASONS, "%s: awards computed every season (%d entries)" % [label, c.award_history.size()])
	_check(c.events.size() <= CareerState.EVENT_LOG_MAX and c.match_log.size() <= CareerState.MATCH_LOG_MAX, "%s: event log and match log stay bounded" % label)
	_check(max_ledger <= 600, "%s: ledgers stay bounded (largest %d entries)" % [label, max_ledger], str(max_ledger))
	var sizes_ok := true
	for k in c.pyramids:
		for d in (c.pyramids[k] as LeaguePyramid).divisions:
			sizes_ok = sizes_ok and (d["team_ids"] as Array).size() == int(start_levels[d["id"]])
	_check(sizes_ok, "%s: every division still has its original size after %d promotion / relegation rounds" % [label, SEASONS])
	var promoted_any := false
	if real:
		for k in c.pyramids:
			for sm in (c.pyramids[k] as LeaguePyramid).history:
				promoted_any = promoted_any or not (sm["promoted"] as Array).is_empty()
		_check(promoted_any and c.pyramids.size() == 5, "%s: promotion and relegation happened in %d league systems" % [label, c.pyramids.size()])
	# growth: memory and save size must level off (the ledgers and an unremoved continental cup used to add ~36 MB per season in
	# the real world, i.e. ~22 % of the baseline per season). The retired players kept for a few seasons fill up toward a steady
	# state, so growth is judged per season over the second half of the run, not as a total.
	var slope := (mem[SEASONS - 1] - mem[SEASONS / 2 - 1]) / float(SEASONS - SEASONS / 2) / mem[2]
	print("[INFO] %s: static memory after season 3: %.1f MB, after season %d: %.1f MB; growth in seasons %d-%d: %.2f %% of the season-3 size per season" % [
			label, mem[2], SEASONS, mem[SEASONS - 1], SEASONS / 2, SEASONS, slope * 100.0])
	_check(slope < 0.04, "%s: memory growth in the second half is %.2f %% per season (< 4 %%)" % [label, slope * 100.0], str(slope))
	var retired_held := 0
	for p: PlayerData in db.players.values():
		retired_held += 1 if p.status == PlayerData.Status.RETIRED else 0
	print("[INFO] %s: %d players in the database (%d retired and still kept)" % [label, db.players.size(), retired_held])
	print("[INFO] %s: save size (KB) %s" % [label, str(save_kb)])
	_check(float(save_kb[SEASONS]) < 1.6 * float(save_kb[1]), "%s: the save stays bounded (%d KB at season 1, %d KB at season %d)" % [label, save_kb[1], save_kb[SEASONS], SEASONS])
	# performance
	week_ms.sort()
	var avg := 0.0
	for v in week_ms:
		avg += v
	avg /= float(week_ms.size())
	print("[INFO] %s advance_week(): n=%d avg %.1f ms, median %.1f, p95 %.1f, max %.1f; season avg %.0f ms; end_season avg %.0f ms" % [
			label, week_ms.size(), avg, _percentile(week_ms, 0.5), _percentile(week_ms, 0.95), week_ms[-1],
			_mean(season_ms), _mean(end_ms)])
	if real:
		_check(avg < BUDGET_AVG_WEEK_MS, "%s: average advance_week() %.1f ms < %.0f ms budget" % [label, avg, BUDGET_AVG_WEEK_MS])
		_check(_mean(season_ms) < BUDGET_SEASON_MS, "%s: a 46-week season takes %.0f ms < %.0f ms budget" % [label, _mean(season_ms), BUDGET_SEASON_MS])
		_check(_mean(end_ms) < BUDGET_END_SEASON_MS, "%s: end_season() takes %.0f ms < %.0f ms budget" % [label, _mean(end_ms), BUDGET_END_SEASON_MS])
		var late := season_ms.slice(SEASONS - 3)
		var early := season_ms.slice(0, 3)
		_check(_mean(late) < 1.6 * _mean(early), "%s: no slowdown over the years (seasons 8-10: %.0f ms vs seasons 1-3: %.0f ms)" % [label, _mean(late), _mean(early)])
	# the user's own progress: appearances come only from engine matches (none were played here)
	_check(c.player_stats.is_empty() and c.season_stats.is_empty(), "%s: no measured statistics exist without an engine match (estimates never leak)" % label)


func _mean(a: Array) -> float:
	var t := 0.0
	for v in a:
		t += float(v)
	return t / float(maxi(a.size(), 1))


## The longest block of work the UI would wait for: each phase of a week is timed on its own (the async runner gives the engine a
## frame between phases), over a whole season of the real world.
func _test_step_blocks() -> void:
	db.load_world(REAL_PACK)
	var c := CareerState.start(db, REAL_CLUB)
	var worst := 0.0
	var worst_name := ""
	var by_phase := {}
	for w in CareerState.WEEKS_PER_SEASON:
		var run := c._begin_week({}, {}, {}, {})
		for step in c._week_steps():
			var t := Time.get_ticks_usec()
			c._run_step(step, run)
			var ms := (Time.get_ticks_usec() - t) / 1000.0
			var phase: String = "league" if step.begins_with("league:") else step
			by_phase[phase] = maxf(float(by_phase.get(phase, 0.0)), ms)
			if ms > worst:
				worst = ms
				worst_name = "%s (week %d)" % [step, c.week]
		c._end_week(run)
	var parts := []
	for k in by_phase:
		parts.append("%s %.0f" % [k, by_phase[k]])
	print("[INFO] longest single block per phase over a real-world season (ms): %s" % ", ".join(parts))
	print("[INFO] longest uninterrupted block: %.0f ms in %s" % [worst, worst_name])
	_check(worst < BUDGET_WORST_STEP_MS, "no phase of a week blocks longer than %.0f ms (worst %.0f ms in %s)" % [BUDGET_WORST_STEP_MS, worst, worst_name])
	_check(c.week == 46 and (CareerValidator.validate(c, false)["errors"] as Array).is_empty(), "a season played phase by phase passes the audit")
