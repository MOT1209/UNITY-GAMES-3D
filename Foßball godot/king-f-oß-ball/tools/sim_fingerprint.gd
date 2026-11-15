## Developer tool: determinism fingerprint of a simulated career (regression check for pure performance refactors).
##   godot --headless --path . res://tools/sim_fingerprint.tscn -- [seasons] [pack]
## Plays `seasons` seasons (default 2) without any user input and prints, after every season, a SHA-256 of the whole
## career state (`CareerState.to_dict()`, keys sorted) and of the player database (team, age, status, contract,
## salary, attributes). Two builds that print the same lines simulate identically.
extends Node


func _ready() -> void:
	await get_tree().process_frame
	var seasons := 2
	var pack := "real_2025"
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		seasons = int(a[0])
	if a.size() > 1:
		pack = "" if a[1] == "fictional" else a[1]
	var db: TeamDatabase = get_node("/root/TeamDB")
	db.load_world(pack)
	var club: String = db.list_teams(TeamData.Category.CLUB)[0].id
	if pack == "real_2025":
		club = "eng_leicester_city_fc"
	var c := CareerState.start(db, club)
	if c.pyramids.is_empty():
		c.add_default_league()
	for s in seasons:
		for w in CareerState.WEEKS_PER_SEASON:
			c.advance_week()
			if w == 22:
				print("season %d week 23: career %s players %s" % [s + 1, _career_hash(c), _players_hash(db)])
		c.end_season()
		print("season %d end: career %s players %s" % [s + 1, _career_hash(c), _players_hash(db)])
	get_tree().quit()


static func _career_hash(c: CareerState) -> String:
	return JSON.stringify(_scrub(c.to_dict()), "", true).sha256_text().substr(0, 16)


## Drops the `est_*` bookkeeping fields (added after the baseline was recorded) so builds can be compared with old ones.
static func _scrub(v: Variant) -> Variant:
	if v is Dictionary:
		var out := {}
		for k in v:
			if not (k is String and ((k as String).begins_with("est_") or k == "world_stats_legacy")):
				out[k] = _scrub(v[k])
		return out
	if v is Array:
		return (v as Array).map(func(x: Variant) -> Variant: return _scrub(x))
	return v


static func _players_hash(db: TeamDatabase) -> String:
	var ids: Array = db.players.keys()
	ids.sort()
	var parts: PackedStringArray = []
	for id in ids:
		var p: PlayerData = db.players[id]
		parts.append("%s|%s|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d" % [id, p.team_id, p.age, p.status, p.unavailable_weeks,
				p.contract_years, p.salary, p.pace, p.shooting, p.passing, p.dribbling, p.defending, p.physical, p.goalkeeping])
	return "\n".join(parts).sha256_text().substr(0, 16)
