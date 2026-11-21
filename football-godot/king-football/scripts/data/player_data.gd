class_name PlayerData
extends Resource

## Single player record (Phase T2). Players come only from team databases or
## the Youth Academy — there is deliberately no manual "create player" tool.
## Ratings use a 1–99 scale. `id` is the stable identity (never the name).

enum Position { GK, CB, LB, RB, CDM, CM, CAM, LM, RM, LW, RW, ST }
enum Foot { RIGHT, LEFT, BOTH }
enum Status { ACTIVE, INJURED, SUSPENDED, LOANED, YOUTH, RETIRED }
## REAL = real-world player record, GENERATED = fictional first-team player, YOUTH = academy prospect.
enum PlayerType { REAL, GENERATED, YOUTH }

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
@export var position: Position = Position.CM:
	set(v):
		position = v
		_overall = -1
@export var preferred_foot: Foot = Foot.RIGHT

@export_group("Identity (database v3)")
## All optional. Empty / 0 = unknown: real-world values are never invented. `display_name`
## stays the full display name; first/last name are derived from it when not stored.
@export var first_name: String = ""
@export var last_name: String = ""
@export var nationality_id: String = ""        # CountryData id, "" when the nationality is not in the country database
@export var birth_year: int = 0
@export var height_cm: int = 0                 # 0 = unknown -> `get_height_cm()` derives it from the appearance
@export var weight_kg: int = 0                 # 0 = unknown -> `get_weight_kg()` derives it
@export var secondary_positions: Array = []    # Position names, e.g. ["CDM"]
@export var player_type: PlayerType = PlayerType.GENERATED
@export var contract_id: String = ""

@export_group("Attributes")
@export var pace: int = 50:
	set(v):
		var old_v := pace
		pace = v
		_overall = -1
		if v != old_v and not detail.is_empty() and not _detail_busy:
			DetailedAttributes.on_broad_changed(self, "pace", v - old_v)
@export var shooting: int = 50:
	set(v):
		var old_v := shooting
		shooting = v
		_overall = -1
		if v != old_v and not detail.is_empty() and not _detail_busy:
			DetailedAttributes.on_broad_changed(self, "shooting", v - old_v)
@export var passing: int = 50:
	set(v):
		var old_v := passing
		passing = v
		_overall = -1
		if v != old_v and not detail.is_empty() and not _detail_busy:
			DetailedAttributes.on_broad_changed(self, "passing", v - old_v)
@export var dribbling: int = 50:
	set(v):
		var old_v := dribbling
		dribbling = v
		_overall = -1
		if v != old_v and not detail.is_empty() and not _detail_busy:
			DetailedAttributes.on_broad_changed(self, "dribbling", v - old_v)
@export var defending: int = 50:
	set(v):
		var old_v := defending
		defending = v
		_overall = -1
		if v != old_v and not detail.is_empty() and not _detail_busy:
			DetailedAttributes.on_broad_changed(self, "defending", v - old_v)
@export var physical: int = 50:
	set(v):
		var old_v := physical
		physical = v
		_overall = -1
		if v != old_v and not detail.is_empty() and not _detail_busy:
			DetailedAttributes.on_broad_changed(self, "physical", v - old_v)
@export var goalkeeping: int = 10:
	set(v):
		var old_v := goalkeeping
		goalkeeping = v
		_overall = -1
		if v != old_v and not detail.is_empty() and not _detail_busy:
			DetailedAttributes.on_broad_changed(self, "goalkeeping", v - old_v)

@export_group("Detailed attributes")
## Trainable detailed attributes (see DetailedAttributes). Empty until the first detailed training: an untouched player reports
## derived values, so old saves / data packs need no migration. When non-empty it holds EVERY name of DetailedAttributes.CATALOG.
@export var detail: Dictionary = {}
## True while DetailedAttributes changes a broad attribute itself (so the change is not propagated back into the details).
var _detail_busy: bool = false

@export_group("Development")
@export var potential: int = 60
@export var experience: int = 0
@export var fitness: int = 100      # 0–100
@export var stamina: int = 100      # 0–100
@export var morale: int = 70        # 0–100
@export var unavailable_weeks: int = 0   # weeks left of an injury / suspension (status INJURED / SUSPENDED)
## Phase K3: the same absence in days (counted down every day by `DailyLife`); 0 = counted in weeks (old saves).
@export var unavailable_days: int = 0
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


## "tm_*" ids come from the real-world data pack, "yth_*" from the academy, the rest are generated.
static func type_for_id(player_id: String) -> PlayerType:
	if player_id.begins_with("tm_") or player_id.begins_with("wp_"):    # wp_ = real player without a transfermarkt id (real_2026)
		return PlayerType.REAL
	if player_id.begins_with("yth_"):
		return PlayerType.YOUTH
	return PlayerType.GENERATED


## Splits a display name into [first, last]; a single word is a last name.
static func split_name(full: String) -> Array:
	var t := full.strip_edges()
	var i := t.find(" ")
	if i < 0:
		return ["", t]
	return [t.substr(0, i), t.substr(i + 1).strip_edges()]


## Stored height, else a deterministic estimate from the stored appearance (cm).
func get_height_cm() -> int:
	if height_cm > 0:
		return height_cm
	return AttributeDetail.estimated_height_cm(self)


func get_weight_kg() -> int:
	if weight_kg > 0:
		return weight_kg
	return AttributeDetail.estimated_weight_kg(self)


## A broad attribute (the seven in ATTRIBUTES) or a detailed one (DetailedAttributes); 0 for anything else.
func get_attribute(attr: String) -> int:
	if attr in ATTRIBUTES:
		return int(get(attr))
	return DetailedAttributes.value(self, attr) if DetailedAttributes.has(attr) else 0


