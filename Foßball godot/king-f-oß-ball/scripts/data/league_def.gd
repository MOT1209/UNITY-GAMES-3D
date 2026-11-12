class_name LeagueDef
extends RefCounted

## One country's league system as shipped in a data pack (`data/packs/<id>/leagues/<key>.json`):
## ordered divisions (tier 1 = top), promotion/relegation counts, optional play-off places,
## the domestic cup and reserve-team links. This is the INITIAL composition; the live,
## season-by-season membership is kept by `LeaguePyramid`.

var key := ""
var country := ""
var display_name := ""
var season := ""
## [{id, name, tier, team_ids: Array, promote, relegate, playoff: {from, to, spots} or {}}] sorted by tier.
var divisions: Array = []
var cup: Dictionary = {}           # {id, name}
var reserves: Dictionary = {}      # reserve team id -> parent team id


static func from_dict(p_key: String, d: Dictionary) -> LeagueDef:
	var l := LeagueDef.new()
	l.key = p_key
	l.country = str(d.get("country", ""))
	l.display_name = str(d.get("name", l.country))
	l.season = str(d.get("season", ""))
	l.cup = (d.get("cup", {}) as Dictionary).duplicate(true)
	l.reserves = (d.get("reserves", {}) as Dictionary).duplicate(true)
	for dv in d.get("divisions", []):
		var div: Dictionary = dv
		l.divisions.append({"id": str(div.get("id", "")), "name": str(div.get("name", "")),
				"tier": int(div.get("tier", 0)), "team_ids": (div.get("team_ids", []) as Array).map(func(x: Variant) -> String: return str(x)),
				"promote": int(div.get("promote", 0)), "relegate": int(div.get("relegate", 0)),
				"playoff": _int_playoff(div.get("playoff", {}))})
	l.divisions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["tier"] < b["tier"])
	return l


static func _int_playoff(po: Variant) -> Dictionary:
	if not (po is Dictionary) or (po as Dictionary).is_empty():
		return {}
	var d: Dictionary = po
	return {"from": int(d.get("from", 0)), "to": int(d.get("to", 0)), "spots": int(d.get("spots", 0))}


## Problems that make the league unusable (empty = valid). `db` = TeamDatabase.
func validate(db: Node) -> Array[String]:
	var errors: Array[String] = []
	if key == "" or country == "":
		errors.append("league has no key/country")
	if divisions.is_empty():
		errors.append("league '%s' has no divisions" % key)
		return errors
	var seen := {}
	for i in divisions.size():
		var d: Dictionary = divisions[i]
		if int(d["tier"]) != i + 1:
			errors.append("league '%s': tiers must be 1..n without gaps" % key)
		if (d["team_ids"] as Array).size() < 4:
			errors.append("division '%s' needs at least 4 teams" % d["id"])
		for t in d["team_ids"]:
			var team: TeamData = db.get_team(t)
			if team == null:
				errors.append("division '%s' references unknown team '%s'" % [d["id"], t])
			elif team.category != TeamData.Category.CLUB:
				errors.append("division '%s': '%s' is not a club" % [d["id"], t])
			if seen.has(t):
				errors.append("team '%s' is in two divisions" % t)
			seen[t] = true
		var po: Dictionary = d["playoff"]
		if not po.is_empty():
			var n := (d["team_ids"] as Array).size()
			if int(po.get("from", 0)) <= int(d["promote"]) or int(po.get("to", 0)) > n \
					or int(po.get("to", 0)) - int(po.get("from", 0)) + 1 < 2 or int(po.get("spots", 0)) != 1:
				errors.append("division '%s' has an invalid play-off definition" % d["id"])
	if int(divisions[0]["promote"]) != 0 or not (divisions[0]["playoff"] as Dictionary).is_empty():
		errors.append("league '%s': the top division cannot promote" % key)
	if int(divisions[divisions.size() - 1]["relegate"]) != 0:
		errors.append("league '%s': the bottom division cannot relegate" % key)
	for i in range(1, divisions.size()):
		var upper: Dictionary = divisions[i - 1]
		var lower: Dictionary = divisions[i]
		var up_spots := int(lower["promote"]) + (1 if not (lower["playoff"] as Dictionary).is_empty() else 0)
		if int(upper["relegate"]) != up_spots:
			errors.append("league '%s': %s relegates %d but %s promotes %d" % [key, upper["id"], upper["relegate"], lower["id"], up_spots])
	for r in reserves:
		if not seen.has(r) or not seen.has(reserves[r]):
			errors.append("league '%s': reserve link %s -> %s references a team outside the league" % [key, r, reserves[r]])
	return errors


func division(id: String) -> Dictionary:
	for d in divisions:
		if d["id"] == id:
			return d
	return {}


func all_team_ids() -> Array:
	var out: Array = []
	for d in divisions:
		out.append_array(d["team_ids"])
	return out
