class_name ScreenRegistry
extends RefCounted

## id -> [title translation key, script path]. Order = navigation order in the hub.
const SCREENS := {
	"team_select": ["SCREEN_TEAM_SELECT", "res://scripts/ui/screens/team_select_screen.gd"],
	"career_wizard": ["SCREEN_CAREER_WIZARD", "res://scripts/ui/screens/career_wizard_screen.gd"],
	"team_details": ["SCREEN_TEAM_DETAILS", "res://scripts/ui/screens/team_details_screen.gd"],
	"squad": ["SCREEN_SQUAD", "res://scripts/ui/screens/squad_screen.gd"],
	"tactics": ["SCREEN_TACTICS", "res://scripts/ui/screens/tactics_screen.gd"],
	"player_profile": ["SCREEN_PLAYER_PROFILE", "res://scripts/ui/screens/player_profile_screen.gd"],
	"collection": ["SCREEN_COLLECTION", "res://scripts/ui/screens/player_collection_screen.gd"],
	"dev_hub": ["SCREEN_DEV_HUB", "res://scripts/ui/screens/dev_hub_screen.gd"],
	"dev_analytics": ["SCREEN_DEV_ANALYTICS", "res://scripts/ui/screens/dev_analytics_screen.gd"],
	"training_center": ["SCREEN_TRAINING_CENTER", "res://scripts/ui/screens/training_center_screen.gd"],
	"coaching_staff": ["SCREEN_COACHING_STAFF", "res://scripts/ui/screens/coaching_staff_screen.gd"],
	"coach_recruitment": ["SCREEN_COACH_RECRUITMENT", "res://scripts/ui/screens/coach_recruitment_screen.gd"],
	"academy": ["SCREEN_ACADEMY", "res://scripts/ui/screens/academy_screen.gd"],
	"youth_hub": ["SCREEN_YOUTH_HUB", "res://scripts/ui/screens/youth_hub_screen.gd"],
	"scouting": ["SCREEN_SCOUTING", "res://scripts/ui/screens/scouting_screen.gd"],
	"training": ["SCREEN_TRAINING", "res://scripts/ui/screens/training_screen.gd"],
	"promotion": ["SCREEN_PROMOTION", "res://scripts/ui/screens/promotion_screen.gd"],
	"competitions": ["SCREEN_COMPETITIONS", "res://scripts/ui/screens/competitions_screen.gd"],
	"leagues": ["SCREEN_LEAGUES", "res://scripts/ui/screens/leagues_screen.gd"],
	"standings": ["SCREEN_STANDINGS", "res://scripts/ui/screens/standings_screen.gd"],
	"bracket": ["SCREEN_BRACKET", "res://scripts/ui/screens/bracket_screen.gd"],
	"inbox": ["NAV_INBOX", "res://scripts/ui/screens/inbox_screen.gd"],
	"save_slots": ["NAV_SAVE_SLOTS", "res://scripts/ui/screens/save_slots_screen.gd"],
	"calendar": ["NAV_CALENDAR", "res://scripts/ui/screens/calendar_screen.gd"],
	"live_match": ["LIVE_TITLE", "res://scripts/ui/screens/live_match_screen.gd"],
	"team_center": ["NAV_TEAM_CENTER", "res://scripts/ui/screens/team_center_screen.gd"],
	"club_history": ["NAV_CLUB_HISTORY", "res://scripts/ui/screens/club_history_screen.gd"],
	"club_manage": ["NAV_CLUB_MANAGE", "res://scripts/ui/screens/club_manage_screen.gd"],
	"career": ["SCREEN_CAREER", "res://scripts/ui/screens/career_screen.gd"],
	"transfers": ["SCREEN_TRANSFERS", "res://scripts/ui/screens/transfers_screen.gd"],
	"finance": ["SCREEN_FINANCE", "res://scripts/ui/screens/finance_screen.gd"],
	"customize": ["SCREEN_CUSTOMIZE", "res://scripts/ui/screens/customize_screen.gd"],
	"kit_editor": ["SCREEN_KIT_EDITOR", "res://scripts/ui/screens/kit_editor_screen.gd"],
	"match_setup": ["SCREEN_MATCH_SETUP", "res://scripts/ui/screens/match_setup_screen.gd"],
	"database": ["SCREEN_DATABASE", "res://scripts/ui/screens/database_tools_screen.gd"],
	"settings": ["SCREEN_SETTINGS", "res://scripts/ui/screens/settings_screen.gd"],
}
## Navigation sections (UX phase 4.2) in order: id, title key, icon, screens. Screens not listed here
## (profile, standings, bracket) are reached from other screens.
## Navigation restructure (Nov 2026): 26 buttons -> 17. One-off screens (new career, team selection, friendly
## match) live in the main menu and on the career dashboard; detail screens open from their parent (PARENT).
const SECTIONS: Array = [
	["home", "NAV_SECTION_HOME", "home", ["career", "inbox", "calendar", "save_slots"]],
	["team", "NAV_SECTION_TEAM", "shirt", ["squad", "team_center", "dev_hub"]],
	["youth", "NAV_SECTION_YOUTH", "sprout", ["academy", "scouting"]],
	["competitions", "NAV_SECTION_COMPETITIONS", "trophy", ["leagues", "competitions", "club_history"]],
	["club", "NAV_SECTION_CLUB", "building", ["transfers", "finance", "club_manage", "kit_editor"]],
	["system", "NAV_SECTION_SYSTEM", "gear", ["settings", "database"]],
]
## Screens without their own navigation button -> the navigation entry that leads to them (highlighted while
## they are open, and their section stays expanded).
const PARENT := {
	"tactics": "squad", "team_details": "team_center", "collection": "team_center", "player_profile": "squad",
	"coaching_staff": "dev_hub", "coach_recruitment": "dev_hub", "dev_analytics": "dev_hub", "training_center": "dev_hub", "promotion": "academy", "training": "academy", "youth_hub": "academy", "customize": "kit_editor", "standings": "leagues", "bracket": "competitions",
	"team_select": "career", "career_wizard": "career", "match_setup": "career", "live_match": "career",
}
## Links shown at the top of a parent screen to the screens it now hosts (HubScreen.sub_links()).
const SUB_LINKS := {
	"career": ["match_setup", "team_select"],
}
## Screens shown as tabs of one page: a tab bar on top of each (HubScreen adds it after build()).
const TAB_GROUPS: Array = [
	["squad", "tactics"],
	["team_center", "team_details", "collection"],
	["academy", "youth_hub", "training", "promotion"],
	["dev_hub", "coaching_staff", "coach_recruitment", "dev_analytics", "training_center"],
	["kit_editor", "customize"],
]


