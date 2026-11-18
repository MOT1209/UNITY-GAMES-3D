class_name CoachingStaff
extends RefCounted

## Development coaching staff of the managed club: six departments (attacking, midfield, defensive, goalkeeping, fitness, tactical),
## a recruitment market that refreshes with the calendar, contracts (salary, years, expiry season), negotiation, renewal, dismissal,
## yearly progression of every coach, and the training multipliers the DevelopmentEngine reads.
## `StaffTeam` (assistant, doctor, chief scout, youth coach ...) is a separate, older system and is left untouched; the injury / goalkeeper
## effects it already has keep working. Everything here is deterministic from `seed_value` (same career -> same candidates).
## Coach record: {id, name, age, nationality, department, specialization, overall, technical, tactical, youth, pro, experience,
## reputation, salary, years, signed_season, expiry_season, status ("employed"), history [{season, event, note}]}.

var coaches: Array = []
var market: Array = []                  # candidates (same fields as a coach + {listed_week, pref_years, flex})
var next_id: int = 1
var market_round: int = 0
var last_market_week: int = -1000
var seed_value: int = 1
var initialized: bool = false
var activity: Array = []                # recruitment log {week, kind, coach_id, name}
var warned: Dictionary = {}             # "expiry:<id>:<season>" -> true (notify once)

const NATIONALITIES: Array[String] = ["Aldoria", "England", "Spain", "Germany", "Italy", "France", "Brazil", "Portugal", "Netherlands", "Argentina"]


func _init(p_seed := 1) -> void:
	seed_value = p_seed


static func _rng(seed_value_: int, a: Variant, b: Variant) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed_value_, a, b])
	return r


# ------------------------------------------------------------------------------------------------- candidates

func _new_id() -> String:
	var id := "coach_%d" % next_id
	next_id += 1
	return id


func generate_candidate(department: String, rng: RandomNumberGenerator, week: int, level_bias: float = 0.0) -> Dictionary:
	var overall := clampi(roundi(rng.randfn(8.0 + level_bias, 3.4)), DevConfig.RATING_MIN, DevConfig.RATING_MAX)
	var age := rng.randi_range(32, 66)
	var experience := clampi((age - 30) / 2 + rng.randi_range(-3, 3), 0, 30)
	var youth_lean := rng.randi_range(-3, 3)                # some coaches are youth specialists, some better with professionals
	var specs: Array = (DevConfig.SPECIALISATIONS[department] as Dictionary).keys()
	var c := {
		"id": _new_id(), "name": YouthGenerator._name(rng, "Aldoria"), "age": age,
		"nationality": NATIONALITIES[rng.randi() % NATIONALITIES.size()], "department": department,
		"specialization": specs[rng.randi() % specs.size()], "overall": overall,
		"technical": _rate(overall + rng.randi_range(-3, 3)), "tactical": _rate(overall + rng.randi_range(-3, 3)),
		"youth": _rate(overall + youth_lean), "pro": _rate(overall - youth_lean),
		"experience": experience, "reputation": clampi(roundi(overall * 4.0 + experience * 0.8 + rng.randfn(0.0, 8.0)), 1, 100),
		"salary": 0, "years": 0, "signed_season": 0, "expiry_season": 0, "status": "available", "history": [],
		"listed_week": week, "pref_years": rng.randi_range(2, 4), "flex": snappedf(rng.randf_range(0.03, 0.10), 0.01),
	}
	c["salary"] = salary_demand(c)
	return c


static func _rate(v: int) -> int:
	return clampi(v, DevConfig.RATING_MIN, DevConfig.RATING_MAX)


## Weekly wage the coach asks for (rating and reputation).
static func salary_demand(c: Dictionary) -> int:
	var ov := float(c["overall"])
	var base := float(DevConfig.WAGE_BASE) + ov * ov * float(DevConfig.WAGE_QUAD)
	return int(snappedf(base * (1.0 + float(c["reputation"]) * DevConfig.WAGE_REPUTATION_SCALE), 10.0))


## Lowest weekly salary the candidate accepts for a contract of `years` (longer security makes him cheaper, a short deal dearer).
static func min_acceptable(c: Dictionary, years: int) -> int:
	var d := float(salary_demand(c)) * (1.0 - float(c.get("flex", 0.05)))
	var pref := int(c.get("pref_years", 3))
	if years > pref:
		d *= 0.97
	elif years < pref:
		d *= 1.05
	return int(ceilf(d))


