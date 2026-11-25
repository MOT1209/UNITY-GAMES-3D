## Prints the home striker every second: depth, 2nd-last-defender line, owner side, intent, speed. Not a test.
extends Node

func _ready() -> void:
	await get_tree().process_frame
	var db: Node = get_node("/root/TeamDB")
	db.reload()
	var setup := MatchSetup.new()
	setup.home_id = "club_royal_harbor"
	setup.away_id = "club_northgate_utd"
	setup.duration_minutes = 5
	setup.human_side = "none"
	setup.difficulty = 1
	setup.rng_seed = 300
	seed(300)
	var m := MatchManager.new()
	m.return_to_menu_on_finish = false
	add_child(m)
	m.begin(setup, db)
	print("formation home ", m.sides["home"]["formation"])
	var st: Dictionary = {}
	for e in m.entries["home"]:
		if FormationData.slot_position(m.sides["home"]["formation"], int(e["slot"])) == PlayerData.Position.ST:
			st = e
			break
	var r := m.rules.restarts
	for f in 60 * 45:
		await get_tree().physics_frame
		if f % 60 != 0:
			continue
		var opp: Array[float] = []
		for o in m.entries["away"]:
			opp.append(r._depth((o["node"] as Node3D).global_position.z, "home"))
		opp.sort()
		opp.reverse()
		var n := st["node"] as CharacterBody3D
		var own := m._owner_entry()
		print("t=%2d phase=%d owner=%s poss=%s | ST depth %.1f line %.1f ball %.1f | intent %s cmd_move %s sprint %s | speed %.1f" % [f / 60, m.state.phase, own.get("side", "-"), m._possession_side, r._depth(n.global_position.z, "home"), opp[1], r._depth(m.ball.global_position.z, "home"), st.get("intent", "?"), str((st["cmd"] as Dictionary).get("move", "-")), str((st["cmd"] as Dictionary).get("sprint", "-")), Vector2(n.velocity.x, n.velocity.z).length()])
	get_tree().quit()
