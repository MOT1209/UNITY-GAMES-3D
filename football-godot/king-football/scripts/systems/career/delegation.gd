class_name Delegation
extends RefCounted

## Career phase C9.3: tasks the manager hands to the assistant. Each domain is "me" or "assistant". The assistant uses the same
## rules as the user (market.renew_contract with the player's own terms, PromotionSystem.promote); his quality (0..1, the staff
## system of C2 will set it from the real assistant) decides how picky he is. Everything he does is reported to the inbox.
## Domains that exist today: academy (promotions of over-age prospects) and renewals (small contract renewals).
## NOT delegable yet (their systems do not exist): training of the first team, friendlies, press conferences, small loans.

const DOMAINS: Array[String] = ["academy", "renewals", "scouting"]
## Assistant levels (1..MAX_LEVEL), bought with club money: each level makes him better (quality) and level 2 unlocks scouting.
const MAX_LEVEL := 5
const LEVEL_COST := 250_000              # x the next level
const DOMAIN_LEVEL := {"academy": 1, "renewals": 1, "scouting": 2}
const ME := "me"
const ASSISTANT := "assistant"

var settings: Dictionary = {}         # domain -> "me" / "assistant"
var quality := 0.5                    # 0..1 (from the staff system)
var level := 1                        # 1..MAX_LEVEL (upgrades)
var last_summary_week := -1


## The assistant's skill: the better of the staff member's quality and his level (0.35 at level 1 .. 0.87 at level 5).
func effective_quality() -> float:
	return clampf(maxf(quality, 0.35 + 0.13 * float(level - 1)), 0.0, 1.0)


func unlocked(domain: String) -> bool:
	return level >= int(DOMAIN_LEVEL.get(domain, 1))


func upgrade_cost() -> int:
	return LEVEL_COST * (level + 1)


## Pays the next level from the club's ledger. Returns "" or an error.
func upgrade(career: CareerState) -> String:
	if level >= MAX_LEVEL:
		return "the assistant is at the top level"
	var cost := upgrade_cost()
	var ledger: FinanceLedger = career.ledger()
	if not ledger.can_afford(-cost, "staff"):
		return "insufficient funds"
	ledger.record("staff", -cost, "Assistant course", career.week, "FIN_ASSISTANT_UPGRADE")
	level += 1
	return ""


func is_delegated(domain: String) -> bool:
	return str(settings.get(domain, ME)) == ASSISTANT


func set_domain(domain: String, who: String) -> bool:
	if not DOMAINS.has(domain) or not [ME, ASSISTANT].has(who):
		return false
	if who == ASSISTANT and not unlocked(domain):
		return false
	settings[domain] = who
	return true


## Runs once a week (a step of `CareerState.advance_week`). Returns the actions taken: [{domain, key, args}].
func run_week(career: CareerState, squads: Dictionary, academies: Dictionary) -> Array:
	var done: Array = []
	if career.manager.unemployed:
		return done
	if is_delegated("academy") and academies.has(career.club_id):
		done.append_array(_academy(career, academies[career.club_id]))
	if is_delegated("renewals"):
		done.append_array(_renewals(career))
	if is_delegated("scouting") and unlocked("scouting"):
		done.append_array(_scouting(career, academies.get(career.club_id)))
	if done.is_empty() and settings.values().has(ASSISTANT) and career.week - last_summary_week >= 4:
		# nothing needed doing: say so once a month, so the manager knows the assistant is at work
		last_summary_week = career.week
		career.inbox.add("assistant_idle:%d:%d" % [career.season, career.week], career.season, career.week, "staff", "INBOX_ASSISTANT_IDLE",
				[career.market.expiring_contracts(career.club_id).size()], {"sender": "assistant"})
	if not done.is_empty():
		career.inbox.add("assistant:%d:%d" % [career.season, career.week], career.season, career.week, "staff", "INBOX_ASSISTANT_REPORT",
				[done.size()], {"sender": "assistant"})
		for a in done:
			career.inbox.add("", career.season, career.week, "staff", str(a["key"]), a["args"], {"sender": "assistant"})
	return done


