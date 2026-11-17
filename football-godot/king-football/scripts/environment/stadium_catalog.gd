class_name StadiumCatalog
extends RefCounted

## The stadiums a match can be played in. "arena" is the original Blender stadium (stadium.glb); every other entry
## adds a generated shell (tools/stadium_gen/build_stadiums.py) - stands, roof, facade, floodlights, screens - on the
## same base, so pitch, goals and all gameplay helpers are identical in every stadium.
##
## `MatchSetup.stadium_id` may be a stadium id, "home" (the home club's stadium) or anything else (-> "arena").
## A club's stadium is its `TeamData.stadium_id` when that names a catalogue stadium, otherwise a stable pick from
## the club id, so every club always plays its home matches in the same ground.

const DEFAULT_ID := "arena"
const HOME := "home"
const SHELL_DIR := "res://assets/models/stadium/shells/"

## id, translation key of the name, shell scene ("" = the original), trees around the plaza, capacity (display).
const STADIUMS: Array[Dictionary] = [
	{"id": "arena", "name_key": "STADIUM_ARENA", "shell": "", "trees": true, "capacity": 45000},
	{"id": "crescent_bowl", "name_key": "STADIUM_CRESCENT_BOWL", "shell": "crescent_bowl.glb", "trees": true, "capacity": 62000},
	{"id": "old_fortress", "name_key": "STADIUM_OLD_FORTRESS", "shell": "old_fortress.glb", "trees": true, "capacity": 36000},
	{"id": "riverside_park", "name_key": "STADIUM_RIVERSIDE_PARK", "shell": "riverside_park.glb", "trees": true, "capacity": 7500},
	{"id": "desert_dome", "name_key": "STADIUM_DESERT_DOME", "shell": "desert_dome.glb", "trees": false, "capacity": 55000},
]


static func ids() -> Array[String]:
	var out: Array[String] = []
	for s in STADIUMS:
		out.append(str(s["id"]))
	return out


static func has(id: String) -> bool:
	return ids().has(id)


## The entry for `id` (the original arena when unknown).
static func entry(id: String) -> Dictionary:
	for s in STADIUMS:
		if s["id"] == id:
			return s
	return STADIUMS[0]


static func display_name(id: String) -> String:
	return Loc.t(str(entry(id)["name_key"]))


## Stadium of a club: its own stadium id when that is a catalogue stadium, else a stable choice from the club id.
static func for_team(team: TeamData) -> String:
	if team == null:
		return DEFAULT_ID
	if has(team.stadium_id):
		return team.stadium_id
	var h := 0
	for c in team.id.to_utf8_buffer():
		h = (h * 31 + c) % 1000003
	return str(STADIUMS[h % STADIUMS.size()]["id"])


## Stadium actually used for `setup_id` ("home" -> the home club's stadium; unknown -> the original arena).
static func resolve(setup_id: String, home_team: TeamData) -> String:
	if setup_id == HOME:
		return for_team(home_team)
	return setup_id if has(setup_id) else DEFAULT_ID


## Configures a StadiumArena node BEFORE it enters the tree (it builds in _ready). Returns the id applied.
static func apply_to(arena: Node, id: String) -> String:
	var e := entry(id)
	if arena == null:
		return str(e["id"])
	var shell := str(e["shell"])
	if shell != "" and "shell" in arena:
		var scene := load(SHELL_DIR + shell) as PackedScene
		if scene == null:
			push_warning("StadiumCatalog: cannot load %s, playing in the arena" % shell)
			return DEFAULT_ID
		arena.set("shell", scene)
	if "show_trees" in arena:
		arena.set("show_trees", bool(e["trees"]))
	return str(e["id"])
