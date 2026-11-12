extends HubScreen

## Youth Training: group focus, intensity, individual focus, weekly processing
## and development reports.

var _last_gains := {}
var _player_index := 0


func build() -> void:
	if not header(Loc.t("TRAIN_YOUTH_TRAINING"), true):
		return
	var ac: Academy = app().academy()
	var plan: TrainingSystem = app().training.get(app().user_team_id)
	if ac == null or plan == null:
		add_child(UIKit.empty_state(Loc.t("COMMON_ONLY_CLUBS_HAVE_AN_ACADEMY")))
		return
	var cats: Array = TrainingSystem.CATEGORIES.keys()
	add_child(UIKit.label(Loc.t("TRAIN_GROUP_PLANS"), 16, UIKit.GOLD))
	for group in AcademyConfig.group_ids():
		var row := UIKit.hbox(8)
		row.add_child(UIKit.label(group, 15, UIKit.MUTED))
		var o := UIKit.option([Loc.t("TRAIN_REST")] + cats.map(func(c: String) -> String: return Loc.enum_name("CAT", c)),
				cats.find(plan.group_focus.get(group, "")) + 1, _set_group.bind(group, cats))
		o.name = "Group_%s" % group
		row.add_child(o)
		add_child(row)
	var irow := UIKit.hbox(8)
	irow.add_child(UIKit.label(Loc.t("TRAIN_INTENSITY"), 15, UIKit.MUTED))
	var sl := HSlider.new()
	sl.min_value = 0
	sl.max_value = 100
	sl.step = 5
	sl.value = plan.intensity * 100.0
	sl.custom_minimum_size = Vector2(200, 20)
	sl.value_changed.connect(func(v: float) -> void: plan.set_intensity(v / 100.0))
	sl.name = "IntensitySlider"
	irow.add_child(sl)
	# Training runs on the career calendar only: one training week per career week.
	var adv1 := UIKit.button(Loc.t("TRAIN_NEXT_WEEK"), _advance, 130)
	adv1.name = "Train1"
	adv1.disabled = app().career == null
	irow.add_child(adv1)
	add_child(irow)
	add_child(UIKit.muted(Loc.t("TRAIN_CALENDAR_NOTE") if app().career != null else Loc.t("TRAIN_NEEDS_CAREER")))
	if ac.roster_ids.is_empty():
		add_child(UIKit.empty_state(Loc.t("TRAIN_NO_PROSPECTS_TO_TRAIN")))
		return
	# Individual focus
	var players: Array = ac.roster_ids.map(func(id: String) -> PlayerData: return db().get_player(id))
	_player_index = clampi(_player_index, 0, players.size() - 1)
	var ind := UIKit.hbox(8)
	ind.add_child(UIKit.label(Loc.t("TRAIN_INDIVIDUAL"), 15, UIKit.MUTED))
	ind.add_child(UIKit.option(players.map(func(p: PlayerData) -> String: return p.display_name), _player_index,
			func(i: int) -> void:
				_player_index = i
				rebuild()))
	var chosen: PlayerData = players[_player_index]
	var io := UIKit.option([Loc.t("TRAIN_GROUP_PLAN")] + cats.map(func(c: String) -> String: return Loc.enum_name("CAT", c)),
			cats.find(plan.individual_focus.get(chosen.id, "")) + 1, _set_individual.bind(chosen.id, cats))
	io.name = "IndividualOption"
	ind.add_child(io)
	add_child(ind)
	add_child(UIKit.label(Loc.t("TRAIN_PROGRESS_REPORTS"), 16, UIKit.GOLD))
	var rows: Array = []
	for p: PlayerData in players:
		var rep := ProgressionModel.development_report(p)
		rows.append([p.display_name, p.age, overall_text(p), "%+d" % rep["overall_gain"], p.fitness,
				(Loc.t("TRAIN_TRAINED") if _last_gains.has(p.id) else "")])
	add_child(UIKit.scroll(UIKit.table([Loc.t("COMMON_NAME"), Loc.t("COMMON_AGE"), Loc.t("COMMON_OVR_POT"), Loc.t("TRAIN_GAIN"), Loc.t("TRAIN_FITNESS"), Loc.t("TRAIN_THIS_WEEK")], rows)))


func _set_group(index: int, group: String, cats: Array) -> void:
	var err: String = app().training[app().user_team_id].set_group_focus(group, "" if index == 0 else cats[index - 1])
	say(err if err != "" else Loc.f("TRAIN_PLAN_UPDATED", group), err != "")


func _set_individual(index: int, pid: String, cats: Array) -> void:
	var err: String = app().training[app().user_team_id].set_individual_focus(db(), pid, "" if index == 0 else cats[index - 1])
	say(err if err != "" else Loc.t("TRAIN_INDIVIDUAL_PLAN_UPDATED"), err != "")


func _advance() -> void:
	var info: Dictionary = app().advance_week()
	if info.is_empty():
		say(Loc.t("COMMON_START_A_CAREER_FIRST"), true)
		return
	_last_gains = {}
	for k in info["trained_ids"]:
		_last_gains[k] = true
	say(Loc.f("TRAIN_WEEK_PLAYER_S_IMPROVED", [info["week"], _last_gains.size()]))
	rebuild()
