class_name DatabaseTools
extends RefCounted

## Developer-facing database operations (database phase 7). No UI in here: the Database screen and
## `tools/db_cli.gd` are thin layers over these functions, so everything is testable and the screen
## can never do something the command line cannot.
##
## validate_all / stats / search_clubs / search_players / club_profile / player_profile /
## set_club_metadata / export_snapshot / import_package / generate_package / crest_report.

const SNAPSHOT_FORMAT := "king_database_snapshot"
const SNAPSHOT_VERSION := 1
## Club fields `set_club_metadata` may change (name and ids are identity, finances belong to the career).
const EDITABLE_CLUB_FIELDS: Array[String] = ["full_name", "nickname", "city", "region", "founding_year", "description",
		"stadium_name", "stadium_capacity", "stadium_level", "manager_id"]
const INT_FIELDS: Array[String] = ["founding_year", "stadium_capacity", "stadium_level"]


# --- statistics -----------------------------------------------------------------------------------

static func stats(db: Node) -> Dictionary:
	var clubs := 0
	var nationals := 0
	var by_type := {}
	var by_country := {}
	var by_division := {}
	for t: TeamData in db.teams.values():
		if t.category == TeamData.Category.NATIONAL:
			nationals += 1
			continue
		clubs += 1
		var k: String = TeamData.ClubType.keys()[t.club_type]
		by_type[k] = int(by_type.get(k, 0)) + 1
		by_country[t.country] = int(by_country.get(t.country, 0)) + 1
		var d := t.league_id if t.league_id != "" else "(none)"
		by_division[d] = int(by_division.get(d, 0)) + 1
	var p_by_type := {}
	var with_nat_id := 0
	var by_pos := {}
	for p: PlayerData in db.players.values():
		var k2: String = PlayerData.PlayerType.keys()[p.player_type]
		p_by_type[k2] = int(p_by_type.get(k2, 0)) + 1
		with_nat_id += 1 if p.nationality_id != "" else 0
		var pn: String = PlayerData.Position.keys()[p.position]
		by_pos[pn] = int(by_pos.get(pn, 0)) + 1
	return {"clubs": clubs, "national_teams": nationals, "players": db.players.size(), "countries": db.countries.size(),
			"leagues": db.leagues.size(), "divisions": by_division.size() - (1 if by_division.has("(none)") else 0),
			"crests": db.crests.crests.size(), "clubs_by_type": by_type, "clubs_by_country": by_country,
			"clubs_by_division": by_division, "players_by_type": p_by_type, "players_by_position": by_pos,
			"players_with_nationality_id": with_nat_id, "kit_repairs": db.kit_repairs.size(),
			"crest_stats": db.crests.stats()}


# --- validation -------------------------------------------------------------------------------------

## {"critical": [...], "warnings": [...], "checked": {...}}. Critical = something is broken and a game
## system could misbehave; warnings = quality notes (look-alike names, unknown optional data).
static func validate_all(db: Node, check_names := true) -> Dictionary:
	var critical: Array[String] = []
	var warnings: Array[String] = []
	for e in db.errors:
		critical.append("load: %s" % e)
	for t: TeamData in db.teams.values():
		for e in t.validate():
			critical.append(e)
	var bad_players := 0
	for p: PlayerData in db.players.values():
		var errs := p.validate()
		bad_players += 1 if not errs.is_empty() else 0
		if errs.size() > 0 and critical.size() < 200:
			critical.append(errs[0])
	critical.append_array(db.validate_relations())
	critical.append_array(db.validate_kits())
	critical.append_array(db.crests.validate(db))
	for key in db.leagues:
		for e in (db.leagues[key] as LeagueDef).validate(db):
			critical.append("league %s: %s" % [key, e])
	var in_squad := {}
	for t: TeamData in db.teams.values():
		for pid in t.squad_ids:
			if in_squad.has(pid) and in_squad[pid] != t.id:
				critical.append("player '%s' is in the squads of '%s' and '%s'" % [pid, in_squad[pid], t.id])
			in_squad[pid] = t.id
	var orphan_players := 0
	for p: PlayerData in db.players.values():
		if p.team_id != "" and not db.teams.has(p.team_id):
			critical.append("player '%s' belongs to unknown team '%s'" % [p.id, p.team_id])
		elif p.team_id != "" and not (db.teams[p.team_id] as TeamData).squad_ids.has(p.id) and p.status != PlayerData.Status.YOUTH \
				and p.status != PlayerData.Status.RETIRED and p.loan_parent == "" and not p.id.begins_with("yth_"):
			orphan_players += 1
	if orphan_players > 0:
		critical.append("%d players name a club but are not in its squad" % orphan_players)
	var missing: Array = db.crests.missing_assets()
	for m in missing:
		critical.append("crest '%s': asset file is missing" % m)
	if check_names:
		var conflicts := NameIndex.find_conflicts(db.players.values().map(func(p: PlayerData) -> String: return p.display_name))
		if conflicts.size() > 0:
			warnings.append("%d player names duplicate or nearly duplicate another name (first: %s)" % [conflicts.size(), str(conflicts[0])])
	var no_nat := 0
	for p: PlayerData in db.players.values():
		no_nat += 1 if p.nationality_id == "" else 0
	if no_nat > 0:
		warnings.append("%d players have a nationality that is not in the country database (no nationality_id)" % no_nat)
	var no_city := 0
	for t: TeamData in db.teams.values():
		no_city += 1 if t.category == TeamData.Category.CLUB and t.is_real and t.city == "" else 0
	if no_city > 0:
		warnings.append("%d real clubs have no city / founding year / finances (no verified source yet)" % no_city)
	if not db.kit_repairs.is_empty():
		warnings.append("%d clubs needed kit repairs at load (see TeamDB.kit_repairs)" % db.kit_repairs.size())
	return {"critical": critical, "warnings": warnings,
			"checked": {"clubs": stats(db)["clubs"], "players": db.players.size(), "crests": db.crests.crests.size(), "leagues": db.leagues.size()}}