## Fills the market so every department has MARKET_PER_DEPT candidates (idempotent).
func fill_market(week: int) -> void:
	for dept in DevConfig.DEPARTMENTS:
		var have := 0
		for c in market:
			if c["department"] == dept:
				have += 1
		var rng := _rng(seed_value, market_round, dept + str(next_id))
		while have < DevConfig.MARKET_PER_DEPT:
			market.append(generate_candidate(dept, rng, week))
			have += 1


## Calendar tick of the market: old candidates leave, new ones arrive every MARKET_REFRESH_WEEKS (absolute career week).
func refresh_market(week: int) -> void:
	if week - last_market_week < DevConfig.MARKET_REFRESH_WEEKS and not market.is_empty():
		return
	last_market_week = week
	market_round += 1
	market = market.filter(func(c: Dictionary) -> bool: return week - int(c["listed_week"]) <= DevConfig.MARKET_MAX_AGE_WEEKS)
	fill_market(week)


func candidate(id: String) -> Dictionary:
	for c in market:
		if c["id"] == id:
			return c
	return {}


## Filtered view of the market: department "" = all; `query` matches the name (case-insensitive); sorted by overall.
func browse(department: String = "", query: String = "") -> Array:
	var out: Array = []
	var q := query.strip_edges().to_lower()
	for c in market:
		if department != "" and c["department"] != department:
			continue
		if q != "" and not (str(c["name"]).to_lower().contains(q)):
			continue
		out.append(c)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["overall"]) > int(b["overall"]))
	return out


# ------------------------------------------------------------------------------------------------- staff

func coach(id: String) -> Dictionary:
	for c in coaches:
		if c["id"] == id:
			return c
	return {}


func in_department(department: String) -> Array:
	return coaches.filter(func(c: Dictionary) -> bool: return c["department"] == department)


func vacancies() -> Array[String]:
	var out: Array[String] = []
	for d in DevConfig.DEPARTMENTS:
		if in_department(d).is_empty():
			out.append(d)
	return out


func weekly_wages() -> int:
	var w := 0
	for c in coaches:
		w += int(c["salary"])
	return w


static func years_left(c: Dictionary, season: int) -> int:
	return int(c["expiry_season"]) - season + 1


func _log(kind: String, c: Dictionary, week: int) -> void:
	activity.append({"week": week, "kind": kind, "coach_id": c["id"], "name": c["name"], "department": c["department"]})
	while activity.size() > DevConfig.ACTIVITY_MAX:
		activity.pop_front()


## Negotiation round without committing: {accepted, reply ("DEV_NEG_ACCEPT" / "DEV_NEG_COUNTER" / "DEV_NEG_REFUSE"), counter_salary, min_salary}.
func negotiate(id: String, salary: int, years: int) -> Dictionary:
	var c := candidate(id)
	if c.is_empty():
		c = coach(id)
	if c.is_empty():
		return {"accepted": false, "reply": "DEV_NEG_REFUSE", "counter_salary": 0, "min_salary": 0}
	if years < DevConfig.CONTRACT_MIN_YEARS or years > DevConfig.CONTRACT_MAX_YEARS:
		return {"accepted": false, "reply": "DEV_NEG_REFUSE", "counter_salary": salary_demand(c), "min_salary": min_acceptable(c, clampi(years, 1, 5))}
	var lowest := min_acceptable(c, years)
	if salary >= lowest:
		return {"accepted": true, "reply": "DEV_NEG_ACCEPT", "counter_salary": salary, "min_salary": lowest}
	# offers below 70 % of his price are refused outright, others get a counter-offer
	var reply := "DEV_NEG_REFUSE" if float(salary) < 0.7 * float(lowest) else "DEV_NEG_COUNTER"
	return {"accepted": false, "reply": reply, "counter_salary": lowest, "min_salary": lowest}


