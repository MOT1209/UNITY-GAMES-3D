extends Node

## Autoload "AppHub" (Phase T10): the live management state shared by every
## screen — selected club, squads, academies, scouting, training, career —
## plus save/load and the bridge between the hub and the match engine.

signal state_changed
## Emitted when `advance_week_async` has finished a week; `info` is the summary `CareerState.advance_week` returns.
signal week_advanced(info: Dictionary)

const AUTOSAVE_MIN_INTERVAL_S := 60
## Folder that holds every save file (manual save, autosave, the pre-new-career backup and the five slots).
## Validation suites set this to `user://test_saves` so a run never reads or deletes a player's saves.
var save_root := "user://saves"
var _last_autosave_s := -1000000

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
## Phase S2: a live simulation handed to the 3D engine ("play from this minute"): {minute, score {home, away}, events, stats};
## `MatchManager.begin` applies it once and clears it.
var pending_resume: Dictionary = {}


func _ready() -> void:
	db = get_node("/root/TeamDB")
	var gm := get_node_or_null("/root/GameManager")
	if gm != null and gm.has_signal("match_finished"):
		gm.match_finished.connect(_on_match_finished)
	week_advanced.connect(func(_info: Dictionary) -> void:
		if Time.get_ticks_msec() / 1000 - _last_autosave_s >= AUTOSAVE_MIN_INTERVAL_S:
			_auto_trigger())


## Android may kill a backgrounded app without a word: save when it is paused, loses focus or is closed.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT \
			or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_auto_trigger()


## The automatic triggers never run headless: the validation suites must not write the player's autosave slot.
func _auto_trigger() -> void:
	if DisplayServer.get_name() != "headless":
		autosave()


## Saves the running career to the autosave slot. Silent: returns "" when there is nothing to save.
func autosave(path := "") -> String:
	if path == "":
		path = autosave_path()
	if career == null or user_team_id == "" or is_advancing():
		return ""
	_last_autosave_s = Time.get_ticks_msec() / 1000
	var err := save_game(path)
	if err != "":
		push_warning("autosave failed: %s" % err)
	return err


## The newer of the manual save and the autosave ("" when neither exists).
func latest_save_path() -> String:
	var best := ""
	var best_time := -1
	var candidates: Array = [save_path(), autosave_path()]
	for n in range(1, SLOT_COUNT + 1):
		candidates.append(slot_path(n))
	for p in candidates:
		if FileAccess.file_exists(p):
			var t := FileAccess.get_modified_time(p)
			if t > best_time:
				best_time = t
				best = p
	return best


# --- save slots (C9.5): 5 manual slots + autosave + a safety copy before a new career replaces the running one ------------

const SLOT_COUNT := 5


## Save paths inside `save_root`.
func save_path() -> String:
	return save_root + "/career.json"


## Written by `autosave()` (app paused / closed, and after weeks at most once a minute); the manual save is never
## overwritten by it. "Continue" and Load take whichever of the two is newer.
func autosave_path() -> String:
	return save_root + "/autosave.json"


func backup_path() -> String:
	return save_root + "/before_new_career.json"


func slot_path(n: int) -> String:
	return "%s/slot_%d.json" % [save_root, n]


## {exists, club, season, week, pack_id, saved_unix} of a save file, read from its `extras.meta` ("exists": false when absent).
func save_info(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"exists": false}
	# Fast path: the small "<path>.meta" sidecar (a full save is 15-25 MB of JSON; parsing 8 of them took 13-18 s).
	var side := SaveManager.read_meta(path)
	if not side.is_empty():
		return {"exists": true, "club": str(side.get("club", "")), "season": int(side.get("season", 0)), "week": int(side.get("week", 0)),
				"pack_id": str(side.get("pack_id", "")), "saved_unix": int(side.get("saved_unix", FileAccess.get_modified_time(path)))}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"exists": false, "corrupt": true}
	SaveManager.write_meta(path, parsed)      # once per old save: the next list opens fast
	var extras: Dictionary = (parsed as Dictionary).get("extras", {})
	var meta: Dictionary = extras.get("meta", {})
	return {"exists": true, "club": str(meta.get("club", "")), "season": int(meta.get("season", 0)), "week": int(meta.get("week", 0)),
			"pack_id": SaveManager.world_of(parsed), "saved_unix": int(meta.get("saved_unix", FileAccess.get_modified_time(path)))}


