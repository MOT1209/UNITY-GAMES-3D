extends HubScreen

## New-career wizard (UX phase 4.1 follow-up): four steps instead of one "Start career" button —
##   1. world   (the default fictional world or an installed data pack such as the real leagues),
##   2. league  (fictional: the King League; data packs: country, then division),
##   3. club    (the division's clubs by strength, with budget and the board's expectation),
##   4. summary (club, league, objective, budget) -> start.
## Back / Next move between steps; Next is enabled once the step has a choice. Switching the world drops a
## running career, so it is confirmed first. Starting uses `AppHub.start_career`, as the old button did.

const STEPS: Array[String] = ["WIZARD_STEP_WORLD", "WIZARD_STEP_LEAGUE", "WIZARD_STEP_CLUB", "WIZARD_STEP_COACH", "WIZARD_STEP_SETTINGS", "WIZARD_STEP_SUMMARY"]

var step := 0
var world_id := ""                 # "" = fictional world, else a data pack id
var league_key := ""               # data packs: LeagueDef key ("" in the fictional world)
var division_index := 0
var club_id := ""
## "club" = choose any club; "scratch" = an unknown manager: three job offers from the weakest clubs of the lowest division (C1.2).
var career_kind := "club"
var wizard_settings := CareerSettings.new()
var coach_name := ""
var coach_country_id := ""
var coach_age := 45
var coach_style := ManagerProfile.DEFAULT_STYLE
var coach_background := "unknown"
## Phase 4: "club" = continue with the club's own manager (when the database has one), "custom" = create your own.
var coach_mode := "custom"
var _initialized := false


func _init() -> void:
	super()
	own_scroll = true       # lays out its own ScrollContainer


func build() -> void:
	add_child(UIKit.title(Loc.t("WIZARD_TITLE")))
	if not _initialized:
		world_id = db().pack_id                  # start from the world that is loaded now
		_initialized = true
	add_child(_step_bar())
	var body := UIKit.vbox(UIKit.SPACE_S)
	body.name = "WizardBody"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	match step:
		0:
			_world_step(body)
		1:
			_league_step(body)
		2:
			_club_step(body)
		3:
			_coach_step(body)
		4:
			_settings_step(body)
		_:
			_summary_step(body)
	add_child(UIKit.scroll(body))
	add_child(_nav_row())


# --- steps ---------------------------------------------------------------------------------

func _step_bar() -> Control:
	var row := UIKit.hbox(UIKit.SPACE_S)
	row.name = "WizardSteps"
	for i in STEPS.size():
		var col := UIKit.vbox(2)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var done := i < step
		var circle := Button.new()
		circle.name = "Step_%d" % i
		circle.text = "✓" if done else Loc.num(i + 1)
		circle.custom_minimum_size = Vector2(44, 44)
		circle.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		circle.disabled = not done                      # a finished step can be revisited; later ones cannot be skipped to
		circle.focus_mode = Control.FOCUS_ALL if done else Control.FOCUS_NONE
		var st := UIKit.box(UIKit.GOLD if i == step else (UIKit.GOOD if done else UIKit.PANEL.lightened(0.12)), UIKit.CLEAR, 0, 22)
		circle.add_theme_stylebox_override("normal", st)
		circle.add_theme_stylebox_override("disabled", st)
		circle.add_theme_stylebox_override("hover", st)
		circle.add_theme_stylebox_override("pressed", st)
		circle.add_theme_color_override("font_color", Color.BLACK if i == step else Color.WHITE)
		circle.add_theme_color_override("font_disabled_color", Color.BLACK if i == step else Color(0.6, 0.66, 0.76))
		circle.pressed.connect(go_to_step.bind(i))
		col.add_child(circle)
		var name_label := UIKit.label(Loc.t(STEPS[i]), 12, UIKit.GOLD if i == step else (UIKit.TEXT if done else UIKit.MUTED))
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		col.add_child(name_label)
		row.add_child(col)
	return row


## Jumps back to a step already passed (the step bar).
func go_to_step(i: int) -> void:
	if i >= 0 and i < step:
		step = i
		rebuild()


