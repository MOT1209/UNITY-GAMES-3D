extends Node

func _ready() -> void:
	await get_tree().process_frame
	var db: TeamDatabase = get_node("/root/TeamDB")
	var pack := "real_2025"
	var a := OS.get_cmdline_user_args()
	if a.size() > 0 and a[0] == "fictional":
		pack = ""
	db.load_world(pack)
	var club: String = "eng_leicester_city_fc" if pack != "" else db.list_teams(TeamData.Category.CLUB)[0].id
	var c := CareerState.start(db, club)
	if c.pyramids.is_empty():
		c.add_default_league()
	for stage in [0, 1, 23, 46, 47, 70]:
		if stage == 47:
			c.end_season()
		elif stage == 70:
			for _w in 24: c.advance_week()
		while c.week < stage and stage < 47:
			c.advance_week()
		var before := JSON.stringify(c.to_dict(), "", true)
		var data := SaveManager.capture(db, {}, {}, {}, {}, {"career": c.to_dict()})
		var txt := JSON.stringify(data, "", true, true)
		var parsed: Dictionary = JSON.parse_string(txt)
		var m := SaveManager.migrate(parsed)
		var errs := SaveManager.validate(m)
		var res := SaveManager.restore(db, m)
		if not res["ok"]:
			print("   RESTORE FAILED: ", str(res["errors"]).left(1500))
			break
		var c2 := CareerState.from_dict(db, res["extras"]["career"])
		var after := JSON.stringify(c2.to_dict(), "", true)
		var aud := CareerValidator.validate(c)
		print("   audit: %d errors, %d warnings %s %s" % [aud["errors"].size(), aud["warnings"].size(), str(aud["errors"].slice(0, 3)), str(aud["warnings"].slice(0, 3))])
		print("stage week %d: save %d KB, validate errs %d, restore ok %s, career round trip equal: %s" % [stage, txt.length() / 1024, errs.size(), res["ok"], before == after])
		if before != after:
			var d1 := c.to_dict(); var d2 := c2.to_dict()
			for k in d1:
				if JSON.stringify(d1[k], "", true) != JSON.stringify(d2.get(k), "", true):
					print("   differs: ", k)
					_diff(d1[k], d2.get(k), k, 0)
	get_tree().quit()


var _shown := 0
func _diff(a: Variant, b: Variant, path: String, depth: int) -> void:
	if _shown > 40:
		return
	if typeof(a) != typeof(b):
		print("      %s: type %d vs %d (%s vs %s)" % [path, typeof(a), typeof(b), str(a).left(60), str(b).left(60)])
		_shown += 1
		return
	if a is Dictionary:
		for k in a:
			if not (b as Dictionary).has(k):
				print("      %s: key '%s' missing after reload" % [path, k]); _shown += 1; return
			_diff(a[k], b[k], path + "/" + str(k), depth + 1)
		for k in b:
			if not (a as Dictionary).has(k):
				print("      %s: key '%s' new after reload" % [path, k]); _shown += 1; return
	elif a is Array:
		if a.size() != b.size():
			print("      %s: size %d vs %d" % [path, a.size(), b.size()]); _shown += 1; return
		for i in a.size():
			_diff(a[i], b[i], path + "[%d]" % i, depth + 1)
	elif a != b:
		print("      %s: %s vs %s" % [path, str(a).left(60), str(b).left(60)]); _shown += 1