func save_to_slot(n: int) -> String:
	if n < 1 or n > SLOT_COUNT:
		return "no such slot"
	var err := save_game(slot_path(n))
	if err == "":
		GameSettings.set_value("career", "last_slot", n)
	return err


func load_slot(n: int) -> String:
	if n < 1 or n > SLOT_COUNT:
		return "no such slot"
	var err := load_game(slot_path(n))
	if err == "":
		GameSettings.set_value("career", "last_slot", n)
	return err


## Copies the running career to the backup file before a new career replaces it. With no career loaded (New Career
## picked straight from the main menu) the newer of the manual save and the autosave is copied instead, because
## `save_new_career()` overwrites both. Returns "" when it worked or there was nothing to back up.
func backup_running_career() -> String:
	if career != null and user_team_id != "":
		return save_game(backup_path())
	var src := ""
	for p in [save_path(), autosave_path()]:
		if FileAccess.file_exists(p) and (src == "" or FileAccess.get_modified_time(p) > FileAccess.get_modified_time(src)):
			src = p
	if src == "":
		return ""
	return _copy_save(src, backup_path())


## Copies a save file and its `.meta` sidecar (or drops a stale sidecar at the destination). Returns "" or an error.
func _copy_save(from: String, to: String) -> String:
	if DirAccess.copy_absolute(from, to) != OK:
		return "cannot copy '%s' to '%s'" % [from, to]
	var to_meta := SaveManager.meta_path(to)
	if FileAccess.file_exists(SaveManager.meta_path(from)):
		DirAccess.copy_absolute(SaveManager.meta_path(from), to_meta)
	elif FileAccess.file_exists(to_meta):
		DirAccess.remove_absolute(to_meta)
	return ""


## Writes a just-started career to disk, as the manual save AND the autosave, so "Continue career" (which loads the
## newer of the two) opens this career and not the previous one or nothing. The previous career was kept in
## `backup_path()` by `backup_running_career()` before it was replaced.
func save_new_career() -> String:
	var err := save_game(save_path())
	if err != "":
		return err
	if _copy_save(save_path(), autosave_path()) != "":
		return save_game(autosave_path())
	return ""


## Every save file with its info, newest first: slots, manual save, autosave and the pre-new-career backup.
func all_saves() -> Array:
	var out: Array = []
	var paths: Array = [save_path(), autosave_path(), backup_path()]
	for n in range(1, SLOT_COUNT + 1):
		paths.append(slot_path(n))
	for p in paths:
		var info := save_info(p)
		if bool(info["exists"]):
			info["path"] = p
			out.append(info)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["saved_unix"]) > int(b["saved_unix"]))
	return out


func has_saved_career() -> bool:
	return latest_save_path() != ""


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


## Phase K: one day (see `CareerState.advance_day`): on a Monday the weekly systems run, every day its own fixtures.
func advance_day() -> Dictionary:
	if career == null or career._advancing:
		return {}
	var info := career.advance_day(squads, academies, training, scouting)
	state_changed.emit()
	return info


## Awaitable single day with a frame afterwards, for the long day-by-day runs (progress bar stays alive).
func advance_day_async() -> void:
	advance_day()
	await get_tree().process_frame


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
	var nm := (career.competitions[competition_id] as Competition).comp_name
	return Loc.t(nm) if nm == "FRIENDLY_NAME" else nm


## The managed club's fixtures due by the current week (league, cup, play-off, continental), oldest
## first: [[Competition, fixture], ...]. Empty without a career.
func due_user_fixtures() -> Array:
	return [] if career == null else career.due_user_fixtures()