func _choice_card(name_text: String, detail: String, chosen: bool, on_pick: Callable, node_name: String, crest_team: Variant = null) -> Control:
	var b := Button.new()
	b.name = node_name
	b.toggle_mode = true
	b.button_pressed = chosen
	b.custom_minimum_size = Vector2(0, 64)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(on_pick)
	var row := UIKit.hbox(UIKit.SPACE_S)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 10.0
	row.offset_right = -10.0
	if crest_team != null:
		var c := UIKit.crest(db(), crest_team, 40, "card")
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(c)
	var text := UIKit.vbox(0)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	var title := UIKit.label(name_text, 17, UIKit.GOLD if chosen else UIKit.TEXT)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(title)
	var d := UIKit.label(detail, 13, UIKit.MUTED)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(d)
	row.add_child(text)
	b.add_child(row)
	return b


func _world_step(body: VBoxContainer) -> void:
	body.add_child(UIKit.label(Loc.t("WIZARD_KIND_TITLE"), 16, UIKit.GOLD))
	body.add_child(_choice_card(Loc.t("WIZARD_KIND_CLUB"), Loc.t("WIZARD_KIND_CLUB_DETAIL"), career_kind == "club", _pick_kind.bind("club"), "Kind_club"))
	body.add_child(_choice_card(Loc.t("WIZARD_KIND_SCRATCH"), Loc.t("WIZARD_KIND_SCRATCH_DETAIL"), career_kind == "scratch", _pick_kind.bind("scratch"), "Kind_scratch"))
	body.add_child(UIKit.muted(Loc.t("WIZARD_WORLD_HINT")))
	body.add_child(_choice_card(Loc.t("SETTINGS_WORLD_DEFAULT"), Loc.t("WIZARD_WORLD_FICTIONAL_DETAIL"),
			world_id == "", _pick_world.bind(""), "World_fictional"))
	for p in TeamDatabase.available_packs():
		var pid := str(p["id"])
		var countries: int = (p.get("countries", []) as Array).size()
		var report: Dictionary = p.get("report", {})
		body.add_child(_choice_card(pack_name(pid, str(p.get("name", pid))),
				Loc.f("WIZARD_WORLD_PACK_DETAIL", [countries, int(report.get("clubs", 0))]),
				world_id == pid, _pick_world.bind(pid), "World_%s" % pid))


func _league_step(body: VBoxContainer) -> void:
	if db().leagues.is_empty():
		body.add_child(UIKit.muted(Loc.t("WIZARD_LEAGUE_FICTIONAL_HINT")))
		body.add_child(_choice_card(Loc.t("LEAGUE_DEFAULT_NAME"), Loc.f("WIZARD_LEAGUE_DETAIL", [division_clubs().size(), Loc.t("LEAGUE_DEFAULT_CUP")]),
				true, func() -> void: pass, "League_fictional"))
		return
	body.add_child(UIKit.muted(Loc.t("WIZARD_LEAGUE_PACK_HINT")))
	var keys: Array = db().leagues.keys()
	keys.sort()
	if league_key == "" or not db().leagues.has(league_key):
		league_key = keys[0]
	var country_row := UIKit.hbox(UIKit.SPACE_S)
	country_row.add_child(UIKit.label(Loc.t("WIZARD_COUNTRY"), 15, UIKit.MUTED))
	var co := UIKit.option(keys.map(func(k: String) -> String: return Loc.country((db().leagues[k] as LeagueDef).country)),
			keys.find(league_key), func(i: int) -> void:
				league_key = keys[i]
				division_index = 0
				club_id = ""
				rebuild())
	co.name = "CountryOption"
	country_row.add_child(co)
	body.add_child(country_row)
	var divs: Array = (db().leagues[league_key] as LeagueDef).divisions
	if career_kind == "scratch":
		body.add_child(UIKit.muted(Loc.t("WIZARD_SCRATCH_LEAGUE_HINT")))
		return
	for i in divs.size():
		var d: Dictionary = divs[i]
		var present := _clubs_of(d).size()
		if present == 0:
			continue                  # a division without clubs cannot be chosen: it would block "Next"
		body.add_child(_choice_card("%s · %s" % [Loc.ltr(str(d["tier"])), LeaguePyramid.label(str(d["name"]))],
				Loc.f("WIZARD_DIVISION_DETAIL", [present, int(d.get("promote", 0)), int(d.get("relegate", 0))]),
				i == division_index, _pick_division.bind(i), "Division_%d" % i))