## Per position: [attribute indexes (into ATTRIBUTES), weights], in the declaration order of OVERALL_WEIGHTS so the float
## sum (and therefore the rounding) is identical to iterating the dictionary. Built once; `get_overall` runs hundreds of
## thousands of times in a season simulation.
static var _overall_plan: Array = []
## `get_overall()` memo: reset by the setters of the position and the seven attributes, so it can never go stale.
var _overall: int = -1


static func _build_overall_plan() -> void:
	_overall_plan.resize(Position.size())
	for pos in OVERALL_WEIGHTS:
		var w: Dictionary = OVERALL_WEIGHTS[pos]
		var idx := PackedInt32Array()
		var ws := PackedFloat64Array()
		for attr in w:
			idx.append(ATTRIBUTES.find(attr))
			ws.append(float(w[attr]))
		_overall_plan[int(pos)] = [idx, ws]


func get_overall() -> int:
	if _overall >= 0:
		return _overall
	if _overall_plan.is_empty():
		_build_overall_plan()
	var plan: Array = _overall_plan[position]
	var idx: PackedInt32Array = plan[0]
	var ws: PackedFloat64Array = plan[1]
	var total := 0.0
	for i in idx.size():
		var v := 0
		match idx[i]:
			0: v = pace
			1: v = shooting
			2: v = passing
			3: v = dribbling
			4: v = defending
			5: v = physical
			_: v = goalkeeping
		total += float(v) * ws[i]
	_overall = clampi(roundi(total), MIN_RATING, MAX_RATING)
	return _overall


## The routine yearly events ("season_development", "birthday") are kept for the latest `keep` entries of each kind; every other
## event (transfers, loans, training, promotion ...) is kept in full. Without this the log of a long career grows by two
## entries per player per season for ever (the profile screen shows only the latest ten).
const ROUTINE_EVENTS: Array[String] = ["season_development", "birthday"]


func trim_history(keep: int = 12, max_total: int = 80) -> void:
	var seen := {}
	var kept: Array = []
	for i in range(development_history.size() - 1, -1, -1):          # newest first
		var e: Variant = development_history[i]
		var kind := str((e as Dictionary).get("event", "")) if e is Dictionary else ""
		if kind in ROUTINE_EVENTS:
			seen[kind] = int(seen.get(kind, 0)) + 1
			if int(seen[kind]) > keep:
				continue
		kept.append(e)
	kept.reverse()
	if kept.size() > max_total:                                   # the origin event ("generated" / "signed") plus the newest ones
		kept = [kept[0]] + kept.slice(kept.size() - (max_total - 1))
	if kept.size() != development_history.size():
		development_history = kept


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
	if birth_year != 0 and (birth_year < 1950 or birth_year > 2100):
		errors.append("player '%s' birth year %d out of range" % [id, birth_year])
	if height_cm != 0 and (height_cm < 140 or height_cm > 220):
		errors.append("player '%s' height %d cm out of range 140-220" % [id, height_cm])
	if weight_kg != 0 and (weight_kg < 40 or weight_kg > 130):
		errors.append("player '%s' weight %d kg out of range 40-130" % [id, weight_kg])
	for sp in secondary_positions:
		if not Position.has(str(sp)):
			errors.append("player '%s' has unknown secondary position '%s'" % [id, sp])
		elif str(sp) == Position.keys()[position]:
			errors.append("player '%s' lists the primary position as secondary" % id)
	errors.append_array(DetailedAttributes.validate(self))
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
		"loan_parent": loan_parent, "loan_weeks_left": loan_weeks_left, "unavailable_weeks": unavailable_weeks, "unavailable_days": unavailable_days,
		"appearance": appearance.duplicate(true),
		"first_name": first_name, "last_name": last_name, "nationality_id": nationality_id,
		"birth_year": birth_year, "height_cm": height_cm, "weight_kg": weight_kg,
		"secondary_positions": secondary_positions.duplicate(), "player_type": PlayerType.keys()[player_type],
		"contract_id": contract_id,
	}
	for attr in ATTRIBUTES:
		d[attr] = get_attribute(attr)
	if not detail.is_empty():
		d["detail"] = detail.duplicate()
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
	p.unavailable_days = maxi(int(d.get("unavailable_days", 0)), 0)
	var app: Variant = d.get("appearance", {})
	p.appearance = _restore_ints((app as Dictionary).duplicate(true)) if app is Dictionary else {}
	# Database v3 identity fields. Old records: names are split from the display name and the
	# type comes from the id prefix, so nothing has to be migrated by hand.
	var parts := split_name(p.display_name)
	p.first_name = str(d.get("first_name", parts[0]))
	p.last_name = str(d.get("last_name", parts[1]))
	p.nationality_id = str(d.get("nationality_id", ""))
	p.birth_year = int(d.get("birth_year", 0))
	p.height_cm = int(d.get("height_cm", 0))
	p.weight_kg = int(d.get("weight_kg", 0))
	p.secondary_positions = (d.get("secondary_positions", []) as Array).duplicate()
	p.player_type = _enum_value(PlayerType, str(d.get("player_type", PlayerType.keys()[type_for_id(p.id)])), type_for_id(p.id))
	p.contract_id = str(d.get("contract_id", ""))
	p.detail = DetailedAttributes.sanitize(_restore_ints(d.get("detail", {})))    # after the broad attributes: loading never propagates
	DetailedAttributes.complete(p)
	return p


static func _enum_value(enum_dict: Dictionary, key: String, fallback: int) -> int:
	return int(enum_dict[key]) if enum_dict.has(key) else fallback
