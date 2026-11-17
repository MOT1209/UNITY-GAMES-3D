class_name YouthDevelopment
extends RefCounted

## Youth development (Nov 2026), all state in `Academy.dev`:
##   * staff        - academy director (intake, golden generations) and youth coach (growth, knowledge); hire market
##   * knowledge    - how well the club knows each prospect's potential (0..1): shown as a range that narrows
##   * mentors      - prospect -> first-team player: extra growth, a chance to pick up a trait at season end
##   * loans        - prospects loaned to lower-league clubs for N weeks: appearances, ratings, extra growth
##   * league       - weekly U19 league (simulated, 10 teams): table, results, player ratings, growth for starters
##   * cup          - yearly youth cup (4 rounds) with prize money for the academy budget
##   * progress     - overall rating every 4 weeks per prospect (development chart)
## Deterministic: every random draw is seeded from the academy seed and the absolute career week.

const LEAGUE_SIZE := 10
const LEAGUE_LINEUP := 11
const CUP_WEEKS: Array[int] = [8, 16, 24, 32]
const CUP_PRIZE_ROUND := 25_000
const CUP_PRIZE_WIN := 150_000
const LOAN_WEEKS := 12
const MAX_LOANS := 4
const STAFF_ROLES: Array[String] = ["director", "coach"]
const STAFF_MARKET_SIZE := 3
const STAFF_HIRE_WEEKS := 20
const MIN_LOAN_AGE := 17


# ------------------------------------------------------------------------------------------------- state

static func state(ac: Academy) -> Dictionary:
	var d := ac.dev
	if not d.has("staff"):
		d["staff"] = {"director": {"name": "", "quality": 0.5, "wage": 2000},
				"coach": {"name": "", "quality": 0.5, "wage": 1500}}
	for k in ["knowledge", "mentors", "loans", "progress", "ratings"]:
		if not d.has(k):
			d[k] = {}
	if not d.has("league"):
		d["league"] = {}
	if not d.has("results"):
		d["results"] = []
	if not d.has("cup"):
		d["cup"] = {"round": 0, "out": false, "won": false}
	if not d.has("market_round"):
		d["market_round"] = 0
	if not d.has("last_week"):
		d["last_week"] = -1
	return d


static func staff_quality(ac: Academy, role: String) -> float:
	return float(((state(ac)["staff"] as Dictionary).get(role, {}) as Dictionary).get("quality", 0.5))


