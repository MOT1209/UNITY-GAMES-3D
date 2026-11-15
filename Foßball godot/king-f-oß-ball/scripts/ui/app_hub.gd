extends Node

## Autoload "AppHub" (Phase T10): the live management state shared by every
## screen — selected club, squads, academies, scouting, training, career —
## plus save/load and the bridge between the hub and the match engine.

signal state_changed
## Emitted when `advance_week_async` has finished a week; `info` is the summary `CareerState.advance_week` returns.
signal week_advanced(info: Dictionary)

const SAVE_PATH := "user://saves/career.json"

var db: Node
var user_team_id: String = ""
var career: CareerState = null
var squads: Dictionary = {}       # team_id -> Squad
var academies: Dictionary = {}    # team_id -> Academy
var scouting: Dictionary = {}     # team_id -> ScoutingSystem
var training: Dictionary = {}     # team_id -> TrainingSystem
var pending_fixture: Dictionary = {}   # {competition_id, match_id} of a hub-launched match
var last_message: String = ""
## When set, the hub opens this screen instead of its default (used by the main menu).
var open_screen_on_start: String = ""


func _ready() -> void:
	db = get_node("/root/TeamDB")
	var gm := get_node_or_null("/root/GameManager")
	if gm != null and gm.has_signal("match_finished"):
		gm.match_finished.connect(_on_match_finished)


## Picks the managed club and creates every system the screens need.
func select_team(team_id: String) -> String:
	var t: TeamData = db.get_team(team_id)
	if t == null:
		return "unknown team '%s'" % team_id
	user_team_id = team_id
	ensure_systems(team_id)
	state_changed.emit()
	return ""


func ensure_systems(team_id: String) -> void:
	var team: TeamData = db.get_team(team_id)
	if team == null:
		return
	if not squads.has(team_id):
		var sq := Squad.new(team_id)
		sq.auto_pick(db)
		squads[team_id] = sq
	if team.category != TeamData.Category.CLUB:
		return
	if not academies.has(team_id):
		var ac := Academy.new(team_id, team.country, hash(team_id) & 0x7fffffff)
		ac.quality = clampf(float(team.reputation) / 100.0, 0.2, 0.9)
		ac.budget = team.budget / 20
		ac.generate_intake(db, 12)
		academies[team_id] = ac
	if not scouting.has(team_id):
		var sc := ScoutingSystem.new(hash(team_id + "_scout") & 0x7fffffff)
		sc.add_scout("scout_a", "Regional Scout", 0.5, 1500)
		sc.add_scout("scout_b", "Chief Scout", 0.85, 4000)
		scouting[team_id] = sc
	if not training.has(team_id):
		var tr := TrainingSystem.new()
		tr.set_group_focus("U15", "dribbling")
		tr.set_group_focus("U17", "passing")
		tr.set_group_focus("U19", "shooting")
		training[team_id] = tr


func start_career(team_id: String) -> String:
	var err := select_team(team_id)
	if err != "":
		return err
	var c := CareerState.start(db, team_id)
	if c == null:
		return "a career needs a club team"
	career = c
	career.add_default_league()        # fictional world: a real league + cup instead of an empty calendar
	state_changed.emit()
	return ""


## Takes a job offered to the unemployed manager: the career switches the club, the hub its team and squads.
func take_job(new_club_id: String) -> String:
	if career == null:
		return "no career"
	var err := career.take_job(new_club_id)
	if err != "":
		return err
	return select_team(new_club_id)


func squad() -> Squad:
	return squads.get(user_team_id)


func academy() -> Academy:
	return academies.get(user_team_id)


## The single way to move the calendar: wages, loans, youth training and
## scouting all advance together, once per week. Returns {} without a career.
func advance_week() -> Dictionary:
	if career == null:
		return {}
	var info := career.advance_week(squads, academies, training, scouting)
	state_changed.emit()
	return info


## True while an asynchronous week is being simulated: saving, loading and ending the season must wait.
func is_advancing() -> bool:
	return career != null and career._advancing


## The same week as `advance_week`, simulated in phases with a frame in between so the UI stays responsive. Fire and forget:
## `week_advanced` (and `state_changed`) fire at the end. Does nothing while a week is already running.
func advance_week_async() -> void:
	if career == null or career._advancing:
		return
	var running := career
	var info: Dictionary = await career.advance_week_async(squads, academies, training, scouting)
	if career != running or info.get("busy", false):
		return
	state_changed.emit()
	week_advanced.emit(info)


## Switches between the default fictional world and a data pack ("" = default). The choice is
## saved; the running career and every per-club system are dropped (they belong to the old world).
func switch_world(pack_id: String) -> String:
	if pack_id != "" and not TeamDatabase.available_packs().any(func(p: Dictionary) -> bool: return p["id"] == pack_id):
		return "unknown data pack '%s'" % pack_id
	TeamDatabase.save_pack_choice(pack_id)
	db.load_world(pack_id)
	user_team_id = ""
	career = null
	squads.clear()
	academies.clear()
	scouting.clear()
	training.clear()
	pending_fixture = {}
	state_changed.emit()
	return ""


## Display name of a competition: translated for league-pyramid competitions (play-offs...),
## the stored name otherwise.
func competition_title(competition_id: String) -> String:
	if career == null or not career.competitions.has(competition_id):
		return competition_id
	for k in career.pyramids:
		var t: String = (career.pyramids[k] as LeaguePyramid).display_name_of(competition_id)
		if t != "":
			return t
	return (career.competitions[competition_id] as Competition).comp_name


