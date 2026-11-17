class_name CareerFlow
extends RefCounted

## Career phase C9.2: turns the career state into inbox messages (`sync`) and moves the calendar until something needs the
## manager (`continue_until_decision`). One set of rules: the same messages are produced whatever screen is open.
## Decision kinds:
##   blocking  - a user match is due, or the season is over: "Continue" always stops here until it is dealt with;
##   decision  - an offer / request: "Continue" stops once (the message is marked `shown`), so ignoring it never traps the user.

const MAX_WEEKS_PER_CONTINUE := 60
const MAX_DAYS_PER_CONTINUE := 400


## Adds the messages of the current state and resolves the decision messages whose condition no longer holds.
static func sync(career: CareerState) -> void:
	var ib := career.inbox
	var active: Dictionary = {}
	var s := career.season
	var w := career.week
	# 1. matches due
	for pair in career.due_user_fixtures():
		var comp: Competition = pair[0]
		var f: Dictionary = pair[1]
		var uid := "match:%s:%s" % [comp.id, f["match_id"]]
		active[uid] = true
		ib.add(uid, s, w, "competitions", "INBOX_MATCH_DUE", [_team(career, f["home"]), _team(career, f["away"])],
				{"needs_decision": true, "blocking": true, "action": {"screen": "career", "params": {}}})
	# 2. transfer offers waiting for the user
	for o: TransferOffer in career.market.offers:
		var uid := ""
		var key := ""
		if o.to_club == career.market.user_club and o.status == TransferOffer.PENDING:
			uid = "offer_in:%d" % o.id
			key = "INBOX_OFFER_INCOMING"
		elif o.from_club == career.market.user_club and o.status == TransferOffer.COUNTERED:
			uid = "offer_counter:%d:%d" % [o.id, o.rounds.size()]
			key = "INBOX_OFFER_COUNTERED"
		elif o.from_club == career.market.user_club and o.status == TransferOffer.ACCEPTED and o.contract.is_empty():
			uid = "offer_contract:%d" % o.id
			key = "INBOX_OFFER_ACCEPTED"
		if uid == "":
			continue
		active[uid] = true
		ib.add(uid, s, w, "transfers", key, [_player(career, o.player_id), _team(career, o.from_club if o.to_club == career.market.user_club else o.to_club), o.fee],
				{"needs_decision": true, "action": {"screen": "transfers", "params": {}}})
	# 3. season over
	if w >= CareerState.WEEKS_PER_SEASON:
		var uid := "season_end:%d" % s
		active[uid] = true
		ib.add(uid, s, w, "board", "INBOX_SEASON_OVER", [s], {"needs_decision": true, "blocking": true, "action": {"screen": "career", "params": {}}})
	# 4. unemployed manager: job offers
	if career.manager.unemployed:
		active["unemployed"] = true
		ib.add("unemployed:%d" % career.manager.history.size(), s, w, "board", "INBOX_UNEMPLOYED", [], {"needs_decision": true, "action": {"screen": "career", "params": {}}})
		active["unemployed:%d" % career.manager.history.size()] = true
	# 5. informational: transfer-market notifications (deduplicated by content)
	for nt in career.market.notifications:
		var uid := "note:%d:%d:%s:%d" % [int(nt["season"]), int(nt["week"]), str(nt["key"]), int(nt.get("offer_id", 0))]
		ib.add(uid, int(nt["season"]), int(nt["week"]), "transfers", "INBOX_NOTE_PREFIX", [Loc.f(str(nt["key"]), _args(career, nt.get("args", [])))],
				{"action": {"screen": "transfers", "params": {}}})
	for m in ib.messages:
		if bool(m["needs_decision"]) and not bool(m["resolved"]) and not active.has(str(m["uid"])):
			m["resolved"] = true


static func _team(career: CareerState, id: String) -> String:
	if TransferMarket.is_external(id):
		return str((career.market.externals.get(id, {}) as Dictionary).get("name", id))
	var t: TeamData = career.db.get_team(id)
	return t.display_name if t != null else id


static func _player(career: CareerState, id: String) -> String:
	var p: PlayerData = career.db.get_player(id)
	return p.display_name if p != null else id


static func _args(career: CareerState, args: Array) -> Array:
	var out: Array = []
	for a in args:
		if a is String and career.db.players.has(a):
			out.append(_player(career, a))
		elif a is String and career.db.teams.has(a):
			out.append(_team(career, a))
		else:
			out.append(a)
	return out


## The decision "Continue" must stop at now, or {}: any blocking one, else the first decision not shown yet.
static func next_stop(career: CareerState) -> Dictionary:
	sync(career)
	var fresh: Dictionary = {}
	for m in career.inbox.pending_decisions():          # newest first
		if bool(m["blocking"]):
			return m
		if not bool(m["shown"]):
			fresh = m
	return fresh


## Advances weeks until something needs the manager. Returns {"weeks": n, "stop": message ({} = limit reached)}.
## `advance` is a Callable performing ONE week (awaitable); the hub passes `AppHub.advance_week_async`.
static func continue_until_decision(career: CareerState, advance: Callable) -> Dictionary:
	var weeks := 0
	while weeks <= MAX_WEEKS_PER_CONTINUE:
		var stop := next_stop(career)
		if not stop.is_empty():
			stop["shown"] = true
			return {"weeks": weeks, "stop": stop}
		if career.week >= CareerState.WEEKS_PER_SEASON:
			return {"weeks": weeks, "stop": {}}
		await advance.call()
		weeks += 1
	return {"weeks": weeks, "stop": {}}


## Phase K5: advances DAY by day until something needs the manager (his match, an offer to answer, a demand, a meeting, a
## promise due, the end of a window, the end of the season) — or until the Julian day `until_jdn` is reached (-1 = no
## target: "Continue"). `advance` performs ONE day (`AppHub.advance_day`). `should_stop` (optional, returns bool) lets the
## UI's Stop button end a long run between two days. Returns {"days": n, "stop": message ({} = target / limit reached)}.
static func continue_days(career: CareerState, advance: Callable, until_jdn: int = -1, should_stop: Callable = Callable()) -> Dictionary:
	var days := 0
	var window_was := TransferMarket.window_days_left(career.season, career.week, career.day) > 0
	while days <= MAX_DAYS_PER_CONTINUE:
		var stop := next_stop(career)
		if not stop.is_empty():
			stop["shown"] = true
			return {"days": days, "stop": stop}
		if until_jdn >= 0 and CareerDate.jdn_of(career.season, career.week, career.day) >= until_jdn:
			return {"days": days, "stop": {}}
		if career.week >= CareerState.WEEKS_PER_SEASON and career.day >= 6:
			return {"days": days, "stop": {}}
		if should_stop.is_valid() and bool(should_stop.call()):
			return {"days": days, "stop": {}, "interrupted": true}
		await advance.call()
		days += 1
		var window_now := TransferMarket.window_days_left(career.season, career.week, career.day) > 0
		if window_was and not window_now and until_jdn < 0:
			career.inbox.add("window_closed:%d:%d" % [career.season, career.week], career.season, career.week, "transfers",
					"INBOX_WINDOW_CLOSED", [], {"needs_decision": true, "action": {"screen": "transfers", "params": {}}})
		window_was = window_now
	return {"days": days, "stop": {}}