static func _rng(ac: Academy, week: int, salt: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([ac.academy_seed, week, salt])
	return r


# ------------------------------------------------------------------------------------------------- potential

## Potential range shown for a prospect: true potential +- a margin that shrinks with knowledge.
static func potential_range(ac: Academy, p: PlayerData) -> Vector2i:
	var k := float((state(ac)["knowledge"] as Dictionary).get(p.id, 0.0))
	var margin := roundi(lerpf(10.0, 0.0, clampf(k, 0.0, 1.0)))
	# the range is not centred on the truth (otherwise its middle would give it away): shift by a stable offset
	var off := (hash(p.id) % 7) - 3
	var lo := clampi(p.potential - margin + roundi(off * (margin / 10.0)), p.get_overall(), 99)
	var hi := clampi(lo + 2 * margin, lo, 99)
	return Vector2i(lo, hi)


static func potential_text(ac: Academy, p: PlayerData) -> String:
	var r := potential_range(ac, p)
	return str(r.x) if r.x == r.y else "%d-%d" % [r.x, r.y]


# ------------------------------------------------------------------------------------------------- weekly

## Runs the youth weeks owed up to `absolute_week` (idempotent). Returns events for the inbox:
## [{key, args}] (cup results, returning loans).
static func sync(db: Node, ac: Academy, squad_ids: Array, absolute_week: int) -> Array:
	var d := state(ac)
	var out: Array = []
	if int(d["last_week"]) < 0:
		d["last_week"] = absolute_week - 1
	var owed := mini(absolute_week - int(d["last_week"]), 4)
	for i in range(owed, 0, -1):
		out.append_array(_week(db, ac, squad_ids, absolute_week - i + 1))
	d["last_week"] = maxi(int(d["last_week"]), absolute_week)
	return out


static func _week(db: Node, ac: Academy, squad_ids: Array, w: int) -> Array:
	var d := state(ac)
	var rng := _rng(ac, w, "week")
	var events: Array = []
	var coach := staff_quality(ac, "coach")
	var season_week := posmod(w - 1, 46) + 1
	# knowledge grows for everybody; faster with a good coach
	var know: Dictionary = d["knowledge"]
	for pid in ac.roster_ids:
		know[pid] = minf(float(know.get(pid, 0.0)) + 0.01 + coach * 0.03, 1.0)
	# league match (weeks 1..36)
	var played: Array[String] = []
	if season_week <= 36:
		played = _league_round(db, ac, rng, w)
	for pid in played:
		_grow(db, ac, pid, rng, 0.6 + coach * 0.4, w)
		know[pid] = minf(float(know.get(pid, 0.0)) + 0.02, 1.0)
	# mentors
	var mentors: Dictionary = d["mentors"]
	for pid in mentors.keys():
		if not (pid in ac.roster_ids) or not (str(mentors[pid]) in squad_ids):
			mentors.erase(pid)
			continue
		_grow(db, ac, pid, rng, 0.5, w)
	# loans
	var loans: Dictionary = d["loans"]
	for pid in loans.keys():
		var l: Dictionary = loans[pid]
		if not (pid in ac.roster_ids):
			loans.erase(pid)
			continue
		if rng.randf() < 0.65:
			l["apps"] = int(l["apps"]) + 1
			l["rating_sum"] = float(l["rating_sum"]) + snappedf(rng.randf_range(5.5, 8.3), 0.1)
			_grow(db, ac, pid, rng, 0.8, w)
		l["weeks_left"] = int(l["weeks_left"]) - 1
		if int(l["weeks_left"]) <= 0:
			var p: PlayerData = db.get_player(pid)
			var avg := float(l["rating_sum"]) / maxf(float(l["apps"]), 1.0)
			events.append({"key": "INBOX_YOUTH_LOAN_BACK", "args": [p.display_name if p != null else pid, int(l["apps"]), "%.1f" % avg]})
			loans.erase(pid)
	# cup
	if season_week in CUP_WEEKS:
		var e := _cup_round(ac, rng, CUP_WEEKS.find(season_week))
		if not e.is_empty():
			events.append(e)
	# rating chart
	if season_week % 4 == 0:
		var prog: Dictionary = d["progress"]
		for pid in ac.roster_ids:
			var p: PlayerData = db.get_player(pid)
			if p == null:
				continue
			var arr: Array = prog.get(pid, [])
			arr.append(p.get_overall())
			if arr.size() > 30:
				arr.pop_front()
			prog[pid] = arr
	return events


static func _grow(db: Node, ac: Academy, pid: String, rng: RandomNumberGenerator, bonus: float, w: int) -> void:
	var p: PlayerData = db.get_player(pid)
	if p == null:
		return
	var attr: String = PlayerData.ATTRIBUTES[rng.randi() % PlayerData.ATTRIBUTES.size()]
	if attr == "goalkeeping" and p.position != PlayerData.Position.GK:
		attr = "physical" if "physical" in PlayerData.ATTRIBUTES else attr
	ProgressionModel.train_week(p, attr, ac.quality, 1.0, w, bonus)


# ------------------------------------------------------------------------------------------------- league

static func available(db: Node, ac: Academy) -> Array[PlayerData]:
	var loans: Dictionary = state(ac)["loans"]
	var out: Array[PlayerData] = []
	for pid in ac.roster_ids:
		var p: PlayerData = db.get_player(pid)
		if p != null and not loans.has(pid):
			out.append(p)
	out.sort_custom(func(a: PlayerData, b: PlayerData) -> bool: return a.get_overall() > b.get_overall())
	return out


static func team_strength(db: Node, ac: Academy) -> float:
	var ps := available(db, ac)
	if ps.is_empty():
		return 30.0
	var n := mini(ps.size(), LEAGUE_LINEUP)
	var s := 0.0
	for i in n:
		s += ps[i].get_overall()
	return s / n - (LEAGUE_LINEUP - n) * 2.0


## The league's 10 sides: the academy (id "own") and 9 opponents named after other clubs (fixed per academy).
static func league_teams(db: Node, ac: Academy) -> Dictionary:
	var d := state(ac)
	var lg: Dictionary = d["league"]
	if lg.has("teams"):
		return lg["teams"]
	var teams := {"own": {"name": "", "strength": 0.0}}
	var clubs: Array = db.list_teams(TeamData.Category.CLUB)
	var r := _rng(ac, 0, "league")
	var tries := 0
	while teams.size() < LEAGUE_SIZE and tries < 200 and not clubs.is_empty():
		tries += 1
		var t: TeamData = clubs[r.randi() % clubs.size()]
		if t.id == ac.team_id or teams.has(t.id):
			continue
		teams[t.id] = {"name": t.display_name, "strength": snappedf(r.randf_range(34.0, 52.0), 0.1)}
	lg["teams"] = teams
	return teams


static func table(db: Node, ac: Academy) -> Array:
	var lg: Dictionary = state(ac)["league"]
	var rows: Dictionary = lg.get("table", {})
	var out: Array = []
	for id in league_teams(db, ac):
		var r: Array = rows.get(id, [0, 0, 0, 0, 0, 0])
		out.append({"id": id, "p": r[0], "w": r[1], "d": r[2], "l": r[3], "gf": r[4], "ga": r[5], "pts": int(r[1]) * 3 + int(r[2])})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["pts"] != b["pts"]:
			return a["pts"] > b["pts"]
		return int(a["gf"]) - int(a["ga"]) > int(b["gf"]) - int(b["ga"]))
	return out


