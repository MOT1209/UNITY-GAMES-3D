## Command-line database tool (database phase 7). Every command is a thin call into DatabaseTools.
##   godot --headless --path . res://tools/db_cli.tscn -- <command> [args]
## Commands (world = real_2025 by default; add "world=default" or "world=<pack id>" anywhere):
##   validate                      critical errors and warnings; exit code 1 when there are critical errors
##   stats                         counts by type / country / division / position
##   search-club <text>            clubs whose name or id contains the text
##   search-player <text>          players by name or id (best first, max 20)
##   export <file.json>            whole-database snapshot
##   import <file.json> [dry]      adds the records of a package (all-or-nothing); "dry" only checks
##   generate <seed> <per_country> <file.json>   fictional clubs/players as an importable package
extends Node


func _ready() -> void:
	await get_tree().process_frame
	var args: Array = []
	var world := "real_2025"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("world="):
			world = a.trim_prefix("world=")
		else:
			args.append(a)
	var db: TeamDatabase = get_node("/root/TeamDB")
	db.load_world("" if world == "default" else world)
	var code := _run(db, args)
	get_tree().quit(code)


func _run(db: TeamDatabase, args: Array) -> int:
	if args.is_empty():
		print("usage: db_cli <validate|stats|search-club|search-player|export|import|generate> ...")
		return 2
	match str(args[0]):
		"validate":
			var r := DatabaseTools.validate_all(db)
			print("checked: %s" % str(r["checked"]))
			for w in r["warnings"]:
				print("WARNING: %s" % w)
			for c in (r["critical"] as Array).slice(0, 40):
				print("CRITICAL: %s" % c)
			print("critical errors: %d, warnings: %d" % [(r["critical"] as Array).size(), (r["warnings"] as Array).size()])
			return 1 if not (r["critical"] as Array).is_empty() else 0
		"stats":
			var s := DatabaseTools.stats(db)
			print(JSON.stringify(s, "  ", true))
			return 0
		"search-club":
			for t in DatabaseTools.search_clubs(db, {"text": str(args[1]) if args.size() > 1 else "", "limit": 30}):
				print("%s | %s | %s | %s" % [t.id, t.display_name, t.country, t.league_id])
			return 0
		"search-player":
			for p in DatabaseTools.search_players(db, {"text": str(args[1]) if args.size() > 1 else "", "limit": 20}):
				print("%s | %s | %s %d | %s" % [p.id, p.display_name, PlayerData.Position.keys()[p.position], p.get_overall(), p.team_id])
			return 0
		"export":
			if args.size() < 2:
				print("export needs a file path")
				return 2
			var err := DatabaseTools.export_snapshot(db, str(args[1]))
			print("exported %d clubs/teams and %d players to %s" % [db.teams.size(), db.players.size(), args[1]] if err == "" else err)
			return 0 if err == "" else 1
		"import":
			if args.size() < 2:
				print("import needs a file path")
				return 2
			var res := DatabaseTools.import_package(db, str(args[1]), args.size() > 2 and str(args[2]) == "dry")
			if res["ok"]:
				print("%s %d teams and %d players" % ["would add" if args.size() > 2 else "added", res["teams"], res["players"]])
				return 0
			for e in res["errors"]:
				print("ERROR: %s" % e)
			return 1
		"generate":
			if args.size() < 4:
				print("generate needs <seed> <per_country> <file.json>")
				return 2
			var g := DatabaseTools.generate_package(db, int(args[1]), int(args[2]), str(args[3]))
			print("generated %d clubs and %d players into %s" % [g["teams"], g["players"], args[3]] if g["ok"] else g["error"])
			return 0 if g["ok"] else 1
	print("unknown command '%s'" % args[0])
	return 2
