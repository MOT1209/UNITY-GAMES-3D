extends Node

## Boot script of scenes/match/match_scene.tscn: reads the pending setup from
## GameManager (or builds a default friendly) and starts a MatchManager.

func _ready() -> void:
	var db := get_node("/root/TeamDB")
	var gm := get_node("/root/GameManager")
	var setup: MatchSetup = gm.get("pending_match_setup")
	if setup == null:
		var clubs: Array[TeamData] = db.list_teams(TeamData.Category.CLUB)
		if clubs.size() < 2:
			push_error("MatchScene: need at least two teams to start a match.")
			return
		setup = MatchSetup.new()
		setup.home_id = clubs[0].id
		setup.away_id = clubs[1].id
	gm.set("pending_match_setup", null)
	var manager := MatchManager.new()
	manager.name = "MatchManager"
	add_child(manager)
	var err := manager.begin(setup, db)
	if err != "":
		push_error("MatchScene: %s" % err)
		manager.queue_free()
