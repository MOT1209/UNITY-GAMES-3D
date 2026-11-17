extends Node
func _ready() -> void:
	for f in ["res://scripts/systems/career/daily_life.gd", "res://scripts/systems/career/training_plan.gd", "res://scripts/systems/career/career_calendar.gd",
			"res://scripts/systems/career/career_state.gd", "res://scripts/systems/career/career_flow.gd", "res://scripts/ui/screens/calendar_screen.gd",
			"res://scripts/ui/screens/career_screen.gd", "res://scripts/systems/career/season_stats.gd", "res://scripts/systems/career/availability.gd",
			"res://scripts/systems/transfers/transfer_market.gd", "res://scripts/systems/competitions/league_pyramid.gd", "res://scripts/systems/competitions/competition.gd",
			"res://scripts/ui/app_hub.gd", "res://scripts/systems/career/career_date.gd", "res://scripts/systems/competitions/career_schedule.gd"]:
		var s: Script = load(f)
		print("LOAD %s %s" % [f.get_file(), "ok" if s != null and s.can_instantiate() else "FAILED"])
	get_tree().quit()
