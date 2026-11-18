## Phone readiness: the Android back button never quits the game by itself, phones start with light graphics,
## and the hub, main menu and touch controls stay out of the display cut-out (notch / rounded corners).
##   godot --headless --path . res://tests/mobile_validation.tscn
extends Node

const TEST_SETTINGS := "user://test_mobile_settings.cfg"

var _passed := 0
var _failed := 0


func _check(ok: bool, name: String, detail := "") -> void:
	if ok:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s%s" % [name, (" — " + detail) if detail != "" else ""])


func _ready() -> void:
	await get_tree().process_frame
	print("=== KING FOOTBALL — Mobile validation ===")
	_test_back_button_setting()
	_test_graphics_defaults()
	await _test_hub_safe_area()
	await _test_menu_back_button()
	UIKit.force_insets = {}
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _test_back_button_setting() -> void:
	_check(ProjectSettings.get_setting("application/config/quit_on_go_back", true) == false,
			"Android back does not quit the app by itself (the screens handle it)")
	var src := (load("res://scripts/systems/match/match_manager_part1.gd") as GDScript).source_code
	_check(src.contains("NOTIFICATION_WM_GO_BACK_REQUEST") and src.contains("toggle_pause_from_controller.call_deferred()"),
			"in a match, Android back pauses / resumes")


func _test_graphics_defaults() -> void:
	var original := GameSettings.settings_path
	GameSettings.settings_path = TEST_SETTINGS
	DirAccess.remove_absolute(TEST_SETTINGS)
	GameSettings.force_mobile = true
	var g := GameSettings.section("graphics")
	_check(g["shadows"] == "low" and int(g["msaa"]) == 0 and is_equal_approx(float(g["render_scale"]), 0.75),
			"phones start with light graphics (low shadows, no MSAA, 75 % render scale)", str(g))
	GameSettings.set_value("graphics", "shadows", "high")
	_check(GameSettings.get_value("graphics", "shadows") == "high", "a phone player can still raise the quality")
	GameSettings.force_mobile = false
	DirAccess.remove_absolute(TEST_SETTINGS)
	_check(GameSettings.section("graphics")["shadows"] == "high", "desktops keep the high defaults")
	GameSettings.settings_path = original


func _test_hub_safe_area() -> void:
	UIKit.force_insets = {"left": 40.0, "top": 0.0, "right": 30.0, "bottom": 10.0}
	var hub := (load("res://ui/hub/hub.tscn") as PackedScene).instantiate() as HubRoot
	add_child(hub)
	await get_tree().process_frame
	var box: Control = hub.get("_root_box")
	_check(box != null and is_equal_approx(box.offset_left, 52.0) and is_equal_approx(box.offset_right, -42.0)
			and is_equal_approx(box.offset_bottom, -22.0), "the hub frame stays out of the notch on every side",
			"%s" % [[box.offset_left, box.offset_right, box.offset_bottom] if box else "null"])
	hub.queue_free()
	var tc := TouchControls.new()
	add_child(tc)
	tc.set_active(true)
	await get_tree().process_frame
	var stick := tc.find_child("Joystick", true, false) as Control
	var pause := tc.find_child("Btn_pause", true, false) as Control
	_check(stick != null and is_equal_approx(stick.offset_left, 64.0) and is_equal_approx(stick.offset_bottom, -34.0),
			"touch stick keeps clear of the left cut-out")
	_check(pause != null and is_equal_approx(pause.offset_right, -54.0), "touch pause button keeps clear of the right cut-out")
	tc.queue_free()
	await get_tree().process_frame


func _test_menu_back_button() -> void:
	UIKit.force_insets = {}
	var menu: Control = load("res://ui/main_menu/main_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	(menu.get_node("%SettingsButton") as Button).pressed.emit()
	await get_tree().process_frame
	menu.propagate_notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	await get_tree().process_frame
	_check(menu.get_node_or_null("SettingsPanel") == null and menu.get_node_or_null("QuitConfirm") == null,
			"main menu: back closes the open settings first")
	menu.propagate_notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	await get_tree().process_frame
	_check(menu.get_node_or_null("QuitConfirm") != null, "main menu: back then asks before leaving the game")
	menu.queue_free()
	await get_tree().process_frame
