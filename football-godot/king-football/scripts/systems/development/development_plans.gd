class_name DevelopmentPlans
extends RefCounted

## Individual development plans (one per player). A plan lists FOCUS ITEMS, each one a DETAILED attribute of DetailedAttributes
## (Finishing, Vision, Tackling, Reflexes ...); the plan's weights are the number of items per attribute. Training an item raises that
## detailed attribute and, by 1/Z, its broad parent (see DetailedAttributes), so what the manager targets is what actually grows and the
## match engine sees the broad result. Plans are templates, never restrictions: a custom plan may target any 1-5 attributes (broad names
## from old saves still work), and a position conversion trains a new position. Plans written before the detailed layer ("v" < 2) are
## upgraded in place the first time they are processed: template plans get the detailed template, their clock / history is kept.
## Plan types: balanced, position, attribute, role, long_term, custom, conversion.

const TYPES: Array[String] = ["balanced", "position", "attribute", "role", "long_term", "custom", "conversion"]
const MAX_CUSTOM_ATTRIBUTES := 5
const PLAN_VERSION := 2
const TEMPLATE_TYPES: Array[String] = ["balanced", "position", "role", "long_term", "conversion"]
const GOAL_POINTS := 3                      # attribute points (across the plan's targets) that complete one plan cycle
const GOAL_MAX_WEEKS := 26                  # ... or this many weeks, whichever comes first

## Position group -> list of [label key, DETAILED attribute].
const TEMPLATES := {
	"gk": [["DEV_ATTR_REFLEXES", "reflexes"], ["DEV_ATTR_DIVING", "diving"], ["DEV_ATTR_HANDLING", "handling"], ["DEV_ATTR_GK_POSITIONING", "gk_positioning"], ["DEV_ATTR_ONE_ON_ONE", "one_on_one"]],
	"cb": [["DEV_ATTR_MARKING", "marking"], ["DEV_ATTR_TACKLING", "tackling"], ["DEV_ATTR_INTERCEPTIONS", "interceptions"], ["DEV_ATTR_STRENGTH", "strength"], ["DEV_ATTR_DEFENSIVE_AWARENESS", "defensive_awareness"]],
	"fb": [["DEV_ATTR_TACKLING", "tackling"], ["DEV_ATTR_STAMINA", "stamina"], ["DEV_ATTR_CROSSING", "crossing"], ["DEV_ATTR_ACCELERATION", "acceleration"], ["DEV_ATTR_DEFENSIVE_POSITIONING", "defensive_positioning"]],
	"cm": [["DEV_ATTR_SHORT_PASSING", "short_passing"], ["DEV_ATTR_LONG_PASSING", "long_passing"], ["DEV_ATTR_VISION", "vision"], ["DEV_ATTR_STAMINA", "stamina"], ["DEV_ATTR_DECISIONS", "decisions"]],
	"am": [["DEV_ATTR_VISION", "vision"], ["DEV_ATTR_DRIBBLING_SKILL", "dribbling_skill"], ["DEV_ATTR_SHORT_PASSING", "short_passing"], ["DEV_ATTR_BALL_CONTROL", "ball_control"], ["DEV_ATTR_FINISHING", "finishing"], ["DEV_ATTR_LONG_SHOTS", "long_shots"]],
	"winger": [["DEV_ATTR_ACCELERATION", "acceleration"], ["DEV_ATTR_SPRINT_SPEED", "sprint_speed"], ["DEV_ATTR_DRIBBLING_SKILL", "dribbling_skill"], ["DEV_ATTR_CROSSING", "crossing"], ["DEV_ATTR_BALL_CONTROL", "ball_control"]],
	"st": [["DEV_ATTR_FINISHING", "finishing"], ["DEV_ATTR_POSITIONING", "positioning"], ["DEV_ATTR_COMPOSURE", "composure"], ["DEV_ATTR_SHOT_POWER", "shot_power"], ["DEV_ATTR_REACTIONS", "reactions"]],
}
## Role-specific variants (group -> role id -> items).
const ROLES := {
	"gk": {"sweeper_keeper": [["DEV_ATTR_KICKING", "kicking"], ["DEV_ATTR_ONE_ON_ONE", "one_on_one"], ["DEV_ATTR_GK_POSITIONING", "gk_positioning"], ["DEV_ATTR_ACCELERATION", "acceleration"]]},
	"cb": {"ball_playing": [["DEV_ATTR_SHORT_PASSING", "short_passing"], ["DEV_ATTR_COMPOSURE", "composure"], ["DEV_ATTR_BALL_CONTROL", "ball_control"], ["DEV_ATTR_TACKLING", "tackling"]]},
	"fb": {"attacking_fullback": [["DEV_ATTR_CROSSING", "crossing"], ["DEV_ATTR_ACCELERATION", "acceleration"], ["DEV_ATTR_DRIBBLING_SKILL", "dribbling_skill"], ["DEV_ATTR_STAMINA", "stamina"]]},
	"cm": {"box_to_box": [["DEV_ATTR_STAMINA", "stamina"], ["DEV_ATTR_TACKLING", "tackling"], ["DEV_ATTR_SHORT_PASSING", "short_passing"], ["DEV_ATTR_LONG_SHOTS", "long_shots"]]},
	"am": {"shadow_striker": [["DEV_ATTR_FINISHING", "finishing"], ["DEV_ATTR_POSITIONING", "positioning"], ["DEV_ATTR_LONG_SHOTS", "long_shots"], ["DEV_ATTR_DRIBBLING_SKILL", "dribbling_skill"]]},
	"winger": {"inside_forward": [["DEV_ATTR_FINISHING", "finishing"], ["DEV_ATTR_DRIBBLING_SKILL", "dribbling_skill"], ["DEV_ATTR_ACCELERATION", "acceleration"], ["DEV_ATTR_POSITIONING", "positioning"]]},
	"st": {"target_man": [["DEV_ATTR_HEADING", "heading"], ["DEV_ATTR_STRENGTH", "strength"], ["DEV_ATTR_COMPOSURE", "composure"], ["DEV_ATTR_FINISHING", "finishing"]], "poacher": [["DEV_ATTR_FINISHING", "finishing"], ["DEV_ATTR_POSITIONING", "positioning"], ["DEV_ATTR_ACCELERATION", "acceleration"], ["DEV_ATTR_REACTIONS", "reactions"]]},
}

