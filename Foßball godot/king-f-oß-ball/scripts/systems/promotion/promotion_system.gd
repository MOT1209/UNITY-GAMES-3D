class_name PromotionSystem
extends RefCounted

## Academy → first-team promotion (Phase T6). All checks run BEFORE any change,
## so a failed promotion never leaves half-moved data. The player keeps the
## same id, attributes and development history; there is no second record.
## Reversal exists only through `release_from_squad()` (free agent) —
## loans/transfers arrive with Phase T9.

const MAX_SHIRT := 99
const DEFAULT_CONTRACT_YEARS := 3


## Shirt numbers already used by the team's first-team squad.
static func used_numbers(db: Node, team_id: String) -> Array[int]:
	var out: Array[int] = []
	for p in db.get_squad(team_id):
		if p.shirt_number > 0:
			out.append(p.shirt_number)
	return out


## First free number in 1..99, or -1 when the squad uses all of them.
static func next_free_number(db: Node, team_id: String) -> int:
	var used := used_numbers(db, team_id)
	for n in range(1, MAX_SHIRT + 1):
		if not (n in used):
			return n
	return -1


## Returns "" on success or an error message. `shirt_number` -1 = auto-assign.
static func promote(db: Node, academy: Academy, player_id: String, shirt_number: int = -1) -> String:
	var p: PlayerData = db.get_player(player_id)
	if p == null:
		return "unknown player '%s'" % player_id
	var team: TeamData = db.get_team(academy.team_id)
	if team == null:
		return "unknown team '%s'" % academy.team_id
	if player_id in team.squad_ids:
		return "player '%s' is already in the first team" % player_id
	if not (player_id in academy.roster_ids):
		return "player '%s' is not in the academy roster" % player_id
	if p.team_id != academy.team_id or p.status != PlayerData.Status.YOUTH:
		return "player '%s' is not an academy youth of '%s'" % [player_id, academy.team_id]
	if p.age < AcademyConfig.MIN_PROMOTION_AGE:
		return "player '%s' is too young to be promoted (min age %d)" % [player_id, AcademyConfig.MIN_PROMOTION_AGE]
	var number := shirt_number
	if number == -1:
		number = next_free_number(db, academy.team_id)
		if number == -1:
			return "no free squad number"
	elif number < 1 or number > MAX_SHIRT:
		return "squad number %d out of range 1-%d" % [number, MAX_SHIRT]
	elif number in used_numbers(db, academy.team_id):
		return "squad number %d is already taken" % number
	# --- all checks passed: mutate ---
	academy.roster_ids.erase(player_id)
	team.squad_ids.append(player_id)
	p.status = PlayerData.Status.ACTIVE
	p.shirt_number = number
	p.contract_years = DEFAULT_CONTRACT_YEARS
	p.salary = p.get_overall() * p.get_overall() / 4
	p.development_history.append({"event": "promoted", "age": p.age, "overall": p.get_overall(),
			"shirt_number": number})
	return ""


## Eligibility helper for the UI: why can't this player be promoted? ("" = can).
static func why_not(db: Node, academy: Academy, player_id: String) -> String:
	var p: PlayerData = db.get_player(player_id)
	if p == null:
		return "unknown player"
	if not (player_id in academy.roster_ids):
		return "not in academy"
	if p.age < AcademyConfig.MIN_PROMOTION_AGE:
		return "too young (min %d)" % AcademyConfig.MIN_PROMOTION_AGE
	return ""


## Releases an academy youth (leaves the club, becomes an unowned free agent).
static func release_youth(db: Node, academy: Academy, player_id: String) -> String:
	if not (player_id in academy.roster_ids):
		return "player '%s' is not in the academy roster" % player_id
	var p: PlayerData = db.get_player(player_id)
	if p == null:
		return "unknown player '%s'" % player_id
	academy.roster_ids.erase(player_id)
	p.team_id = ""
	p.status = PlayerData.Status.ACTIVE
	p.development_history.append({"event": "released", "age": p.age})
	return ""


## Removes a first-team player from the squad (free agent). Also strips them
## from the lineup so no ghost entries remain.
static func release_from_squad(db: Node, team_id: String, player_id: String, squad: Squad = null) -> String:
	var team: TeamData = db.get_team(team_id)
	if team == null:
		return "unknown team '%s'" % team_id
	if not (player_id in team.squad_ids):
		return "player '%s' is not in the first team" % player_id
	var idx := team.squad_ids.find(player_id)
	team.squad_ids.remove_at(idx)
	var p: PlayerData = db.get_player(player_id)
	if p != null:
		p.team_id = ""
		p.shirt_number = 0
		p.development_history.append({"event": "released", "age": p.age})
	if squad != null:
		for i in squad.starting.size():
			if squad.starting[i] == player_id:
				squad.starting[i] = ""
		squad.bench.erase(player_id)
		squad.reserves.erase(player_id)
		if squad.captain_id == player_id:
			squad.captain_id = ""
		for k in squad.set_pieces:
			if squad.set_pieces[k] == player_id:
				squad.set_pieces[k] = ""
	return ""
