## Main menu controller — Phase 1 foundations only.
## Play / Quit are functional. Settings is deliberately disabled until a
## settings system exists in a later phase.
extends Control

@onready var _play: Button = %PlayButton
@onready var _settings: Button = %SettingsButton
@onready var _quit: Button = %QuitButton


func _ready() -> void:
	_play.pressed.connect(_on_play_pressed)
	_settings.pressed.connect(_on_settings_pressed)
	_quit.pressed.connect(_on_quit_pressed)
	_play.grab_focus()


func _on_play_pressed() -> void:
	GameManager.start_match()


func _on_settings_pressed() -> void:
	# Guard: this button must never accidentally trigger a nonexistent system.
	push_warning("Settings are not implemented yet — coming in a later phase.")


func _on_quit_pressed() -> void:
	GameManager.quit_game()
