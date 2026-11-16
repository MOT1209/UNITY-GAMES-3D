class_name PlayerRelations
extends RefCounted

## Career phases C3.3 - C3.6: talks with a player (praise / criticise / motivate / promises), promises that are tracked and
## judged, player demands as events, dressing-room leaders, position training and mentoring. Saved with the career.
## Everything is deterministic (seeded by season, week and player id) and uses the personality of `PlayerPersonality`.

const TALK_KINDS: Array[String] = ["praise", "criticise", "motivate", "promise_minutes", "promise_contract"]
const PROMISE_WEEKS := 6                       # a minutes promise is judged after this many weeks
const MAX_MENTEES := 2                         # per mentor
const POSITION_TRAINING_WEEKS := 8
const MAX_LEADERS := 3

var relationship: Dictionary = {}              # player id -> 0..100 (default 50)
var promises: Array = []                       # [{player_id, kind, week_abs, apps_at_start, status: open|kept|broken}]
var demands: Array = []                        # [{id, player_id, kind, week_abs, status: open|settled|ignored}]
var position_training: Dictionary = {}         # player id -> {target, weeks_left}
var mentoring: Dictionary = {}                 # mentee id -> mentor id
var leaders: Array = []                        # ids of the leaders seen at the last check
var _next_demand := 1


func rel(player_id: String) -> int:
	return int(relationship.get(player_id, 50))


func _bump(player_id: String, delta: int) -> void:
	relationship[player_id] = clampi(rel(player_id) + delta, 0, 100)


# --- talks ----------------------------------------------------------------------------------------------------

## A talk with one player. Returns {success, reply (translation key), morale_delta}. Morale and the relationship move for real.
func talk(career: CareerState, p: PlayerData, kind: String) -> Dictionary:
	if not TALK_KINDS.has(kind) or p.team_id != career.club_id:
		return {"success": false, "reply": "TALK_REPLY_NONE", "morale_delta": 0}
	var pers := PlayerPersonality.for_player(p)
	var roll := float(hash([career.season, career.week, p.id, kind]) & 0xffff) / 65535.0
	var bonus := (float(rel(p.id)) - 50.0) / 200.0                       # +-0.25
	var success := false
	var delta := 0
	match kind:
		"praise":
			success = true
			delta = 2 + (1 if int(pers["ambition"]) >= 12 else 0)
		"criticise":
			var thick := float(int(pers["temperament"])) / 20.0 + bonus      # calm players take criticism
			success = roll < clampf(0.25 + thick * 0.7, 0.05, 0.95)
			delta = 3 if success else -5
		"motivate":
			success = roll < clampf(0.5 + bonus + (0.1 if p.morale < 60 else 0.0), 0.1, 0.95)
			delta = 4 if success else 0
		"promise_minutes":
			success = true
			delta = 5
			promises.append({"player_id": p.id, "kind": "minutes", "week_abs": career.absolute_week(), "apps_at_start": _apps(career, p.id), "status": "open"})
		"promise_contract":
			success = true
			delta = 4
			promises.append({"player_id": p.id, "kind": "contract", "week_abs": career.absolute_week(), "apps_at_start": 0, "status": "open"})
	var real := career.morale.apply(p, delta, "MORALE_TALK_PLAYER_" + kind.to_upper() if success or delta != 0 else "MORALE_TALK_PLAYER", career.season, career.week)
	_bump(p.id, 4 if success else -4)
	return {"success": success, "reply": "TALK_REPLY_%s_%s" % [kind.to_upper(), "OK" if success else "BAD"], "morale_delta": real}


static func _apps(career: CareerState, pid: String) -> int:
	var r: Dictionary = career.world_stats.get(pid, {})
	return int(r.get("apps", 0)) + int(r.get("est_apps", 0))


## Weekly: judges promises. A minutes promise is broken when the player did not play enough in PROMISE_WEEKS weeks; a contract promise
## is kept when the contract was renewed. Returns [{player_id, status}].
func weekly_promises(career: CareerState) -> Array:
	var out: Array = []
	for pr in promises:
		if pr["status"] != "open":
			continue
		var p: PlayerData = career.db.get_player(str(pr["player_id"]))
		if p == null or p.team_id != career.club_id:
			pr["status"] = "broken" if p != null else "kept"
			continue
		var age_weeks := career.absolute_week() - int(pr["week_abs"])
		if pr["kind"] == "minutes" and age_weeks >= PROMISE_WEEKS:
			var played := _apps(career, p.id) - int(pr["apps_at_start"])
			pr["status"] = "kept" if played >= 3 else "broken"
		elif pr["kind"] == "contract":
			var renewed := p.development_history.any(func(h: Dictionary) -> bool: return str(h.get("event", "")) == "renewed" and int(h.get("week", -1)) >= int(pr["week_abs"]) % CareerState.WEEKS_PER_SEASON)
			if renewed:
				pr["status"] = "kept"
			elif age_weeks >= 16:
				pr["status"] = "broken"
		if pr["status"] == "kept":
			career.morale.apply(p, 5, "MORALE_PROMISE_KEPT", career.season, career.week)
			_bump(p.id, 8)
			out.append({"player_id": p.id, "status": "kept"})
		elif pr["status"] == "broken":
			career.morale.apply(p, -12, "MORALE_PROMISE_BROKEN", career.season, career.week)
			_bump(p.id, -15)
			career.inbox.add("broken:%s:%d" % [p.id, career.absolute_week()], career.season, career.week, "players", "INBOX_PROMISE_BROKEN", [p.display_name], {"action": {"screen": "player_profile", "params": {"player_id": p.id}}})
			out.append({"player_id": p.id, "status": "broken"})
	return out