## Hires a market candidate. Returns {ok, error (translation key), coach}. `external_wages` = other staff wages counted against the
## club's wage budget; `ledger` may be null (tests).
func hire(id: String, salary: int, years: int, training_level: int, ledger: FinanceLedger, week: int, season: int, external_wages: int = 0) -> Dictionary:
	var c := candidate(id)
	if c.is_empty():
		return {"ok": false, "error": "DEV_ERR_UNKNOWN_CANDIDATE"}
	var dept := str(c["department"])
	if in_department(dept).size() >= DevConfig.dept_cap(training_level):
		return {"ok": false, "error": "DEV_ERR_DEPT_FULL"}
	if coaches.size() >= DevConfig.total_slots(training_level):
		return {"ok": false, "error": "DEV_ERR_STAFF_FULL"}
	var neg := negotiate(id, salary, years)
	if not bool(neg["accepted"]):
		return {"ok": false, "error": str(neg["reply"]), "counter_salary": neg["counter_salary"]}
	if ledger != null and ledger.wage_budget > 0 and weekly_wages() + external_wages + salary > ledger.wage_budget:
		return {"ok": false, "error": "DEV_ERR_WAGE_BUDGET"}
	var bonus := salary * DevConfig.SIGNING_WEEKS
	if ledger != null:
		if ledger.balance < bonus:                      # salary payments are "unavoidable" in the ledger, a signing bonus is not
			return {"ok": false, "error": "DEV_ERR_NO_MONEY"}
		ledger.record("salary", -bonus, "Staff signing bonus", week, "FIN_STAFF_COMPENSATION")
	market.erase(c)
	c["salary"] = salary
	c["years"] = years
	c["signed_season"] = season
	c["expiry_season"] = season + years - 1
	c["status"] = "employed"
	(c["history"] as Array).append({"season": season, "event": "hired", "note": "%d years" % years})
	c.erase("listed_week")
	c.erase("pref_years")
	c.erase("flex")
	coaches.append(c)
	_log("hired", c, week)
	return {"ok": true, "error": "", "coach": c}


func reject(id: String, week: int) -> bool:
	var c := candidate(id)
	if c.is_empty():
		return false
	market.erase(c)
	_log("rejected", c, week)
	return true


## Renews a coach: the same negotiation rules (his flexibility and preferred length are re-derived from his id).
func renew(id: String, salary: int, years: int, ledger: FinanceLedger, week: int, season: int, external_wages: int = 0) -> Dictionary:
	var c := coach(id)
	if c.is_empty():
		return {"ok": false, "error": "DEV_ERR_UNKNOWN_COACH"}
	var probe := c.duplicate()
	var r := _rng(seed_value, id, "renew")
	probe["flex"] = snappedf(r.randf_range(0.03, 0.10), 0.01)
	probe["pref_years"] = r.randi_range(2, 4)
	var lowest := min_acceptable(probe, years)
	if years < DevConfig.CONTRACT_MIN_YEARS or years > DevConfig.CONTRACT_MAX_YEARS:
		return {"ok": false, "error": "DEV_NEG_REFUSE"}
	if salary < lowest:
		return {"ok": false, "error": "DEV_NEG_REFUSE" if float(salary) < 0.7 * float(lowest) else "DEV_NEG_COUNTER", "counter_salary": lowest}
	if ledger != null and ledger.wage_budget > 0 and weekly_wages() - int(c["salary"]) + external_wages + salary > ledger.wage_budget:
		return {"ok": false, "error": "DEV_ERR_WAGE_BUDGET"}
	c["salary"] = salary
	c["years"] = years
	c["expiry_season"] = maxi(int(c["expiry_season"]), season - 1) + years      # the new years follow the current contract
	(c["history"] as Array).append({"season": season, "event": "renewed", "note": "%d years" % years})
	_log("renewed", c, week)
	return {"ok": true, "error": "", "coach": c}


static func dismiss_cost(c: Dictionary, season: int) -> int:
	var weeks := clampi(maxi(years_left(c, season) - 1, 0) * DevConfig.DISMISS_WEEKS_PER_YEAR + DevConfig.DISMISS_WEEKS_MIN, DevConfig.DISMISS_WEEKS_MIN, DevConfig.DISMISS_WEEKS_MAX)
	return int(c["salary"]) * weeks


func dismiss(id: String, ledger: FinanceLedger, week: int, season: int) -> String:
	var c := coach(id)
	if c.is_empty():
		return "DEV_ERR_UNKNOWN_COACH"
	var cost := dismiss_cost(c, season)
	if ledger != null:
		ledger.record("salary", -cost, "Staff compensation", week, "FIN_STAFF_COMPENSATION")
	(c["history"] as Array).append({"season": season, "event": "dismissed", "note": ""})
	coaches.erase(c)
	_log("dismissed", c, week)
	return ""


# ------------------------------------------------------------------------------------------------- calendar

## Weekly tick: wages, market, contract warnings. Returns inbox events [{key, args, id}].
func weekly(ledger: FinanceLedger, week: int, season: int) -> Array:
	var events: Array = []
	var w := weekly_wages()
	if w > 0 and ledger != null:
		ledger.record("salary", -w, "Staff wages", week, "FIN_STAFF_WAGES")
	refresh_market(week)
	for c in coaches:
		if years_left(c, season) <= DevConfig.EXPIRY_WARNING_SEASONS:
			var key := "expiry:%s:%d" % [c["id"], season]
			if not warned.has(key):
				warned[key] = true
				events.append({"key": "INBOX_COACH_EXPIRING", "args": [c["name"], Loc.t("DEV_DEPT_" + str(c["department"]).to_upper())], "id": key})
	for d in vacancies():
		var vkey := "vacancy:%s:%d" % [d, season]
		if not warned.has(vkey) and initialized:
			warned[vkey] = true
			events.append({"key": "INBOX_COACH_VACANCY", "args": [Loc.t("DEV_DEPT_" + d.to_upper())], "id": vkey})
	return events


