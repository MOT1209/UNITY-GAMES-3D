class_name Delegation
extends RefCounted

## Career phase C9.3: tasks the manager hands to the assistant. Each domain is "me" or "assistant". The assistant uses the same
## rules as the user (market.renew_contract with the player's own terms, PromotionSystem.promote); his quality (0..1, the staff
## system of C2 will set it from the real assistant) decides how picky he is. Everything he does is reported to the inbox.
## Domains that exist today: academy (promotions of over-age prospects) and renewals (small contract renewals).
## NOT delegable yet (their systems do not exist): training of the first team, friendlies, press conferences, small loans.

const DOMAINS: Array[String] = ["academy", "renewals"]
const ME := "me"
const ASSISTANT := "assistant"

var settings: Dictionary = {}         # domain -> "me" / "assistant"
var quality := 0.5                    # 0..1


func is_delegated(domain: String) -> bool:
	return str(settings.get(domain, ME)) == ASSISTANT


func set_domain(domain: String, who: String) -> bool:
	if not DOMAINS.has(domain) or not [ME, ASSISTANT].has(who):
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
	if not done.is_empty():
		career.inbox.add("assistant:%d:%d" % [career.season, career.week], career.season, career.week, "staff", "INBOX_ASSISTANT_REPORT",
				[done.size()], {"sender": "assistant"})
		for a in done:
			career.inbox.add("", career.season, career.week, "staff", str(a["key"]), a["args"], {"sender": "assistant"})
	return done


func _academy(career: CareerState, academy: Academy) -> Array:
	var out: Array = []
	var db: Node = career.db
	for pid in academy.over_age_ids(db):
		var p: PlayerData = db.get_player(pid)
		if p == null:
			continue
		var team: TeamData = db.get_team(career.club_id)
		var floor_rating := _squad_floor(db, team) - int(round((1.0 - quality) * 6.0))
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
		if p.get_overall() < floor_rating + int(round(quality * 4.0)) - 2 and p.status != PlayerData.Status.YOUTH:
			continue                                                      # not worth the wage: let him go
		var c := career.market.default_contract(p, career.club_id, true)
		if career.market.renew_contract(career.club_id, p.id, c.salary, c.years, career.week) == "":
			out.append({"domain": "renewals", "key": "INBOX_ASSISTANT_RENEWED", "args": [p.display_name, c.years]})
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
	return {"settings": settings.duplicate(), "quality": quality}


static func from_dict(d: Dictionary) -> Delegation:
	var x := Delegation.new()
	for k in (d.get("settings", {}) as Dictionary):
		if DOMAINS.has(str(k)):
			x.settings[str(k)] = ASSISTANT if str(d["settings"][k]) == ASSISTANT else ME
	x.quality = clampf(float(d.get("quality", 0.5)), 0.0, 1.0)
	return x
