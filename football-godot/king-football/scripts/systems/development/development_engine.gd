class_name DevelopmentEngine
extends RefCounted

## Weekly development calculation of the KING Player Development System. One calendar-driven pass per career week:
##   first team (managed club) -> plan-based training x coach multipliers x consistency x age / headroom (ProgressionModel) + match
##   experience, fatigue and training-caused injury risk, season gain caps;
##   academy -> the growth itself stays in TrainingSystem (it reads the plan through `academy_focus` and the coaching multiplier through
##   the dev bonus); this engine does the bookkeeping for the academy too (plan clock, gain detection, snapshots, readiness).
## `sync` catches up every owed week in order and is idempotent (`state.last_week`), so a week is never processed twice.
## All formulas read DevConfig; all randomness is seeded from (week, player id).

static func facility_quality(career: CareerState) -> float:
	return clampf(float(career.facilities.level("training") - 1) / 4.0, 0.0, 1.0)


static func _rng(week: int, pid: String, salt: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([week, pid, salt])
	return r


static func kind_of(p: PlayerData) -> String:
	return "youth" if p.age <= 21 or p.status == PlayerData.Status.YOUTH else "pro"


## Runs the owed weeks up to `absolute_week`. Returns inbox events [{key, args, id}].
## At most `budget` weeks are processed per call; the rest stay queued (`state.pending_weeks`) and the next call resumes them.
static func sync(career: CareerState, state: DevelopmentState, absolute_week: int, academy: Academy = null, budget: int = DevConfig.CATCH_UP_BATCH_WEEKS) -> Array:
	var events: Array = []
	ensure_staff(career, state)
	if state.last_week < 0:
		state.last_week = absolute_week - 1
	var owed := absolute_week - state.last_week
	if owed <= 0:
		return events                                     # already processed: never twice
	var valid := {}                                      # forget players who left the club / academy or no longer exist
	for p in _first_team(career):
		valid[p.id] = true
	if academy != null:
		for pid in academy.roster_ids:
			if career.db.get_player(pid) != null:
				valid[pid] = true
	state.prune(valid)
	var upto := mini(absolute_week, state.last_week + maxi(budget, 1))
	for w in range(state.last_week + 1, upto + 1):
		events.append_array(_week(career, state, w, academy))
		state.last_week = w                                   # advanced per processed week: an interrupted run never repeats or loses one
	return events


static func _first_team(career: CareerState) -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	for p in career.db.get_squad(career.club_id):
		if p.status != PlayerData.Status.YOUTH and p.status != PlayerData.Status.RETIRED and p.status != PlayerData.Status.LOANED:
			out.append(p)
	return out


static func _week(career: CareerState, state: DevelopmentState, w: int, academy: Academy) -> Array:
	var events: Array = []
	var season := career.season
	var squad := _first_team(career)
	var coaching := state.coaching
	var fq := facility_quality(career)
	var monthly := w % DevConfig.SNAPSHOT_EVERY_WEEKS == 0
	var improved: Array = []
	for p in squad:
		var res := _first_team_week(career, state, p, w, fq)
		events.append_array(res["events"])
		if monthly:
			_snapshot_report(state, p, w, improved)
	if academy != null:
		for pid in academy.roster_ids:
			var p: PlayerData = career.db.get_player(pid)
			if p == null:
				continue
			_academy_week(career, state, p, w)
			if monthly:
				_snapshot_report(state, p, w, improved)
		if monthly:
			events.append_array(_ready_notifications(career, state, academy, w))
	if monthly:
		improved.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["delta"]) > int(b["delta"]))
		state.reports.append({"kind": "monthly", "week": w, "season": season, "players": squad.size() + (academy.roster_ids.size() if academy != null else 0),
				"top": improved.filter(func(r: Dictionary) -> bool: return int(r["delta"]) > 0).slice(0, 5),
				"coach_mult": snappedf(coaching.academy_factor(), 0.001)})
		while state.reports.size() > DevConfig.HISTORY_MAX:
			state.reports.pop_front()
	events.append_array(coaching.weekly(career.ledger(), w, season))
	for e in events:
		if e.has("id"):
			state.note(str(e["id"]), w, season, str(e["key"]), e["args"])
	return events


