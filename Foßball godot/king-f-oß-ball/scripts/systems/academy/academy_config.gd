class_name AcademyConfig
extends RefCounted

## Configurable academy rules (Phase T4). Age eligibility lives here only —
## no other script hardcodes age assumptions.

## Ordered youngest → oldest: {id, min_age, max_age, capacity}.
const AGE_GROUPS: Array[Dictionary] = [
	{"id": "U15", "min_age": 14, "max_age": 15, "capacity": 20},
	{"id": "U17", "min_age": 16, "max_age": 17, "capacity": 20},
	{"id": "U19", "min_age": 18, "max_age": 19, "capacity": 20},
]
const FIRST_TEAM := "FIRST_TEAM"
const MIN_PROMOTION_AGE := 16
## Over-age prospects may be kept in a development pathway up to this age; after
## that a promote/release decision is forced again.
const MAX_EXTENDED_AGE := 21

const OUTFIELD_POSITIONS: Array[int] = [
	PlayerData.Position.CB, PlayerData.Position.LB, PlayerData.Position.RB,
	PlayerData.Position.CDM, PlayerData.Position.CM, PlayerData.Position.CAM,
	PlayerData.Position.LM, PlayerData.Position.RM, PlayerData.Position.LW,
	PlayerData.Position.RW, PlayerData.Position.ST,
]
const TRAITS: Array[String] = [
	"Fast Learner", "Late Bloomer", "Hard Worker", "Injury Prone",
	"Natural Finisher", "Playmaker", "Leader", "Inconsistent",
]


static func group_for_age(age: int) -> String:
	for g in AGE_GROUPS:
		if age >= g["min_age"] and age <= g["max_age"]:
			return g["id"]
	return ""


## Oldest age any academy group covers (derived from AGE_GROUPS, never hardcoded).
static func max_age() -> int:
	var m := 0
	for g in AGE_GROUPS:
		m = maxi(m, int(g["max_age"]))
	return m


static func is_over_age(age: int) -> bool:
	return age > max_age()


static func group_ids() -> Array[String]:
	var out: Array[String] = []
	for g in AGE_GROUPS:
		out.append(g["id"])
	return out


static func capacity(group_id: String) -> int:
	for g in AGE_GROUPS:
		if g["id"] == group_id:
			return g["capacity"]
	return 0


static func is_eligible(age: int, group_id: String) -> bool:
	return group_for_age(age) == group_id
