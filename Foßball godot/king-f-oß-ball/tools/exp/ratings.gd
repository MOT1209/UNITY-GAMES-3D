extends Node
func _ready() -> void:
	var db: Node = get_node("/root/TeamDB"); db.reload()
	for t in db.list_teams():
		print("%s %d" % [t.id, db.get_team_rating(t.id)])
	get_tree().quit()