func _club_step(body: VBoxContainer) -> void:
	body.add_child(UIKit.muted(Loc.t("WIZARD_SCRATCH_CLUB_HINT") if career_kind == "scratch" else Loc.t("WIZARD_CLUB_HINT")))
	var div := division()
	for t: TeamData in division_clubs():
		var obj := BoardObjectives.for_club(db(), t.id, div)
		body.add_child(_choice_card(t.display_name, Loc.f("WIZARD_CLUB_DETAIL", [db().get_team_rating(t.id), Loc.money(t.budget),
				int(obj.get("target_rank", 0))]), t.id == club_id, _pick_club.bind(t.id), "Club_%s" % t.id, t))


## C1.2: the manager's profile. Style gives a small fixed edge (shown on each card); the background sets the starting reputation.
## The club's own manager from the database ("" when it stores none).
func club_manager_name() -> String:
	var t: TeamData = db().get_team(club_id)
	return t.manager_name.strip_edges() if t != null else ""


## The mode really used: "club" only while the chosen club has a manager in the database.
func effective_coach_mode() -> String:
	return "club" if coach_mode == "club" and club_manager_name() != "" else "custom"


func _pick_coach_mode(mode: String) -> void:
	coach_mode = mode
	rebuild()


## Two cards: continue with the club's manager / create your own. Selected card gold-framed; the club card is disabled
## (with the reason) when the database has no manager for this club.
func _coach_mode_cards(body: VBoxContainer) -> void:
	var t: TeamData = db().get_team(club_id)
	var mgr := club_manager_name()
	var mode := effective_coach_mode()
	var row := HFlowContainer.new()
	row.name = "CoachModeCards"
	row.add_theme_constant_override("h_separation", UIKit.SPACE_S)
	row.add_theme_constant_override("v_separation", UIKit.SPACE_S)
	# A: the club's manager
	var a := _mode_card("CoachMode_club", mode == "club", mgr != "")
	var ab: VBoxContainer = a.get_meta("body")
	ab.add_child(UIKit.label(Loc.t("WIZARD_MGR_EXISTING"), 13, UIKit.MUTED))
	var head := UIKit.hbox(UIKit.SPACE_S)
	if t != null:
		head.add_child(UIKit.crest(db(), t, 36, "card"))
	head.add_child(UIKit.label(mgr if mgr != "" else Loc.t("WIZARD_MGR_NONE_IN_DB"), 18, UIKit.GOLD if mode == "club" else UIKit.TEXT))
	ab.add_child(head)
	if mgr != "":
		ab.add_child(UIKit.label(Loc.f("WIZARD_MGR_CLUB_LINE", t.display_name), 13))
		ab.add_child(UIKit.muted(Loc.f("WIZARD_MGR_NATIONALITY_AGE", [Loc.t("WIZARD_MGR_NOT_IN_DB"), Loc.t("WIZARD_MGR_NOT_IN_DB")])))
		ab.add_child(UIKit.muted(Loc.t("WIZARD_MGR_EXISTING_DETAIL")))
	else:
		ab.add_child(UIKit.muted(Loc.t("WIZARD_MGR_NONE_DETAIL")))
	var ac := UIKit.button(Loc.t("WIZARD_MGR_CONTINUE"), _pick_coach_mode.bind("club"), 180)
	ac.name = "CoachModeClubButton"
	ac.disabled = mgr == ""
	ab.add_child(ac)
	row.add_child(a)
	# B: create your own
	var b := _mode_card("CoachMode_custom", mode == "custom", true)
	var bb: VBoxContainer = b.get_meta("body")
	bb.add_child(UIKit.label(Loc.t("WIZARD_MGR_NEW"), 13, UIKit.MUTED))
	bb.add_child(UIKit.label(Loc.t("WIZARD_MGR_NEW_TITLE"), 18, UIKit.GOLD if mode == "custom" else UIKit.TEXT))
	bb.add_child(UIKit.muted(Loc.t("WIZARD_MGR_NEW_DETAIL")))
	var bc := UIKit.button(Loc.t("WIZARD_MGR_CREATE"), _pick_coach_mode.bind("custom"), 180)
	bc.name = "CoachModeCustomButton"
	bb.add_child(bc)
	row.add_child(b)
	body.add_child(row)


