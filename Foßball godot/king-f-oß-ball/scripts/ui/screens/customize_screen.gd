extends HubScreen

## Team Customization: create fictional clubs (name, colours, logo template,
## strength), manage your own clubs and export/delete them. Seed teams cannot
## be deleted.

var _name := "New Club FC"
var _short := "NCF"
var _country := 0
var _strength := 55
var _logo := 0
var _primary := Color("2e86c1")
var _secondary := Color("f4d03f")


func build() -> void:
	add_child(UIKit.title(Loc.t("CUSTOM_TEAM_CUSTOMIZATION")))
	var countries: Array = YouthGenerator.NAME_POOLS.keys()
	var form := UIKit.vbox(6)
	var r1 := UIKit.hbox(8)
	r1.add_child(UIKit.label(Loc.t("COMMON_NAME"), 14, UIKit.MUTED))
	var ne := LineEdit.new()
	ne.text = _name
	ne.custom_minimum_size = Vector2(220, 0)
	ne.name = "NameEdit"
	ne.text_changed.connect(func(t: String) -> void: _name = t)
	r1.add_child(ne)
	r1.add_child(UIKit.label(Loc.t("CUSTOM_SHORT"), 14, UIKit.MUTED))
	var se := LineEdit.new()
	se.text = _short
	se.max_length = 5
	se.custom_minimum_size = Vector2(80, 0)
	se.name = "ShortEdit"
	se.text_changed.connect(func(t: String) -> void: _short = t)
	r1.add_child(se)
	r1.add_child(UIKit.label(Loc.t("CUSTOM_COUNTRY"), 14, UIKit.MUTED))
	r1.add_child(UIKit.option(countries, _country, func(i: int) -> void: _country = i))
	form.add_child(r1)
	var r2 := UIKit.hbox(8)
	r2.add_child(UIKit.label(Loc.t("CUSTOM_PRIMARY"), 14, UIKit.MUTED))
	var pc := ColorPickerButton.new()
	pc.color = _primary
	pc.custom_minimum_size = Vector2(60, 28)
	pc.color_changed.connect(func(c: Color) -> void: _primary = c)
	r2.add_child(pc)
	r2.add_child(UIKit.label(Loc.t("CUSTOM_SECONDARY"), 14, UIKit.MUTED))
	var sc := ColorPickerButton.new()
	sc.color = _secondary
	sc.custom_minimum_size = Vector2(60, 28)
	sc.color_changed.connect(func(c: Color) -> void: _secondary = c)
	r2.add_child(sc)
	r2.add_child(UIKit.label(Loc.t("CUSTOM_LOGO"), 14, UIKit.MUTED))
	r2.add_child(UIKit.option(LogoService.TEMPLATES, _logo, func(i: int) -> void: _logo = i))
	r2.add_child(UIKit.label(Loc.t("CUSTOM_STRENGTH"), 14, UIKit.MUTED))
	var st := SpinBox.new()
	st.min_value = ClubCreator.MIN_STRENGTH
	st.max_value = ClubCreator.MAX_STRENGTH
	st.value = _strength
	st.value_changed.connect(func(v: float) -> void: _strength = int(v))
	r2.add_child(st)
	form.add_child(r2)
	var create := UIKit.button(Loc.t("CUSTOM_CREATE_CLUB"), _create.bind(countries), 150)
	create.name = "CreateClub"
	form.add_child(create)
	form.add_child(UIKit.muted(Loc.t("CUSTOM_A_BALANCED_23_PLAYER_SQUAD_IS_GENE")))
	add_child(UIKit.panel(form))
	add_child(UIKit.label(Loc.t("CUSTOM_YOUR_CLUBS"), 16, UIKit.GOLD))
	var found := false
	for t: TeamData in db().list_teams(TeamData.Category.CLUB):
		if not FileAccess.file_exists("%s/%s.json" % [ClubCreator.USER_DIR, t.id]):
			continue
		found = true
		var row := UIKit.hbox(8)
		row.add_child(UIKit.kit_preview(t, "home"))
		row.add_child(UIKit.label(Loc.f("CUSTOM_RATING", [t.display_name, t.short_name, db().get_team_rating(t.id)]), 16))
		row.add_child(UIKit.button(Loc.t("CUSTOM_KITS"), go.bind("kit_editor", {"team_id": t.id}), 70))
		row.add_child(UIKit.button(Loc.t("CUSTOM_EXPORT"), _export.bind(t.id), 80))
		var del := UIKit.button(Loc.t("CUSTOM_DELETE"), _confirm_delete.bind(t.id), 80)
		del.name = "Delete_%s" % t.id
		row.add_child(del)
		add_child(UIKit.panel(row))
	if not found:
		add_child(UIKit.empty_state(Loc.t("CUSTOM_CLUBS_YOU_CREATE_APPEAR_HERE")))


func _create(countries: Array) -> void:
	var res := ClubCreator.create_club(db(), {"name": _name, "short_name": _short, "country": countries[_country],
			"primary": _primary, "secondary": _secondary, "strength": _strength,
			"logo": LogoService.template_ref(LogoService.TEMPLATES[_logo]), "seed": randi()}, true)
	say(Loc.f("CUSTOM_CREATED", _name) if res["ok"] else res["error"], not res["ok"])
	if res["ok"]:
		app().state_changed.emit()
	rebuild()


func _export(team_id: String) -> void:
	var path := "user://exports/%s.json" % team_id
	var err := ClubCreator.export_team(db(), team_id, path)
	say(Loc.f("CUSTOM_EXPORTED_TO", path) if err == "" else err, err != "")


func _confirm_delete(team_id: String) -> void:
	UIKit.confirm(self, Loc.t("CUSTOM_DELETE_THIS_CLUB_AND_ALL_OF_ITS_PL"), _delete.bind(team_id))


func _delete(team_id: String) -> void:
	if app().user_team_id == team_id:
		say(Loc.t("CUSTOM_YOU_ARE_MANAGING_THIS_CLUB_SELECT"), true)
		return
	var err := ClubCreator.delete_user_club(db(), team_id)
	say(Loc.t("CUSTOM_CLUB_DELETED") if err == "" else err, err != "")
	rebuild()
