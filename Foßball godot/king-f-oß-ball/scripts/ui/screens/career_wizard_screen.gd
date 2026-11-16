extends HubScreen

## New-career wizard (UX phase 4.1 follow-up): four steps instead of one "Start career" button —
##   1. world   (the default fictional world or an installed data pack such as the real leagues),
##   2. league  (fictional: the King League; data packs: country, then division),
##   3. club    (the division's clubs by strength, with budget and the board's expectation),
##   4. summary (club, league, objective, budget) -> start.
## Back / Next move between steps; Next is enabled once the step has a choice. Switching the world drops a
## running career, so it is confirmed first. Starting uses `AppHub.start_career`, as the old button did.

const STEPS: Array[String] = ["WIZARD_STEP_WORLD", "WIZARD_STEP_LEAGUE", "WIZARD_STEP_CLUB", "WIZARD_STEP_COACH", "WIZARD_STEP_SUMMARY"]

var step := 0
var world_id := ""                 # "" = fictional world, else a data pack id
var league_key := ""               # data packs: LeagueDef key ("" in the fictional world)
var division_index := 0
var club_id := ""
var coach_name := ""
var coach_country_id := ""
var coach_age := 45
var coach_style := ManagerProfile.DEFAULT_STYLE
var coach_background := "unknown"
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
		_:
			_summary_step(body)
	add_child(UIKit.scroll(body))
	add_child(_nav_row())


# --- steps ---------------------------------------------------------------------------------

func _step_bar() -> Control:
	var row := UIKit.hbox(UIKit.SPACE_S)
	row.name = "WizardSteps"
	for i in STEPS.size():
		var l := UIKit.label(Loc.f("WIZARD_STEP_N", [i + 1, Loc.t(STEPS[i])]), 15,
				UIKit.GOLD if i == step else (UIKit.TEXT if i < step else UIKit.MUTED))
		l.name = "Step_%d" % i
		row.add_child(l)
		if i < STEPS.size() - 1:
			row.add_child(UIKit.label("—", 15, UIKit.MUTED))
	return row


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
	for i in divs.size():
		var d: Dictionary = divs[i]
		var present := _clubs_of(d).size()
		if present == 0:
			continue                  # a division without clubs cannot be chosen: it would block "Next"
		body.add_child(_choice_card("%s · %s" % [Loc.ltr(str(d["tier"])), LeaguePyramid.label(str(d["name"]))],
				Loc.f("WIZARD_DIVISION_DETAIL", [present, int(d.get("promote", 0)), int(d.get("relegate", 0))]),
				i == division_index, _pick_division.bind(i), "Division_%d" % i))


func _club_step(body: VBoxContainer) -> void:
	body.add_child(UIKit.muted(Loc.t("WIZARD_CLUB_HINT")))
	var div := division()
	for t: TeamData in division_clubs():
		var obj := BoardObjectives.for_club(db(), t.id, div)
		body.add_child(_choice_card(t.display_name, Loc.f("WIZARD_CLUB_DETAIL", [db().get_team_rating(t.id), Loc.money(t.budget),
				int(obj.get("target_rank", 0))]), t.id == club_id, _pick_club.bind(t.id), "Club_%s" % t.id, t))


## C1.2: the manager's profile. Style gives a small fixed edge (shown on each card); the background sets the starting reputation.
func _coach_step(body: VBoxContainer) -> void:
	body.add_child(UIKit.muted(Loc.t("WIZARD_COACH_HINT")))
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
	var nat := UIKit.option(ids.map(func(i: String) -> String: return Loc.country((db().countries[i] as CountryData).country_name)),
			maxi(ids.find(coach_country_id), 0), func(i: int) -> void: coach_country_id = str(ids[i]))
	nat.name = "CoachNationality"
	nat.custom_minimum_size.y = 48.0
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
	body.add_child(UIKit.label(Loc.t("WIZARD_COACH_STYLE"), 16, UIKit.GOLD))
	for st in ManagerProfile.STYLES:
		body.add_child(_choice_card(Loc.t("COACH_STYLE_" + str(st).to_upper()), Loc.t("COACH_STYLE_" + str(st).to_upper() + "_DETAIL"),
				coach_style == st, _pick_style.bind(str(st)), "Style_%s" % st))
	body.add_child(UIKit.label(Loc.t("WIZARD_COACH_BACKGROUND"), 16, UIKit.GOLD))
	for bg in ManagerProfile.START_TIERS:
		body.add_child(_choice_card(Loc.t("COACH_BG_" + str(bg).to_upper()), Loc.t("COACH_BG_" + str(bg).to_upper() + "_DETAIL"),
				coach_background == bg, _pick_background.bind(str(bg)), "Background_%s" % bg))


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
	body.add_child(UIKit.label(Loc.f("WIZARD_SUMMARY_COACH", [coach_name if coach_name.strip_edges() != "" else Loc.t("WIZARD_COACH_DEFAULT_NAME"),
			Loc.t("COACH_STYLE_" + coach_style.to_upper()), Loc.t("COACH_BG_" + coach_background.to_upper())]), 16))
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
		3:
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
	return divs[clampi(division_index, 0, divs.size() - 1)] if not divs.is_empty() else {}


## Clubs of the chosen division, strongest first.
func division_clubs() -> Array:
	var out := _clubs_of(division())
	out.sort_custom(func(a: TeamData, b: TeamData) -> bool:
		var ra: int = db().get_team_rating(a.id)
		var rb: int = db().get_team_rating(b.id)
		return ra > rb if ra != rb else a.display_name < b.display_name)
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
	(app().career as CareerState).manager.set_profile(coach_name if coach_name.strip_edges() != "" else Loc.t("WIZARD_COACH_DEFAULT_NAME"),
			coach_country_id, coach_age, coach_style, coach_background, hash(coach_name + club_id) & 0x7fffffff)
	say(Loc.f("SELECT_CAREER_STARTED_WITH", db().get_team(club_id).display_name))
	go("career")
	return ""