func _mode_card(node_name: String, chosen: bool, enabled: bool) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = node_name
	p.custom_minimum_size = Vector2(300, 0)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := UIKit.box(UIKit.PANEL if enabled else UIKit.PANEL.darkened(0.25), UIKit.GOLD if chosen else UIKit.PANEL.lightened(0.15),
			3 if chosen else 1, 10, 14)
	p.add_theme_stylebox_override("panel", sb)
	p.set_meta("chosen", chosen)
	var v := UIKit.vbox(6)
	p.add_child(v)
	p.set_meta("body", v)
	return p


func _coach_step(body: VBoxContainer) -> void:
	body.add_child(UIKit.muted(Loc.t("WIZARD_COACH_HINT")))
	_coach_mode_cards(body)
	if effective_coach_mode() == "custom":
		_custom_coach_fields(body)
	body.add_child(UIKit.label(Loc.t("WIZARD_COACH_STYLE"), 16, UIKit.GOLD))
	for st in ManagerProfile.STYLES:
		body.add_child(_choice_card(Loc.t("COACH_STYLE_" + str(st).to_upper()), Loc.t("COACH_STYLE_" + str(st).to_upper() + "_DETAIL"),
				coach_style == st, _pick_style.bind(str(st)), "Style_%s" % st))
	body.add_child(UIKit.label(Loc.t("WIZARD_COACH_BACKGROUND"), 16, UIKit.GOLD))
	for bg in ManagerProfile.START_TIERS:
		body.add_child(_choice_card(Loc.t("COACH_BG_" + str(bg).to_upper()), Loc.t("COACH_BG_" + str(bg).to_upper() + "_DETAIL"),
				coach_background == bg, _pick_background.bind(str(bg)), "Background_%s" % bg))


## Option B: name, nationality (searchable picker) and age of the manager you create.
func _custom_coach_fields(body: VBoxContainer) -> void:
	body.add_child(UIKit.label(Loc.t("WIZARD_MGR_PERSONAL"), 16, UIKit.GOLD))
	var name_row := UIKit.hbox(UIKit.SPACE_S)
	name_row.add_child(UIKit.label(Loc.t("WIZARD_COACH_NAME"), 15, UIKit.MUTED))
	var edit := LineEdit.new()
	edit.name = "CoachName"
	edit.text = coach_name
	edit.placeholder_text = Loc.t("WIZARD_COACH_NAME_PLACEHOLDER")
	edit.max_length = 24
	edit.custom_minimum_size = Vector2(220, 48)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text_changed.connect(func(t: String) -> void: coach_name = t)
	name_row.add_child(edit)
	body.add_child(name_row)
	var ids: Array = db().countries.keys()
	ids.sort()
	if coach_country_id == "" and not ids.is_empty():
		coach_country_id = str(ids[0])
	var nat_row := UIKit.hbox(UIKit.SPACE_S)
	nat_row.add_child(UIKit.label(Loc.t("WIZARD_COACH_NATIONALITY"), 15, UIKit.MUTED))
	var nat := CountryPicker.make(ids.map(func(i: String) -> String: return Loc.country((db().countries[i] as CountryData).country_name)),
			maxi(ids.find(coach_country_id), 0), func(i: int) -> void: coach_country_id = str(ids[i]), "CoachNationality")
	nat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nat_row.add_child(nat)
	body.add_child(nat_row)
	var age_row := UIKit.hbox(UIKit.SPACE_S)
	age_row.add_child(UIKit.label(Loc.t("WIZARD_COACH_AGE"), 15, UIKit.MUTED))
	var age := SpinBox.new()
	age.name = "CoachAge"
	age.min_value = 30
	age.max_value = 75
	age.value = coach_age
	age.custom_minimum_size.y = 48.0
	age.value_changed.connect(func(v: float) -> void: coach_age = int(v))
	age_row.add_child(age)
	body.add_child(age_row)


