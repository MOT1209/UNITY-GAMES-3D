extends HubScreen

## Tactical Formation: formation, mentality, pressing, defensive line,
## build-up, passing style and saved presets. Values live in the real
## `Squad`/`TacticsPreset` objects the match engine reads.


func build() -> void:
	if not header(Loc.t("TACTICS_TACTICAL_FORMATION"), true):
		return
	var squad: Squad = app().squad()
	var tactics: TacticsPreset = squad.get_tactics()
	var form_row := UIKit.hbox(8)
	form_row.add_child(UIKit.label(Loc.t("TACTICS_FORMATION"), 15, UIKit.MUTED))
	var ids := FormationData.ids()
	var fo := UIKit.option(ids, maxi(ids.find(squad.formation_id), 0), _on_formation.bind(ids))
	fo.name = "FormationOption"
	form_row.add_child(fo)
	add_child(form_row)
	add_child(_pitch_preview(squad, tactics))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_child(UIKit.label(Loc.t("TACTICS_MENTALITY"), 15, UIKit.MUTED))
	var mo := UIKit.option(Loc.enum_names("MENTALITY", TacticsPreset.Mentality.keys()), int(tactics.mentality), _on_mentality)
	mo.name = "MentalityOption"
	grid.add_child(mo)
	grid.add_child(UIKit.label(Loc.t("TACTICS_PRESSING_INTENSITY"), 15, UIKit.MUTED))
	var ps := _slider(tactics.pressing, _on_pressing)
	ps.name = "PressingSlider"
	grid.add_child(ps)
	grid.add_child(UIKit.label(Loc.t("TACTICS_DEFENSIVE_LINE"), 15, UIKit.MUTED))
	var dl := _slider(tactics.defensive_line, _on_line)
	dl.name = "LineSlider"
	grid.add_child(dl)
	grid.add_child(UIKit.label(Loc.t("TACTICS_BUILD_UP"), 15, UIKit.MUTED))
	grid.add_child(UIKit.option(Loc.enum_names("BUILDUP", TacticsPreset.BuildUp.keys()), int(tactics.build_up), _on_buildup))
	grid.add_child(UIKit.label(Loc.t("TACTICS_PASSING_STYLE"), 15, UIKit.MUTED))
	grid.add_child(UIKit.option(Loc.enum_names("PASSING", TacticsPreset.PassingStyle.keys()), int(tactics.passing_style), _on_passing))
	add_child(UIKit.panel(grid))
	# Presets
	add_child(UIKit.label(Loc.t("TACTICS_PRESETS"), 16, UIKit.GOLD))
	var save_row := UIKit.hbox(8)
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = Loc.t("TACTICS_PRESET_NAME")
	name_edit.custom_minimum_size = Vector2(200, 0)
	name_edit.name = "PresetName"
	save_row.add_child(name_edit)
	save_row.add_child(UIKit.button(Loc.t("TACTICS_SAVE_CURRENT_AS_PRESET"), _save_preset.bind(name_edit), 200))
	add_child(save_row)
	for i in squad.presets.size():
		var p: TacticsPreset = squad.presets[i]
		var row := UIKit.hbox(8)
		row.add_child(UIKit.label(Loc.f("TACTICS_PRESS_LINE", [
				"▶ " if i == squad.active_preset else "", Loc.t("TACTICS_DEFAULT_PRESET") if p.preset_name == "Default" else p.preset_name,
				Loc.enum_name("MENTALITY", TacticsPreset.Mentality.keys()[p.mentality]), p.pressing, p.defensive_line]), 15))
		var use := UIKit.button(Loc.t("TACTICS_USE"), _use_preset.bind(p.preset_name), 60)
		use.name = "UsePreset_%d" % i
		row.add_child(use)
		add_child(row)


func _slider(value: int, callback: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = 0
	s.max_value = 100
	s.step = 5
	s.value = value
	s.custom_minimum_size = Vector2(220, 20)
	s.value_changed.connect(callback)
	return s


## Simple top-down pitch with a dot per formation slot (reflects real slot data).
func _pitch_preview(squad: Squad, tactics: TacticsPreset) -> Control:
	var pitch := PitchDiagram.new()
	pitch.name = "PitchPreview"          # drawn directly: never mirrored, never loses its markers in RTL
	var pts: Array[Vector2] = []
	for slot in 11:
		pts.append(tactics.target_position(squad.formation_id, slot, 0.5))
	pitch.set_points(pts)
	return pitch


func _on_formation(index: int, ids: Array) -> void:
	var err: String = app().squad().set_formation(ids[index])
	if err == "":
		app().squad().auto_pick(db())     # re-fit the XI to the new shape
		say(Loc.f("TACTICS_FORMATION_LINEUP_REFRESHED", ids[index]))
	else:
		say(err, true)
	rebuild()


func _on_mentality(index: int) -> void:
	app().squad().get_tactics().mentality = index as TacticsPreset.Mentality
	say(Loc.t("TACTICS_MENTALITY_UPDATED"))


func _on_pressing(value: float) -> void:
	app().squad().get_tactics().pressing = int(value)


func _on_line(value: float) -> void:
	app().squad().get_tactics().defensive_line = int(value)


func _on_buildup(index: int) -> void:
	app().squad().get_tactics().build_up = index as TacticsPreset.BuildUp


func _on_passing(index: int) -> void:
	app().squad().get_tactics().passing_style = index as TacticsPreset.PassingStyle


func _save_preset(edit: LineEdit) -> void:
	var squad: Squad = app().squad()
	var current := squad.get_tactics()
	var copy := TacticsPreset.from_dict(current.to_dict())
	copy.preset_name = edit.text.strip_edges()
	var err := squad.save_preset(copy)
	if err == "":
		squad.select_preset(copy.preset_name)
		say(Loc.f("TACTICS_PRESET_SAVED", copy.preset_name))
	else:
		say(err, true)
	rebuild()


func _use_preset(preset_name: String) -> void:
	app().squad().select_preset(preset_name)
	say(Loc.f("TACTICS_PRESET_ACTIVE", preset_name))
	rebuild()
