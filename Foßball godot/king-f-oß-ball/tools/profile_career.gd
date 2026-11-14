## Developer tool: measures where a career week spends its time (performance aid).
##   godot --headless --path . res://tools/profile_career.tscn -- [weeks]
## Loads the real pack, starts a career and times the parts of a week.
extends Node


func _ready() -> void:
	await get_tree().process_frame
	var weeks := 5
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		weeks = int(a[0])
	var db: TeamDatabase = get_node("/root/TeamDB")
	var t0 := Time.get_ticks_msec()
	db.load_world("real_2025")
	print("load_world: %d ms" % (Time.get_ticks_msec() - t0))
	print("clubs: %d  players: %d" % [db.teams.size(), db.players.size()])

	t0 = Time.get_ticks_msec()
	var c := CareerState.start(db, "eng_leicester_city_fc")
	print("career start: %d ms" % (Time.get_ticks_msec() - t0))

	t0 = Time.get_ticks_msec()
	var sweep := 0
	for t: TeamData in db.list_teams(TeamData.Category.CLUB):
		sweep += db.get_team_rating(t.id)
	print("rating sweep over all clubs: %d ms (sum %d)" % [Time.get_ticks_msec() - t0, sweep])

	t0 = Time.get_ticks_msec()
	var offers := c.job_offers()
	print("job_offers: %d ms (%d offers)" % [Time.get_ticks_msec() - t0, offers.size()])

	for w in weeks:
		t0 = Time.get_ticks_msec()
		c.advance_week()
		print("week %d: %d ms" % [w + 1, Time.get_ticks_msec() - t0])
	get_tree().quit()
