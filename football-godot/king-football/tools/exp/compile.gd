extends Node
func _ready() -> void:
	for f in ["scripts/systems/competitions/match_event_engine.gd", "scripts/ui/match/pause_menu.gd", "scripts/systems/match/match_menus.gd", "scripts/ui/app_hub.gd", "scripts/ui/screens/settings_screen.gd", "scripts/ui/screens/live_match_screen.gd", "scripts/ui/screens/team_center_screen.gd",
			"scripts/ui/match/match_radar.gd", "scripts/ui/match/match_hud.gd", "scripts/systems/match/match_manager.gd", "scripts/systems/career/season_stats.gd",
			"scripts/systems/career/career_state.gd", "scripts/ui/screens/career_screen.gd", "scripts/ui/hub/screen_registry.gd"]:
		var s: Script = load("res://" + f)
		print("LOAD %s %s" % [f.get_file(), "ok" if s != null and s.can_instantiate() else "FAILED"])
	get_tree().quit()