static func _snapshot_report(state: DevelopmentState, p: PlayerData, w: int, improved: Array) -> void:
	var arr: Array = state.history.get(p.id, [])
	var prev := int(arr[-1]["overall"]) if not arr.is_empty() else p.get_overall()
	state.snapshot(p, w)
	improved.append({"player_id": p.id, "name": p.display_name, "delta": p.get_overall() - prev, "overall": p.get_overall()})


# ------------------------------------------------------------------------------------------------- first team

static func _first_team_week(career: CareerState, state: DevelopmentState, p: PlayerData, w: int, fq: float) -> Dictionary:
	var events: Array = []
	var plan := state.plans.ensure(p, w)
	plan["weeks"] = int(plan["weeks"]) + 1
	plan["cycle_weeks"] = int(plan["cycle_weeks"]) + 1
	var rng := _rng(w, p.id, "dev")
	var can_train := p.status == PlayerData.Status.ACTIVE
	var kind := kind_of(p)
	var intensity := float(plan["intensity"])
	var weights: Dictionary = plan["weights"]
	var coaching := state.coaching
	# match experience input: appearances since the last processed week
	var row: Dictionary = career.world_stats.get(p.id, {})
	var apps_now := int(row.get("apps", 0))
	var apps_delta := maxi(apps_now - int(state.last_apps.get(p.id, apps_now)), 0)
	state.last_apps[p.id] = apps_now
	# minutes: real ones from engine matches, 90 per model match (see SeasonStats); a save from before minutes existed falls back to 90 per appearance
	var mins_now := int(row.get("minutes", apps_now * 90 if not row.has("minutes") else 0))
	var mins_delta := maxi(mins_now - int(state.last_minutes.get(p.id, mins_now)), 0)
	state.last_minutes[p.id] = mins_now
	if apps_delta > 0:
		state.idle_weeks[p.id] = 0
	else:
		state.idle_weeks[p.id] = int(state.idle_weeks.get(p.id, 0)) + 1
	var gains := {}
	if can_train and p.fitness >= DevConfig.FATIGUE_EXCESS_FITNESS:
		var rate := DevConfig.LONG_TERM_RATE if bool(plan["long_term"]) else 1.0
		if bool(plan["long_term"]) and int(plan["weeks"]) >= DevConfig.LONG_TERM_BONUS_WEEKS:
			rate *= DevConfig.LONG_TERM_BONUS
		var cons := DevelopmentPlans.consistency(plan)
		var spread := DevelopmentPlans._spread(plan)
		for a in weights:
			var mult := coaching.attribute_multiplier(a, kind) * cons * rate * spread * float(weights[a]) * DevConfig.ENGINE_SCALE
			var pts := ProgressionModel.weekly_points(p, a, fq, intensity, mult)
			gains[a] = int(gains.get(a, 0)) + _apply(state, p, a, pts, w, "plan")
		# match experience: only players who actually played; better ratings help, scaled by age and headroom
		if mins_delta > 0:
			var avg := float(row.get("rating_sum", 0.0)) / maxf(float(apps_now), 1.0)
			var rmult := clampf(1.0 + (avg - DevConfig.MATCH_RATING_BASE) * DevConfig.MATCH_RATING_SCALE, 0.7, DevConfig.MATCH_RATING_CAP) if avg > 0.0 else 1.0
			var base := DevConfig.MATCH_POINTS * minf(float(mins_delta) / 90.0, 3.0) * rmult * ProgressionModel.age_factor(p.age) * ProgressionModel.room_factor(p) * DevConfig.ENGINE_SCALE
			for a in weights:
				gains[a] = int(gains.get(a, 0)) + _apply(state, p, a, base * float(weights[a]), w, "match")
	# scheduled training sessions: extra attribute points per session, fatigue per session, overload risk
	var session_load := 0.0
	if can_train:
		for ss in state.sessions_for(p.id):
			var spec: Array = DevConfig.SESSIONS[ss["session"]]
			var sattr: String = spec[1]
			if sattr == "goalkeeping" and p.position != PlayerData.Position.GK:
				continue
			var inten := float(ss["intensity"])
			session_load += inten
			if p.fitness >= DevConfig.FATIGUE_EXCESS_FITNESS:
				var spts := DevConfig.SESSION_POINTS * ProgressionModel.age_factor(p.age) * ProgressionModel.room_factor(p) \
						* coaching.attribute_multiplier(sattr, kind) * DevConfig.ENGINE_SCALE * (0.6 + 0.8 * inten) * (0.6 + 0.4 * ProgressionModel.trait_factor(p))
				gains[sattr] = int(gains.get(sattr, 0)) + _apply(state, p, sattr, spts, w, "session")
			p.fitness = clampi(p.fitness - roundi(inten * DevConfig.SESSION_FATIGUE * (1.5 if spec[0] == "physical" else 1.0)), 0, 100)
	# fitness: an individual plan intensity moves fitness a little (the daily training plan does the main recovery)
	if can_train:
		var load := (intensity - 0.5) * DevConfig.FITNESS_SWING
		if load > 0.0 and bool(plan["long_term"]):
			load *= DevConfig.LONG_TERM_FATIGUE
		p.fitness = clampi(p.fitness - roundi(load), 0, 100)
		# training-caused injury risk on top of the baseline
		var risk := maxf(session_load - DevConfig.SESSION_OVERLOAD_FROM, 0.0) * DevConfig.SESSION_OVERLOAD_SLOPE \
				+ maxf(intensity - DevConfig.INJURY_OVERLOAD_START, 0.0) * DevConfig.INJURY_OVERLOAD_SLOPE \
				+ float(maxi(DevConfig.FATIGUE_WARN_FITNESS - p.fitness, 0)) * DevConfig.INJURY_FATIGUE_SLOPE
		if risk > 0.0:
			risk *= (1.0 + (1.0 - coaching.dept_multiplier("fitness", kind)) * 1.0) * career.injury_factor_for(career.club_id)
			if "Injury Prone" in p.traits:
				risk *= 1.5
			if rng.randf() < minf(risk, DevConfig.INJURY_MAX_WEEKLY):
				Availability.injure(career, p, rng.randi_range(DevConfig.INJURY_MIN_WEEKS, DevConfig.INJURY_MAX_WEEKS))
	events.append_array(_notify(career, state, p, plan, gains, w))
	return {"events": events, "gains": gains}


