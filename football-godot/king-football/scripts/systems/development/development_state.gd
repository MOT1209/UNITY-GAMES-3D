class_name DevelopmentState
extends RefCounted

## Saved state of the KING Player Development System (one dictionary under the career key "development"; old saves have none and get
## safe defaults, see `from_dict`): coaching staff, individual plans, the processed-week marker (so a week is never run twice and a
## long calendar jump is caught up week by week), history snapshots, season gains, reports and notifications.

var coaching: CoachingStaff = CoachingStaff.new()
var plans: DevelopmentPlans = DevelopmentPlans.new()
var last_week: int = -1                     # last absolute career week processed
var skipped_weeks: int = 0                  # weeks dropped by the safety cap in one jump (reported, normally 0)
var history: Dictionary = {}                # player id -> [{week, overall, attrs{}, fitness}] (weekly / 4-weekly snapshots)
var last_attrs: Dictionary = {}             # player id -> {attr: value} at the last processed week (gain detection)
var last_apps: Dictionary = {}              # player id -> appearances seen at the last processed week
var idle_weeks: Dictionary = {}             # player id -> weeks in a row without an appearance
var season_gain: Dictionary = {}            # player id -> {attr: points gained through the weekly engine this season}
var milestones: Dictionary = {}             # player id -> highest overall milestone (multiples of 5) already announced
var reports: Array = []                     # {kind ("monthly"/"seasonal"), week, season, ...}
var notifications: Array = []               # {id, week, season, key, args, player_id, read}
var fatigue_flagged: Dictionary = {}        # player id -> week of the last fatigue warning
var sessions: Array = []                    # weekly training schedule: {id, session, day 0..6, intensity 0..1, player_ids}
var next_session_id: int = 1
var version: int = DevConfig.STATE_VERSION


## Adds a session to the weekly schedule. `match_days` (day index -> true) refuses match days. Returns "" or an error key.
func add_session(session: String, day: int, intensity: float, player_ids: Array, match_days: Dictionary = {}) -> String:
	if not DevConfig.SESSIONS.has(session):
		return "DEV_ERR_SESSION"
	if day < 0 or day > 6:
		return "DEV_ERR_DAY"
	if match_days.has(day):
		return "DEV_ERR_MATCH_DAY"
	if player_ids.is_empty():
		return "DEV_ERR_NO_PLAYERS"
	for pid in player_ids:
		if sessions_for(str(pid)).size() >= DevConfig.MAX_SESSIONS_WEEK:
			return "DEV_ERR_TOO_MANY_SESSIONS"
	sessions.append({"id": "ses_%d" % next_session_id, "session": session, "day": day, "intensity": clampf(intensity, 0.0, 1.0),
			"player_ids": player_ids.map(func(x: Variant) -> String: return str(x))})
	next_session_id += 1
	return ""


func remove_session(id: String) -> bool:
	for s in sessions:
		if s["id"] == id:
			sessions.erase(s)
			return true
	return false


func sessions_for(pid: String) -> Array:
	return sessions.filter(func(s: Dictionary) -> bool: return pid in s["player_ids"])


func init_for_career(club_seed: int) -> void:
	coaching = CoachingStaff.new(club_seed)


func note(uid: String, week: int, season: int, key: String, args: Array, player_id: String = "") -> bool:
	for n in notifications:
		if n["id"] == uid:
			return false
	notifications.append({"id": uid, "week": week, "season": season, "key": key, "args": args, "player_id": player_id, "read": false})
	while notifications.size() > DevConfig.NOTIFY_MAX:
		notifications.pop_front()
	return true


func snapshot(p: PlayerData, week: int) -> void:
	var arr: Array = history.get(p.id, [])
	if not arr.is_empty() and int(arr[-1]["week"]) == week:
		return                                    # the same week is never snapshotted twice
	var attrs := {}
	for a in PlayerData.ATTRIBUTES:
		attrs[a] = p.get_attribute(a)
	arr.append({"week": week, "overall": p.get_overall(), "attrs": attrs, "fitness": p.fitness})
	while arr.size() > DevConfig.HISTORY_MAX:
		arr.pop_front()
	history[p.id] = arr


func to_dict() -> Dictionary:
	return {"version": version, "coaching": coaching.to_dict(), "plans": plans.to_dict(), "last_week": last_week, "skipped": skipped_weeks,
			"history": history.duplicate(true), "last_attrs": last_attrs.duplicate(true), "last_apps": last_apps.duplicate(),
			"idle": idle_weeks.duplicate(), "season_gain": season_gain.duplicate(true), "milestones": milestones.duplicate(),
			"reports": reports.duplicate(true), "notifications": notifications.duplicate(true), "fatigue_flagged": fatigue_flagged.duplicate(), "sessions": sessions.duplicate(true), "next_session_id": next_session_id}