## C1.2: options saved with the career (see CareerSettings).
func _settings_step(body: VBoxContainer) -> void:
	body.add_child(UIKit.muted(Loc.t("WIZARD_SETTINGS_HINT")))
	var ws := wizard_settings
	body.add_child(_setting_row("WIZARD_SET_MATCH_DIFF", "SetMatchDiff", CareerSettings.LEVELS, ws.match_difficulty, "LEVEL_", func(v: String) -> void: ws.match_difficulty = v))
	body.add_child(_setting_row("WIZARD_SET_MARKET_DIFF", "SetMarketDiff", CareerSettings.LEVELS, ws.market_difficulty, "LEVEL_", func(v: String) -> void: ws.market_difficulty = v))
	body.add_child(_setting_row("WIZARD_SET_BUDGET", "SetBudget", CareerSettings.BUDGETS, ws.start_budget, "BUDGET_", func(v: String) -> void: ws.start_budget = v))
	body.add_child(_setting_row("WIZARD_SET_MATCH_MODE", "SetMatchMode", CareerSettings.MATCH_MODES, ws.default_match_mode, "MODE_", func(v: String) -> void: ws.default_match_mode = v))
	body.add_child(_toggle_row("WIZARD_SET_INJURIES", "SetInjuries", ws.injuries, func(v: bool) -> void: ws.injuries = v))
	body.add_child(_toggle_row("WIZARD_SET_DELEGATE_ACADEMY", "SetDelegateAcademy", ws.delegate_academy, func(v: bool) -> void: ws.delegate_academy = v))
	body.add_child(_toggle_row("WIZARD_SET_DELEGATE_RENEWALS", "SetDelegateRenewals", ws.delegate_renewals, func(v: bool) -> void: ws.delegate_renewals = v))


func _setting_row(label_key: String, node_name: String, values: Array, current: String, prefix: String, on_change: Callable) -> Control:
	var row := UIKit.hbox(UIKit.SPACE_S)
	var l := UIKit.label(Loc.t(label_key), 15)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var o := UIKit.option(values.map(func(v: String) -> String: return Loc.t("WIZARD_" + prefix + v.to_upper())), maxi(values.find(current), 0), func(i: int) -> void: on_change.call(values[i]))
	o.name = node_name
	o.custom_minimum_size.y = 48.0
	row.add_child(o)
	return row


func _toggle_row(label_key: String, node_name: String, current: bool, on_change: Callable) -> Control:
	var row := UIKit.hbox(UIKit.SPACE_S)
	var l := UIKit.label(Loc.t(label_key), 15)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var c := CheckButton.new()
	c.name = node_name
	c.button_pressed = current
	c.custom_minimum_size.y = 48.0
	c.toggled.connect(on_change)
	row.add_child(c)
	return row


func _pick_kind(kind: String) -> void:
	career_kind = kind
	club_id = ""
	if kind == "scratch":
		coach_background = "unknown"
	rebuild()


func _pick_style(st: String) -> void:
	coach_style = st
	rebuild()


func _pick_background(bg: String) -> void:
	coach_background = bg
	rebuild()


func _summary_step(body: VBoxContainer) -> void:
	var t: TeamData = db().get_team(club_id)
	if t == null:
		body.add_child(UIKit.empty_state(Loc.t("WIZARD_PICK_CLUB_FIRST")))
		return
	var obj := BoardObjectives.for_club(db(), club_id, division())
	var head := UIKit.hbox(UIKit.SPACE_M)
	head.add_child(UIKit.crest(db(), t, 72, "full"))
	var info := UIKit.vbox(4)
	info.add_child(UIKit.label(t.display_name, 24, UIKit.GOLD))
	info.add_child(UIKit.label(Loc.f("WIZARD_SUMMARY_LEAGUE", league_title()), 16))
	info.add_child(UIKit.label(Loc.f("WIZARD_SUMMARY_RATING", [db().get_team_rating(club_id), int(obj.get("rating_rank", 0)), int(obj.get("division_size", 0))]), 16))
	info.add_child(UIKit.label(Loc.f("WIZARD_SUMMARY_BUDGET", Loc.money(t.budget)), 16))
	info.add_child(UIKit.label(Loc.f("WIZARD_SUMMARY_OBJECTIVE", int(obj.get("target_rank", 0))), 16, UIKit.GOOD))
	head.add_child(info)
	body.add_child(UIKit.panel(head))
	var shown_name := club_manager_name() if effective_coach_mode() == "club" else (coach_name if coach_name.strip_edges() != "" else Loc.t("WIZARD_COACH_DEFAULT_NAME"))
	body.add_child(UIKit.label(Loc.f("WIZARD_SUMMARY_COACH", [shown_name,
			Loc.t("COACH_STYLE_" + coach_style.to_upper()), Loc.t("COACH_BG_" + coach_background.to_upper())]), 16))
	body.add_child(UIKit.label(Loc.f("WIZARD_SUMMARY_SETTINGS", [Loc.t("WIZARD_LEVEL_" + wizard_settings.match_difficulty.to_upper()), Loc.t("WIZARD_BUDGET_" + wizard_settings.start_budget.to_upper())]), 14, UIKit.MUTED))
	if app().career != null:
		body.add_child(UIKit.muted(Loc.t("WIZARD_REPLACES_CAREER")))