func _academy(career: CareerState, academy: Academy) -> Array:
	var out: Array = []
	var db: Node = career.db
	var team0: TeamData = db.get_team(career.club_id)
	var ready_floor := _squad_floor(db, team0) - int(round((1.0 - effective_quality()) * 4.0))
	for pid in academy.roster_ids.duplicate():
		# a prospect who is already as good as the squad's regulars goes up (whatever his age in the academy)
		var y: PlayerData = db.get_player(pid)
		if y != null and y.age >= AcademyConfig.MIN_PROMOTION_AGE and y.get_overall() >= ready_floor and team0.squad_ids.size() < 30:
			if PromotionSystem.promote(db, academy, pid) == "":
				out.append({"domain": "academy", "key": "INBOX_ASSISTANT_PROMOTED", "args": [y.display_name]})
	for pid in academy.over_age_ids(db):
		var p: PlayerData = db.get_player(pid)
		if p == null:
			continue
		var team: TeamData = db.get_team(career.club_id)
		var floor_rating := _squad_floor(db, team) - int(round((1.0 - effective_quality()) * 6.0))
		if p.get_overall() >= floor_rating and p.age >= AcademyConfig.MIN_PROMOTION_AGE:
			if PromotionSystem.promote(db, academy, pid) == "":
				out.append({"domain": "academy", "key": "INBOX_ASSISTANT_PROMOTED", "args": [p.display_name]})
		else:
			var err := academy.keep_extended(db, pid)             # not good enough yet: keep developing him
			if err == "":
				out.append({"domain": "academy", "key": "INBOX_ASSISTANT_KEPT", "args": [p.display_name]})
	return out


func _renewals(career: CareerState) -> Array:
	var out: Array = []
	var db: Node = career.db
	var team: TeamData = db.get_team(career.club_id)
	var floor_rating := _squad_floor(db, team)
	for p in career.market.expiring_contracts(career.club_id):
		if p.get_overall() < floor_rating + int(round(effective_quality() * 4.0)) - 4 and p.status != PlayerData.Status.YOUTH:
			if not _reported_letgo.has(p.id):
				_reported_letgo[p.id] = true
				out.append({"domain": "renewals", "key": "INBOX_ASSISTANT_LET_GO", "args": [p.display_name]})
			continue                                                      # not worth the wage: let him go (said once)
		var c := career.market.default_contract(p, career.club_id, true)
		var err := career.market.renew_contract(career.club_id, p.id, c.salary, c.years, career.week)
		if err != "":
			# second try: the player's minimum wage (a good assistant also offers a longer deal)
			var years := 2 if effective_quality() < 0.6 else 3
			err = career.market.renew_contract(career.club_id, p.id, career.market.minimum_wage(p), years, career.week)
			if err == "":
				c.years = years
		if err == "":
			out.append({"domain": "renewals", "key": "INBOX_ASSISTANT_RENEWED", "args": [p.display_name, c.years]})
		elif not _reported_fail.has(p.id + err):
			_reported_fail[p.id + err] = true
			out.append({"domain": "renewals", "key": "INBOX_ASSISTANT_RENEW_FAILED", "args": [p.display_name, ErrorText.localize(err, db)]})
	return out


var _reported_letgo: Dictionary = {}
var _reported_fail: Dictionary = {}


## Level 2+: idle scouts go out worldwide for 4 weeks when the academy budget allows it.
func _scouting(career: CareerState, academy: Academy) -> Array:
	var out: Array = []
	var app := (Engine.get_main_loop() as SceneTree).root.get_node_or_null("AppHub") if Engine.get_main_loop() is SceneTree else null
	if academy == null or app == null or not (app.scouting as Dictionary).has(career.club_id):
		return out
	var sc: ScoutingSystem = app.scouting[career.club_id]
	for sid in sc.scouts.keys():
		if sc.is_scout_busy(sid):
			continue
		if sc.start_mission(academy, sid, ScoutingSystem.WORLDWIDE, 4) == "":
			out.append({"domain": "scouting", "key": "INBOX_ASSISTANT_SCOUT_SENT", "args": [str(sc.scouts[sid]["name"])]})
	return out


## Rating of the 14th best first-team player: below it a player is not a regular.
static func _squad_floor(db: Node, team: TeamData) -> int:
	var ovr: Array = []
	for p in db.get_squad(team.id):
		ovr.append(p.get_overall())
	ovr.sort()
	ovr.reverse()
	return int(ovr[mini(13, ovr.size() - 1)]) if not ovr.is_empty() else 0


func to_dict() -> Dictionary:
	return {"settings": settings.duplicate(), "quality": quality, "level": level, "last_summary_week": last_summary_week}


static func from_dict(d: Dictionary) -> Delegation:
	var x := Delegation.new()
	for k in (d.get("settings", {}) as Dictionary):
		if DOMAINS.has(str(k)):
			x.settings[str(k)] = ASSISTANT if str(d["settings"][k]) == ASSISTANT else ME
	x.quality = clampf(float(d.get("quality", 0.5)), 0.0, 1.0)
	x.level = clampi(int(d.get("level", 1)), 1, MAX_LEVEL)
	x.last_summary_week = int(d.get("last_summary_week", -1))
	return x