static func _apply(state: DevelopmentState, p: PlayerData, attr: String, pts: float, w: int, event: String) -> int:
	var cap := DevConfig.season_attr_cap(p.age)
	var sg: Dictionary = state.season_gain.get(p.id, {})
	if int(sg.get(attr, 0)) >= cap:
		p.growth_progress[attr] = minf(float(p.growth_progress.get(attr, 0.0)), 0.99)
		return 0
	var g := ProgressionModel.apply_points(p, attr, pts, w, event)
	if g > 0:
		sg[attr] = int(sg.get(attr, 0)) + g
		state.season_gain[p.id] = sg
	return g


static func _notify(career: CareerState, state: DevelopmentState, p: PlayerData, plan: Dictionary, gains: Dictionary, w: int) -> Array:
	var events: Array = []
	var season := career.season
	for a in gains:
		if int(gains[a]) > 0:
			state.note("attr:%d:%s:%s" % [w, p.id, a], w, season, "INBOX_DEV_ATTR_UP", [p.display_name, a, p.get_attribute(a)], p.id)
	# milestones: every 5 overall points
	var ms := int(state.milestones.get(p.id, (p.get_overall() / 5) * 5))
	var now_ms := (p.get_overall() / 5) * 5
	if now_ms > ms:
		var e := {"key": "INBOX_DEV_MILESTONE", "args": [p.display_name, now_ms], "id": "milestone:%s:%d" % [p.id, now_ms]}
		events.append(e)
		state.note(e["id"], w, season, e["key"], e["args"], p.id)
	state.milestones[p.id] = maxi(ms, now_ms)
	# plan completion (a cycle = GOAL_POINTS attribute points on the targets or GOAL_MAX_WEEKS)
	var total := 0
	for a in (plan["weights"] as Dictionary):
		total += p.get_attribute(a) - int((plan["cycle_start_attrs"] as Dictionary).get(a, p.get_attribute(a)))
	if str(plan["type"]) == "conversion":
		if int(plan["weeks"]) >= DevConfig.CONVERSION_WEEKS:
			var target := str(plan["target_position"])
			if target != "" and not p.secondary_positions.has(target):
				p.secondary_positions.append(target)
			state.plans.assign(p, "position", w)
			var e2 := {"key": "INBOX_DEV_CONVERSION_DONE", "args": [p.display_name, target], "id": "conv:%s:%d" % [p.id, w]}
			events.append(e2)
			state.note(e2["id"], w, season, e2["key"], e2["args"], p.id)
	elif total >= DevelopmentPlans.GOAL_POINTS or int(plan["cycle_weeks"]) >= DevelopmentPlans.GOAL_MAX_WEEKS:
		plan["cycles"] = int(plan["cycles"]) + 1
		plan["cycle_weeks"] = 0
		var cs := {}
		for a in PlayerData.ATTRIBUTES:
			cs[a] = p.get_attribute(a)
		plan["cycle_start_attrs"] = cs
		var e3 := {"key": "INBOX_DEV_PLAN_DONE", "args": [p.display_name, total], "id": "plan:%s:%d" % [p.id, w]}
		events.append(e3)
		state.note(e3["id"], w, season, e3["key"], e3["args"], p.id)
	# fatigue warning (at most every 6 weeks per player)
	if p.fitness < DevConfig.FATIGUE_WARN_FITNESS and p.status == PlayerData.Status.ACTIVE and w - int(state.fatigue_flagged.get(p.id, -100)) >= 6:
		state.fatigue_flagged[p.id] = w
		var e4 := {"key": "INBOX_DEV_FATIGUE", "args": [p.display_name, p.fitness], "id": "fatigue:%s:%d" % [p.id, w]}
		events.append(e4)
		state.note(e4["id"], w, season, e4["key"], e4["args"], p.id)
	# a young player who does not play
	if p.age <= 21 and int(state.idle_weeks.get(p.id, 0)) == DevConfig.LOW_PLAYTIME_WEEKS:
		state.note("idle:%s:%d" % [p.id, w], w, season, "INBOX_DEV_NO_PLAYTIME", [p.display_name, DevConfig.LOW_PLAYTIME_WEEKS], p.id)
	return events


