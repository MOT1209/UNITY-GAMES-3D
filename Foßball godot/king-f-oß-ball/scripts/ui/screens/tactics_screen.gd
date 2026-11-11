extends HubScreen

## Tactical Formation: formation, mentality, pressing, defensive line,
## build-up, passing style and saved presets. Values live in the real
## `Squad`/`TacticsPreset` objects the match engine reads.


func build() -> void:
	if not header("Tactical Formation", true):
		return
	var squad: Squad = app().squad()
	var tactics: TacticsPreset = squad.get_tactics()
	var form_row := UIKit.hbox(8)
	form_row.add_child(UIKit.label("Formation", 15, UIKit.MUTED))
	var ids := FormationData.ids()
	var fo := UIKit.option(ids, maxi(ids.find(squad.formation_id), 0), _on_formation.bind(ids))
	fo.name = "FormationOption"
	form_row.add_child(fo)
	add_child(form_row)
	add_child(_pitch_preview(squad, tactics))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_child(UIKit.label("Mentality", 15, UIKit.MUTED))
	var mo := UIKit.option(TacticsPreset.Mentality.keys(), int(tactics.mentality), _on_mentality)
	mo.name = "MentalityOption"
	grid.add_child(mo)
	grid.add_child(UIKit.label("Pressing intensity", 15, UIKit.MUTED))
	var ps := _slider(tactics.pressing, _on_pressing)
	ps.name = "PressingSlider"
	grid.add_child(ps)
	grid.add_child(UIKit.label("Defensive line", 15, UIKit.MUTED))
	var dl := _slider(tactics.defensive_line, _on_line)
	dl.name = "LineSlider"
	grid.add_child(dl)
	grid.add_child(UIKit.label("Build-up", 15, UIKit.MUTED))
	grid.add_child(UIKit.option(TacticsPreset.BuildUp.keys(), int(tactics.build_up), _on_buildup))
	grid.add_child(UIKit.label("Passing style", 15, UIKit.MUTED))
	grid.add_child(UIKit.option(TacticsPreset.PassingStyle.keys(), int(tactics.passing_style), _on_passing))
	add_child(UIKit.panel(grid))
	# Presets
	add_child(UIKit.label("Presets", 16, UIKit.GOLD))
	var save_row := UIKit.hbox(8)
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "Preset name"
	name_edit.custom_minimum_size = Vector2(200, 0)
	name_edit.name = "PresetName"
	save_row.add_child(name_edit)
	save_row.add_child(UIKit.button("Save current as preset", _save_preset.bind(name_edit), 200))
	add_child(save_row)
	for i in squad.presets.size():
		var p: TacticsPreset = squad.presets[i]
		var row := UIKit.hbox(8)
		row.add_child(UIKit.label("%s%s — %s, press %d, line %d" % [
				"▶ " if i == squad.active_preset else "", p.preset_name,
				TacticsPreset.Mentality.keys()[p.mentality], p.pressing, p.defensive_line], 15))
		var use := UIKit.button("Use", _use_preset.bind(p.preset_name), 60)
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
	var pitch := Control.new()
	pitch.custom_minimum_size = Vector2(300, 180)
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.4, 0.15)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	pitch.add_child(bg)
	for slot in 11:
		var rel := tactics.target_position(squad.formation_id, slot, 0.5)
		var dot := UIKit.color_swatch(Color.WHITE, Vector2(10, 10))
		dot.position = Vector2((rel.x + 1.0) * 0.5 * 280.0 + 10.0, (1.0 - rel.y) * 160.0 + 10.0)
		pitch.add_child(dot)
	return pitch


func _on_formation(index: int, ids: Array) -> void:
	var err: String = app().squad().set_formation(ids[index])
	if err == "":
		app().squad().auto_pick(db())     # re-fit the XI to the new shape
		say("Formation %s — lineup refreshed" % ids[index])
	else:
		say(err, true)
	rebuild()


func _on_mentality(index: int) -> void:
	app().squad().get_tactics().mentality = index as TacticsPreset.Mentality
	say("Mentality updated")


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
		say("Preset '%s' saved" % copy.preset_name)
	else:
		say(err, true)
	rebuild()


func _use_preset(preset_name: String) -> void:
	app().squad().select_preset(preset_name)
	say("Preset '%s' active" % preset_name)
	rebuild()
