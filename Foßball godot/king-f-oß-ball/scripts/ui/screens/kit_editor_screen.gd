extends HubScreen

## Kit Editor: edit home / away / third / goalkeeper kits (colours + pattern)
## with a live preview built from the saved kit data. User clubs are saved to
## disk; other teams change for this session only.

var _slot := 0


func build() -> void:
	add_child(UIKit.title(Loc.t("KIT_KIT_EDITOR")))
	var team_id: String = params.get("team_id", app().user_team_id)
	var team: TeamData = db().get_team(team_id)
	if team == null:
		add_child(UIKit.empty_state(Loc.t("KIT_PICK_A_TEAM_FIRST_TEAM_SELECTION_O")))
		return
	params["team_id"] = team_id
	add_child(UIKit.label(team.display_name, 20, UIKit.GOLD))
	var slot_row := UIKit.hbox(8)
	var so := UIKit.option(Loc.enum_names("KITSLOT", KitEditor.SLOTS), _slot, func(i: int) -> void:
		_slot = i
		rebuild())
	so.name = "SlotOption"
	slot_row.add_child(so)
	add_child(slot_row)
	var slot: String = KitEditor.SLOTS[_slot]
	if not team.kits.has(slot):
		KitEditor.set_field(team, slot, "pattern", "solid")
		for f in KitEditor.COLOR_FIELDS:
			KitEditor.set_field(team, slot, f, team.primary_color.to_html(false))
	var body := UIKit.hbox(24)
	var fields := UIKit.vbox(6)
	for f in KitEditor.COLOR_FIELDS:
		var row := UIKit.hbox(8)
		var l := UIKit.label(Loc.enum_name("KITCOLOR", f), 14, UIKit.MUTED)
		l.custom_minimum_size = Vector2(90, 0)
		row.add_child(l)
		var picker := ColorPickerButton.new()
		picker.color = Color.from_string(str(team.kits[slot].get(f, "ffffff")), Color.WHITE)
		picker.custom_minimum_size = Vector2(70, 28)
		picker.name = "Color_%s" % f
		picker.color_changed.connect(_on_color.bind(team_id, slot, f))
		row.add_child(picker)
		fields.add_child(row)
	var prow := UIKit.hbox(8)
	prow.add_child(UIKit.label(Loc.t("KIT_PATTERN"), 14, UIKit.MUTED))
	var po := UIKit.option(Loc.enum_names("PATTERN", KitEditor.PATTERNS), maxi(KitEditor.PATTERNS.find(str(team.kits[slot].get("pattern", "solid"))), 0),
			_on_pattern.bind(team_id, slot))
	po.name = "PatternOption"
	prow.add_child(po)
	fields.add_child(prow)
	body.add_child(fields)
	body.add_child(UIKit.panel(UIKit.kit_preview(team, slot)))
	add_child(body)
	var save := UIKit.button(Loc.t("KIT_SAVE_KIT"), _save.bind(team_id), 120)
	save.name = "SaveKit"
	add_child(save)


func _on_color(color: Color, team_id: String, slot: String, field: String) -> void:
	var err := KitEditor.set_field(db().get_team(team_id), slot, field, color.to_html(false))
	if err != "":
		say(err, true)


func _on_pattern(index: int, team_id: String, slot: String) -> void:
	var err := KitEditor.set_field(db().get_team(team_id), slot, "pattern", KitEditor.PATTERNS[index])
	say(err if err != "" else Loc.t("KIT_PATTERN_SET"), err != "")
	rebuild()


func _save(team_id: String) -> void:
	var path := "%s/%s.json" % [ClubCreator.USER_DIR, team_id]
	if not FileAccess.file_exists(path):
		say(Loc.t("KIT_KIT_APPLIED_FOR_THIS_SESSION_ONLY"))
		rebuild()
		return
	var err := ClubCreator.export_team(db(), team_id, path)
	say(Loc.t("KIT_KIT_SAVED") if err == "" else err, err != "")
	rebuild()
