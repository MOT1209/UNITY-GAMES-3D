class_name PlayerLifecycle
extends RefCounted

## What happens to every player between two seasons (called by `CareerState.end_season`):
##   1. free agents age (squad players were aged by the season rollover already);
##   2. retirement — chance rises from RETIRE_FROM, certain at RETIRE_CERTAIN (keepers later);
##      retired players leave every squad, get status RETIRED and never age again;
##   3. development outside the academy — young players grow toward their potential, players
##      past 30 decline (the user's academy still develops through `TrainingSystem`);
##   4. AI squad maintenance — every club except the user's keeps SQUAD_MIN..SQUAD_MAX players
##      with enough keepers / defenders / midfielders / forwards, first by signing suitable free
##      agents, otherwise by bringing in a young player at about the club's level.
## Everything is deterministic (seeded by season and ids), so a loaded career replays identically.

const RETIRE_FROM := 33
const RETIRE_CERTAIN := 40
const RETIRE_CERTAIN_GK := 42
const SQUAD_MIN := 22
const SQUAD_MAX := 28
const FREE_AGENT_MAX_AGE := 33
## A club whose XI is more than QUALITY_GAP below its base level signs up to QUALITY_SIGNINGS ready players.
const QUALITY_GAP := 2
const QUALITY_SIGNINGS := 3
## Minimum players per line for AI clubs.
const LINE_MIN := {"GK": 2, "DEF": 6, "MID": 6, "FWD": 4}
const LINES := {
	PlayerData.Position.GK: "GK",
	PlayerData.Position.CB: "DEF", PlayerData.Position.LB: "DEF", PlayerData.Position.RB: "DEF",
	PlayerData.Position.CDM: "MID", PlayerData.Position.CM: "MID", PlayerData.Position.CAM: "MID",
	PlayerData.Position.LM: "MID", PlayerData.Position.RM: "MID",
	PlayerData.Position.LW: "FWD", PlayerData.Position.RW: "FWD", PlayerData.Position.ST: "FWD",
}
## Position a generated player gets when a line is short (cycled for variety).
const LINE_POSITIONS := {
	"GK": [PlayerData.Position.GK],
	"DEF": [PlayerData.Position.CB, PlayerData.Position.LB, PlayerData.Position.CB, PlayerData.Position.RB],
	"MID": [PlayerData.Position.CM, PlayerData.Position.CDM, PlayerData.Position.CAM, PlayerData.Position.CM],
	"FWD": [PlayerData.Position.ST, PlayerData.Position.LW, PlayerData.Position.RW],
}


## AI contract decision: keep players who are young or still good enough for the club.
static func ai_renews(p: PlayerData, club_level: int) -> bool:
	return p.age <= 29 or (p.age <= 32 and p.get_overall() >= club_level - 4)


static func renewal_years(p: PlayerData) -> int:
	return 1 if p.age >= 30 else (3 if p.age <= 24 else 2)


static func line_of(p: PlayerData) -> String:
	return LINES.get(p.position, "MID")


static func retire_chance(age: int, goalkeeper: bool) -> float:
	var certain := RETIRE_CERTAIN_GK if goalkeeper else RETIRE_CERTAIN
	var start := RETIRE_FROM + (2 if goalkeeper else 0)
	if age >= certain:
		return 1.0
	if age < start:
		return 0.0
	return pow(float(age - start + 1) / float(certain - start + 1), 1.6)


