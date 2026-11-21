class_name StaffTeam
extends RefCounted

## Career phase C2.6: the managed club's coaching staff. Roles, a deterministic market, hiring and firing (with compensation),
## and REAL effects: the assistant sets the delegation quality, the fitness coach and the doctor shorten / reduce injuries, the
## youth coach speeds up academy development, the goalkeeping coach develops goalkeepers, the chief scout sets scouting accuracy.
## Wages go through the FinanceLedger (weekly, category "salary").

const ROLES: Array[String] = ["assistant", "first_team_coach", "goalkeeping_coach", "fitness_coach", "doctor", "chief_scout", "youth_coach"]
const BASE_SLOTS := 4                          # staff members allowed; +1 per training facility level above 1
const FIRING_WEEKS := 8                        # compensation = wage x weeks
const PERSONALITIES: Array[String] = ["calm", "demanding", "friendly", "strict"]

## Roles now owned by the development coaching staff (`CoachingStaff`, hired on its own screens): the fitness, goalkeeping and first-team
## (head) coach, the latter as the tactical coach. A legacy member of such a role is imported into the department once
## (`DevelopmentEngine._import_legacy`) and his wage is paid by the coaching staff from then on. Their effects here read the better of
## the legacy member and the development coach of that department; none of them multiplies into training (CoachingStaff does that).
const BRIDGED := {"fitness_coach": "fitness", "goalkeeping_coach": "goalkeeping", "first_team_coach": "tactical"}
const UI_ROLES: Array[String] = ["assistant", "doctor", "chief_scout", "youth_coach"]
var coaching_link: CoachingStaff = null         # not saved; set by DevelopmentEngine.ensure_staff / CareerState.from_dict

var members: Array = []                        # {id, role, name, age, nationality_id, skill (1-20), wage, years, personality}


## Deterministic candidates for a role in a season (same career, same list).
static func market(role: String, season: int, club_seed: int, count: int = 4) -> Array:
	var out: Array = []
	if not ROLES.has(role):
		return out
	for i in count:
		var h := hash([role, season, club_seed, i]) & 0x7fffffff
		var skill := clampi(4 + (h % 14) + ((h / 14) % 3), 1, 20)
		out.append({"id": "staff_%s_%d_%d_%d" % [role, season, club_seed % 1000, i], "role": role, "name": _name(h), "age": 35 + (h / 7) % 30,
				"nationality_id": "", "skill": skill, "wage": 800 + skill * skill * 12, "years": 2, "personality": PERSONALITIES[(h / 3) % PERSONALITIES.size()]})
	return out


static func _name(h: int) -> String:
	var first := ["Karim", "Jonas", "Luca", "Omar", "Mateo", "Sven", "Yusuf", "Pavel", "Idris", "Tomás"]
	var last := ["Hadad", "Brandt", "Moretti", "Salim", "Ferrer", "Lindqvist", "Okafor", "Novak", "Reyes", "Haddad"]
	return "%s %s" % [first[h % first.size()], last[(h / 11) % last.size()]]


func slots(training_level: int) -> int:
	return BASE_SLOTS + maxi(training_level - 1, 0)


func member_for(role: String) -> Dictionary:
	for m in members:
		if m["role"] == role:
			return m
	return {}


## Rating of the person in a role (0 when the post is empty).
func skill(role: String) -> int:
	var own := int(member_for(role).get("skill", 0))
	if coaching_link != null and BRIDGED.has(role):
		for co in coaching_link.in_department(str(BRIDGED[role])):
			own = maxi(own, int(co["overall"]))
	return own


## Hires a candidate into an empty role. Returns "" or an error key.
## `wage_budget` >= 0 replaces `ledger.wage_budget` (the career passes `TransferMarket.wage_budget_of`). `external_wages` = the
## coaching staff's wages, counted against the same budget (the coaching hire / renewal count this team's wages the same way).
func hire(candidate: Dictionary, training_level: int, ledger: FinanceLedger, week: int, wage_budget: int = -1, external_wages: int = 0) -> String:
	var role := str(candidate.get("role", ""))
	if not ROLES.has(role):
		return "STAFF_ERR_UNKNOWN"
	if not member_for(role).is_empty():
		return "STAFF_ERR_FILLED"
	if members.size() >= slots(training_level):
		return "STAFF_ERR_FULL"
	var budget := wage_budget if wage_budget >= 0 else (ledger.wage_budget if ledger != null else 0)
	if budget > 0 and weekly_wages() + external_wages + int(candidate["wage"]) > budget:
		return "STAFF_ERR_BUDGET"
	members.append(candidate.duplicate(true))
	return ""


## Fires the person in a role and pays the compensation. Returns "" or an error key.
func fire(role: String, ledger: FinanceLedger, week: int) -> String:
	var m := member_for(role)
	if m.is_empty():
		return "STAFF_ERR_EMPTY"
	var comp := int(m["wage"]) * FIRING_WEEKS
	if ledger != null:
		ledger.record("salary", -comp, "Staff compensation", week, "FIN_STAFF_COMPENSATION")
	members.erase(m)
	return ""


func weekly_wages() -> int:
	var w := 0
	for m in members:
		w += int(m["wage"])
	return w


func weekly(ledger: FinanceLedger, week: int) -> void:
	var w := weekly_wages()
	if w > 0 and ledger != null:
		ledger.record("salary", -w, "Staff wages", week, "FIN_STAFF_WAGES")
	for m in members:                                       # contracts count down once a year (every 46 weeks is handled by the season end)
		pass


## Season end: contracts shorten; those at zero leave.
func season_end() -> Array:
	var left: Array = []
	for m in members.duplicate():
		m["years"] = int(m["years"]) - 1
		if int(m["years"]) <= 0:
			members.erase(m)
			left.append(m["role"])
	return left


# --- effects (neutral when the post is empty) -------------------------------------------------------------

func assistant_quality() -> float:
	return clampf(float(skill("assistant")) / 20.0, 0.0, 1.0) if skill("assistant") > 0 else 0.3


func injury_factor() -> float:
	return 1.0 - 0.15 * clampf(float(skill("fitness_coach")) / 20.0, 0.0, 1.0)


func recovery_factor() -> float:
	return 1.0 - 0.20 * clampf(float(skill("doctor")) / 20.0, 0.0, 1.0)


## The club's youth coach. It is one of the sources of academy coaching (see DevelopmentEngine.best_academy_coaching), never a multiplier on top.
func youth_factor() -> float:
	return 1.0 + 0.10 * clampf(float(skill("youth_coach")) / 20.0, 0.0, 1.0)


func scouting_accuracy() -> float:
	return clampf(0.4 + 0.5 * float(skill("chief_scout")) / 20.0, 0.0, 1.0)


func to_dict() -> Dictionary:
	return {"members": members.duplicate(true)}


static func from_dict(d: Dictionary) -> StaffTeam:
	var s := StaffTeam.new()
	for m in d.get("members", []):
		if typeof(m) == TYPE_DICTIONARY and ROLES.has(str(m.get("role", ""))) and s.member_for(str(m["role"])).is_empty():
			var c: Dictionary = PlayerData._restore_ints((m as Dictionary).duplicate(true))
			c["skill"] = clampi(int(c.get("skill", 10)), 1, 20)
			s.members.append(c)
	return s