# ------------------------------------------------------------------------------------------------- academy

## The attribute an academy prospect trains this week according to his plan (deterministic weighted pick), "" when he has no plan.
static func academy_focus(state: DevelopmentState, p: PlayerData, w: int) -> String:
	var plan := state.plans.ensure(p, w)
	var weights: Dictionary = plan["weights"]
	var keys: Array = weights.keys()
	keys.sort()
	var roll := float(hash([p.id, w, "focus"]) & 0xffff) / 65536.0
	var acc := 0.0
	for k in keys:
		acc += float(weights[k])
		if roll < acc:
			return str(k)
	return str(keys[-1]) if not keys.is_empty() else ""


static func _academy_week(career: CareerState, state: DevelopmentState, p: PlayerData, w: int) -> void:
	var plan := state.plans.ensure(p, w)
	plan["weeks"] = int(plan["weeks"]) + 1
	plan["cycle_weeks"] = int(plan["cycle_weeks"]) + 1
	var before: Dictionary = state.last_attrs.get(p.id, {})
	var now := {}
	for a in PlayerData.ATTRIBUTES:
		now[a] = p.get_attribute(a)
		if before.has(a) and int(now[a]) > int(before[a]):
			state.note("attr:%d:%s:%s" % [w, p.id, a], w, career.season, "INBOX_DEV_ATTR_UP", [p.display_name, a, now[a]], p.id)
	state.last_attrs[p.id] = now


## Youth prospects close enough to the first team's rotation level (one notification per player).
static func promotion_candidates(db: Node, academy: Academy, club_id: String) -> Array[PlayerData]:
	var squad_ov: Array = []
	for p in db.get_squad(club_id):
		if p.status != PlayerData.Status.YOUTH:
			squad_ov.append(p.get_overall())
	squad_ov.sort()
	squad_ov.reverse()
	var bench := int(squad_ov[mini(17, squad_ov.size() - 1)]) if not squad_ov.is_empty() else 0
	var out: Array[PlayerData] = []
	for pid in academy.roster_ids:
		var p: PlayerData = db.get_player(pid)
		if p != null and p.age >= AcademyConfig.MIN_PROMOTION_AGE and p.get_overall() + DevConfig.READY_OVERALL_MARGIN >= bench:
			out.append(p)
	out.sort_custom(func(a: PlayerData, b: PlayerData) -> bool: return a.get_overall() > b.get_overall())
	return out