# --- search -------------------------------------------------------------------------------------------

## Filters: text (name / id fragment), country (name), division (league id), type (REAL/FICTIONAL/CUSTOM), limit.
static func search_clubs(db: Node, f: Dictionary = {}) -> Array[TeamData]:
	var out: Array[TeamData] = []
	var text := NameIndex.normalize(str(f.get("text", "")))
	var raw := str(f.get("text", "")).strip_edges().to_lower()
	for t: TeamData in db.list_teams(TeamData.Category.CLUB):
		if raw != "" and not (NameIndex.normalize(t.display_name).contains(text) or t.id.to_lower().contains(raw) or NameIndex.normalize(t.short_name) == text):
			continue
		if f.get("country", "") != "" and t.country != f["country"]:
			continue
		if f.get("division", "") != "" and t.league_id != f["division"]:
			continue
		if f.get("type", "") != "" and TeamData.ClubType.keys()[t.club_type] != f["type"]:
			continue
		out.append(t)
		if out.size() >= int(f.get("limit", 100000)):
			break
	return out


## Filters: text (name or id), country (nationality), club (team id), position (name, e.g. "CB"), min_age, max_age,
## type (REAL/GENERATED/YOUTH), limit. Sorted by overall (best first) then id.
static func search_players(db: Node, f: Dictionary = {}) -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	var text := NameIndex.normalize(str(f.get("text", "")))
	var raw_text := str(f.get("text", "")).strip_edges().to_lower()
	if raw_text != "" and db.players.has(str(f.get("text", "")).strip_edges()):
		return [db.players[str(f.get("text", "")).strip_edges()]]       # an exact id is exactly one player
	for p: PlayerData in db.players.values():
		if raw_text != "" and not (NameIndex.normalize(p.display_name).contains(text) or p.id.to_lower().contains(raw_text)):
			continue
		if f.get("country", "") != "" and p.nationality != f["country"]:
			continue
		if f.get("club", "") != "" and p.team_id != f["club"]:
			continue
		if f.get("position", "") != "" and PlayerData.Position.keys()[p.position] != f["position"]:
			continue
		if p.age < int(f.get("min_age", 0)) or p.age > int(f.get("max_age", 200)):
			continue
		if f.get("type", "") != "" and PlayerData.PlayerType.keys()[p.player_type] != f["type"]:
			continue
		out.append(p)
	out.sort_custom(func(a: PlayerData, b: PlayerData) -> bool:
		var oa := a.get_overall()
		var ob := b.get_overall()
		return a.id < b.id if oa == ob else oa > ob)
	var limit := int(f.get("limit", 100000))
	return out.slice(0, limit) if out.size() > limit else out


# --- profiles (what the screen shows) ---------------------------------------------------------------------

