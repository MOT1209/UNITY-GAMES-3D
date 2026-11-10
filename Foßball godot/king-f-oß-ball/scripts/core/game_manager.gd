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

enum State {
	BOOT,
	MAIN_MENU,
	IN_MATCH,
}

const SCENE_MAIN := "res://scenes/main/main.tscn"
const SCENE_STADIUM := "res://scenes/stadium/stadium_prototype.tscn"

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
