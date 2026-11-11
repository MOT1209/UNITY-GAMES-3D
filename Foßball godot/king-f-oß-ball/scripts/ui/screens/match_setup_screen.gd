extends HubScreen

## Match Setup (Friendly): teams, stadium, duration, difficulty, conditions.
## Start in the real 3D engine or simulate instantly.

var _home := 0
var _away := 1
var _duration := 2
var _difficulty := 1
var _human := 0
var _weather := 0


func build() -> void:
	add_child(UIKit.title("Match Setup — Friendly"))
	var teams := team_names()
	if teams.size() < 2:
		add_child(UIKit.empty_state("At least two teams are needed."))
		return
	if app().user_team_id != "" and _home == 0:
		_home = maxi(0, team_names().find(db().get_team(app().user_team_id).display_name))
	_away = clampi(_away, 0, teams.size() - 1)
	if _away == _home:
		_away = (_home + 1) % teams.size()
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 8)
	grid.add_child(UIKit.label("Home team", 15, UIKit.MUTED))
	var ho := UIKit.option(teams, _home, func(i: int) -> void: _home = i)
	ho.name = "HomeOption"
	grid.add_child(ho)
	grid.add_child(UIKit.label("Away team", 15, UIKit.MUTED))
	var ao := UIKit.option(teams, _away, func(i: int) -> void: _away = i)
	ao.name = "AwayOption"
	grid.add_child(ao)
	grid.add_child(UIKit.label("Stadium", 15, UIKit.MUTED))
	grid.add_child(UIKit.option(["Arena (default)"], 0))
	grid.add_child(UIKit.label("Duration (real minutes)", 15, UIKit.MUTED))
	var durations: Array = MatchSetup.ALLOWED_DURATIONS.map(func(d: int) -> String: return "%d min" % d)
	var dop := UIKit.option(durations, _duration, func(i: int) -> void: _duration = i)
	dop.name = "DurationOption"
	grid.add_child(dop)
	grid.add_child(UIKit.label("Difficulty", 15, UIKit.MUTED))
	grid.add_child(UIKit.option(MatchSetup.DIFFICULTIES, _difficulty, func(i: int) -> void: _difficulty = i))
	grid.add_child(UIKit.label("You control", 15, UIKit.MUTED))
	grid.add_child(UIKit.option(MatchSetup.SIDES, _human, func(i: int) -> void: _human = i))
	grid.add_child(UIKit.label("Weather", 15, UIKit.MUTED))
	grid.add_child(UIKit.option(["clear", "rain", "fog"], _weather, func(i: int) -> void: _weather = i))
	add_child(UIKit.panel(grid))
	var bar := UIKit.hbox(8)
	var start := UIKit.button("Start match (3D)", _start, 170)
	start.name = "StartMatch"
	bar.add_child(start)
	var quick := UIKit.button("Quick simulate", _quick, 150)
	quick.name = "QuickSim"
	bar.add_child(quick)
	add_child(bar)


func make_setup() -> MatchSetup:
	var s := MatchSetup.new()
	s.home_id = team_id_at(_home)
	s.away_id = team_id_at(_away)
	s.duration_minutes = MatchSetup.ALLOWED_DURATIONS[_duration]
	s.difficulty = _difficulty
	s.human_side = MatchSetup.SIDES[_human]
	s.conditions = {"weather": ["clear", "rain", "fog"][_weather], "time_of_day": "day"}
	s.rng_seed = randi()
	return s


func _start() -> void:
	var err: String = app().play_match(make_setup())
	if err != "":
		say(err, true)


func _quick() -> void:
	var s := make_setup()
	var problems := s.validate(db())
	if not problems.is_empty():
		say(problems[0], true)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = s.rng_seed
	var hr: int = db().get_team_rating(s.home_id) + 4
	var ar: int = db().get_team_rating(s.away_id)
	var hg: int = app()._goals(rng, hr - ar)
	var ag: int = app()._goals(rng, ar - hr)
	say("%s %d - %d %s" % [db().get_team(s.home_id).display_name, hg, ag, db().get_team(s.away_id).display_name])