func _nav_row() -> Control:
	var row := UIKit.hbox(UIKit.SPACE_S)
	row.name = "WizardNav"
	var back := UIKit.button(Loc.t("WIZARD_BACK"), go_back_step, 140)
	back.name = "WizardBack"
	back.disabled = step == 0
	row.add_child(back)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	if step < STEPS.size() - 1:
		var next := UIKit.button(Loc.t("WIZARD_NEXT"), go_next_step, 160)
		next.name = "WizardNext"
		next.disabled = not can_advance()
		if next.disabled:
			var why := UIKit.label(blocked_reason(), 13, UIKit.BAD)
			why.name = "WizardBlockedReason"
			row.add_child(why)
		row.add_child(next)
	else:
		var start := UIKit.button(Loc.t("WIZARD_START"), start_career, 200)
		start.name = "WizardStart"
		start.disabled = club_id == ""
		row.add_child(start)
	return row


# --- state ----------------------------------------------------------------------------------

## Translated pack name ("WORLD_PACK_<ID>" with the season as an LTR-isolated argument, so "2025-26"
## does not turn into "26-2025" in Arabic), else the pack's own name.
static func pack_name(pid: String, stored: String) -> String:
	var key := "WORLD_PACK_%s" % pid.to_upper()
	if not Loc.has_key(key, Localization.FALLBACK_LANGUAGE):
		return Loc.iso(Loc.isolate_years(stored))
	var re := RegEx.new()
	re.compile("\\d{4}-\\d{2}")
	var m := re.search(stored)
	return Loc.f(key, Loc.ltr(m.get_string() if m != null else "")).strip_edges()


func can_advance() -> bool:
	match step:
		0:
			return world_id == "" or TeamDatabase.available_packs().any(func(p: Dictionary) -> bool: return p["id"] == world_id)   # Next reloads the world if needed
		1:
			return not division_clubs().is_empty()
		2:
			return club_id != "" and db().get_team(club_id) != null
		3, 4:
			return true
	return false


## Why "Next" is disabled ("" when it is enabled).
func blocked_reason() -> String:
	if can_advance():
		return ""
	match step:
		0:
			return Loc.t("WIZARD_NEXT_BLOCKED_WORLD")
		1:
			return Loc.t("WIZARD_NEXT_BLOCKED_NO_CLUBS")
	return Loc.t("WIZARD_NEXT_BLOCKED_CLUB")


## Makes sure the loaded database is the chosen world and is self-consistent (a save from another world, or a
## failed load, can leave clubs of one world with the leagues of another). Reloads the world when it is not.
func ensure_world_loaded() -> void:
	if world_id != db().pack_id or not db().is_consistent().is_empty():
		var career_world: String = world_id
		app().switch_world(career_world)
		league_key = ""
		division_index = 0
		club_id = ""


func go_next_step() -> void:
	if step == 0:
		ensure_world_loaded()
	if can_advance():
		step += 1
		rebuild()


func go_back_step() -> void:
	if step > 0:
		step -= 1
		rebuild()


## The chosen division as {team_ids, relegate, name}: the data-pack division, or every club of the fictional world.
func division() -> Dictionary:
	if db().leagues.is_empty():
		var ids: Array = db().list_teams(TeamData.Category.CLUB).map(func(t: TeamData) -> String: return t.id)
		return {"team_ids": ids, "relegate": 0, "name": "LEAGUE_DEFAULT_NAME"}
	if not db().leagues.has(league_key):
		return {}
	var divs: Array = (db().leagues[league_key] as LeagueDef).divisions
	if career_kind == "scratch":
		return divs[divs.size() - 1] if not divs.is_empty() else {}     # the lowest division
	return divs[clampi(division_index, 0, divs.size() - 1)] if not divs.is_empty() else {}