static func _ready_notifications(career: CareerState, state: DevelopmentState, academy: Academy, w: int) -> Array:
	var events: Array = []
	for p in promotion_candidates(career.db, academy, career.club_id):
		var e := {"key": "INBOX_DEV_READY", "args": [p.display_name, p.get_overall()], "id": "ready:%s" % p.id}
		if state.note(e["id"], w, career.season, e["key"], e["args"], p.id):
			events.append(e)
	return events


# ------------------------------------------------------------------------------------------------- season

## Season end: seasonal report from the snapshots, season gain counters reset, coaches progress / contracts run out.
## `success` 0..1 = how well the club did. Returns inbox events.
static func season_end(career: CareerState, state: DevelopmentState, success: float, academy: Academy = null) -> Array:
	var w := career.absolute_week()
	var rows: Array = []
	for pid in state.history:
		var arr: Array = state.history[pid]
		if arr.size() >= 2:
			var p: PlayerData = career.db.get_player(pid)
			rows.append({"player_id": pid, "name": p.display_name if p != null else pid, "from": int(arr[0]["overall"]), "to": int(arr[-1]["overall"])})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["to"]) - int(a["from"]) > int(b["to"]) - int(b["from"]))
	state.reports.append({"kind": "seasonal", "week": w, "season": career.season, "top": rows.slice(0, 5), "players": rows.size()})
	state.season_gain.clear()
	var valid := {}
	for p in _first_team(career):
		valid[p.id] = true
	if academy != null:
		for pid in academy.roster_ids:
			valid[pid] = true
	state.prune(valid)
	var events := state.coaching.season_end(career.season, success, w)
	for e in events:
		state.note(str(e["id"]), w, career.season, str(e["key"]), e["args"])
	return events


## Seeds the starter staff (once) with a career-specific seed. Called before the first development / academy week.
static func ensure_staff(career: CareerState, state: DevelopmentState) -> void:
	career.staff.coaching_link = state.coaching
	if state.coaching.initialized:
		return
	state.coaching.seed_value = hash([career.club_id, "coaching"])
	var club: TeamData = career.db.get_team(career.club_id)
	state.coaching.seed_starter_staff(int(club.reputation) if club != null else 50, career.season)
	_import_legacy(career, state)


## One-off migration: a fitness / goalkeeping coach the old staff system had hired becomes the coach of that department (his wage is
## paid by the coaching staff from now on, so it is never paid twice) and leaves the old staff list.
static func _import_legacy(career: CareerState, state: DevelopmentState) -> void:
	for role in StaffTeam.BRIDGED:
		var m := career.staff.member_for(role)
		if m.is_empty():
			continue
		var dept: String = StaffTeam.BRIDGED[role]
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([str(m.get("id", "")), "legacy"])
		var c := state.coaching.generate_candidate(dept, rng, 0)
		var sk := clampi(int(m.get("skill", 10)), 1, 20)
		for k in ["overall", "technical", "tactical", "youth", "pro"]:
			c[k] = sk
		c["name"] = str(m.get("name", c["name"]))
		c["age"] = int(m.get("age", c["age"]))
		c["salary"] = int(m.get("wage", c["salary"]))
		c["years"] = maxi(int(m.get("years", 1)), 1)
		c["signed_season"] = career.season
		c["expiry_season"] = career.season + int(c["years"]) - 1
		c["status"] = "employed"
		c["history"] = [{"season": career.season, "event": "club staff", "note": "imported"}]
		for k in ["listed_week", "pref_years", "flex"]:
			c.erase(k)
		for old in state.coaching.in_department(dept):
			state.coaching.coaches.erase(old)           # replaces the starter coach of this department
		state.coaching.coaches.append(c)
		career.staff.members.erase(m)

