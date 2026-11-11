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
	_add_hub_button()
	_play.grab_focus()


## Adds the Phase T10 management entry (career, squad, academy, transfers...).
func _add_hub_button() -> void:
	var box := _play.get_parent()
	var hub := MenuItemButton.new()
	hub.name = "HubButton"
	hub.text = "Management Hub"
	hub.custom_minimum_size = _play.custom_minimum_size
	hub.add_theme_font_size_override("font_size", 24)
	hub.pressed.connect(_on_hub_pressed)
	box.add_child(hub)
	box.move_child(hub, _play.get_index() + 1)


func _on_hub_pressed() -> void:
	get_tree().change_scene_to_file("res://ui/hub/hub.tscn")


func _on_play_pressed() -> void:
	GameManager.start_match()


func _on_settings_pressed() -> void:
	# Guard: this button must never accidentally trigger a nonexistent system.
	push_warning("Settings are not implemented yet — coming in a later phase.")


func _on_quit_pressed() -> void:
	GameManager.quit_game()
