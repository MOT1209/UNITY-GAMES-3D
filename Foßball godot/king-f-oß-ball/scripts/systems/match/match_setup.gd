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
var competition_id: String = ""
var match_id: String = ""
var knockout: bool = false              # draws are settled by penalties
var rng_seed: int = 1
var home_squad: Squad = null
var away_squad: Squad = null


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
	var starters: Array = []
	for slot in 11:
		starters.append({"slot": slot, "player_id": squad.starting[slot]})
	var kit := "home"
	if side == "away":
		var home_team: TeamData = db.get_team(home_id)
		kit = KitEditor.pick_away_kit(db.get_team(away_id), home_team.kits.get("home", {}))
	return {"team_id": team_id, "side": side, "squad": squad, "formation": squad.formation_id,
			"tactics": squad.get_tactics(), "starters": starters, "bench": squad.bench.duplicate(), "kit": kit}
