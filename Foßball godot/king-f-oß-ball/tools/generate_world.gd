## Developer tool: generates the fictional third divisions of the real_2025 pack (database phase 6).
## Deterministic: the same seed and the same real data always give the same files.
##   godot --headless --path . res://tools/generate_world.tscn -- [seed] [per_country]
## Writes data/packs/real_2025/fictional/{clubs/*.json, manifest.json}, adds the third division to the
## pack's leagues/*.json (and sets the second division's relegation places to match) and updates the
## counts in pack.json. Re-run it after rebuilding the pack with tools/import_real. Then run
## tools/generate_crests.tscn so the new clubs get crests.
extends Node

const PACK := "res://data/packs/real_2025"


func _ready() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/generation/config.json"))
	var world_seed := int(args[0]) if args.size() > 0 else int(cfg["world_seed"])
	var per_country := int(args[1]) if args.size() > 1 else int(cfg["per_country"])
	var db: TeamDatabase = get_node("/root/TeamDB")
	db.skip_fictional_layer = true
	db.load_world("real_2025")
	db.skip_fictional_layer = false
	var real_clubs := db.teams.size()
	var real_players := db.players.size()
	var cups := {}
	for key in WorldGenerator.cup_keys():
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("%s/leagues/%s.json" % [PACK, key]))
		cups[key] = str((d.get("cup", {}) as Dictionary).get("id", ""))
	var result := WorldGenerator.generate(db, world_seed, per_country, cups)
	# clear the old layer, write the new one
	var dir := PACK + "/fictional/clubs"
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute("%s/%s" % [dir, f])
	for entry in result["clubs"]:
		_write("%s/%s.json" % [dir, (entry["team"] as TeamData).id], WorldGenerator.club_file(entry, world_seed))
	_write(PACK + "/fictional/manifest.json", result["manifest"])
	# leagues: third division + matching relegation places of the second division
	for key in result["divisions"]:
		var path := "%s/leagues/%s.json" % [PACK, key]
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var divs: Array = (d["divisions"] as Array).filter(func(x: Dictionary) -> bool: return int(x["tier"]) < 3)
		divs[divs.size() - 1]["relegate"] = WorldGenerator.PROMOTE
		divs.append(result["divisions"][key])
		d["divisions"] = divs
		_write(path, d)
	# pack.json report
	var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PACK + "/pack.json"))
	var rep: Dictionary = info["report"]
	rep["clubs"] = real_clubs + int(result["manifest"]["clubs"])
	rep["players"] = real_players + int(result["manifest"]["players"])
	rep["fictional_clubs"] = int(result["manifest"]["clubs"])
	rep["fictional_players"] = int(result["manifest"]["players"])
	for country in WorldGenerator.THIRD_TIER:
		(rep["countries"][country.to_lower()] as Dictionary)[WorldGenerator.THIRD_TIER[country]["name"]] = per_country
	info["generated_note"] = "Second-tier players are generated with fictional names (the snapshot covers first tiers only). The third divisions (fictional/ folder) are entirely fictional: generated clubs and players, seed %d." % world_seed
	_write(PACK + "/pack.json", info)
	print("generated %d fictional clubs, %d players (seed %d) on top of %d real clubs / %d players" % [
			result["manifest"]["clubs"], result["manifest"]["players"], world_seed, real_clubs, real_players])
	get_tree().quit()


func _write(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, " ", true))
	f.close()