var plans: Dictionary = {}              # player id -> plan record (see `_new_plan`)


static func group_of(position: int) -> String:
	match position:
		PlayerData.Position.GK:
			return "gk"
		PlayerData.Position.CB:
			return "cb"
		PlayerData.Position.LB, PlayerData.Position.RB:
			return "fb"
		PlayerData.Position.CDM, PlayerData.Position.CM:
			return "cm"
		PlayerData.Position.CAM:
			return "am"
		PlayerData.Position.LW, PlayerData.Position.RW, PlayerData.Position.LM, PlayerData.Position.RM:
			return "winger"
	return "st"


static func roles_for(group: String) -> Array:
	return (ROLES.get(group, {}) as Dictionary).keys()


static func weights_of(items: Array) -> Dictionary:
	var w := {}
	for it in items:
		w[str(it[1])] = float(w.get(str(it[1]), 0.0)) + 1.0
	var total := 0.0
	for k in w:
		total += float(w[k])
	for k in w:
		w[k] = float(w[k]) / maxf(total, 1.0)
	return w


static func _balanced_items(p: PlayerData) -> Array:
	var items: Array = []
	if p.position == PlayerData.Position.GK:
		for n in ["reflexes", "diving", "handling", "gk_positioning", "one_on_one", "kicking", "acceleration", "short_passing", "strength"]:
			items.append(["DEV_ATTR_" + str(n).to_upper(), n])
		return items
	for n in DetailedAttributes.names():
		if DetailedAttributes.applicable(p, str(n)) and DetailedAttributes.group_of(str(n)) != "goalkeeping":
			items.append(["DEV_ATTR_" + str(n).to_upper(), n])
	return items


