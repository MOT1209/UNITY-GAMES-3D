class_name WorldGenerator
extends RefCounted

## Builds the fictional third divisions of the five database countries on top of a loaded pack
## (database phase 6). Pure function of (pack contents, world seed): nothing is written here, so a
## test can regenerate everything and compare it with the shipped files.
##   result = {"clubs": [{"club", "team", "players"}], "divisions": {league key: division dict},
##             "manifest": {...}}

const THIRD_TIER := {
	"England": {"key": "england", "cc": "eng", "name": "League One"},
	"Spain": {"key": "spain", "cc": "esp", "name": "Primera Federación"},
	"Germany": {"key": "germany", "cc": "ger", "name": "3. Liga"},
	"Italy": {"key": "italy", "cc": "ita", "name": "Serie C"},
	"France": {"key": "france", "cc": "fra", "name": "National"},
}
const PER_COUNTRY := 20


static func cup_keys() -> Array[String]:
	var out: Array[String] = []
	for c in THIRD_TIER:
		out.append(THIRD_TIER[c]["key"])
	return out

const PROMOTE := 3          # third division -> second division places (and the same number the other way)
const CREATED_AT := "2026-11-12"


## `db` = a TeamDatabase with the pack loaded WITHOUT its fictional layer (see TeamDatabase.skip_fictional_layer).
## `cups` = league key -> domestic cup id (read from the league files, which may already list the third division).
static func generate(db: Node, world_seed: int, per_country: int = PER_COUNTRY, cups: Dictionary = {}) -> Dictionary:
	var club_names := NameIndex.new()
	var player_names := NameIndex.new()
	for t: TeamData in db.teams.values():
		club_names.add(t.display_name)
	for p: PlayerData in db.players.values():
		player_names.add(p.display_name)
	var used := {"names": club_names, "places": {}, "shorts": {}, "ids": {}}
	for t: TeamData in db.teams.values():
		used["shorts"][t.short_name.to_upper()] = true
		used["ids"][t.id] = true
	var clubs: Array = []
	var divisions := {}
	var total_players := 0
	for country in NameBank.COUNTRIES:
		var info: Dictionary = THIRD_TIER[country]
		var division_id := "%s_d3" % info["cc"]
		var cup_id: String = str(cups.get(info["key"], "%s_cup" % info["cc"]))
		var raw: Array = []
		for i in per_country:
			raw.append(ClubGenerator.generate_club(world_seed, country, i, 3, division_id, used, cup_id))
		for i in raw.size():
			var club: Dictionary = raw[i]
			var squad := ClubGenerator.generate_squad(club, player_names)
			var rivals: Array = [raw[(i + 1) % raw.size()]["id"], raw[(i + 7) % raw.size()]["id"]]
			var team := ClubGenerator.make_team(club, squad, rivals, world_seed)
			clubs.append({"club": club, "team": team, "players": squad})
			total_players += squad.size()
		divisions[info["key"]] = {"id": division_id, "name": info["name"], "tier": 3, "promote": PROMOTE, "relegate": 0,
				"team_ids": raw.map(func(c: Dictionary) -> String: return c["id"])}
	return {"clubs": clubs, "divisions": divisions,
			"manifest": {"version": 1, "generator_version": ClubGenerator.GENERATOR_VERSION, "world_seed": world_seed,
					"per_country": per_country, "clubs": clubs.size(), "players": total_players, "created_at": CREATED_AT,
					"note": "FICTIONAL clubs and players. Nothing here is real. Regenerate with tools/generate_world.tscn."}}


## JSON-ready file content of one generated club (same format TeamDB loads).
static func club_file(entry: Dictionary, world_seed: int) -> Dictionary:
	var team: TeamData = entry["team"]
	var players: Array = []
	for p: PlayerData in entry["players"]:
		players.append(p.to_dict())
	return {"team": team.to_dict(), "players": players, "players_source": "generated", "stadium_name": team.stadium_name,
			"generator": {"version": ClubGenerator.GENERATOR_VERSION, "seed": world_seed}}
