class_name PlayerData
extends Resource

## Single player record (Phase T2). Players come only from team databases or
## the Youth Academy — there is deliberately no manual "create player" tool.
## Ratings use a 1–99 scale. `id` is the stable identity (never the name).

enum Position { GK, CB, LB, RB, CDM, CM, CAM, LM, RM, LW, RW, ST }
enum Foot { RIGHT, LEFT, BOTH }
enum Status { ACTIVE, INJURED, SUSPENDED, LOANED, YOUTH, RETIRED }

const MIN_RATING := 1
const MAX_RATING := 99
const ATTRIBUTES: Array[String] = [
	"pace", "shooting", "passing", "dribbling", "defending", "physical", "goalkeeping",
]
## Weights per position used to derive the overall rating (sum = 1.0).
const OVERALL_WEIGHTS := {
	Position.GK:  {"goalkeeping": 0.70, "passing": 0.10, "physical": 0.10, "pace": 0.10},
	Position.CB:  {"defending": 0.50, "physical": 0.25, "passing": 0.10, "pace": 0.10, "dribbling": 0.05},
	Position.LB:  {"defending": 0.35, "pace": 0.25, "passing": 0.15, "physical": 0.10, "dribbling": 0.15},
	Position.RB:  {"defending": 0.35, "pace": 0.25, "passing": 0.15, "physical": 0.10, "dribbling": 0.15},
	Position.CDM: {"defending": 0.35, "passing": 0.25, "physical": 0.20, "dribbling": 0.10, "pace": 0.10},
	Position.CM:  {"passing": 0.30, "dribbling": 0.20, "defending": 0.15, "physical": 0.15, "shooting": 0.10, "pace": 0.10},
	Position.CAM: {"passing": 0.30, "dribbling": 0.30, "shooting": 0.20, "pace": 0.10, "physical": 0.10},
	Position.LM:  {"pace": 0.25, "dribbling": 0.30, "passing": 0.25, "shooting": 0.10, "physical": 0.10},
	Position.RM:  {"pace": 0.25, "dribbling": 0.30, "passing": 0.25, "shooting": 0.10, "physical": 0.10},
	Position.LW:  {"pace": 0.30, "dribbling": 0.30, "shooting": 0.20, "passing": 0.15, "physical": 0.05},
	Position.RW:  {"pace": 0.30, "dribbling": 0.30, "shooting": 0.20, "passing": 0.15, "physical": 0.05},
	Position.ST:  {"shooting": 0.40, "pace": 0.20, "dribbling": 0.15, "physical": 0.20, "passing": 0.05},
}

@export var id: String = ""
@export var display_name: String = ""
@export var age: int = 18
@export var nationality: String = ""
@export var shirt_number: int = 0
@export var position: Position = Position.CM
@export var preferred_foot: Foot = Foot.RIGHT

@export_group("Attributes")
@export var pace: int = 50
@export var shooting: int = 50
@export var passing: int = 50
@export var dribbling: int = 50
@export var defending: int = 50
@export var physical: int = 50
@export var goalkeeping: int = 10

@export_group("Development")
@export var potential: int = 60
@export var experience: int = 0
@export var fitness: int = 100      # 0–100
@export var stamina: int = 100      # 0–100
@export var morale: int = 70        # 0–100
@export var unavailable_weeks: int = 0   # weeks left of an injury / suspension (status INJURED / SUSPENDED)
@export var development_history: Array = []
@export var growth_progress: Dictionary = {}  # attribute -> fractional training progress
@export var traits: Array = []       # development traits, e.g. "Fast Learner"

@export_group("Appearance")
## Visual identity (see PlayerAppearance). Empty = not generated yet; it is then
## derived from `id` on first use, so old saves and data files keep working.
@export var appearance: Dictionary = {}

@export_group("Career")
@export var team_id: String = ""
@export var contract_years: int = 1
@export var salary: int = 0         # per week
@export var transfer_value: int = 0
@export var status: Status = Status.ACTIVE
@export var loan_parent: String = ""      # owning club while on loan
@export var loan_weeks_left: int = 0


func get_attribute(attr: String) -> int:
	return int(get(attr)) if attr in ATTRIBUTES else 0


func get_overall() -> int:
	var weights: Dictionary = OVERALL_WEIGHTS[position]
	var total := 0.0
	for attr in weights:
		total += float(get_attribute(attr)) * float(weights[attr])
	return clampi(roundi(total), MIN_RATING, MAX_RATING)


