class_name MoraleSystem
extends RefCounted

## Career phases C3.2 / C3.5: morale with visible reasons and the team atmosphere.
## `log` (saved with the career): player id -> newest-last list of {week, season, key, delta}. Reasons are translation keys
## ("MORALE_WIN" ...), so the player sees WHY a number moved. Deterministic: no randomness.

const LOG_MAX := 6
const DRIFT_TARGET := 70
const BIG_MOVE := 8                 # |delta| above this is clamped, so one event never wrecks a squad

var log: Dictionary = {}


## Applies `delta` to the player's morale and records why. Returns the delta really applied.
func apply(p: PlayerData, delta: int, key: String, season: int, week: int) -> int:
	var before := p.morale
	p.morale = clampi(p.morale + clampi(delta, -BIG_MOVE, BIG_MOVE), 0, 100)
	var real := p.morale - before
	if real != 0:
		var l: Array = log.get(p.id, [])
		l.append({"week": week, "season": season, "key": key, "delta": real})
		while l.size() > LOG_MAX:
			l.pop_front()
		log[p.id] = l
	return real


func reasons(player_id: String) -> Array:
	var l: Array = log.get(player_id, [])
	var out := l.duplicate(true)
	out.reverse()
	return out


## Weekly update of the managed club's squad. `last_result` = "win" / "draw" / "loss" / "" for this week's league match.
func weekly(career: CareerState, last_result: String) -> void:
	var team: TeamData = career.db.get_team(career.club_id)
	if team == null or career.manager.unemployed:
		return
	var squad: Array = career.db.get_squad(career.club_id)
	squad = squad.filter(func(p: PlayerData) -> bool: return p.status != PlayerData.Status.YOUTH)
	squad.sort_custom(func(a: PlayerData, b: PlayerData) -> bool: return a.get_overall() > b.get_overall())
	var rate := float(career.manager.style_effects()["morale"])
	for i in squad.size():
		var p: PlayerData = squad[i]
		match last_result:
			"win":
				apply(p, 3, "MORALE_WIN", career.season, career.week)
			"loss":
				apply(p, -3 if PlayerPersonality.trait_value(p, "temperament") >= 8 else -4, "MORALE_LOSS", career.season, career.week)
		if i >= 14 and PlayerPersonality.trait_value(p, "ambition") >= 8:
			apply(p, -2, "MORALE_BENCH", career.season, career.week)
		for h in p.development_history:
			if str(h.get("event", "")) == "renewed" and int(h.get("week", -99)) == career.week and bool(h.get("fresh", true)):
				apply(p, 6, "MORALE_NEW_CONTRACT", career.season, career.week)
				h["fresh"] = false
		# drift back toward normal; motivators recover faster
		var step := int(round(1.0 * rate))
		if p.morale > DRIFT_TARGET + 5:
			p.morale = maxi(p.morale - step, DRIFT_TARGET)
		elif p.morale < DRIFT_TARGET - 5:
			p.morale = mini(p.morale + step, DRIFT_TARGET)


## Average morale of the first eleven's worth of players (the 14 best): 0..100.
static func average(db: Node, club_id: String) -> float:
	var squad: Array = db.get_squad(club_id)
	squad.sort_custom(func(a: PlayerData, b: PlayerData) -> bool: return a.get_overall() > b.get_overall())
	var n := mini(14, squad.size())
	if n == 0:
		return float(DRIFT_TARGET)
	var sum := 0
	for i in n:
		sum += (squad[i] as PlayerData).morale
	return float(sum) / float(n)


## Name and the factor (at most +-3%) the atmosphere puts on the club's attacking output in simulated matches.
static func atmosphere(db: Node, club_id: String) -> Dictionary:
	var avg := average(db, club_id)
	var name_key := "ATMOSPHERE_EXCELLENT" if avg >= 80 else ("ATMOSPHERE_GOOD" if avg >= 68 else ("ATMOSPHERE_TENSE" if avg >= 52 else "ATMOSPHERE_POOR"))
	return {"key": name_key, "factor": 1.0 + clampf((avg - float(DRIFT_TARGET)) / 30.0, -1.0, 1.0) * 0.03, "average": avg}


func to_dict() -> Dictionary:
	return {"log": log.duplicate(true)}


static func from_dict(d: Dictionary) -> MoraleSystem:
	var m := MoraleSystem.new()
	for pid in (d.get("log", {}) as Dictionary):
		var l: Array = []
		for e in d["log"][pid]:
			if typeof(e) == TYPE_DICTIONARY:
				l.append({"week": int(e.get("week", 0)), "season": int(e.get("season", 1)), "key": str(e.get("key", "")), "delta": int(e.get("delta", 0))})
		m.log[str(pid)] = l.slice(maxi(l.size() - LOG_MAX, 0))
	return m
