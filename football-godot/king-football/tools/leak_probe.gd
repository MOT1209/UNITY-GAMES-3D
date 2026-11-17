## Developer tool: finds what keeps the world alive at shutdown (leak probe).
##   godot --headless --path . res://tools/leak_probe.tscn -- [clean]
## Without "clean" it only reports the sizes; with "clean" it releases the
## static caches and the database before quitting, to see what the leak is.
extends Node


func _ready() -> void:
	await get_tree().process_frame
	var db: TeamDatabase = get_node("/root/TeamDB")
	db.load_world("real_2025")
	print("players=%d teams=%d countries=%d leagues=%d" % [
			db.players.size(), db.teams.size(), db.countries.size(), db.leagues.size()])
	print("crest_cache=%d kit_cache=%d" % [CrestService.cache.size(), KitService.cache.size()])
	if OS.get_cmdline_user_args().has("clean"):
		CrestService.cache.clear()
		KitService.cache.clear()
		db.clear()
		print("cleaned")
	get_tree().quit()