## Every attribute a plan can target or report on for `p`: the seven broad ones plus the detailed ones that apply to the position.
static func tracked_attrs(p: PlayerData) -> Array:
	var out: Array = PlayerData.ATTRIBUTES.duplicate()
	for n in DetailedAttributes.names():
		if DetailedAttributes.applicable(p, str(n)):
			out.append(n)
	return out


## Whether `p` can train `attr` (a broad attribute or a detailed one); goalkeeping attributes only for goalkeepers.
static func trainable(p: PlayerData, attr: String) -> bool:
	if attr in PlayerData.ATTRIBUTES:
		return attr != "goalkeeping" or p.position == PlayerData.Position.GK
	return DetailedAttributes.applicable(p, attr)


func plan_for(pid: String) -> Dictionary:
	return plans.get(pid, {})


func _new_plan(p: PlayerData, type: String, items: Array, week: int) -> Dictionary:
	DetailedAttributes.ensure(p)                      # a planned player has stored detailed attributes (his start values are fixed from here on)
	var start_attrs := {}
	for a in tracked_attrs(p):
		start_attrs[a] = p.get_attribute(a)
	return {"v": PLAN_VERSION, "player_id": p.id, "type": type, "items": items, "weights": weights_of(items), "intensity": DevConfig.INTENSITY_DEFAULT,
			"started_week": week, "switched_week": week, "weeks": 0, "start_overall": p.get_overall(), "start_attrs": start_attrs,
			"cycle_start_attrs": start_attrs.duplicate(), "cycle_weeks": 0, "cycles": 0, "target_position": "", "long_term": type == "long_term",
			"role": "", "history": [], "auto": false}


## The focus items of a plan type for `p`: {items, role, target, error}. `params`: role, attribute, attrs {attribute: weight}, target_position.
func _items_for(p: PlayerData, type: String, params: Dictionary) -> Dictionary:
	var group := group_of(p.position)
	var out := {"items": [], "role": "", "target": "", "error": ""}
	match type:
		"balanced":
			out["items"] = _balanced_items(p)
		"position", "long_term":
			out["items"] = (TEMPLATES[group] as Array).duplicate(true)
		"role":
			var role := str(params.get("role", ""))
			var rs: Dictionary = ROLES.get(group, {})
			if not rs.has(role):
				out["error"] = "no role '%s' for this position" % role
				return out
			out["role"] = role
			out["items"] = (rs[role] as Array).duplicate(true)
		"attribute":
			var a := str(params.get("attribute", ""))
			if not (a in PlayerData.ATTRIBUTES) and not DetailedAttributes.has(a):
				out["error"] = "unknown attribute '%s'" % a
				return out
			if not trainable(p, a):
				out["error"] = "only goalkeepers train goalkeeping"
				return out
			out["items"] = [["DEV_ATTR_" + a.to_upper(), a]]
		"custom":
			var attrs: Dictionary = params.get("attrs", {})
			if attrs.is_empty() or attrs.size() > MAX_CUSTOM_ATTRIBUTES:
				out["error"] = "a custom plan needs 1 to %d attributes" % MAX_CUSTOM_ATTRIBUTES
				return out
			var list: Array = []
			for a in attrs:
				if not (str(a) in PlayerData.ATTRIBUTES) and not DetailedAttributes.has(str(a)):
					out["error"] = "invalid custom attribute '%s'" % str(a)
					return out
				if float(attrs[a]) <= 0.0:
					out["error"] = "invalid custom attribute '%s'" % str(a)
					return out
				if not trainable(p, str(a)):
					out["error"] = "only goalkeepers train goalkeeping"
					return out
				for i in clampi(roundi(float(attrs[a]) * 2.0), 1, 6):          # weight 0.5 steps -> item count
					list.append(["DEV_ATTR_" + str(a).to_upper(), str(a)])
			out["items"] = list
		"conversion":
			var target := str(params.get("target_position", ""))
			if not (target in PlayerData.Position.keys()):
				out["error"] = "unknown position '%s'" % target
				return out
			if target == PlayerData.Position.keys()[p.position] or p.secondary_positions.has(target):
				out["error"] = "player already plays %s" % target
				return out
			if (target == "GK") != (p.position == PlayerData.Position.GK):
				out["error"] = "goalkeepers and outfield players cannot convert to each other"
				return out
			out["target"] = target
			out["items"] = (TEMPLATES[group_of(int(PlayerData.Position[target]))] as Array).duplicate(true)
	return out


