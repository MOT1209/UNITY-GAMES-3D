class_name DailyLife
extends RefCounted

## Phase K3: what happens every day of the career, for every club.
##   * Fitness: every active player recovers daily — base RECOVERY_BASE points, more when young, less when old, scaled by
##     his physical rating, and for the managed club by the day's training (rest recovers most, intense least) and the
##     fitness staff. Matches take it away again (`match_fatigue`, applied by `SeasonStats.record_simulated` for simulated
##     matches; engine matches drain it through `MatchState` stamina).
##   * Injuries and suspensions are counted in days (`PlayerData.unavailable_days`); a player is back the day it reaches 0.
##   * Training (managed club): the day's plan (`TrainingPlan`) — intensity changes recovery, the weekly development bonus
##     and a small injury risk on intense days.

const RECOVERY_BASE := 6.0
const INTENSE_INJURY_CHANCE := 0.0015       # per player and intense training day
const FATIGUE := {"GK": 4, "CB": 12, "LB": 14, "RB": 14, "CDM": 14, "CM": 15, "CAM": 14, "LM": 15, "RM": 15, "LW": 15, "RW": 15, "ST": 13}


## Daily recovery of one player (fitness points).
static func recovery(p: PlayerData, training_mod: float = 0.0, staff_factor: float = 1.0) -> float:
	var age_f := 1.2 if p.age <= 23 else (0.8 if p.age >= 32 else 1.0)
	var phys := 0.8 + float(p.physical) / 250.0
	return maxf(RECOVERY_BASE * age_f * phys * staff_factor + training_mod, 0.5)


## Fitness a full match costs a player of `position` (string key of PlayerData.Position).
static func match_fatigue(position_key: String) -> int:
	return int(FATIGUE.get(position_key, 14))


## One day for every club. `day_jdn` = the Julian day being lived (for the training plan and the seeds).
static func day(career: CareerState, day_jdn: int) -> void:
	var db: Node = career.db
	var plan := career.training.day_plan(career, day_jdn)
	var mod := TrainingPlan.recovery_mod(str(plan.get("intensity", "medium")))
	var staff_f := 1.0
	if career.staff != null and career.staff.has_method("assistant_quality"):
		staff_f = 0.9 + 0.2 * clampf(float(career.staff.assistant_quality()), 0.0, 1.0)
	var rng := RandomNumberGenerator.new()
	for t: TeamData in db.list_teams(TeamData.Category.CLUB):
		var mine := t.id == career.club_id
		for pid in t.squad_ids:
			var p: PlayerData = db.players.get(pid)
			if p == null:
				continue
			if p.fitness >= 100 and p.unavailable_days == 0 and not mine:
				continue                                # nothing to recover or count (most of the world, most days)
			if p.unavailable_days > 0 and p.status != PlayerData.Status.INJURED and p.status != PlayerData.Status.SUSPENDED:
				p.unavailable_days = 0                  # healed / banned-lifted by other means: no days left to count
			if p.unavailable_days > 0:
				p.unavailable_days -= 1
				p.unavailable_weeks = ceili(p.unavailable_days / 7.0)
				if p.unavailable_days <= 0 and (p.status == PlayerData.Status.INJURED or p.status == PlayerData.Status.SUSPENDED):
					p.status = PlayerData.Status.ACTIVE
					p.unavailable_weeks = 0
			if p.status == PlayerData.Status.RETIRED:
				continue
			var gain := recovery(p, mod if mine else 0.0, staff_f if mine else 1.0)
			p.fitness = clampi(p.fitness + roundi(gain), 30, 100)
			if mine and plan.get("intensity", "") == "intense" and p.status == PlayerData.Status.ACTIVE:
				rng.seed = hash("train|%d|%s" % [day_jdn, p.id])
				if rng.randf() < INTENSE_INJURY_CHANCE * career.injury_factor_for(p.team_id):
					Availability.injure(career, p, 1)
	career.training.note_day(str(plan.get("intensity", "medium")))
