## Developer tool: finds generated players whose name duplicates (or looks too much like) another player's
## name and proposes a new, unique one. Real players (`tm_*`) are never renamed. Deterministic: the new
## name of a player depends only on the player's id and the names already taken.
##   godot --headless --path . res://tools/dedupe_names.tscn -- <output.json>
## Writes {"renames": {player_id: new_name}, ...}; apply it to the pack files with
## tools/apply_renames.py (keeps the pack JSON formatting).
extends Node


func _ready() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var out_path := args[0] if args.size() > 0 else "user://renames.json"
	var db: TeamDatabase = get_node("/root/TeamDB")
	db.load_world("real_2025")
	var ids: Array = db.players.keys()
	ids.sort()
	var index := NameIndex.new()
	for pid: String in ids:
		if not (pid as String).begins_with("gen_"):
			index.add((db.players[pid] as PlayerData).display_name)
	var gen_n := 0
	var renames := {}
	var unresolved := 0
	for pid: String in ids:
		if not (pid as String).begins_with("gen_"):
			continue
		gen_n += 1
		var p: PlayerData = db.players[pid]
		if index.check(p.display_name) == "":
			index.add(p.display_name)
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("rename|" + pid)
		var country: String = p.nationality if NameBank.has_pool(p.nationality) else "England"
		var fresh := ""
		for i in 400:
			var cand := NameBank.random_name(rng, country)
			if index.check(cand) == "":
				fresh = cand
				break
		if fresh == "":
			unresolved += 1
			continue
		index.add(fresh)
		renames[pid] = fresh
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"renames": renames, "unresolved": unresolved}, "\t"))
	f.close()
	print("generated players seen: %d, renames: %d, unresolved: %d" % [gen_n, renames.size(), unresolved])
	get_tree().quit()