## `valid_player` (id -> bool) drops references to players that no longer exist; null keeps everything.
static func from_dict(d: Dictionary, valid_player: Callable = Callable()) -> DevelopmentState:
	var s := DevelopmentState.new()
	if d.is_empty():
		return s                                  # old save: nothing yet (the career seeds the starter staff on its first week)
	d = PlayerData._restore_ints(d) as Dictionary   # JSON gives every number as a float: whole numbers become integers again
	s.coaching = CoachingStaff.from_dict(d.get("coaching", {}) as Dictionary)
	s.plans = DevelopmentPlans.from_dict(d.get("plans", {}) as Dictionary, valid_player)
	s.last_week = int(d.get("last_week", -1))
	s.skipped_weeks = int(d.get("skipped", 0))
	var ok := func(pid: String) -> bool: return not valid_player.is_valid() or bool(valid_player.call(pid))
	for pid in (d.get("history", {}) as Dictionary):
		if not ok.call(str(pid)) or typeof(d["history"][pid]) != TYPE_ARRAY:
			continue
		var arr: Array = []
		for e in (d["history"][pid] as Array):
			if typeof(e) == TYPE_DICTIONARY:
				var attrs := {}
				for a in (e.get("attrs", {}) as Dictionary):
					attrs[str(a)] = int(e["attrs"][a])
				arr.append({"week": int(e.get("week", 0)), "overall": int(e.get("overall", 0)), "attrs": attrs, "fitness": int(e.get("fitness", 100))})
		s.history[str(pid)] = arr.slice(-DevConfig.HISTORY_MAX)
	for pid in (d.get("last_attrs", {}) as Dictionary):
		if ok.call(str(pid)):
			var m := {}
			for a in (d["last_attrs"][pid] as Dictionary):
				m[str(a)] = int(d["last_attrs"][pid][a])
			s.last_attrs[str(pid)] = m
	for k in ["last_apps", "idle", "milestones", "fatigue_flagged"]:
		var target: Dictionary = {"last_apps": s.last_apps, "idle": s.idle_weeks, "milestones": s.milestones, "fatigue_flagged": s.fatigue_flagged}[k]
		for pid in (d.get(k, {}) as Dictionary):
			if ok.call(str(pid)):
				target[str(pid)] = int(d[k][pid])
	for pid in (d.get("season_gain", {}) as Dictionary):
		if ok.call(str(pid)):
			var g := {}
			for a in (d["season_gain"][pid] as Dictionary):
				g[str(a)] = int(d["season_gain"][pid][a])
			s.season_gain[str(pid)] = g
	s.next_session_id = maxi(int(d.get("next_session_id", 1)), 1)
	for ss in (d.get("sessions", []) as Array):
		if typeof(ss) == TYPE_DICTIONARY and DevConfig.SESSIONS.has(str(ss.get("session", ""))):
			var pl: Array = []
			for pid in (ss.get("player_ids", []) as Array):
				if ok.call(str(pid)):
					pl.append(str(pid))
			if not pl.is_empty():
				s.sessions.append({"id": str(ss.get("id", "ses_x")), "session": str(ss["session"]), "day": clampi(int(ss.get("day", 0)), 0, 6),
						"intensity": clampf(float(ss.get("intensity", 0.5)), 0.0, 1.0), "player_ids": pl})
	for r in (d.get("reports", []) as Array):
		if typeof(r) == TYPE_DICTIONARY:
			var rr := (r as Dictionary).duplicate(true)
			if rr.has("coach_mult"):
				rr["coach_mult"] = float(rr["coach_mult"])
			s.reports.append(rr)
	for n in (d.get("notifications", []) as Array):
		if typeof(n) == TYPE_DICTIONARY and str(n.get("id", "")) != "":
			var nn := (n as Dictionary).duplicate(true)
			nn["week"] = int(nn.get("week", 0))
			nn["season"] = int(nn.get("season", 0))
			s.notifications.append(nn)
	return s


## Integrity check used by the tests and the save validator: returns error strings (empty = fine).
func validate() -> Array[String]:
	var errors: Array[String] = []
	var ids := {}
	for c in coaching.coaches + coaching.market:
		if ids.has(c["id"]):
			errors.append("duplicate coach id '%s'" % c["id"])
		ids[c["id"]] = true
		if not (str(c["department"]) in DevConfig.DEPARTMENTS):
			errors.append("coach '%s' has an unknown department" % c["id"])
		for k in ["overall", "technical", "tactical", "youth", "pro"]:
			if int(c[k]) < DevConfig.RATING_MIN or int(c[k]) > DevConfig.RATING_MAX:
				errors.append("coach '%s' rating %s out of range" % [c["id"], k])
	for c in coaching.coaches:
		if int(c["expiry_season"]) < int(c["signed_season"]):
			errors.append("coach '%s' expires before he was signed" % c["id"])
	for pid in plans.plans:
		var pl: Dictionary = plans.plans[pid]
		if (pl["weights"] as Dictionary).is_empty():
			errors.append("plan of '%s' has no targets" % pid)
	return errors