## Runs the whole between-seasons step. `season` = the season that just ended.
## Returns {"retired": [ids], "retired_mine": [ids], "signed": {team: [ids]}, "generated": {team: [ids]}}.
static func run(career: CareerState, season: int, squads: Dictionary = {}, aged: Dictionary = {}) -> Dictionary:
	var db: Node = career.db
	var out := {"retired": [], "retired_mine": [], "signed": {}, "generated": {}}
	var players: Array = db.players.values()
	players.sort_custom(func(a: PlayerData, b: PlayerData) -> bool: return a.id < b.id)
	for p: PlayerData in players:
		if p.status == PlayerData.Status.RETIRED or p.status == PlayerData.Status.YOUTH:
			continue
		if p.team_id == "" and not aged.has(p.id):
			p.age += 1                         # squad players (incl. those just released) were aged by the rollover
		var rng := _rng(season, p.id, "retire")
		if rng.randf() < retire_chance(p.age, p.position == PlayerData.Position.GK):
			if p.team_id == career.club_id and p.team_id != "":
				out["retired_mine"].append(p.id)
			retire(db, p, squads)
			out["retired"].append(p.id)
			continue
		develop(p, _rng(season, p.id, "develop"))
	var pool := free_agent_pool(db)
	for team: TeamData in db.list_teams(TeamData.Category.CLUB):
		if team.id == career.club_id:
			continue
		var r := maintain_squad(career, team, season, pool)
		if not r["signed"].is_empty():
			out["signed"][team.id] = r["signed"]
		if not r["generated"].is_empty():
			out["generated"][team.id] = r["generated"]
	return out


## Retires a player: leaves his club (and any lineup), status RETIRED, no contract.
static func retire(db: Node, p: PlayerData, squads: Dictionary = {}) -> void:
	if p.team_id != "":
		var team: TeamData = db.get_team(p.team_id)
		if team != null and p.id in team.squad_ids:
			PromotionSystem.release_from_squad(db, team.id, p.id, squads.get(team.id))
	p.team_id = ""
	p.loan_parent = ""
	p.loan_weeks_left = 0
	p.contract_years = 0
	p.salary = 0
	p.status = PlayerData.Status.RETIRED
	p.development_history.append({"event": "retired", "age": p.age})


## Yearly change outside the academy: growth toward potential before 24, decline after 30.
static func develop(p: PlayerData, rng: RandomNumberGenerator) -> void:
	var steps := 0
	if p.age <= 23:
		steps = rng.randi_range(0, 3)
	elif p.age >= 34:
		steps = -rng.randi_range(1, 3)
	elif p.age >= 31:
		steps = -rng.randi_range(0, 2)
	var weights: Dictionary = PlayerData.OVERALL_WEIGHTS[p.position]
	for i in absi(steps):
		if steps > 0 and p.get_overall() >= p.potential:
			break
		for attr in weights:
			p.set(attr, clampi(p.get_attribute(attr) + (1 if steps > 0 else -1), PlayerData.MIN_RATING, PlayerData.MAX_RATING))
	if steps > 0 and p.get_overall() > p.potential:
		# one step can overshoot by a point: undo the last weighted increase
		for attr in weights:
			p.set(attr, clampi(p.get_attribute(attr) - 1, PlayerData.MIN_RATING, PlayerData.MAX_RATING))
	p.potential = maxi(p.potential, p.get_overall())
	if steps != 0:
		p.development_history.append({"event": "season_development", "age": p.age, "overall": p.get_overall()})


## Brings an AI club back to SQUAD_MIN..SQUAD_MAX with every line covered.
static func maintain_squad(career: CareerState, team: TeamData, season: int, pool: Dictionary = {}) -> Dictionary:
	if pool.is_empty():
		pool = free_agent_pool(career.db)
	var db: Node = career.db
	var out := {"signed": [], "generated": []}
	var level := maxi(career.base_level(team.id), 45)
	var counter := 0
	for _guard in 40:
		var need := _needed_line(db, team)
		if need == "":
			break
		var p := _take_free_agent(pool, need, level)
		var signed := false
		if p != null:
			var wage := career.market.minimum_wage(p)
			# AI clubs sign at the minimum wage on a two-year deal; budget rules still apply.
			if career.market.buy(team.id, p.id, 0, wage, 2, career.week) == "":
				out["signed"].append(p.id)
				signed = true
		if not signed:
			var g := generate_player(db, team, need, level, season, counter)
			counter += 1
			if g != null:
				out["generated"].append(g.id)
			else:
				break
	# Quality upkeep: a club that fell clearly below its base level brings in up to three ready
	# players (ages 23-27, about its base level) — the abstraction of the transfer window.
	for _i in QUALITY_SIGNINGS:
		if db.get_team_rating(team.id) >= level - QUALITY_GAP:
			break
		if db.get_squad(team.id).size() >= TransferMarket.MAX_SQUAD and not _release_weakest_veteran(db, team):
			break
		var g := generate_player(db, team, _weakest_line(db, team), level, season, counter, true)
		counter += 1
		if g == null:
			break
		out["generated"].append(g.id)
	return out