static func club_profile(db: Node, club_id: String) -> Dictionary:
	var t: TeamData = db.get_team(club_id)
	if t == null:
		return {}
	var squad: Array = db.get_squad(club_id)
	var groups := {"GK": 0, "DEF": 0, "MID": 0, "ATT": 0}
	var total := 0
	for p in squad:
		total += p.get_overall()
		match p.position:
			PlayerData.Position.GK: groups["GK"] += 1
			PlayerData.Position.CB, PlayerData.Position.LB, PlayerData.Position.RB: groups["DEF"] += 1
			PlayerData.Position.CDM, PlayerData.Position.CM, PlayerData.Position.CAM, PlayerData.Position.LM, PlayerData.Position.RM: groups["MID"] += 1
			_: groups["ATT"] += 1
	var crest := CrestService.crest_of(db, t)
	return {"id": t.id, "name": t.display_name, "full_name": t.full_name, "short_name": t.short_name, "nickname": t.nickname,
			"country": t.country, "country_id": t.country_id, "city": t.city, "founding_year": t.founding_year,
			"type": TeamData.ClubType.keys()[t.club_type], "real": t.is_real, "league_id": t.league_id, "division": t.division,
			"reputation": t.reputation, "rating": db.get_team_rating(club_id), "squad_size": squad.size(), "squad_groups": groups,
			"squad_average_overall": (float(total) / squad.size()) if squad.size() > 0 else 0.0,
			"finance": {"budget": t.budget, "transfer_budget": t.transfer_budget, "wage_budget": t.wage_budget,
					"balance": t.current_balance, "weekly_expenses": t.weekly_expenses, "sponsorship": t.sponsorship_income,
					"status": t.financial_status()},
			"stadium": {"name": t.stadium_name, "capacity": t.stadium_capacity, "level": t.stadium_level},
			"crest_id": t.crest_id, "crest_type": CrestData.AssetType.keys()[crest.asset_type] if crest != null else "",
			"rivals": Array(t.rival_club_ids), "kit_slots": t.kits.keys()}


static func player_profile(db: Node, player_id: String) -> Dictionary:
	var p: PlayerData = db.get_player(player_id)
	if p == null:
		return {}
	var team: TeamData = db.get_team(p.team_id) if p.team_id != "" else null
	var app := PlayerAppearance.ensure(p)
	return {"id": p.id, "name": p.display_name, "first_name": p.first_name, "last_name": p.last_name, "age": p.age,
			"nationality": p.nationality, "nationality_id": p.nationality_id, "type": PlayerData.PlayerType.keys()[p.player_type],
			"position": PlayerData.Position.keys()[p.position], "secondary_positions": p.secondary_positions.duplicate(),
			"foot": PlayerData.Foot.keys()[p.preferred_foot], "overall": p.get_overall(), "potential": p.potential,
			"height_cm": p.get_height_cm(), "weight_kg": p.get_weight_kg(),
			"height_is_estimate": p.height_cm == 0, "attributes": AttributeDetail.for_player(p),
			"club_id": p.team_id, "club": team.display_name if team != null else "", "shirt_number": p.shirt_number,
			"contract_years": p.contract_years, "salary": p.salary, "transfer_value": p.transfer_value,
			"status": PlayerData.Status.keys()[p.status], "history": p.development_history.duplicate(true),
			"appearance": {"version": int(app.get("v", 0)), "seed": int(app.get("seed", 0)), "signature": PlayerAppearance.signature(app),
					"fields": app.keys()}}


# --- editing -------------------------------------------------------------------------------------------------

## Changes one supported club field. Validates the result and restores the old value on failure.
## Returns "" or an error message.
static func set_club_metadata(db: Node, club_id: String, field: String, value: String) -> String:
	var t: TeamData = db.get_team(club_id)
	if t == null:
		return "unknown club '%s'" % club_id
	if not (field in EDITABLE_CLUB_FIELDS):
		return "field '%s' cannot be edited here (supported: %s)" % [field, ", ".join(EDITABLE_CLUB_FIELDS)]
	var old: Variant = t.get(field)
	if field in INT_FIELDS:
		if not value.strip_edges().is_valid_int():
			return "'%s' needs a whole number" % field
		t.set(field, int(value))
	else:
		t.set(field, value.strip_edges())
	var errs := t.validate()
	if not errs.is_empty():
		t.set(field, old)
		return errs[0]
	return ""


# --- export / import ---------------------------------------------------------------------------------------------

## Writes the whole database (or one world) as one JSON snapshot. Deterministic: no timestamps, sorted keys.
static func export_snapshot(db: Node, path: String) -> String:
	var teams: Array = []
	for t: TeamData in db.list_teams():
		teams.append(t.to_dict())
	var ids: Array = db.players.keys()
	ids.sort()
	var players: Array = []
	for id in ids:
		players.append((db.players[id] as PlayerData).to_dict())
	var data := {"format": SNAPSHOT_FORMAT, "version": SNAPSHOT_VERSION, "pack": db.pack_id,
			"counts": {"teams": teams.size(), "players": players.size()}, "teams": teams, "players": players}
	return _write(path, data)


static func _write(path: String, data: Dictionary) -> String:
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return "cannot write '%s'" % path
	f.store_string(JSON.stringify(data, " ", true))
	f.close()
	return ""