## The tab group `screen_id` belongs to (empty when none).
static func tab_group(screen_id: String) -> Array:
	for g in TAB_GROUPS:
		if screen_id in g:
			return g
	return []


## The navigation entry that represents `screen_id` (itself, or its parent).
static func nav_entry(screen_id: String) -> String:
	return str(PARENT.get(screen_id, screen_id))


## Section id of a screen ("" when it has no navigation entry).
static func section_of(screen_id: String) -> String:
	var id := nav_entry(screen_id)
	for s in SECTIONS:
		if id in s[3]:
			return s[0]
	return ""


## Screens shown in the navigation bar (player_profile needs a parameter).
const NAV_HIDDEN: Array[String] = ["player_profile", "standings", "bracket", "live_match"]
## Screens for developers only: listed in the navigation in debug builds or when the hidden setting
## `[developer] enabled=true` is set in user://settings.cfg; never in a release build otherwise.
const DEVELOPER_ONLY: Array[String] = ["database"]

## -1 = decide from the build / setting; 0 / 1 = forced (tests).
static var force_developer := -1


static func developer_mode() -> bool:
	if force_developer >= 0:
		return force_developer == 1
	return OS.is_debug_build() or bool(GameSettings.get_value("developer", "enabled"))


## True when `id` gets a navigation button.
static func in_navigation(id: String) -> bool:
	if id in NAV_HIDDEN:
		return false
	return developer_mode() or not (id in DEVELOPER_ONLY)


static func create(id: String) -> HubScreen:
	if not SCREENS.has(id):
		return null
	var script: Script = load(SCREENS[id][1])
	return script.new() as HubScreen
