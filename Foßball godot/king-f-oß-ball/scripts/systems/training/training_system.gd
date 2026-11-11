class_name TrainingSystem
extends RefCounted

## Academy training plans + weekly processing (Phase T5).
## Plan = per-age-group default focus + per-player overrides + intensity.
## Individual focus beats group focus. Categories map 1:1 to attributes.

const CATEGORIES := {
	"pace": "Pace Training", "shooting": "Shooting Training", "passing": "Passing Training",
	"dribbling": "Dribbling Training", "defending": "Defending Training",
	"physical": "Physical Training", "goalkeeping": "Goalkeeping Training",
}

var group_focus: Dictionary = {}    # group_id -> attribute
var individual_focus: Dictionary = {}  # player_id -> attribute
var intensity: float = 0.6          # 0..1
var week: int = 0


func set_group_focus(group_id: String, attr: String) -> String:
	if not (group_id in AcademyConfig.group_ids()):
		return "unknown group '%s'" % group_id
	if attr != "" and not CATEGORIES.has(attr):
		return "unknown training category '%s'" % attr
	group_focus[group_id] = attr
	return ""


func set_individual_focus(db: Node, player_id: String, attr: String) -> String:
	if db.get_player(player_id) == null:
		return "unknown player '%s'" % player_id
	if attr != "" and not CATEGORIES.has(attr):
		return "unknown training category '%s'" % attr
	if attr == "":
		individual_focus.erase(player_id)
	else:
		individual_focus[player_id] = attr
	return ""


func set_intensity(value: float) -> void:
	intensity = clampf(value, 0.0, 1.0)


func focus_for(p: PlayerData) -> String:
	if individual_focus.has(p.id):
		return individual_focus[p.id]
	return str(group_focus.get(AcademyConfig.group_for_age(p.age), ""))


## Runs one training week for the whole academy. Returns {player_id: [attrs gained]}.
func advance_week(db: Node, academy: Academy) -> Dictionary:
	week += 1
	var result := {}
	for pid in academy.roster_ids:
		var p: PlayerData = db.get_player(pid)
		if p == null:
			continue
		var attr := focus_for(p)
		if attr == "":
			# Rest week: fitness recovers, no development.
			p.fitness = clampi(p.fitness + 5, 0, 100)
			continue
		if ProgressionModel.train_week(p, attr, academy.quality, intensity, week) > 0:
			result[pid] = [attr]
	return result


## Season rollover: everyone ages one year. Returns ids that are now too old
## for the academy (they need a promotion/release decision in Phase T6).
func age_up(db: Node, academy: Academy) -> Array[String]:
	var aged_out: Array[String] = []
	for pid in academy.roster_ids:
		var p: PlayerData = db.get_player(pid)
		if p == null:
			continue
		p.age += 1
		p.development_history.append({"event": "birthday", "age": p.age, "overall": p.get_overall()})
		if AcademyConfig.group_for_age(p.age) == "":
			aged_out.append(pid)
	return aged_out


func to_dict() -> Dictionary:
	return {"group_focus": group_focus.duplicate(), "individual_focus": individual_focus.duplicate(),
			"intensity": intensity, "week": week}


static func from_dict(d: Dictionary) -> TrainingSystem:
	var t := TrainingSystem.new()
	t.group_focus = (d.get("group_focus", {}) as Dictionary).duplicate()
	t.individual_focus = (d.get("individual_focus", {}) as Dictionary).duplicate()
	t.intensity = float(d.get("intensity", 0.6))
	t.week = int(d.get("week", 0))
	return t
