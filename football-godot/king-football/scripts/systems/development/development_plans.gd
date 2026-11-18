class_name DevelopmentPlans
extends RefCounted

## Individual development plans (one per player). The player model has seven attributes (pace, shooting, passing, dribbling, defending,
## physical, goalkeeping); a plan lists FOCUS ITEMS (the fine-grained skills of a position, e.g. "Finishing", "Heading") and each item
## maps to one of those seven attributes, so the plan's attribute weights are the number of items per attribute. The labels are what the
## manager reads; the attributes are what actually grows. Plans are templates, never restrictions: a custom plan may target any 1-3
## attributes, and a position conversion trains a new position.
## Plan types: balanced, position, attribute, role, long_term, custom, conversion.

const TYPES: Array[String] = ["balanced", "position", "attribute", "role", "long_term", "custom", "conversion"]
const MAX_CUSTOM_ATTRIBUTES := 3
const GOAL_POINTS := 3                      # attribute points (across the plan's targets) that complete one plan cycle
const GOAL_MAX_WEEKS := 26                  # ... or this many weeks, whichever comes first

## Position group -> list of [label key, attribute].
const TEMPLATES := {
	"gk": [["DEV_FOCUS_SHOT_STOPPING", "goalkeeping"], ["DEV_FOCUS_REFLEXES", "goalkeeping"], ["DEV_FOCUS_HANDLING", "goalkeeping"],
			["DEV_FOCUS_POSITIONING", "goalkeeping"], ["DEV_FOCUS_DIVING", "goalkeeping"], ["DEV_FOCUS_DISTRIBUTION", "passing"],
			["DEV_FOCUS_ONE_ON_ONE", "goalkeeping"]],
	"cb": [["DEV_FOCUS_DEF_POSITIONING", "defending"], ["DEV_FOCUS_TACKLING", "defending"], ["DEV_FOCUS_INTERCEPTIONS", "defending"],
			["DEV_FOCUS_STRENGTH", "physical"], ["DEV_FOCUS_AERIAL", "physical"], ["DEV_FOCUS_ANTICIPATION", "defending"],
			["DEV_FOCUS_PASSING", "passing"]],
	"fb": [["DEV_FOCUS_DEF_AWARENESS", "defending"], ["DEV_FOCUS_PACE", "pace"], ["DEV_FOCUS_STAMINA", "physical"],
			["DEV_FOCUS_CROSSING", "passing"], ["DEV_FOCUS_TACKLING", "defending"], ["DEV_FOCUS_DEF_POSITIONING", "defending"],
			["DEV_FOCUS_BALL_CONTROL", "dribbling"]],
	"cm": [["DEV_FOCUS_PASSING", "passing"], ["DEV_FOCUS_VISION", "passing"], ["DEV_FOCUS_BALL_CONTROL", "dribbling"],
			["DEV_FOCUS_STAMINA", "physical"], ["DEV_FOCUS_DEF_AWARENESS", "defending"], ["DEV_FOCUS_LONG_SHOTS", "shooting"],
			["DEV_FOCUS_DEF_POSITIONING", "defending"]],
	"am": [["DEV_FOCUS_VISION", "passing"], ["DEV_FOCUS_CREATIVITY", "dribbling"], ["DEV_FOCUS_DRIBBLING", "dribbling"],
			["DEV_FOCUS_PASSING", "passing"], ["DEV_FOCUS_BALL_CONTROL", "dribbling"], ["DEV_FOCUS_FINISHING", "shooting"],
			["DEV_FOCUS_LONG_SHOTS", "shooting"]],
	"winger": [["DEV_FOCUS_ACCELERATION", "pace"], ["DEV_FOCUS_SPRINT_SPEED", "pace"], ["DEV_FOCUS_DRIBBLING", "dribbling"],
			["DEV_FOCUS_CROSSING", "passing"], ["DEV_FOCUS_AGILITY", "dribbling"], ["DEV_FOCUS_FINISHING", "shooting"],
			["DEV_FOCUS_ATT_POSITIONING", "shooting"]],
	"st": [["DEV_FOCUS_FINISHING", "shooting"], ["DEV_FOCUS_SHOT_POWER", "shooting"], ["DEV_FOCUS_ATT_POSITIONING", "shooting"],
			["DEV_FOCUS_OFF_THE_BALL", "pace"], ["DEV_FOCUS_HEADING", "physical"], ["DEV_FOCUS_COMPOSURE", "shooting"],
			["DEV_FOCUS_ACCELERATION", "pace"]],
}
## Role-specific variants (group -> role id -> items).
const ROLES := {
	"gk": {"sweeper_keeper": [["DEV_FOCUS_DISTRIBUTION", "passing"], ["DEV_FOCUS_ONE_ON_ONE", "goalkeeping"], ["DEV_FOCUS_POSITIONING", "goalkeeping"], ["DEV_FOCUS_PACE", "pace"]]},
	"cb": {"ball_playing": [["DEV_FOCUS_PASSING", "passing"], ["DEV_FOCUS_COMPOSURE", "passing"], ["DEV_FOCUS_BALL_CONTROL", "dribbling"], ["DEV_FOCUS_TACKLING", "defending"]]},
	"fb": {"attacking_fullback": [["DEV_FOCUS_CROSSING", "passing"], ["DEV_FOCUS_PACE", "pace"], ["DEV_FOCUS_DRIBBLING", "dribbling"], ["DEV_FOCUS_STAMINA", "physical"]]},
	"cm": {"box_to_box": [["DEV_FOCUS_STAMINA", "physical"], ["DEV_FOCUS_TACKLING", "defending"], ["DEV_FOCUS_PASSING", "passing"], ["DEV_FOCUS_LONG_SHOTS", "shooting"]]},
	"am": {"shadow_striker": [["DEV_FOCUS_FINISHING", "shooting"], ["DEV_FOCUS_OFF_THE_BALL", "pace"], ["DEV_FOCUS_LONG_SHOTS", "shooting"], ["DEV_FOCUS_CREATIVITY", "dribbling"]]},
	"winger": {"inside_forward": [["DEV_FOCUS_FINISHING", "shooting"], ["DEV_FOCUS_DRIBBLING", "dribbling"], ["DEV_FOCUS_ACCELERATION", "pace"], ["DEV_FOCUS_ATT_POSITIONING", "shooting"]]},
	"st": {"target_man": [["DEV_FOCUS_HEADING", "physical"], ["DEV_FOCUS_STRENGTH", "physical"], ["DEV_FOCUS_COMPOSURE", "shooting"], ["DEV_FOCUS_FINISHING", "shooting"]],
			"poacher": [["DEV_FOCUS_FINISHING", "shooting"], ["DEV_FOCUS_ATT_POSITIONING", "shooting"], ["DEV_FOCUS_ACCELERATION", "pace"], ["DEV_FOCUS_OFF_THE_BALL", "pace"]]},
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
		for i in 3:
			items.append(["DEV_FOCUS_GOALKEEPING", "goalkeeping"])
		for a in ["pace", "passing", "physical"]:
			items.append(["DEV_ATTR_" + a.to_upper(), a])
		return items
	for a in PlayerData.ATTRIBUTES:
		if a != "goalkeeping":
			items.append(["DEV_ATTR_" + a.to_upper(), a])
	return items


func plan_for(pid: String) -> Dictionary:
	return plans.get(pid, {})


func _new_plan(p: PlayerData, type: String, items: Array, week: int) -> Dictionary:
	var start_attrs := {}
	for a in PlayerData.ATTRIBUTES:
		start_attrs[a] = p.get_attribute(a)
	return {"player_id": p.id, "type": type, "items": items, "weights": weights_of(items), "intensity": DevConfig.INTENSITY_DEFAULT,
			"started_week": week, "switched_week": week, "weeks": 0, "start_overall": p.get_overall(), "start_attrs": start_attrs,
			"cycle_start_attrs": start_attrs.duplicate(), "cycle_weeks": 0, "cycles": 0, "target_position": "", "long_term": type == "long_term",
			"role": "", "history": [], "auto": false}


## Assigns (or switches to) a plan. params: role, attribute, attrs {attribute: weight}, target_position (name), intensity 0..1.
## Returns "" or an error text. A switch keeps the old plan in `history` and starts the adaptation period.
func assign(p: PlayerData, type: String, week: int, params: Dictionary = {}) -> String:
	if p == null:
		return "unknown player"
	if not (type in TYPES):
		return "unknown plan type '%s'" % type
	var group := group_of(p.position)
	var items: Array = []
	var role := ""
	var target := ""
	match type:
		"balanced":
			items = _balanced_items(p)
		"position", "long_term":
			items = (TEMPLATES[group] as Array).duplicate(true)
		"role":
			role = str(params.get("role", ""))
			var rs: Dictionary = ROLES.get(group, {})
			if not rs.has(role):
				return "no role '%s' for this position" % role
			items = (rs[role] as Array).duplicate(true)
		"attribute":
			var a := str(params.get("attribute", ""))
			if not (a in PlayerData.ATTRIBUTES):
				return "unknown attribute '%s'" % a
			if a == "goalkeeping" and p.position != PlayerData.Position.GK:
				return "only goalkeepers train goalkeeping"
			items = [["DEV_ATTR_" + a.to_upper(), a]]
		"custom":
			var attrs: Dictionary = params.get("attrs", {})
			if attrs.is_empty() or attrs.size() > MAX_CUSTOM_ATTRIBUTES:
				return "a custom plan needs 1 to %d attributes" % MAX_CUSTOM_ATTRIBUTES
			for a in attrs:
				if not (str(a) in PlayerData.ATTRIBUTES) or float(attrs[a]) <= 0.0:
					return "invalid custom attribute '%s'" % str(a)
				if str(a) == "goalkeeping" and p.position != PlayerData.Position.GK:
					return "only goalkeepers train goalkeeping"
				for i in clampi(roundi(float(attrs[a]) * 2.0), 1, 6):          # weight 0.5 steps -> item count
					items.append(["DEV_ATTR_" + str(a).to_upper(), str(a)])
		"conversion":
			target = str(params.get("target_position", ""))
			if not (target in PlayerData.Position.keys()):
				return "unknown position '%s'" % target
			if target == PlayerData.Position.keys()[p.position] or p.secondary_positions.has(target):
				return "player already plays %s" % target
			if (target == "GK") != (p.position == PlayerData.Position.GK):
				return "goalkeepers and outfield players cannot convert to each other"
			items = (TEMPLATES[group_of(int(PlayerData.Position[target]))] as Array).duplicate(true)
	var plan := _new_plan(p, type, items, week)
	plan["role"] = role
	plan["target_position"] = target
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
		plan["start_attrs"] = old["start_attrs"]
	plans[p.id] = plan
	return ""


static func _same_plan(a: Dictionary, b: Dictionary) -> bool:
	return a["type"] == b["type"] and a["weights"] == b["weights"] and a["target_position"] == b["target_position"] and a["role"] == b["role"]


## Every player gets a plan: the position template unless the manager chose another.
func ensure(p: PlayerData, week: int) -> Dictionary:
	if not plans.has(p.id):
		assign(p, "position", week)
		plans[p.id]["auto"] = true
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
			"department": DevConfig.ATTRIBUTE_LEAD.get(lead_attr, "tactical"), "weeks_per_point": (1.0 / per_week) if per_week > 0.001 else -1.0,
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
			if str(a) in PlayerData.ATTRIBUTES and float(plan["weights"][a]) > 0.0:
				weights[str(a)] = float(plan["weights"][a])
		if weights.is_empty() or not (str(plan.get("type", "")) in TYPES):
			continue
		plan["weights"] = weights
		plan["player_id"] = str(pid)
		for k in ["started_week", "switched_week", "weeks", "start_overall", "cycle_weeks", "cycles"]:
			plan[k] = int(plan.get(k, 0))
		plan["intensity"] = clampf(float(plan.get("intensity", DevConfig.INTENSITY_DEFAULT)), 0.0, 1.0)
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