## Returns human-readable validation errors (empty array = valid).
func validate() -> Array[String]:
	var errors: Array[String] = []
	if id.strip_edges() == "":
		errors.append("player has empty id")
	if display_name.strip_edges() == "":
		errors.append("player '%s' has empty name" % id)
	if age < 14 or age > 50:
		errors.append("player '%s' age %d out of range 14-50" % [id, age])
	if shirt_number < 0 or shirt_number > 99:
		errors.append("player '%s' shirt number %d out of range 0-99" % [id, shirt_number])
	for attr in ATTRIBUTES:
		var v := get_attribute(attr)
		if v < MIN_RATING or v > MAX_RATING:
			errors.append("player '%s' %s=%d out of range 1-99" % [id, attr, v])
	if potential < MIN_RATING or potential > MAX_RATING:
		errors.append("player '%s' potential %d out of range 1-99" % [id, potential])
	elif potential < get_overall():
		errors.append("player '%s' potential %d below overall %d" % [id, potential, get_overall()])
	for pct in ["fitness", "stamina", "morale"]:
		var pv := int(get(pct))
		if pv < 0 or pv > 100:
			errors.append("player '%s' %s=%d out of range 0-100" % [id, pct, pv])
	return errors


func to_dict() -> Dictionary:
	var d := {
		"id": id, "name": display_name, "age": age, "nationality": nationality,
		"shirt_number": shirt_number, "position": Position.keys()[position],
		"foot": Foot.keys()[preferred_foot], "potential": potential,
		"experience": experience, "fitness": fitness, "stamina": stamina,
		"morale": morale, "development_history": development_history.duplicate(true), "traits": traits.duplicate(), "growth_progress": growth_progress.duplicate(),
		"team_id": team_id, "contract_years": contract_years, "salary": salary,
		"transfer_value": transfer_value, "status": Status.keys()[status],
		"loan_parent": loan_parent, "loan_weeks_left": loan_weeks_left, "unavailable_weeks": unavailable_weeks,
		"appearance": appearance.duplicate(true),
	}
	for attr in ATTRIBUTES:
		d[attr] = get_attribute(attr)
	return d


## Builds a PlayerData from a dictionary. Unknown enum names fall back to the
## default and are reported by `validate()` callers via `from_dict_errors`.
## JSON has one number type, so whole numbers come back as floats. Restore them
## to ints (recursively) so a save/load round trip is byte-identical.
static func _restore_ints(v: Variant) -> Variant:
	if v is Array:
		var out: Array = []
		for item in v:
			out.append(_restore_ints(item))
		return out
	if v is Dictionary:
		var out: Dictionary = {}
		for k in v:
			out[k] = _restore_ints(v[k])
		return out
	if v is float and is_equal_approx(v, roundf(v)) and absf(v) < 1.0e15:
		return int(v)
	return v


static func from_dict(d: Dictionary) -> PlayerData:
	var p := PlayerData.new()
	p.id = str(d.get("id", ""))
	p.display_name = str(d.get("name", ""))
	p.age = int(d.get("age", 18))
	p.nationality = str(d.get("nationality", ""))
	p.shirt_number = int(d.get("shirt_number", 0))
	p.position = _enum_value(Position, str(d.get("position", "CM")), Position.CM)
	p.preferred_foot = _enum_value(Foot, str(d.get("foot", "RIGHT")), Foot.RIGHT)
	for attr in ATTRIBUTES:
		p.set(attr, int(d.get(attr, p.get(attr))))
	p.potential = int(d.get("potential", p.potential))
	p.experience = int(d.get("experience", 0))
	p.fitness = int(d.get("fitness", 100))
	p.stamina = int(d.get("stamina", 100))
	p.morale = int(d.get("morale", 70))
	p.development_history = _restore_ints((d.get("development_history", []) as Array).duplicate(true))
	p.traits = (d.get("traits", []) as Array).duplicate()
	p.growth_progress = (d.get("growth_progress", {}) as Dictionary).duplicate()
	p.team_id = str(d.get("team_id", ""))
	p.contract_years = int(d.get("contract_years", 1))
	p.salary = int(d.get("salary", 0))
	p.transfer_value = int(d.get("transfer_value", 0))
	p.status = _enum_value(Status, str(d.get("status", "ACTIVE")), Status.ACTIVE)
	p.loan_parent = str(d.get("loan_parent", ""))
	p.loan_weeks_left = int(d.get("loan_weeks_left", 0))
	p.unavailable_weeks = maxi(int(d.get("unavailable_weeks", 0)), 0)
	var app: Variant = d.get("appearance", {})
	p.appearance = _restore_ints((app as Dictionary).duplicate(true)) if app is Dictionary else {}
	return p


static func _enum_value(enum_dict: Dictionary, key: String, fallback: int) -> int:
	return int(enum_dict[key]) if enum_dict.has(key) else fallback