## The managed club's fixtures due by the current week (league, cup, play-off, continental), oldest
## first: [[Competition, fixture], ...]. Empty without a career.
func due_user_fixtures() -> Array:
	var mine: Array = []
	if career == null:
		return mine
	for k in career.pyramids:
		var pyr: LeaguePyramid = career.pyramids[k]
		for role in pyr.comp:
			var comp: Competition = career.competitions.get(pyr.comp[role])
			if comp == null:
				continue
			for f in comp.pending_fixtures():
				if (f["home"] == career.club_id or f["away"] == career.club_id) and pyr.week_of(role, comp, f) <= career.week:
					mine.append([comp, f])
	if career.continental != null:
		var cc: Competition = career.continental.competition(career)
		if cc != null:
			for f in cc.pending_fixtures():
				if (f["home"] == career.club_id or f["away"] == career.club_id) and career.continental.week_of(f) <= career.week:
					mine.append([cc, f])
	return mine


## Starts the 3D match of one of the user's fixtures. Returns "" or an error.
func play_fixture(competition_id: String, f: Dictionary) -> String:
	var setup := MatchSetup.new()
	setup.home_id = f["home"]
	setup.away_id = f["away"]
	setup.competition_id = competition_id
	setup.match_id = f["match_id"]
	setup.knockout = f["stage"] == "ko" or f["stage"] == "third"
	setup.human_side = "home" if f["home"] == user_team_id else "away"
	return play_match(setup, {"competition_id": competition_id, "match_id": f["match_id"]})


## The pyramid that runs `competition_id`, or null for hand-made competitions.
func pyramid_of(competition_id: String) -> LeaguePyramid:
	if career == null:
		return null
	for k in career.pyramids:
		if (career.pyramids[k] as LeaguePyramid).role_of(competition_id) != "":
			return career.pyramids[k]
	return null


func notify(text: String) -> void:
	last_message = text
	state_changed.emit()


# --- save / load ---------------------------------------------------------------------------------

func save_game(path: String = SAVE_PATH) -> String:
	if is_advancing():
		return Loc.t("HUB_WEEK_IN_PROGRESS")
	var backup_err := SaveManager.backup_if_outdated(path)      # an older save is copied before it is replaced
	if backup_err != "":
		return backup_err
	var extras := {"user_team_id": user_team_id}
	if career != null:
		# Never write a career that fails its integrity audit: the old file (a good save) must not be replaced by a bad one.
		var audit := CareerValidator.validate(career, false)
		if not (audit["errors"] as Array).is_empty():
			push_warning("career not saved, integrity audit failed: %s" % str((audit["errors"] as Array).slice(0, 3)))
			return Loc.f("HUB_SAVE_REFUSED", [str((audit["errors"] as Array)[0])])
		extras["career"] = career.to_dict()
	var data := SaveManager.capture(db, academies, scouting, training, squads, extras)
	return SaveManager.write_file(path, data)


func load_game(path: String = SAVE_PATH) -> String:
	if is_advancing():
		return Loc.t("HUB_WEEK_IN_PROGRESS")
	var backup_err := SaveManager.backup_if_outdated(path)      # keep the original of a save written by an older version
	if backup_err != "":
		return backup_err
	var rd := SaveManager.read_file(path)
	if not rd["ok"]:
		return rd["error"]
	var res := SaveManager.restore(db, rd["data"])
	if not res["ok"]:
		return str(res["errors"][0])
	academies = res["academies"]
	scouting = res["scouting"]
	training = res["training"]
	squads = res["squads"]
	user_team_id = str(res["extras"].get("user_team_id", ""))
	career = null
	if res["extras"].has("career"):
		career = CareerState.from_dict(db, res["extras"]["career"])
	state_changed.emit()
	return ""


# --- matches ---------------------------------------------------------------------------------------

## Launches a configured match through the engine. `fixture` = {competition_id, match_id}.
func play_match(setup: MatchSetup, fixture: Dictionary = {}) -> String:
	var problems := setup.validate(db)
	if not problems.is_empty():
		return problems[0]
	if setup.home_squad == null and squads.has(setup.home_id):
		setup.home_squad = squads[setup.home_id]
	if setup.away_squad == null and squads.has(setup.away_id):
		setup.away_squad = squads[setup.away_id]
	pending_fixture = fixture
	setup.walkout = true                       # the teams walk out before a match started from the hub
	var gm := get_node("/root/GameManager")
	gm.set("return_scene_path", "res://ui/hub/hub.tscn")
	gm.start_configured_match(setup)
	return ""


func _on_match_finished(result: MatchResult) -> void:
	var gm := get_node_or_null("/root/GameManager")
	if career != null and gm != null:
		career.record_match(gm.get("last_match_report"), str(pending_fixture.get("competition_id", "")))      # idempotent by match uid
	if pending_fixture.is_empty() or career == null:
		return
	var comp_id: String = pending_fixture.get("competition_id", "")
	var err := career.submit_result(comp_id, result)
	last_message = Loc.t("HUB_RESULT_RECORDED") if err == "" else Loc.f("HUB_RESULT_NOT_RECORDED", err)
	pending_fixture = {}
	state_changed.emit()


## Quick simulation of a fixture without the 3D engine (strength-weighted).
func simulate_fixture(competition_id: String, match_id: String, seed_value: int = 0) -> String:
	if career == null or not career.competitions.has(competition_id):
		return "no such competition"
	var comp: Competition = career.competitions[competition_id]
	var f := comp.get_fixture(match_id)
	if f.is_empty():
		return "unknown match"
	return career.submit_result(competition_id, MatchSimulator.result(db, f, seed_value))


## Kept for callers of the old helper (match setup screen).
func _goals(rng: RandomNumberGenerator, edge: int) -> int:
	return MatchSimulator.goals(rng, edge)