## Assigns (or switches to) a plan. params: role, attribute, attrs {attribute: weight}, target_position (name), intensity 0..1.
## Returns "" or an error text. A switch keeps the old plan in `history` and starts the adaptation period.
func assign(p: PlayerData, type: String, week: int, params: Dictionary = {}) -> String:
	if p == null:
		return "unknown player"
	if not (type in TYPES):
		return "unknown plan type '%s'" % type
	var built := _items_for(p, type, params)
	if str(built["error"]) != "":
		return str(built["error"])
	var plan := _new_plan(p, type, built["items"], week)
	plan["role"] = built["role"]
	plan["target_position"] = built["target"]
	plan["intensity"] = clampf(float(params.get("intensity", DevConfig.INTENSITY_DEFAULT)), 0.0, 1.0)
	var old: Dictionary = plans.get(p.id, {})
	if not old.is_empty():
		if _same_plan(old, plan):
			old["intensity"] = plan["intensity"]
			return ""
		var hist: Array = (old["history"] as Array).duplicate(true)
		hist.append({"type": old["type"], "from_week": old["started_week"], "to_week": week, "weeks": old["weeks"]})
		plan["history"] = hist.slice(-10)
		plan["start_overall"] = old["start_overall"]       # progress of the player is not reset by a switch, only the plan clock
		var carried: Dictionary = (old["start_attrs"] as Dictionary).duplicate()
		for a in (plan["start_attrs"] as Dictionary):      # attributes the old plan never tracked start at their value now
			if not carried.has(a):
				carried[a] = plan["start_attrs"][a]
		plan["start_attrs"] = carried
	plans[p.id] = plan
	return ""


## One-off upgrade of a plan written before the detailed attributes existed: template plans take the detailed template for the player's
## position (clock, cycles and history are kept); attribute / custom plans keep their broad targets, which still train. New tracked
## attributes start at their current value.
func _upgrade(p: PlayerData, plan: Dictionary) -> void:
	if int(plan.get("v", 1)) >= PLAN_VERSION:
		return
	plan["v"] = PLAN_VERSION
	DetailedAttributes.ensure(p)
	if str(plan.get("type", "")) in TEMPLATE_TYPES:
		var built := _items_for(p, str(plan["type"]), {"role": plan.get("role", ""), "target_position": plan.get("target_position", "")})
		if str(built["error"]) == "" and not (built["items"] as Array).is_empty():
			plan["items"] = built["items"]
			plan["weights"] = weights_of(built["items"])
	for k in ["start_attrs", "cycle_start_attrs"]:
		var m: Dictionary = plan.get(k, {})
		for a in tracked_attrs(p):
			if not m.has(a):
				m[a] = p.get_attribute(a)
		plan[k] = m


static func _same_plan(a: Dictionary, b: Dictionary) -> bool:
	return a["type"] == b["type"] and a["weights"] == b["weights"] and a["target_position"] == b["target_position"] and a["role"] == b["role"]


## Every player gets a plan: the position template unless the manager chose another.
func ensure(p: PlayerData, week: int) -> Dictionary:
	if not plans.has(p.id):
		assign(p, "position", week)
		plans[p.id]["auto"] = true
	_upgrade(p, plans[p.id])
	return plans[p.id]


func set_intensity(pid: String, value: float) -> bool:
	if not plans.has(pid):
		return false
	plans[pid]["intensity"] = clampf(value, 0.0, 1.0)
	return true


func remove(pid: String) -> void:
	plans.erase(pid)


## Plan-clock multiplier: adaptation after a switch, then up to CONSISTENCY_MAX for staying with the plan.
static func consistency(plan: Dictionary) -> float:
	var w := int(plan.get("weeks", 0))
	if w < DevConfig.PLAN_SWITCH_ADAPTATION_WEEKS and not (plan["history"] as Array).is_empty():
		return DevConfig.PLAN_SWITCH_ADAPTATION
	return lerpf(DevConfig.CONSISTENCY_MIN, DevConfig.CONSISTENCY_MAX, clampf(float(w) / float(DevConfig.CONSISTENCY_FULL_WEEKS), 0.0, 1.0))


