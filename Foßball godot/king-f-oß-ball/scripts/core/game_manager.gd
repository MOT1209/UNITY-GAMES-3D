## Autoload singleton (registered in project.godot as "GameManager").
## The autoload name IS the global name — no class_name is declared, because
## a class_name identical to an autoload hides it and fails to compile in Godot 4.7.
extends Node
##
## Phase 1 responsibilities ONLY:
##   - Owning the global game state.
##   - Scene transitions between the main menu and the prototype stadium.
##   - One documented exit point for quitting the game.
##
## Deliberately NOT implemented here yet (later phases):
##   - Match management, score/teams, pause systems, save data, multiplayer.

signal state_changed(state: State)
## Emitted by the match engine when a configured match ends (Phase T11).
signal match_finished(result)

enum State {
	BOOT,
	MAIN_MENU,
	IN_MATCH,
}

const SCENE_MAIN := "res://scenes/main/main.tscn"
const SCENE_STADIUM := "res://scenes/stadium/stadium_arena.tscn"
const SCENE_STADIUM_PROTOTYPE := "res://scenes/stadium/stadium_prototype.tscn"
const SCENE_MATCH := "res://scenes/match/match_scene.tscn"

## Setup handed to the match scene by `start_configured_match()`.
var pending_match_setup: MatchSetup = null
## Result of the most recent configured match (read by career/competition flows).
var last_match_result: MatchResult = null

var state: State = State.BOOT:
	set(value):
		if state == value:
			return
		state = value
		state_changed.emit(state)


func _ready() -> void:
	# The project boots straight into scenes/main/main.tscn (the menu),
	# so mark the boot state as resolved once the autoload is alive.
	state = State.MAIN_MENU


## Starts the prototype match scene (the stadium).
func start_match() -> void:
	_transition_to(SCENE_STADIUM, State.IN_MATCH)


## Starts a full match from a `MatchSetup` (teams, squads, tactics, rules).
func start_configured_match(setup: MatchSetup) -> void:
	pending_match_setup = setup
	_transition_to(SCENE_MATCH, State.IN_MATCH)


## Returns to the main menu scene.
func return_to_menu() -> void:
	_transition_to(SCENE_MAIN, State.MAIN_MENU)


## Quits the application from a single, documented place.
func quit_game() -> void:
	get_tree().quit()


func _transition_to(scene_path: String, new_state: State) -> void:
	if not ResourceLoader.exists(scene_path):
		push_error("GameManager: scene does not exist: %s" % scene_path)
		return
	var err := get_tree().change_scene_to_file(scene_path)
	if err != OK:
		push_error("GameManager: failed to change scene to %s (error %s)" % [scene_path, err])
		return
	state = new_state
	state_changed.emit(state)