## Starts the 3D match of one of the user's fixtures. Returns "" or an error.
func play_fixture(competition_id: String, f: Dictionary) -> String:
	var setup := MatchSetup.new()
	setup.home_id = f["home"]
	setup.away_id = f["away"]
	setup.competition_id = competition_id
	setup.match_id = f["match_id"]
	setup.stadium_id = StadiumCatalog.HOME        # competition matches are played at the home club's ground
	setup.knockout = f["stage"] == "ko" or f["stage"] == "third"
	setup.human_side = "home" if f["home"] == user_team_id else "away"
	if career != null:              # transfers v2: a loanee with the clause does not play against his own club
		setup.excluded = career.market.blocked_against(f["home"], f["away"]) + career.market.blocked_against(f["away"], f["home"])
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

func save_game(path := "") -> String:
	if path == "":
		path = save_path()
	if is_advancing():
		return Loc.t("HUB_WEEK_IN_PROGRESS")
	var backup_err := SaveManager.backup_if_outdated(path)      # an older save is copied before it is replaced
	if backup_err != "":
		return backup_err
	var club_name := ""
	if career != null and db.get_team(career.club_id) != null:
		club_name = db.get_team(career.club_id).display_name
	var extras := {"meta": {"club": club_name, "season": career.season if career != null else 0, "week": career.week if career != null else 0,
			"saved_unix": int(Time.get_unix_time_from_system())}, "user_team_id": user_team_id, "world": {"pack_id": db.pack_id, "pack_version": str(db.pack_info.get("version", ""))}}
	if career != null:
		# Never write a career that fails its integrity audit: the old file (a good save) must not be replaced by a bad one.
		var audit := CareerValidator.validate(career, false)
		if not (audit["errors"] as Array).is_empty():
			push_warning("career not saved, integrity audit failed: %s" % str((audit["errors"] as Array).slice(0, 3)))
			return Loc.f("HUB_SAVE_REFUSED", [str((audit["errors"] as Array)[0])])
		extras["career"] = career.to_dict()
	var data := SaveManager.capture(db, academies, scouting, training, squads, extras)
	return SaveManager.write_file(path, data)


func load_game(path: String = "") -> String:
	if path == "":
		path = latest_save_path() if latest_save_path() != "" else save_path()
	if is_advancing():
		return Loc.t("HUB_WEEK_IN_PROGRESS")
	var backup_err := SaveManager.backup_if_outdated(path)      # keep the original of a save written by an older version
	if backup_err != "":
		return backup_err
	var rd := SaveManager.read_file(path)
	if not rd["ok"]:
		return rd["error"]
	var save_world := SaveManager.world_of(rd["data"])
	if save_world != db.pack_id:
		# The save belongs to another world than the one loaded: load that world first (clubs AND leagues).
		if save_world != "" and not TeamDatabase.available_packs().any(func(p: Dictionary) -> bool: return p["id"] == save_world):
			return Loc.f("HUB_SAVE_WORLD_MISSING", save_world)
		db.load_world(save_world)
		TeamDatabase.save_pack_choice(save_world)
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
	_auto_trigger()                            # Phase K5: autosave after every match
	state_changed.emit()


## Quick simulation of a fixture without the 3D engine (strength-weighted).
func simulate_fixture(competition_id: String, match_id: String, seed_value: int = 0) -> String:
	if career == null or not career.competitions.has(competition_id):
		return "no such competition"
	var comp: Competition = career.competitions[competition_id]
	var f := comp.get_fixture(match_id)
	if f.is_empty():
		return "unknown match"
	var err := career.submit_result(competition_id, MatchSimulator.career_result(career, f, seed_value))
	if err == "":
		_auto_trigger()
	return err


## Kept for callers of the old helper (match setup screen).
func _goals(rng: RandomNumberGenerator, edge: int) -> int:
	return MatchSimulator.goals(rng, edge)