# --- demands --------------------------------------------------------------------------------------------------

## Weekly: players who have a reason (and the temperament) ask for something. At most one new demand per week. Deterministic.
func weekly_demands(career: CareerState) -> Dictionary:
	var squad: Array = career.db.get_squad(career.club_id).filter(func(p: PlayerData) -> bool: return p.status != PlayerData.Status.YOUTH and p.loan_parent == "")
	squad.sort_custom(func(a: PlayerData, b: PlayerData) -> bool: return a.get_overall() > b.get_overall())
	for i in squad.size():
		var p: PlayerData = squad[i]
		if demands.any(func(d: Dictionary) -> bool: return d["player_id"] == p.id and d["status"] == "open"):
			continue
		var pers := PlayerPersonality.for_player(p)
		var kind := ""
		if p.morale < 45 and int(pers["ambition"]) >= 11:
			kind = "wants_leave"
		elif i < 3 and p.contract_years <= 1 and int(pers["ambition"]) >= 10:
			kind = "wants_contract"
		elif i >= 14 and p.morale < 60 and int(pers["ambition"]) >= 8:
			kind = "wants_playing_time"
		if kind == "":
			continue
		if (hash([career.season, career.week, p.id, "demand"]) & 0xff) > 60:
			continue
		var d := {"id": _next_demand, "player_id": p.id, "kind": kind, "week_abs": career.absolute_week(), "status": "open"}
		_next_demand += 1
		demands.append(d)
		career.inbox.add("demand:%d" % d["id"], career.season, career.week, "players", "INBOX_DEMAND_" + kind.to_upper(), [p.display_name],
				{"needs_decision": true, "action": {"screen": "player_profile", "params": {"player_id": p.id}}})
		return d
	return {}


## The user answers a demand: "grant" (the player is satisfied), "calm" (a temporary calm), "refuse" (he gets angrier; a leave request
## then lists him for sale). Returns {ok, morale_delta, listed}.
func answer_demand(career: CareerState, demand_id: int, choice: String) -> Dictionary:
	for d in demands:
		if int(d["id"]) != demand_id or d["status"] != "open":
			continue
		var p: PlayerData = career.db.get_player(str(d["player_id"]))
		if p == null:
			return {"ok": false, "morale_delta": 0, "listed": false}
		var delta := 0
		var listed := false
		match choice:
			"grant":
				delta = 8
				_bump(p.id, 10)
				if d["kind"] == "wants_contract":
					var c := career.market.default_contract(p, career.club_id, true)
					career.market.renew_contract(career.club_id, p.id, c.salary, c.years, career.week)
			"calm":
				delta = 3
				_bump(p.id, 2)
			_:
				delta = -6
				_bump(p.id, -10)
				if d["kind"] == "wants_leave":
					listed = career.market.set_listing(career.club_id, p.id, TransferMarket.LISTING_TRANSFER) == ""
		d["status"] = "settled"
		career.morale.apply(p, delta, "MORALE_DEMAND_" + choice.to_upper(), career.season, career.week)
		var msg := career.inbox.get_message(int(career.inbox._uids.get("demand:%d" % demand_id, 0)))
		if not msg.is_empty():
			career.inbox.resolve(int(msg["id"]))
		return {"ok": true, "morale_delta": delta, "listed": listed}
	return {"ok": false, "morale_delta": 0, "listed": false}


# --- leaders -------------------------------------------------------------------------------------------------

## The dressing-room leaders: the three with the most leadership weight (leadership trait, age, overall).
static func current_leaders(career: CareerState) -> Array:
	var squad: Array = career.db.get_squad(career.club_id).filter(func(p: PlayerData) -> bool: return p.status != PlayerData.Status.YOUTH)
	var weight := func(p: PlayerData) -> float:
		return float(PlayerPersonality.trait_value(p, "leadership")) * 2.0 + float(p.age - 20) * 0.3 + float(p.get_overall()) * 0.1
	squad.sort_custom(func(a: PlayerData, b: PlayerData) -> bool:
		var wa: float = weight.call(a)
		var wb: float = weight.call(b)
		return wa > wb if not is_equal_approx(wa, wb) else a.id < b.id)
	return squad.slice(0, MAX_LEADERS).map(func(p: PlayerData) -> String: return p.id)


