class_name Academy
extends RefCounted

## Youth academy of one club (Phase T4). Prospects are real `PlayerData`
## records (status YOUTH) registered in the player database under their
## stable id, but are NOT part of the first-team `squad_ids` until promoted
## (Phase T6). State saved: seed, next_index and roster ids — so loading never
## regenerates players.

var team_id: String = ""
var country: String = "Aldoria"
var academy_seed: int = 1
var next_index: int = 1
var quality: float = 0.5                  # facilities level 0..1
var roster_ids: Array[String] = []
var budget: int = 0
## Over-age prospects the manager chose to keep one more development stretch
## (see AcademyConfig.MAX_EXTENDED_AGE). They stay in `roster_ids`, so nobody
## is ever lost between "too old for a group" and a decision.
var extended_ids: Array[String] = []


func _init(p_team_id := "", p_country := "Aldoria", p_seed := 1) -> void:
	team_id = p_team_id
	country = p_country
	academy_seed = p_seed


func group_players(db: Node, group_id: String) -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	for pid in roster_ids:
		var p: PlayerData = db.get_player(pid)
		if p != null and AcademyConfig.group_for_age(p.age) == group_id:
			out.append(p)
	return out


func group_count(db: Node, group_id: String) -> int:
	return group_players(db, group_id).size()


## Over-Age Prospects: roster players older than the oldest age group that still
## need a decision (promote / release / keep). Independent of the group lists.
func over_age_ids(db: Node) -> Array[String]:
	var out: Array[String] = []
	for pid in roster_ids:
		var p: PlayerData = db.get_player(pid)
		if p != null and AcademyConfig.is_over_age(p.age) and not (pid in extended_ids):
			out.append(pid)
	return out


## Players kept in the extended development pathway (still in the roster).
func extended_players(db: Node) -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	for pid in extended_ids:
		var p: PlayerData = db.get_player(pid)
		if p != null and pid in roster_ids:
			out.append(p)
	return out


## Keeps an over-age prospect in the academy for further development. Returns ""
## or an error. Only allowed up to AcademyConfig.MAX_EXTENDED_AGE.
func keep_extended(db: Node, player_id: String) -> String:
	var p: PlayerData = db.get_player(player_id)
	if p == null or not (player_id in roster_ids):
		return "player '%s' is not in the academy roster" % player_id
	if not AcademyConfig.is_over_age(p.age):
		return "player '%s' is not over-age" % player_id
	if p.age > AcademyConfig.MAX_EXTENDED_AGE:
		return "player '%s' is too old to stay (max %d) — promote or release" % [player_id, AcademyConfig.MAX_EXTENDED_AGE]
	if player_id in extended_ids:
		return "player '%s' is already kept" % player_id
	extended_ids.append(player_id)
	return ""


## Drops extensions that ended (player left, or aged past the extended limit).
## Returns the ids that are over-age again and need a fresh decision.
func expire_extensions(db: Node) -> Array[String]:
	var again: Array[String] = []
	var keep: Array[String] = []
	for pid in extended_ids:
		var p: PlayerData = db.get_player(pid)
		if p == null or not (pid in roster_ids):
			continue
		if p.age > AcademyConfig.MAX_EXTENDED_AGE:
			again.append(pid)
		else:
			keep.append(pid)
	extended_ids = keep
	return again


func has_room(db: Node, group_id: String) -> bool:
	return group_count(db, group_id) < AcademyConfig.capacity(group_id)


## Generates up to `count` new prospects. Returns the created players
## (fewer than asked when the target age groups are full). Each one is
## registered in the database; ids/indices are never reused.
func generate_intake(db: Node, count: int, forced_age: int = -1) -> Array[PlayerData]:
	var created: Array[PlayerData] = []
	var guard := 0
	while created.size() < count and guard < count * 20:
		guard += 1
		var idx := next_index
		next_index += 1
		var p := YouthGenerator.generate(academy_seed, idx, team_id, country, quality, forced_age)
		if not has_room(db, AcademyConfig.group_for_age(p.age)):
			continue
		if _is_clone(db, p):
			continue
		if not db.register_player(p):
			continue
		PlayerAppearance.ensure(p)                       # visual identity is fixed at intake
		roster_ids.append(p.id)
		created.append(p)
	return created


## Rejects a prospect identical (name + all attributes) to an existing one.
func _is_clone(db: Node, p: PlayerData) -> bool:
	for pid in roster_ids:
		var o: PlayerData = db.get_player(pid)
		if o != null and o.display_name == p.display_name and o.age == p.age:
			var same := true
			for a in PlayerData.ATTRIBUTES:
				if o.get_attribute(a) != p.get_attribute(a):
					same = false
					break
			if same:
				return true
	return false


func to_dict() -> Dictionary:
	return {"team_id": team_id, "country": country, "seed": academy_seed,
			"next_index": next_index, "quality": quality, "roster": Array(roster_ids),
			"budget": budget, "extended": Array(extended_ids)}


static func from_dict(d: Dictionary) -> Academy:
	var a := Academy.new(str(d.get("team_id", "")), str(d.get("country", "Aldoria")),
			int(d.get("seed", 1)))
	a.next_index = int(d.get("next_index", 1))
	a.quality = float(d.get("quality", 0.5))
	a.budget = int(d.get("budget", 0))
	a.roster_ids.assign((d.get("roster", []) as Array).map(func(x: Variant) -> String: return str(x)))
	a.extended_ids.assign((d.get("extended", []) as Array).map(func(x: Variant) -> String: return str(x)))
	return a