static func _goals(rng: RandomNumberGenerator, diff: float) -> int:
	var lam := clampf(1.3 + diff * 0.06, 0.2, 4.0)
	var l := exp(-lam)
	var k := 0
	var p := 1.0
	while true:
		p *= rng.randf()
		if p <= l:
			return k
		k += 1
	return k


static func _league_round(db: Node, ac: Academy, rng: RandomNumberGenerator, w: int) -> Array[String]:
	var d := state(ac)
	var lg: Dictionary = d["league"]
	var teams := league_teams(db, ac)
	var ids: Array = teams.keys()
	var rows: Dictionary = lg.get("table", {})
	var own_s := team_strength(db, ac)
	# round-robin pairing by rotation
	var n := ids.size()
	var rot := posmod(w, n - 1)
	var order: Array = [ids[0]]
	for i in range(1, n):
		order.append(ids[1 + posmod(i - 1 + rot, n - 1)])
	var played: Array[String] = []
	for i in n / 2:
		var a: String = order[i]
		var b: String = order[n - 1 - i]
		var sa := own_s if a == "own" else float(teams[a]["strength"])
		var sb := own_s if b == "own" else float(teams[b]["strength"])
		var ga := _goals(rng, sa - sb)
		var gb := _goals(rng, sb - sa)
		for pair in [[a, ga, gb], [b, gb, ga]]:
			var r: Array = rows.get(pair[0], [0, 0, 0, 0, 0, 0])
			r[0] += 1
			r[1] += 1 if pair[1] > pair[2] else 0
			r[2] += 1 if pair[1] == pair[2] else 0
			r[3] += 1 if pair[1] < pair[2] else 0
			r[4] += pair[1]
			r[5] += pair[2]
			rows[pair[0]] = r
		if a == "own" or b == "own":
			var opp := b if a == "own" else a
			var mine := ga if a == "own" else gb
			var theirs := gb if a == "own" else ga
			var res: Array = d["results"]
			res.append({"week": w, "opp": str(teams[opp]["name"]), "for": mine, "against": theirs})
			if res.size() > 10:
				res.pop_front()
			var ratings: Dictionary = d["ratings"]
			var lineup := available(db, ac)
			for k in mini(lineup.size(), LEAGUE_LINEUP):
				var pid := lineup[k].id
				var rt := snappedf(clampf(6.4 + (mine - theirs) * 0.3 + rng.randfn(0.0, 0.6), 4.0, 10.0), 0.1)
				var arr: Array = ratings.get(pid, [])
				arr.append(rt)
				if arr.size() > 10:
					arr.pop_front()
				ratings[pid] = arr
				played.append(pid)
	lg["table"] = rows
	return played


# ------------------------------------------------------------------------------------------------- cup

static func _cup_round(ac: Academy, rng: RandomNumberGenerator, round_index: int) -> Dictionary:
	var cup: Dictionary = state(ac)["cup"]
	if bool(cup["out"]) or bool(cup["won"]) or int(cup["round"]) != round_index:
		return {}
	var p_win := clampf(0.45 + (ac.quality - 0.5) * 0.4 + (staff_quality(ac, "coach") - 0.5) * 0.3, 0.15, 0.85)
	if rng.randf() < p_win:
		cup["round"] = round_index + 1
		var prize := CUP_PRIZE_WIN if round_index == CUP_WEEKS.size() - 1 else CUP_PRIZE_ROUND
		ac.budget += prize
		if round_index == CUP_WEEKS.size() - 1:
			cup["won"] = true
			return {"key": "INBOX_YOUTH_CUP_WON", "args": [prize]}
		return {"key": "INBOX_YOUTH_CUP_WIN", "args": [round_index + 1, prize]}
	cup["out"] = true
	return {"key": "INBOX_YOUTH_CUP_OUT", "args": [round_index + 1]}


# ------------------------------------------------------------------------------------------------- loans / mentors

