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
			"budget": budget}


static func from_dict(d: Dictionary) -> Academy:
	var a := Academy.new(str(d.get("team_id", "")), str(d.get("country", "Aldoria")),
			int(d.get("seed", 1)))
	a.next_index = int(d.get("next_index", 1))
	a.quality = float(d.get("quality", 0.5))
	a.budget = int(d.get("budget", 0))
	a.roster_ids.assign((d.get("roster", []) as Array).map(func(x: Variant) -> String: return str(x)))
	return a