## Line whose best players are weakest relative to the starting XI (keepers only if < 2 decent).
static func _weakest_line(db: Node, team: TeamData) -> String:
	var best := {"DEF": [], "MID": [], "FWD": []}
	for p: PlayerData in db.get_squad(team.id):
		var l := line_of(p)
		if best.has(l):
			best[l].append(p.get_overall())
	var need := {"DEF": 4, "MID": 4, "FWD": 2}
	var worst := "MID"
	var worst_avg := 999.0
	for l in best:
		var arr: Array = best[l]
		arr.sort()
		arr.reverse()
		var top: Array = arr.slice(0, need[l])
		var avg := 0.0 if top.is_empty() else float(top.reduce(func(a: int, b: int) -> int: return a + b, 0)) / float(top.size())
		if avg < worst_avg:
			worst_avg = avg
			worst = l
	return worst


## Frees a place by releasing the weakest outfield player aged 30+. False if there is none.
static func _release_weakest_veteran(db: Node, team: TeamData) -> bool:
	var pick: PlayerData = null
	for p: PlayerData in db.get_squad(team.id):
		if p.age < 30 or p.position == PlayerData.Position.GK or p.loan_parent != "":
			continue
		if pick == null or p.get_overall() < pick.get_overall():
			pick = p
	if pick == null:
		return false
	return PromotionSystem.release_from_squad(db, team.id, pick.id) == ""


static func _needed_line(db: Node, team: TeamData) -> String:
	var squad: Array = db.get_squad(team.id)
	if squad.size() >= TransferMarket.MAX_SQUAD:
		return ""                          # hard cap of the market; a missing keeper may use the last places
	var counts := {"GK": 0, "DEF": 0, "MID": 0, "FWD": 0}
	for p: PlayerData in squad:
		counts[line_of(p)] += 1
	for line in ["GK", "DEF", "MID", "FWD"]:
		if counts[line] < int(LINE_MIN[line]):
			return line
	if squad.size() < SQUAD_MIN and squad.size() < SQUAD_MAX:
		# the line with the smallest share of its minimum
		var best := "MID"
		var ratio := 99.0
		for line in ["DEF", "MID", "FWD"]:
			var r := float(counts[line]) / float(LINE_MIN[line])
			if r < ratio:
				ratio = r
				best = line
		return best
	return ""


## Unattached active players by line, best first (built once per season rollover).
static func free_agent_pool(db: Node) -> Dictionary:
	var pool := {"GK": [], "DEF": [], "MID": [], "FWD": []}
	for p: PlayerData in db.players.values():
		if p.team_id == "" and p.status == PlayerData.Status.ACTIVE and p.age <= FREE_AGENT_MAX_AGE:
			pool[line_of(p)].append(p)
	for line in pool:
		(pool[line] as Array).sort_custom(func(a: PlayerData, b: PlayerData) -> bool:
			return a.get_overall() > b.get_overall() if a.get_overall() != b.get_overall() else a.id < b.id)
	return pool


## Removes and returns the best free agent of `line` that fits the club (not far above its level).
static func _take_free_agent(pool: Dictionary, line: String, level: int) -> PlayerData:
	var list: Array = pool.get(line, [])
	for i in list.size():
		var p: PlayerData = list[i]
		if p.team_id != "" or p.status != PlayerData.Status.ACTIVE:
			continue
		if p.get_overall() <= level + 6:
			list.remove_at(i)
			return p
	return null


