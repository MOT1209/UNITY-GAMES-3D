class_name MatchSetup
extends RefCounted

## Everything the match engine needs to start a match (Phase T11): which two
## teams, their squads/formations/tactics, stadium, duration, difficulty and
## conditions. Squads come from `Squad` objects (auto-picked when absent).

const ALLOWED_DURATIONS: Array[int] = [2, 3, 5, 8, 10, 15, 20, 30, 45, 90]
const DIFFICULTIES: Array[String] = ["easy", "normal", "hard"]
const SIDES: Array[String] = ["home", "away", "none"]

var home_id: String = ""
var away_id: String = ""
var stadium_id: String = "arena"
var duration_minutes: int = 10          # real minutes for the WHOLE match
var difficulty: int = 1                 # index into DIFFICULTIES
var conditions: Dictionary = {"weather": "clear", "time_of_day": "day"}
var human_side: String = "home"         # which side the player controls
## Automatic player switching for this match: "auto" | "semi" | "manual"; "" = the saved setting.
var switch_mode: String = ""
## Teams walk out side by side before kick-off (matches started from the menus; tests start without it).
var walkout: bool = false
var competition_id: String = ""
var match_id: String = ""
var knockout: bool = false              # draws are settled by penalties
var rng_seed: int = 1
var home_squad: Squad = null
var away_squad: Squad = null
## Players who may not take part (a loanee against his own club, transfers v2). Replaced in the lineup by the best
## available player for the slot; the career's own squad is never changed.
var excluded: Array = []


## Returns human-readable problems (empty = the match can start).
func validate(db: Node) -> Array[String]:
	var errors: Array[String] = []
	if home_id == "" or away_id == "":
		errors.append("both teams must be selected")
		return errors
	if home_id == away_id:
		errors.append("a team cannot play against itself")
	for id in [home_id, away_id]:
		if db.get_team(id) == null:
			errors.append("unknown team '%s'" % id)
	if not errors.is_empty():
		return errors
	if not (duration_minutes in ALLOWED_DURATIONS):
		errors.append("unsupported match duration %d" % duration_minutes)
	if difficulty < 0 or difficulty >= DIFFICULTIES.size():
		errors.append("unknown difficulty %d" % difficulty)
	if not (human_side in SIDES):
		errors.append("unknown human side '%s'" % human_side)
	if knockout and match_id == "" and competition_id != "":
		errors.append("competition matches need a match id")
	for id in [home_id, away_id]:
		var playable := 0
		var keepers := 0
		for p in db.get_squad(id):
			if p.status == PlayerData.Status.ACTIVE:
				playable += 1
				if p.position == PlayerData.Position.GK:
					keepers += 1
		if playable < 11:
			errors.append("team '%s' has only %d available players" % [id, playable])
		if keepers < 1:
			errors.append("team '%s' has no available goalkeeper" % id)
	return errors


## Lineup description of one side, ready for the engine.
## {team_id, squad, formation, tactics, starters:[{slot, player_id}], bench:[ids], kit}
func build_side(db: Node, side: String) -> Dictionary:
	var team_id := home_id if side == "home" else away_id
	var squad: Squad = home_squad if side == "home" else away_squad
	if squad == null or not squad.validate(db).is_empty():
		squad = Squad.new(team_id, squad.formation_id if squad != null else "4-3-3")
		squad.auto_pick(db)
		if side == "home":
			home_squad = squad
		else:
			away_squad = squad
	if not excluded.is_empty():
		squad = _without_excluded(db, squad)
	var starters: Array = []
	for slot in 11:
		starters.append({"slot": slot, "player_id": squad.starting[slot]})
	var kit := "home"
	if side == "away":
		var home_team: TeamData = db.get_team(home_id)
		kit = KitEditor.pick_away_kit(db.get_team(away_id), home_team.kits.get("home", {}))
	return {"team_id": team_id, "side": side, "squad": squad, "formation": squad.formation_id,
			"tactics": squad.get_tactics(), "starters": starters, "bench": squad.bench.duplicate(), "kit": kit}


