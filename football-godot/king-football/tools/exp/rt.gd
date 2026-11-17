extends Node
func _ready() -> void:
	await get_tree().process_frame
	var app: Node = get_node("/root/AppHub")
	app.switch_world("")
	app.start_career("club_desert_kings")
	for i in 8: app.advance_week()
	var c: CareerState = app.career
	var a: Dictionary = c.to_dict()
	var c2 := CareerState.from_dict(app.db, JSON.parse_string(JSON.stringify(a)))
	var b: Dictionary = c2.to_dict()
	for k in a:
		if JSON.stringify(a[k], "", true) != JSON.stringify(b.get(k), "", true):
			print("RT differs: ", k)
			var sa := JSON.stringify(a[k], "", true)
			var sb := JSON.stringify(b.get(k), "", true)
			var n := 0
			while n < sa.length() and n < sb.length() and sa[n] == sb[n]: n += 1
			print("   a: ", sa.substr(maxi(n - 60, 0), 160).replace("\n", " "))
			print("   b: ", sb.substr(maxi(n - 60, 0), 160).replace("\n", " "))
	get_tree().quit()