## Season end: contracts run out (the coach leaves, unless renewed before), every coach ages / gains experience and his ratings move
## at his own rate. `success` 0..1 = how well the club did (league position). Returns inbox events.
func season_end(season: int, success: float, week: int = 0) -> Array:
	var events: Array = []
	for c in coaches.duplicate():
		c["age"] = int(c["age"]) + 1
		c["experience"] = int(c["experience"]) + 1
		_progress_coach(c, season, success)
		if int(c["expiry_season"]) <= season:
			(c["history"] as Array).append({"season": season, "event": "left", "note": "contract expired"})
			coaches.erase(c)
			_log("expired", c, week)
			events.append({"key": "INBOX_COACH_LEFT", "args": [c["name"], Loc.t("DEV_DEPT_" + str(c["department"]).to_upper())], "id": "left:%s:%d" % [c["id"], season]})
	warned.clear()
	return events


## Every rating moves by its own roll: young coaches improve more, successful clubs raise reputation, old coaches may decline.
func _progress_coach(c: Dictionary, season: int, success: float) -> void:
	var r := _rng(seed_value, str(c["id"]), season)
	var age := int(c["age"])
	var age_f := 1.2 if age < 45 else (1.0 if age < 55 else (0.6 if age < 62 else 0.3))
	var p_up := 0.30 * age_f * (0.7 + 0.6 * clampf(success, 0.0, 1.0))
	var p_down := 0.04 if age < 60 else 0.18
	for k in ["overall", "technical", "tactical", "youth", "pro"]:
		var v := int(c[k])
		var roll := r.randf()
		if roll < p_up * (1.0 - float(v) / 24.0) * (1.4 if k == "youth" and int(c["youth"]) >= int(c["pro"]) else 1.0):
			v += 1
		elif roll > 1.0 - p_down:
			v -= 1
		c[k] = _rate(v)
	var rep := int(c["reputation"]) + roundi((clampf(success, 0.0, 1.0) - 0.4) * 8.0 + r.randfn(0.0, 1.5))
	c["reputation"] = clampi(rep, 1, 100)


# ------------------------------------------------------------------------------------------------- effects

## Effective rating (1..20) of a coach for players of `kind` ("youth" or "pro").
static func effective_rating(c: Dictionary, kind: String) -> float:
	var dev := float(c["youth"]) if kind == "youth" else float(c["pro"])
	return float(c["overall"]) * DevConfig.W_OVERALL + float(c["technical"]) * DevConfig.W_TECHNICAL \
			+ float(c["tactical"]) * DevConfig.W_TACTICAL + dev * DevConfig.W_DEVELOPMENT


static func rating_to_mult(rating: float) -> float:
	var t := clampf((rating - float(DevConfig.RATING_MIN)) / float(DevConfig.RATING_MAX - DevConfig.RATING_MIN), 0.0, 1.0)
	return lerpf(DevConfig.MIN_COACH_MULT, DevConfig.MAX_COACH_MULT, t)


## Training multiplier of a department for `attr` (optional) and player group `kind`.
## Vacant: VACANT_MULT. Otherwise the best coach sets the level, further coaches add a little, a matching specialisation adds a little.
func dept_multiplier(department: String, kind: String = "pro", attr: String = "") -> float:
	var list := in_department(department)
	if list.is_empty():
		return DevConfig.VACANT_MULT
	var ratings: Array = []
	var spec := 0.0
	for c in list:
		ratings.append(effective_rating(c, kind))
		var sp: Dictionary = DevConfig.SPECIALISATIONS[department]
		if attr != "" and sp.get(str(c["specialization"]), "") == attr:
			spec = DevConfig.SPECIALISATION_BONUS
	ratings.sort()
	ratings.reverse()
	var m := rating_to_mult(float(ratings[0]))
	for i in range(1, ratings.size()):
		m += DevConfig.SECOND_COACH_BONUS * clampf(float(ratings[i]) / float(DevConfig.RATING_MAX), 0.0, 1.0)
	return minf(m + spec, DevConfig.DEPT_MULT_CAP)


## Multiplier for training `attr`: the leading department plus a share of the tactical coach's level.
func attribute_multiplier(attr: String, kind: String = "pro") -> float:
	var lead: String = DevConfig.ATTRIBUTE_LEAD.get(attr, "tactical")
	var m := dept_multiplier(lead, kind, attr)
	var tac := dept_multiplier("tactical", kind, "")
	return m * (1.0 + (tac - 1.0) * DevConfig.TACTICAL_SHARE)


