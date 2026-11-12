class_name ScreenRegistry
extends RefCounted

## id -> [title translation key, script path]. Order = navigation order in the hub.
const SCREENS := {
	"team_select": ["SCREEN_TEAM_SELECT", "res://scripts/ui/screens/team_select_screen.gd"],
	"team_details": ["SCREEN_TEAM_DETAILS", "res://scripts/ui/screens/team_details_screen.gd"],
	"squad": ["SCREEN_SQUAD", "res://scripts/ui/screens/squad_screen.gd"],
	"tactics": ["SCREEN_TACTICS", "res://scripts/ui/screens/tactics_screen.gd"],
	"player_profile": ["SCREEN_PLAYER_PROFILE", "res://scripts/ui/screens/player_profile_screen.gd"],
	"collection": ["SCREEN_COLLECTION", "res://scripts/ui/screens/player_collection_screen.gd"],
	"academy": ["SCREEN_ACADEMY", "res://scripts/ui/screens/academy_screen.gd"],
	"scouting": ["SCREEN_SCOUTING", "res://scripts/ui/screens/scouting_screen.gd"],
	"training": ["SCREEN_TRAINING", "res://scripts/ui/screens/training_screen.gd"],
	"promotion": ["SCREEN_PROMOTION", "res://scripts/ui/screens/promotion_screen.gd"],
	"competitions": ["SCREEN_COMPETITIONS", "res://scripts/ui/screens/competitions_screen.gd"],
	"standings": ["SCREEN_STANDINGS", "res://scripts/ui/screens/standings_screen.gd"],
	"bracket": ["SCREEN_BRACKET", "res://scripts/ui/screens/bracket_screen.gd"],
	"career": ["SCREEN_CAREER", "res://scripts/ui/screens/career_screen.gd"],
	"transfers": ["SCREEN_TRANSFERS", "res://scripts/ui/screens/transfers_screen.gd"],
	"finance": ["SCREEN_FINANCE", "res://scripts/ui/screens/finance_screen.gd"],
	"customize": ["SCREEN_CUSTOMIZE", "res://scripts/ui/screens/customize_screen.gd"],
	"kit_editor": ["SCREEN_KIT_EDITOR", "res://scripts/ui/screens/kit_editor_screen.gd"],
	"match_setup": ["SCREEN_MATCH_SETUP", "res://scripts/ui/screens/match_setup_screen.gd"],
	"settings": ["SCREEN_SETTINGS", "res://scripts/ui/screens/settings_screen.gd"],
}
## Screens shown in the navigation bar (player_profile needs a parameter).
const NAV_HIDDEN: Array[String] = ["player_profile", "standings", "bracket"]


static func create(id: String) -> HubScreen:
	if not SCREENS.has(id):
		return null
	var script: Script = load(SCREENS[id][1])
	return script.new() as HubScreen
