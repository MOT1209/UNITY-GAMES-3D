class_name Availability
extends RefCounted

## Injuries and suspensions (Phase 7). Status INJURED / SUSPENDED + `unavailable_weeks` on `PlayerData`.
## * Suspensions come from REAL match events: a red card (a straight red or a second yellow) = a one-week ban, and five yellow
##   cards in a season = a one-week ban (the counter restarts).
## * Injuries are a probability model, not a script: per player and match `injury_probability()` (base 1.5 %, higher when fouled
##   in the match, tired, old or injury-prone), rolled with an RNG seeded from the match uid and the player id, so the same
##   match gives the same outcome. Between matches every player also has a small weekly chance (0.4 %).
## * Every week `unavailable_weeks` counts down; at zero the player is ACTIVE again.
## * Squads: an unavailable starter makes a squad invalid (existing rule), so the match falls back to the auto-picked lineup;
##   `weekly()` also repairs the lineups it is given by swapping in the best available bench player.

const BASE_INJURY := 0.015
const WEEKLY_INJURY := 0.004
const YELLOWS_FOR_BAN := 5


static func injury_probability(p: PlayerData, fouled: int, weekly: bool = false) -> float:
	var base := WEEKLY_INJURY if weekly else BASE_INJURY
	var prob := base * (1.0 + 0.5 * float(fouled)) * (1.0 + float(100 - p.fitness) / 100.0)
	if "Injury Prone" in p.traits:
		prob *= 1.3
	prob *= 1.0 + maxf(float(p.age - 30), 0.0) * 0.05
	return clampf(prob, 0.0, 0.5)


## Injury length in weeks (1..8, short injuries are far more common) for a roll in 0..1.
static func injury_weeks(roll: float) -> int:
	return 1 + int(roll * roll * 8.0)


static func _rng_for(seed_text: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_text)
	return rng


## Only the user's own players and stars (overall 75+) go into the world log, so the news is not flooded by every AI reserve.
static func _newsworthy(career: CareerState, p: PlayerData) -> bool:
	return p.team_id == career.club_id or p.get_overall() >= 75


static func injure(career: CareerState, p: PlayerData, weeks: int) -> void:
	if p.status != PlayerData.Status.ACTIVE or weeks <= 0:
		return
	p.status = PlayerData.Status.INJURED
	p.unavailable_weeks = weeks
	if _newsworthy(career, p):
		career.add_event("injury", [p.id, p.team_id, weeks])


static func suspend(career: CareerState, p: PlayerData, weeks: int) -> void:
	if weeks <= 0 or p.status == PlayerData.Status.RETIRED:
		return
	p.status = PlayerData.Status.SUSPENDED
	p.unavailable_weeks = maxi(p.unavailable_weeks, weeks)
	if _newsworthy(career, p):
		career.add_event("ban", [p.id, p.team_id, weeks])


## Consequences of a finished engine match (`MatchReport`): bans from cards, injuries from the probability model.
static func after_match(career: CareerState, report: Dictionary) -> void:
	var uid := str(report.get("uid", report.get("match_id", "")))
	for row in report.get("players", []):
		var p: PlayerData = career.db.get_player(str(row["player_id"]))
		if p == null or p.status == PlayerData.Status.RETIRED:
			continue
		if int(row.get("red", 0)) > 0:
			suspend(career, p, 1)
			continue
		var yellows := int(row.get("yellow", 0))
		if yellows > 0:
			career.yellow_counts[p.id] = int(career.yellow_counts.get(p.id, 0)) + yellows
			if int(career.yellow_counts[p.id]) >= YELLOWS_FOR_BAN:
				career.yellow_counts[p.id] = 0
				suspend(career, p, 1)
		var rng := _rng_for("%s|%s" % [uid, p.id])
		if rng.randf() < injury_probability(p, int(row.get("fouled", 0))):
			injure(career, p, injury_weeks(rng.randf()))


## One calendar week: counts down injuries and bans, rolls the small weekly injury chance, repairs lineups in `squads`.
static func weekly(career: CareerState, squads: Dictionary = {}) -> void:
	var db: Node = career.db
	for t: TeamData in db.list_teams(TeamData.Category.CLUB):
		for p in db.get_squad(t.id):
			if p.status == PlayerData.Status.INJURED or p.status == PlayerData.Status.SUSPENDED:
				p.unavailable_weeks -= 1
				if p.unavailable_weeks <= 0:
					p.unavailable_weeks = 0
					p.status = PlayerData.Status.ACTIVE
			elif p.status == PlayerData.Status.ACTIVE:
				var rng := _rng_for("w|%d|%d|%s" % [career.season, career.week, p.id])
				if rng.randf() < injury_probability(p, 0, true):
					injure(career, p, injury_weeks(rng.randf()))
	for team_id in squads:
		fix_lineup(squads[team_id] as Squad, db)


## Replaces unavailable starters by the best available bench player of the same fit. Returns the number of swaps.
static func fix_lineup(squad: Squad, db: Node) -> int:
	var swaps := 0
	for slot in 11:
		var pid: String = squad.starting[slot]
		var p: PlayerData = db.get_player(pid) if pid != "" else null
		if p == null or p.status == PlayerData.Status.ACTIVE:
			continue
		var in_id := ManagerAI._pick_replacement(squad, slot, db)
		if in_id != "" and squad.substitute(db, slot, in_id) == "":
			swaps += 1
	# unavailable players must not sit on the bench either: they go to the reserves and available reserves fill the bench
	for pid in squad.bench.duplicate():
		var bp: PlayerData = db.get_player(pid)
		if bp == null or bp.status != PlayerData.Status.ACTIVE:
			squad.bench.erase(pid)
			squad.reserves.append(pid)
	var fill: Array = squad.reserves.filter(func(pid: String) -> bool:
		var rp: PlayerData = db.get_player(pid)
		return rp != null and rp.status == PlayerData.Status.ACTIVE)
	fill.sort_custom(func(a: String, b: String) -> bool: return db.get_player(a).get_overall() > db.get_player(b).get_overall())
	for pid in fill:
		if squad.bench.size() >= Squad.MAX_BENCH:
			break
		squad.reserves.erase(pid)
		squad.bench.append(pid)
	return swaps