## Average multiplier across the attributes a plain academy week trains (used for the existing academy dev_bonus).
func academy_factor() -> float:
	var s := 0.0
	for a in PlayerData.ATTRIBUTES:
		s += attribute_multiplier(a, "youth")
	return s / float(PlayerData.ATTRIBUTES.size())


# ------------------------------------------------------------------------------------------------- starter staff / persistence

## One coach per department for a club that has none (new career or an old save), quality by club reputation (0..100).
func seed_starter_staff(club_reputation: int, season: int) -> void:
	if initialized:
		return
	initialized = true
	var bias := clampf((float(club_reputation) - 50.0) / 12.0, -3.0, 4.0) - 1.5   # starter coaches are modest
	for dept in DevConfig.DEPARTMENTS:
		if not in_department(dept).is_empty():
			continue
		var rng := _rng(seed_value, "starter", dept)
		var c := generate_candidate(dept, rng, 0, bias)
		c["overall"] = clampi(int(c["overall"]), 3, 12)
		c["salary"] = salary_demand(c)
		c["years"] = 2
		c["signed_season"] = season
		c["expiry_season"] = season + 1
		c["status"] = "employed"
		(c["history"] as Array).append({"season": season, "event": "club staff", "note": ""})
		for k in ["listed_week", "pref_years", "flex"]:
			c.erase(k)
		coaches.append(c)
	fill_market(0)


func to_dict() -> Dictionary:
	return {"coaches": coaches.duplicate(true), "market": market.duplicate(true), "next_id": next_id, "market_round": market_round,
			"last_market_week": last_market_week, "seed": seed_value, "initialized": initialized, "activity": activity.duplicate(true),
			"warned": warned.duplicate()}


static func from_dict(d: Dictionary) -> CoachingStaff:
	var s := CoachingStaff.new(int(d.get("seed", 1)))
	s.next_id = maxi(int(d.get("next_id", 1)), 1)
	s.market_round = int(d.get("market_round", 0))
	s.last_market_week = int(d.get("last_market_week", -1000))
	s.initialized = bool(d.get("initialized", false))
	s.warned = (d.get("warned", {}) as Dictionary).duplicate()
	var seen := {}
	for src in [[d.get("coaches", []), true], [d.get("market", []), false]]:
		for raw in (src[0] as Array):
			if typeof(raw) != TYPE_DICTIONARY:
				continue
			var c := _sanitize(raw as Dictionary, bool(src[1]))
			if c.is_empty() or seen.has(c["id"]):
				continue
			seen[c["id"]] = true
			if bool(src[1]):
				s.coaches.append(c)
			else:
				s.market.append(c)
			var n := str(c["id"]).trim_prefix("coach_")
			if n.is_valid_int():
				s.next_id = maxi(s.next_id, int(n) + 1)
	for a in (d.get("activity", []) as Array):
		if typeof(a) == TYPE_DICTIONARY:
			s.activity.append((a as Dictionary).duplicate())
	return s


## Validated coach record from a save (JSON gives floats; ratings are clamped, unknown departments are dropped).
static func _sanitize(raw: Dictionary, employed: bool) -> Dictionary:
	var dept := str(raw.get("department", ""))
	if not (dept in DevConfig.DEPARTMENTS) or str(raw.get("id", "")) == "":
		return {}
	var c := raw.duplicate(true)
	for k in ["overall", "technical", "tactical", "youth", "pro"]:
		c[k] = _rate(int(c.get(k, 8)))
	for k in ["age", "experience", "reputation", "salary", "years", "signed_season", "expiry_season", "listed_week", "pref_years"]:
		if c.has(k):
			c[k] = int(c[k])
	c["age"] = clampi(int(c.get("age", 45)), 25, 80)
	c["reputation"] = clampi(int(c.get("reputation", 30)), 1, 100)
	c["salary"] = maxi(int(c.get("salary", 0)), 0)
	c["status"] = "employed" if employed else "available"
	var specs: Dictionary = DevConfig.SPECIALISATIONS[dept]
	if not specs.has(str(c.get("specialization", ""))):
		c["specialization"] = specs.keys()[0]
	if typeof(c.get("history")) != TYPE_ARRAY:
		c["history"] = []
	if not employed:
		c["listed_week"] = int(c.get("listed_week", 0))
		c["pref_years"] = int(c.get("pref_years", 3))
		c["flex"] = float(c.get("flex", 0.05))
	return c