## Progress view of a plan for the screens: per target attribute {attr, share, start, current, gain}, weeks, overall change, the
## leading coaching department and an ESTIMATE of weeks per attribute point at neutral coaching (null growth is reported as -1).
func progress(p: PlayerData, facility_quality: float = 0.5) -> Dictionary:
	var plan := plan_for(p.id)
	if plan.is_empty():
		return {}
	var targets: Array = []
	var lead_attr := ""
	var lead_share := -1.0
	for a in (plan["weights"] as Dictionary):
		var share := float(plan["weights"][a])
		var start := int((plan["start_attrs"] as Dictionary).get(a, p.get_attribute(a)))
		targets.append({"attr": a, "share": share, "start": start, "current": p.get_attribute(a), "gain": p.get_attribute(a) - start,
				"progress": float(p.growth_progress.get(a, 0.0))})
		if share > lead_share:
			lead_share = share
			lead_attr = a
	targets.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["share"]) > float(y["share"]))
	var per_week := 0.0
	if lead_attr != "":
		per_week = ProgressionModel.weekly_points(p, lead_attr, facility_quality, float(plan["intensity"])) * lead_share * _spread(plan)
	return {"plan": plan, "targets": targets, "weeks": int(plan["weeks"]), "overall_change": p.get_overall() - int(plan["start_overall"]),
			"department": DevConfig.lead_department(lead_attr), "weeks_per_point": (1.0 / per_week) if per_week > 0.001 else -1.0,
			"cycles": int(plan["cycles"]), "conversion_weeks_left": maxi(DevConfig.CONVERSION_WEEKS - int(plan["weeks"]), 0) if plan["type"] == "conversion" else 0}


static func _spread(plan: Dictionary) -> float:
	return minf(1.0 + DevConfig.FOCUS_SPREAD * float(maxi((plan["weights"] as Dictionary).size() - 1, 0)), DevConfig.FOCUS_SPREAD_CAP)


func to_dict() -> Dictionary:
	return {"plans": plans.duplicate(true)}


static func from_dict(d: Dictionary, valid_player: Callable = Callable()) -> DevelopmentPlans:
	var out := DevelopmentPlans.new()
	for pid in (d.get("plans", {}) as Dictionary):
		var r: Variant = d["plans"][pid]
		if typeof(r) != TYPE_DICTIONARY or str(pid) == "":
			continue
		if valid_player.is_valid() and not bool(valid_player.call(str(pid))):
			continue                                              # invalid reference: the player no longer exists
		var plan := (r as Dictionary).duplicate(true)
		var weights := {}
		for a in (plan.get("weights", {}) as Dictionary):
			if (str(a) in PlayerData.ATTRIBUTES or DetailedAttributes.has(str(a))) and float(plan["weights"][a]) > 0.0:
				weights[str(a)] = float(plan["weights"][a])
		if weights.is_empty() or not (str(plan.get("type", "")) in TYPES):
			continue
		plan["weights"] = weights
		plan["player_id"] = str(pid)
		for k in ["started_week", "switched_week", "weeks", "start_overall", "cycle_weeks", "cycles"]:
			plan[k] = int(plan.get(k, 0))
		plan["intensity"] = clampf(float(plan.get("intensity", DevConfig.INTENSITY_DEFAULT)), 0.0, 1.0)
		plan["v"] = int(plan.get("v", 1))
		for k in ["start_attrs", "cycle_start_attrs"]:
			var m := {}
			for a in (plan.get(k, {}) as Dictionary):
				m[str(a)] = int(plan[k][a])
			plan[k] = m
		if typeof(plan.get("history")) != TYPE_ARRAY:
			plan["history"] = []
		if typeof(plan.get("items")) != TYPE_ARRAY:
			plan["items"] = []
		out.plans[str(pid)] = plan
	return out
