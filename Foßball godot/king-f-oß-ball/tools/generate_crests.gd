## Developer tool: (re)generates data/crests/crests.json, the shipped crest records, from the
## clubs of every shipped world. Deterministic: same clubs -> same file. Run it again only when
## shipped clubs change; existing crest ids/designs of unchanged clubs stay identical because the
## design is derived from the club id (clubs are processed in id order).
##   godot --headless --path . res://tools/generate_crests.tscn
extends Node


func _ready() -> void:
	await get_tree().process_frame
	var db: TeamDatabase = get_node("/root/TeamDB")
	var gen := CrestRegistry.new()
	gen.load_blocklist()
	var used := {}
	var out: Array = []
	for world in ["", "real_2025"]:
		db.load_world(world)
		for t: TeamData in db.list_teams(TeamData.Category.CLUB):
			var c := CrestGenerator.generate(t.id, t.primary_color, t.secondary_color, t.accent_color, t.is_real,
					used, gen.blocked_symbols(t.id))
			out.append(c.to_dict())
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["crest_id"] < b["crest_id"])
	var f := FileAccess.open(CrestRegistry.CRESTS_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "note": "Original generated crest records. Not official artwork and not affiliated with any club. Regenerate with tools/generate_crests.tscn.", "crests": out}, " ", true))
	f.close()
	print("wrote %d crests to %s" % [out.size(), CrestRegistry.CRESTS_PATH])
	get_tree().quit()