## Clubs of the chosen division, strongest first.
func division_clubs() -> Array:
	var out := _clubs_of(division())
	out.sort_custom(func(a: TeamData, b: TeamData) -> bool:
		var ra: int = db().get_team_rating(a.id)
		var rb: int = db().get_team_rating(b.id)
		return ra > rb if ra != rb else a.display_name < b.display_name)
	if career_kind == "scratch":
		out.reverse()                      # weakest first
		return out.slice(0, 3)             # the three job offers
	return out


## The clubs of a division that exist in the loaded database (unsorted).
func _clubs_of(div: Dictionary) -> Array:
	var out: Array = []
	for id in div.get("team_ids", []):
		var t: TeamData = db().get_team(str(id))
		if t != null and t.category == TeamData.Category.CLUB:
			out.append(t)
	return out


func league_title() -> String:
	if db().leagues.is_empty():
		return Loc.t("LEAGUE_DEFAULT_NAME")
	var d := division()
	return "%s · %s" % [Loc.country((db().leagues[league_key] as LeagueDef).country), LeaguePyramid.label(str(d.get("name", "")))]


func _pick_world(pid: String) -> void:
	if pid == db().pack_id:
		world_id = pid
		rebuild()
		return
	if app().career != null:
		UIKit.confirm(self, Loc.t("SETTINGS_WORLD_CONFIRM"), select_world.bind(pid))
	else:
		select_world(pid)


## Loads the world (data pack or the fictional one) — also the direct entry point for tests.
func select_world(pid: String) -> String:
	var err: String = app().switch_world(pid)
	if err != "":
		say(err, true)
		return err
	world_id = pid
	league_key = ""
	division_index = 0
	club_id = ""
	rebuild()
	return ""


func _pick_division(i: int) -> void:
	division_index = i
	club_id = ""
	rebuild()


func _pick_club(id: String) -> void:
	club_id = id
	rebuild()


func start_career() -> String:
	if club_id == "":
		return "no club"
	var backup_err: String = app().backup_running_career()      # the career being replaced is kept in a safety copy
	if backup_err != "":
		say(backup_err, true)
		return backup_err
	var err: String = app().start_career(club_id)
	if err != "":
		say(err, true)
		return err
	var bg := "unknown" if career_kind == "scratch" else coach_background
	var mgr: ManagerProfile = (app().career as CareerState).manager
	# Exactly one manager per career: the club's own (taken over, the database untouched) or the one created here.
	if effective_coach_mode() == "club":
		mgr.set_club_manager(db().get_team(club_id), coach_style, bg)
	else:
		mgr.set_profile(coach_name if coach_name.strip_edges() != "" else Loc.t("WIZARD_COACH_DEFAULT_NAME"),
				coach_country_id, coach_age, coach_style, bg, hash(coach_name + club_id) & 0x7fffffff)
	mgr.origin_club_id = club_id if mgr.is_club_manager() else ""
	var started: CareerState = app().career
	started.settings = CareerSettings.from_dict(wizard_settings.to_dict())
	started.settings.apply_to(started)
	var t_club: TeamData = db().get_team(club_id)
	started.inbox.add("welcome", started.season, started.week, "board", "INBOX_WELCOME",
			[t_club.display_name, Loc.t("VISION_" + started.vision().to_upper()), int(started.manager.objective.get("target_rank", 0)), Loc.money(started.ledger().transfer_budget)],
			{"sender": "chairman", "action": {"screen": "career", "params": {}}})
	# The new career goes to disk at once: "Continue career" in the main menu loads the newest save, which otherwise
	# was the previous career (or no file at all, "save file not found").
	var save_err: String = app().save_new_career()
	if save_err != "":
		say(ErrorText.localize(save_err), true)
	else:
		say(Loc.f("SELECT_CAREER_STARTED_WITH", db().get_team(club_id).display_name))
	go("career")
	return ""
