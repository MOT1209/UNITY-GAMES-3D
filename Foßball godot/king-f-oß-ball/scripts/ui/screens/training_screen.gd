extends HubScreen

## Youth Training: group focus, intensity, individual focus, weekly processing
## and development reports.

var _last_gains := {}
var _player_index := 0


func build() -> void:
	if not header("Youth Training", true):
		return
	var ac: Academy = app().academy()
	var plan: TrainingSystem = app().training.get(app().user_team_id)
	if ac == null or plan == null:
		add_child(UIKit.empty_state("Only clubs have an academy."))
		return
	var cats: Array = TrainingSystem.CATEGORIES.keys()
	add_child(UIKit.label("Group plans", 16, UIKit.GOLD))
	for group in AcademyConfig.group_ids():
		var row := UIKit.hbox(8)
		row.add_child(UIKit.label(group, 15, UIKit.MUTED))
		var o := UIKit.option(["Rest"] + cats.map(func(c: String) -> String: return TrainingSystem.CATEGORIES[c]),
				cats.find(plan.group_focus.get(group, "")) + 1, _set_group.bind(group, cats))
		o.name = "Group_%s" % group
		row.add_child(o)
		add_child(row)
	var irow := UIKit.hbox(8)
	irow.add_child(UIKit.label("Intensity", 15, UIKit.MUTED))
	var sl := HSlider.new()
	sl.min_value = 0
	sl.max_value = 100
	sl.step = 5
	sl.value = plan.intensity * 100.0
	sl.custom_minimum_size = Vector2(200, 20)
	sl.value_changed.connect(func(v: float) -> void: plan.set_intensity(v / 100.0))
	sl.name = "IntensitySlider"
	irow.add_child(sl)
	var adv1 := UIKit.button("Train 1 week", _advance.bind(1), 130)
	adv1.name = "Train1"
	irow.add_child(adv1)
	irow.add_child(UIKit.button("Train 4 weeks", _advance.bind(4), 130))
	add_child(irow)
	add_child(UIKit.muted("Week %d · heavy training builds fitness cost; rest weeks recover it." % plan.week))
	if ac.roster_ids.is_empty():
		add_child(UIKit.empty_state("No prospects to train."))
		return
	# Individual focus
	var players: Array = ac.roster_ids.map(func(id: String) -> PlayerData: return db().get_player(id))
	_player_index = clampi(_player_index, 0, players.size() - 1)
	var ind := UIKit.hbox(8)
	ind.add_child(UIKit.label("Individual", 15, UIKit.MUTED))
	ind.add_child(UIKit.option(players.map(func(p: PlayerData) -> String: return p.display_name), _player_index,
			func(i: int) -> void:
				_player_index = i
				rebuild()))
	var chosen: PlayerData = players[_player_index]
	var io := UIKit.option(["Group plan"] + cats.map(func(c: String) -> String: return TrainingSystem.CATEGORIES[c]),
			cats.find(plan.individual_focus.get(chosen.id, "")) + 1, _set_individual.bind(chosen.id, cats))
	io.name = "IndividualOption"
	ind.add_child(io)
	add_child(ind)
	add_child(UIKit.label("Progress reports", 16, UIKit.GOLD))
	var rows: Array = []
	for p: PlayerData in players:
		var rep := ProgressionModel.development_report(p)
		rows.append([p.display_name, p.age, overall_text(p), "%+d" % rep["overall_gain"], p.fitness,
				("trained" if _last_gains.has(p.id) else "")])
	add_child(UIKit.scroll(UIKit.table(["Name", "Age", "OVR/POT", "Gain", "Fitness", "This week"], rows)))


func _set_group(index: int, group: String, cats: Array) -> void:
	var err: String = app().training[app().user_team_id].set_group_focus(group, "" if index == 0 else cats[index - 1])
	say(err if err != "" else "%s plan updated" % group, err != "")


func _set_individual(index: int, pid: String, cats: Array) -> void:
	var err: String = app().training[app().user_team_id].set_individual_focus(db(), pid, "" if index == 0 else cats[index - 1])
	say(err if err != "" else "Individual plan updated", err != "")


func _advance(weeks: int) -> void:
	var plan: TrainingSystem = app().training[app().user_team_id]
	_last_gains = {}
	for i in weeks:
		var gains: Dictionary = plan.advance_week(db(), app().academy())
		for k in gains:
			_last_gains[k] = true
	say("%d week(s) of training done — %d player(s) improved" % [weeks, _last_gains.size()])
	rebuild()
