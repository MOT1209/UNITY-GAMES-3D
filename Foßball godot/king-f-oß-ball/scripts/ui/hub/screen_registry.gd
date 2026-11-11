class_name ScreenRegistry
extends RefCounted

## id -> [title, script path]. Order = navigation order in the hub.
const SCREENS := {
	"team_select": ["Team Selection", "res://scripts/ui/screens/team_select_screen.gd"],
	"team_details": ["Team Details", "res://scripts/ui/screens/team_details_screen.gd"],
	"squad": ["Squad Management", "res://scripts/ui/screens/squad_screen.gd"],
	"tactics": ["Tactical Formation", "res://scripts/ui/screens/tactics_screen.gd"],
	"player_profile": ["Player Profile", "res://scripts/ui/screens/player_profile_screen.gd"],
	"academy": ["Youth Academy", "res://scripts/ui/screens/academy_screen.gd"],
	"scouting": ["Youth Scouting", "res://scripts/ui/screens/scouting_screen.gd"],
	"training": ["Youth Training", "res://scripts/ui/screens/training_screen.gd"],
	"promotion": ["Promotion", "res://scripts/ui/screens/promotion_screen.gd"],
	"competitions": ["Competitions", "res://scripts/ui/screens/competitions_screen.gd"],
	"standings": ["League Standings", "res://scripts/ui/screens/standings_screen.gd"],
	"bracket": ["Tournament Bracket", "res://scripts/ui/screens/bracket_screen.gd"],
	"career": ["Career Dashboard", "res://scripts/ui/screens/career_screen.gd"],
	"transfers": ["Transfer Market", "res://scripts/ui/screens/transfers_screen.gd"],
	"finance": ["Club Finance", "res://scripts/ui/screens/finance_screen.gd"],
	"customize": ["Team Customization", "res://scripts/ui/screens/customize_screen.gd"],
	"kit_editor": ["Kit Editor", "res://scripts/ui/screens/kit_editor_screen.gd"],
	"match_setup": ["Match Setup", "res://scripts/ui/screens/match_setup_screen.gd"],
}
## Screens shown in the navigation bar (player_profile needs a parameter).
const NAV_HIDDEN: Array[String] = ["player_profile", "standings", "bracket"]


static func create(id: String) -> HubScreen:
	if not SCREENS.has(id):
		return null
	var script: Script = load(SCREENS[id][1])
	return script.new() as HubScreen