## A young player (18-22) at about the club's level, registered in the database and the squad.
static func generate_player(db: Node, team: TeamData, line: String, level: int, season: int, index: int,
		ready := false) -> PlayerData:
	var pid := "gen_%s_s%d_%02d" % [team.id, season, index + 1]
	if db.get_player(pid) != null:
		return null
	var rng := _rng(season, pid, "generate")
	var positions: Array = LINE_POSITIONS[line]
	var p := PlayerData.new()
	p.id = pid
	p.position = positions[(index + rng.randi()) % positions.size()]
	p.age = rng.randi_range(23, 27) if ready else rng.randi_range(18, 22)
	p.nationality = team.country
	p.team_id = ""
	p.status = PlayerData.Status.ACTIVE
	p.preferred_foot = [PlayerData.Foot.RIGHT, PlayerData.Foot.RIGHT, PlayerData.Foot.LEFT, PlayerData.Foot.BOTH][rng.randi() % 4] as PlayerData.Foot
	# `level` is the club's BASE level (fixed at career start): anchoring new players to it, not to
	# the current XI, keeps the divisions from drifting up or down over many seasons.
	var target := clampi((level + rng.randi_range(-2, 2)) if ready else (level - 3 + rng.randi_range(-3, 3)), 40, 90)
	_set_attributes(p, target, rng)
	# Peak around the club's base level (a few become better, a few never get there).
	p.potential = clampi(level + rng.randi_range(-2, 6) if not ready else p.get_overall() + rng.randi_range(0, 3), p.get_overall(), 95)
	p.contract_years = 3
	p.salary = p.get_overall() * p.get_overall() / 4
	p.transfer_value = p.get_overall() * p.get_overall() * 400
	p.morale = 70
	p.display_name = _name(db, team, rng)
	p.development_history = [{"event": "signed" if ready else "signed_youth", "age": p.age, "overall": p.get_overall()}]
	PlayerAppearance.ensure(p)
	if not db.register_player(p):
		return null
	p.team_id = team.id
	p.shirt_number = maxi(PromotionSystem.next_free_number(db, team.id), 0)
	team.squad_ids.append(p.id)
	return p


static func _set_attributes(p: PlayerData, target: int, rng: RandomNumberGenerator) -> void:
	for attr in YouthGenerator.OUTFIELD_ATTRS:
		var bias: int = YouthGenerator.BIAS.get(p.position, {}).get(attr, 0)
		p.set(attr, clampi(target + bias + rng.randi_range(-4, 4), 1, 99))
	if p.position == PlayerData.Position.GK:
		p.goalkeeping = clampi(target + rng.randi_range(-1, 1), 1, 99)
		for attr in YouthGenerator.OUTFIELD_ATTRS:
			p.set(attr, clampi(target - 18 + rng.randi_range(-5, 5), 1, 99))
	else:
		p.goalkeeping = rng.randi_range(5, 15)
	var weights: Dictionary = PlayerData.OVERALL_WEIGHTS[p.position]
	for _i in 60:
		var delta := target - p.get_overall()
		if delta == 0:
			break
		for attr in weights:
			p.set(attr, clampi(p.get_attribute(attr) + signi(delta), 1, 99))
			if p.get_overall() == target:
				break


static func _name(db: Node, team: TeamData, rng: RandomNumberGenerator) -> String:
	var pool: Dictionary = YouthGenerator.pool_for(team.country)
	var used := {}
	for p in db.get_squad(team.id):
		used[(p as PlayerData).display_name] = true
	var nm := ""
	for _i in 30:
		nm = "%s %s" % [(pool["first"] as Array)[rng.randi() % (pool["first"] as Array).size()],
				(pool["last"] as Array)[rng.randi() % (pool["last"] as Array).size()]]
		if not used.has(nm):
			break
	return nm


static func _rng(season: int, id: String, salt: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([season, id, salt])
	return r