static func loan_out(db: Node, ac: Academy, pid: String) -> String:
	var loans: Dictionary = state(ac)["loans"]
	var p: PlayerData = db.get_player(pid)
	if p == null or not (pid in ac.roster_ids):
		return "unknown prospect"
	if p.age < MIN_LOAN_AGE:
		return "prospects can be loaned from age %d" % MIN_LOAN_AGE
	if loans.has(pid):
		return "already on loan"
	if loans.size() >= MAX_LOANS:
		return "at most %d youth loans" % MAX_LOANS
	var clubs: Array = db.list_teams(TeamData.Category.CLUB)
	var r := _rng(ac, int(state(ac)["last_week"]), pid)
	var club: TeamData = clubs[r.randi() % clubs.size()] if not clubs.is_empty() else null
	loans[pid] = {"club": club.display_name if club != null else "?", "weeks_left": LOAN_WEEKS, "apps": 0, "rating_sum": 0.0}
	(state(ac)["mentors"] as Dictionary).erase(pid)
	return ""


static func recall(ac: Academy, pid: String) -> void:
	(state(ac)["loans"] as Dictionary).erase(pid)


static func set_mentor(ac: Academy, pid: String, senior_id: String) -> void:
	var m: Dictionary = state(ac)["mentors"]
	if senior_id == "":
		m.erase(pid)
	else:
		m[pid] = senior_id


# ------------------------------------------------------------------------------------------------- season end

## Season end: mentors pass on a trait (30 %), a golden generation may appear in this intake, the league and cup
## restart. Returns inbox events.
static func season_end(db: Node, ac: Academy, intake: Array, season: int) -> Array:
	var d := state(ac)
	var rng := _rng(ac, season * 1000, "season")
	var events: Array = []
	var mentors: Dictionary = d["mentors"]
	for pid in mentors:
		var p: PlayerData = db.get_player(pid)
		var s: PlayerData = db.get_player(str(mentors[pid]))
		if p == null or s == null or s.traits.is_empty() or rng.randf() >= 0.3:
			continue
		var t = s.traits[rng.randi() % s.traits.size()]
		if not (t in p.traits):
			p.traits.append(t)
			events.append({"key": "INBOX_YOUTH_MENTOR_TRAIT", "args": [p.display_name, Loc.t("TRAIT_" + str(t).to_upper().replace(" ", "_")) if Loc.has_key("TRAIT_" + str(t).to_upper().replace(" ", "_")) else str(t), s.display_name]})
	var director := staff_quality(ac, "director")
	if not intake.is_empty() and rng.randf() < 0.04 + director * 0.12:
		var star: PlayerData = intake[rng.randi() % intake.size()]
		star.potential = mini(star.potential + rng.randi_range(10, 16), 95)
		events.append({"key": "INBOX_YOUTH_GOLDEN", "args": [star.display_name]})
	(d["league"] as Dictionary)["table"] = {}
	d["results"] = []
	d["cup"] = {"round": 0, "out": false, "won": false}
	return events


# ------------------------------------------------------------------------------------------------- staff market

static func staff_candidates(ac: Academy, role: String) -> Array:
	var r := _rng(ac, int(state(ac)["market_round"]), "staff_" + role)
	var out: Array = []
	for i in STAFF_MARKET_SIZE:
		var q := snappedf(r.randf_range(0.35, 0.95), 0.01)
		out.append({"name": YouthGenerator._name(r, "Aldoria"), "quality": q, "wage": int(snappedf(800.0 + q * q * 4200.0, 50.0))})
	return out


static func hire_fee(c: Dictionary) -> int:
	return int(c["wage"]) * STAFF_HIRE_WEEKS


static func hire_staff(ac: Academy, role: String, index: int) -> String:
	var list := staff_candidates(ac, role)
	if index < 0 or index >= list.size():
		return "unknown candidate"
	var fee := hire_fee(list[index])
	if fee > ac.budget:
		return "insufficient academy budget (%d needed, %d available)" % [fee, ac.budget]
	ac.budget -= fee
	(state(ac)["staff"] as Dictionary)[role] = (list[index] as Dictionary).duplicate()
	state(ac)["market_round"] = int(state(ac)["market_round"]) + 1
	return ""


## Growth factor of the youth coach for academy training (0.9 .. 1.2).
static func coach_factor(ac: Academy) -> float:
	return 0.9 + staff_quality(ac, "coach") * 0.3


## Extra prospect in the intake for a strong director.
static func intake_bonus(ac: Academy) -> int:
	return 1 if staff_quality(ac, "director") >= 0.7 else 0