## Reads a snapshot / package ({"teams": [...], "players": [...]}) and adds its records to `db`.
## All-or-nothing: every record is checked first (valid, no duplicate or already existing id, squads and
## player clubs resolve inside the package or the database); nothing is added when anything is wrong.
## `dry_run` only checks. Returns {"ok", "errors", "teams", "players"}.
static func import_package(db: Node, path: String, dry_run := false) -> Dictionary:
	var fail := func(msgs: Array) -> Dictionary: return {"ok": false, "errors": msgs, "teams": 0, "players": 0}
	if not FileAccess.file_exists(path):
		return fail.call(["file not found: %s" % path])
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY or not (parsed as Dictionary).has("teams") or not (parsed as Dictionary).has("players"):
		return fail.call(["not a database package (needs 'teams' and 'players')"])
	var d: Dictionary = parsed
	if d.has("format") and d["format"] != SNAPSHOT_FORMAT:
		return fail.call(["unknown package format '%s'" % d["format"]])
	if int(d.get("version", SNAPSHOT_VERSION)) > SNAPSHOT_VERSION:
		return fail.call(["package version %d is newer than supported (%d)" % [int(d["version"]), SNAPSHOT_VERSION]])
	var errors: Array = []
	var teams: Array[TeamData] = []
	var players: Array[PlayerData] = []
	var team_ids := {}
	var player_ids := {}
	for td in d["teams"]:
		if typeof(td) != TYPE_DICTIONARY:
			errors.append("a team record is not an object")
			continue
		var t := TeamData.from_dict(td)
		for e in t.validate():
			errors.append(e)
		if db.teams.has(t.id) or team_ids.has(t.id):
			errors.append("team id '%s' already exists" % t.id)
		team_ids[t.id] = true
		teams.append(t)
	for pd in d["players"]:
		if typeof(pd) != TYPE_DICTIONARY:
			errors.append("a player record is not an object")
			continue
		var p := PlayerData.from_dict(pd)
		for e in p.validate():
			errors.append(e)
		if db.players.has(p.id) or player_ids.has(p.id):
			errors.append("player id '%s' already exists" % p.id)
		player_ids[p.id] = true
		if p.team_id != "" and not team_ids.has(p.team_id) and not db.teams.has(p.team_id):
			errors.append("player '%s' belongs to unknown team '%s'" % [p.id, p.team_id])
		players.append(p)
	for t in teams:
		for pid in t.squad_ids:
			if not player_ids.has(pid):
				errors.append("team '%s' lists missing player '%s'" % [t.id, pid])
	if not errors.is_empty():
		return fail.call(errors.slice(0, 50))
	if dry_run:
		return {"ok": true, "errors": [], "teams": teams.size(), "players": players.size()}
	var by_team := {}
	for p in players:
		if not by_team.has(p.team_id):
			by_team[p.team_id] = []
		by_team[p.team_id].append(p)
	var added_players := 0
	for t in teams:
		var roster: Array[PlayerData] = []
		for p: PlayerData in by_team.get(t.id, []):
			roster.append(p)
		if not db.register_team(t, roster, "import"):
			return fail.call([str(db.errors[-1])])     # cannot happen after the checks above; reported, never silent
		added_players += roster.size()
	for p in players:                                     # players of clubs already in the database / free agents
		if p.team_id == "" or not team_ids.has(p.team_id):
			if db.register_player(p):
				added_players += 1
	return {"ok": true, "errors": [], "teams": teams.size(), "players": added_players}


## Generates fictional clubs (not added to `db`) and writes them as an importable package.
## Club and player names avoid everything already in `db`. Returns {"ok", "error", "teams", "players"}.
static func generate_package(db: Node, world_seed: int, per_country: int, path: String) -> Dictionary:
	var cups := {}
	for key in db.leagues:
		cups[key] = str((db.leagues[key] as LeagueDef).cup.get("id", ""))
	var result := WorldGenerator.generate(db, world_seed, per_country, cups)
	var teams: Array = []
	var players: Array = []
	for entry in result["clubs"]:
		var t: TeamData = entry["team"]
		t.league_id = ""                       # not part of any league until the user puts it in one
		t.division = 0
		teams.append(t.to_dict())
		for p: PlayerData in entry["players"]:
			players.append(p.to_dict())
	var err := _write(path, {"format": SNAPSHOT_FORMAT, "version": SNAPSHOT_VERSION, "pack": "generated",
			"counts": {"teams": teams.size(), "players": players.size()}, "teams": teams, "players": players})
	return {"ok": err == "", "error": err, "teams": teams.size(), "players": players.size()}


# --- crests ----------------------------------------------------------------------------------------------------------

static func crest_report(db: Node) -> Dictionary:
	return {"stats": db.crests.stats(), "missing_assets": db.crests.missing_assets(), "problems": db.crests.validate(db),
			"orphans": db.crests.orphan_crests(db).size()}