## Weekly: if a leader left the club since the last check, everyone's morale drops once. Returns the ids that left.
func weekly_leaders(career: CareerState) -> Array:
	var left: Array = []
	for id in leaders:
		var p: PlayerData = career.db.get_player(str(id))
		if p == null or p.team_id != career.club_id or p.status == PlayerData.Status.RETIRED:
			left.append(id)
	if not left.is_empty():
		for pl: PlayerData in career.db.get_squad(career.club_id).filter(func(x: PlayerData) -> bool: return x.status != PlayerData.Status.YOUTH):
			career.morale.apply(pl, -4, "MORALE_LEADER_LEFT", career.season, career.week)
	leaders = current_leaders(career)
	return left


# --- position training and mentoring -----------------------------------------------------------------------

func start_position_training(p: PlayerData, target: String) -> String:
	if not (target in PlayerData.Position.keys()) or target == PlayerData.Position.keys()[p.position]:
		return "POSTRAIN_ERR_TARGET"
	if p.secondary_positions.has(target):
		return "POSTRAIN_ERR_HAS"
	if position_training.has(p.id):
		return "POSTRAIN_ERR_BUSY"
	position_training[p.id] = {"target": target, "weeks_left": POSITION_TRAINING_WEEKS}
	return ""


func weekly_position_training(career: CareerState) -> Array:
	var done: Array = []
	for pid in position_training.keys():
		var p: PlayerData = career.db.get_player(str(pid))
		if p == null or p.team_id != career.club_id:
			position_training.erase(pid)
			continue
		var st: Dictionary = position_training[pid]
		st["weeks_left"] = int(st["weeks_left"]) - 1
		if int(st["weeks_left"]) <= 0:
			if not p.secondary_positions.has(st["target"]):
				p.secondary_positions.append(st["target"])
			position_training.erase(pid)
			done.append(pid)
	return done


func assign_mentor(career: CareerState, mentor: PlayerData, mentee: PlayerData) -> String:
	if mentor.team_id != career.club_id or mentee.team_id != career.club_id or mentor.id == mentee.id:
		return "MENTOR_ERR_INVALID"
	if mentor.age < 28 or mentee.age > 21:
		return "MENTOR_ERR_AGE"
	if PlayerPersonality.trait_value(mentor, "professionalism") < 12:
		return "MENTOR_ERR_PRO"
	if mentoring.values().count(mentor.id) >= MAX_MENTEES:
		return "MENTOR_ERR_FULL"
	mentoring[mentee.id] = mentor.id
	return ""


## Weekly: a mentee gains extra growth progress on his weakest attribute (+0.12 a week), scaled by the mentor's professionalism.
func weekly_mentoring(career: CareerState) -> int:
	var n := 0
	for mid in mentoring.keys():
		var mentee: PlayerData = career.db.get_player(str(mid))
		var mentor: PlayerData = career.db.get_player(str(mentoring[mid]))
		if mentee == null or mentor == null or mentee.team_id != career.club_id or mentor.team_id != career.club_id:
			mentoring.erase(mid)
			continue
		var weakest := ""
		var low := 1000
		for a in PlayerData.ATTRIBUTES:
			if a == "goalkeeping" and mentee.position != PlayerData.Position.GK:
				continue
			var v := mentee.get_attribute(a)
			if v < low:
				low = v
				weakest = a
		if weakest != "":
			mentee.growth_progress[weakest] = float(mentee.growth_progress.get(weakest, 0.0)) + 0.12 * (float(PlayerPersonality.trait_value(mentor, "professionalism")) / 15.0)
			n += 1
	return n


func to_dict() -> Dictionary:
	return {"relationship": relationship.duplicate(), "promises": promises.duplicate(true), "demands": demands.duplicate(true), "position_training": position_training.duplicate(true),
			"mentoring": mentoring.duplicate(), "leaders": leaders.duplicate(), "next_demand": _next_demand}


static func from_dict(d: Dictionary) -> PlayerRelations:
	var r := PlayerRelations.new()
	for k in (d.get("relationship", {}) as Dictionary):
		r.relationship[str(k)] = clampi(int(d["relationship"][k]), 0, 100)
	r.promises = PlayerData._restore_ints((d.get("promises", []) as Array).duplicate(true))
	r.demands = PlayerData._restore_ints((d.get("demands", []) as Array).duplicate(true))
	r.position_training = PlayerData._restore_ints((d.get("position_training", {}) as Dictionary).duplicate(true))
	for k in (d.get("mentoring", {}) as Dictionary):
		r.mentoring[str(k)] = str(d["mentoring"][k])
	r.leaders = (d.get("leaders", []) as Array).map(func(x: Variant) -> String: return str(x))
	r._next_demand = maxi(int(d.get("next_demand", 1)), 1)
	return r