## A copy of `squad` with every excluded player taken out: an excluded starter is replaced by the best fitting player
## from the bench or the rest of the squad (a keeper only by a keeper).
func _without_excluded(db: Node, squad: Squad) -> Squad:
	var hit := false
	for pid in excluded:
		if pid in squad.starting or pid in squad.bench:
			hit = true
	if not hit:
		return squad
	var copy := Squad.from_dict(squad.to_dict())
	for pid in excluded:
		copy.bench.erase(pid)
		copy.reserves.erase(pid)
	for slot in 11:
		if not (copy.starting[slot] in excluded):
			continue
		var slot_pos := FormationData.slot_position(copy.formation_id, slot)
		var best: PlayerData = null
		var best_score := -1.0
		for p: PlayerData in db.get_squad(copy.team_id):
			if p.id in excluded or p.id in copy.starting or p.status != PlayerData.Status.ACTIVE:
				continue
			if (p.position == PlayerData.Position.GK) != (slot_pos == PlayerData.Position.GK):
				continue
			var score := FormationData.position_fit(p.position, slot_pos) * p.get_overall() + (0.5 if p.id in copy.bench else 0.0)
			if score > best_score:
				best_score = score
				best = p
		copy.starting[slot] = best.id if best != null else ""
		if best != null:
			copy.bench.erase(best.id)
	if copy.captain_id in excluded:
		copy.captain_id = ""
	for k in copy.set_pieces:
		if copy.set_pieces[k] in excluded:
			copy.set_pieces[k] = ""
	return copy


## Serialisable form (match save, restart). Squads are saved as they are at this moment.
func to_dict() -> Dictionary:
	return {"home_id": home_id, "away_id": away_id, "stadium_id": stadium_id, "duration_minutes": duration_minutes,
			"difficulty": difficulty, "conditions": conditions.duplicate(), "human_side": human_side,
			"competition_id": competition_id, "match_id": match_id, "knockout": knockout, "rng_seed": rng_seed,
			"switch_mode": switch_mode, "walkout": walkout, "excluded": excluded.duplicate(),
			"home_squad": home_squad.to_dict() if home_squad != null else {},
			"away_squad": away_squad.to_dict() if away_squad != null else {}}


static func from_dict(d: Dictionary) -> MatchSetup:
	var s := MatchSetup.new()
	s.home_id = str(d.get("home_id", ""))
	s.away_id = str(d.get("away_id", ""))
	s.stadium_id = str(d.get("stadium_id", "arena"))
	s.duration_minutes = int(d.get("duration_minutes", 10))
	s.difficulty = int(d.get("difficulty", 1))
	s.conditions = (d.get("conditions", {"weather": "clear", "time_of_day": "day"}) as Dictionary).duplicate()
	s.human_side = str(d.get("human_side", "home"))
	s.competition_id = str(d.get("competition_id", ""))
	s.match_id = str(d.get("match_id", ""))
	s.knockout = bool(d.get("knockout", false))
	s.rng_seed = int(d.get("rng_seed", 1))
	s.switch_mode = str(d.get("switch_mode", ""))
	s.walkout = bool(d.get("walkout", false))
	s.excluded = (d.get("excluded", []) as Array).map(func(x: Variant) -> String: return str(x))
	if not (d.get("home_squad", {}) as Dictionary).is_empty():
		s.home_squad = Squad.from_dict(d["home_squad"])
	if not (d.get("away_squad", {}) as Dictionary).is_empty():
		s.away_squad = Squad.from_dict(d["away_squad"])
	return s


## Independent copy (squads included): a match must never change the career's own lineups.
func duplicate_for_match(db: Node) -> MatchSetup:
	build_side(db, "home")           # fills in / repairs missing squads
	build_side(db, "away")
	return MatchSetup.from_dict(to_dict())
