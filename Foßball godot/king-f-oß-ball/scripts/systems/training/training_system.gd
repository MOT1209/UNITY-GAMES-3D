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
## Absolute career week last processed (-1 = never synced). Training only moves
## when the career calendar moves, and never twice for the same week.
var calendar_week: int = -1
const MAX_CATCH_UP := 4


## Applies the training weeks owed up to the career's `absolute_week`. Idempotent:
## calling it again for the same week does nothing. Returns {player_id: [attrs]}.
func sync_to_calendar(db: Node, academy: Academy, absolute_week: int) -> Dictionary:
	if calendar_week < 0:
		calendar_week = absolute_week - 1     # first sync processes just this week
	if absolute_week <= calendar_week:
		return {}
	var owed := mini(absolute_week - calendar_week, MAX_CATCH_UP)
	calendar_week = absolute_week
	var result := {}
	for i in owed:
		var gains := advance_week(db, academy)
		for pid in gains:
			result[pid] = gains[pid]
	return result


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
	var group := AcademyConfig.group_for_age(p.age)
	if group == "" and AcademyConfig.is_over_age(p.age):
		group = AcademyConfig.group_ids()[-1]     # kept over-age prospects follow the oldest group's plan
	return str(group_focus.get(group, ""))


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
			"intensity": intensity, "week": week, "calendar_week": calendar_week}


static func from_dict(d: Dictionary) -> TrainingSystem:
	var t := TrainingSystem.new()
	t.group_focus = (d.get("group_focus", {}) as Dictionary).duplicate()
	t.individual_focus = (d.get("individual_focus", {}) as Dictionary).duplicate()
	t.intensity = float(d.get("intensity", 0.6))
	t.week = int(d.get("week", 0))
	t.calendar_week = int(d.get("calendar_week", -1))
	return t
