extends HubScreen

## Phase K4: the season calendar as a month of days (replaces the 4-weeks-per-page list of C9.4).
##   * a strip of the season's months (July .. June) on top — mirrored in RTL like every container;
##   * a 7-column grid of days, starting on Saturday in Arabic and Monday otherwise; each cell shows the day number, the
##     user's match (opponent crest, home/away, competition colour, the score with a win/draw/loss colour), the training
##     of the day, international breaks and open transfer windows; today is framed, past days are dimmed;
##   * a side panel: today's date, the next competition and match, the transfer window ("open" + days until it closes)
##     and the team's average fitness;
##   * clicking a day shows its details: the match, the training plan (editable: intensity and focus) and
##     "Simulate to this day"; the buttons Continue / One day / Stop move the calendar (`CareerFlow.continue_days`).

const COMP_COLORS := {"league": Color(0.25, 0.55, 0.95), "cup": Color(0.95, 0.65, 0.2), "continental": Color(0.65, 0.35, 0.95),
		"playoff": Color(0.9, 0.3, 0.45), "friendly": Color(0.55, 0.6, 0.65), "national": Color(0.3, 0.8, 0.75)}
const RESULT_COLORS := {"W": Color(0.35, 0.8, 0.5), "D": Color(0.85, 0.8, 0.4), "L": Color(0.9, 0.35, 0.35)}
const TRAIN_ICONS := {"rest": "☾", "light": "◔", "medium": "◑", "intense": "●", "match": "⚽"}

var shown := [0, 0]                 # [year, month] on screen (0 = the current month)
var selected_jdn := -1
var _running := false
var _stop_requested := false
var _progress: Label


func build() -> void:
	add_child(UIKit.title(Loc.t("SCREEN_CALENDAR")))
	var career: CareerState = app().career
	if career == null:
		add_child(UIKit.empty_state(Loc.t("CAREER_NO_CAREER_IN_PROGRESS_PICK_A_CLUB")))
		return
	var today := career.date()
	if int(shown[0]) == 0:
		shown = [int(today["year"]), int(today["month"])]
	add_child(_controls())
	add_child(_month_strip(career))
	var body := UIKit.hbox(UIKit.SPACE_M)
	var grid_box := UIKit.vbox(4)
	grid_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_box.add_child(_grid(career))
	if selected_jdn >= 0:
		grid_box.add_child(_details(career, selected_jdn))
	body.add_child(grid_box)
	body.add_child(_side_panel(career))
	add_child(body)


# --- time controls ---------------------------------------------------------------------------------------

func _controls() -> Control:
	var row := UIKit.hbox(UIKit.SPACE_S)
	row.name = "CalControls"
	var cont := UIKit.button(Loc.t("CAL2_CONTINUE"), _continue, 120)
	cont.name = "CalContinue"
	cont.disabled = _running
	row.add_child(cont)
	var one := UIKit.button(Loc.t("CAL2_ONE_DAY"), _one_day, 110)
	one.name = "CalOneDay"
	one.disabled = _running
	row.add_child(one)
	var stop := UIKit.button(Loc.t("CAL2_STOP"), func() -> void: _stop_requested = true, 90)
	stop.name = "CalStop"
	stop.disabled = not _running
	row.add_child(stop)
	_progress = UIKit.muted("")
	_progress.name = "CalProgress"
	_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_progress)
	return row


func _one_day() -> void:
	if _running or app().career == null:
		return
	app().advance_day()
	_after_advance({"days": 1, "stop": CareerFlow.next_stop(app().career)})


func _continue() -> void:
	await _run_until(-1)


## "Simulate to this day" (and Continue with until = -1): day by day with a progress line and a Stop button; stops at
## any event that needs the manager — his own match first of all.
func _run_until(until_jdn: int) -> void:
	var career: CareerState = app().career
	if _running or career == null or app().is_advancing():
		return
	_running = true
	_stop_requested = false
	rebuild()
	var start := CareerDate.jdn_of(career.season, career.week, career.day)
	var total := maxi(until_jdn - start, 1) if until_jdn >= 0 else 0
	var advance := func() -> void:
		app().advance_day()
		if is_instance_valid(_progress):
			var done := CareerDate.jdn_of(career.season, career.week, career.day) - start
			_progress.text = Loc.f("CAL2_ADVANCING", [done, total]) if total > 0 else CareerDate.format(career.date())
		await get_tree().process_frame
	var res: Dictionary = await CareerFlow.continue_days(career, advance, until_jdn, func() -> bool: return _stop_requested)
	_running = false
	if app().career != career:
		return
	_after_advance(res)


func _after_advance(res: Dictionary) -> void:
	var career: CareerState = app().career
	var stop: Dictionary = res.get("stop", {})
	var today := career.date()
	shown = [int(today["year"]), int(today["month"])]
	if stop.is_empty():
		say(Loc.f("CAL2_DAYS_DONE", int(res.get("days", 0))))
	else:
		say(Loc.f(str(stop["key"]), stop["args"]))
		if str(stop.get("key", "")) == "INBOX_MATCH_DUE":
			say(Loc.t("CAL2_PLAY_HOW"))
			go("career")                      # the career page offers: play in 3D / simulate (live sim: Phase S)
			return
	rebuild()


# --- month strip -------------------------------------------------------------------------------------------

func _month_strip(career: CareerState) -> Control:
	var row := UIKit.hbox(4)
	row.name = "CalMonths"
	for ym in CareerCalendar.season_months(career):
		var b := Button.new()
		b.text = CareerDate.month_name(int(ym[1]))
		b.toggle_mode = true
		b.button_pressed = int(ym[0]) == int(shown[0]) and int(ym[1]) == int(shown[1])
		b.custom_minimum_size = Vector2(56, 40)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		b.name = "CalMonth_%d_%d" % [int(ym[0]), int(ym[1])]
		b.pressed.connect(func() -> void:
			shown = [int(ym[0]), int(ym[1])]
			selected_jdn = -1
			rebuild())
		row.add_child(b)
	return row


# --- the grid ----------------------------------------------------------------------------------------------

## First column of the week: Saturday in Arabic, Monday otherwise.
func _week_start() -> int:
	return 5 if Loc.language == "ar" else 0


func _grid(career: CareerState) -> Control:
	var view := CareerCalendar.month_view(career, int(shown[0]), int(shown[1]))
	var grid := GridContainer.new()
	grid.name = "CalGrid"
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var start := _week_start()
	for i in 7:
		var h := UIKit.label(Loc.t(CareerDate.WEEKDAY_KEYS[(start + i) % 7]), 13, UIKit.MUTED)
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(h)
	var lead := posmod(int(view["first_weekday"]) - start, 7)
	for i in lead:
		grid.add_child(Control.new())
	for d in view["days"]:
		grid.add_child(_cell(d))
	return grid


func _cell(d: Dictionary) -> Control:
	var b := Button.new()
	b.name = "CalDay_%d" % int(d["jdn"])
	b.toggle_mode = true
	b.button_pressed = int(d["jdn"]) == selected_jdn
	b.custom_minimum_size = Vector2(0, 74)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_contents = true
	b.pressed.connect(func() -> void:
		selected_jdn = -1 if selected_jdn == int(d["jdn"]) else int(d["jdn"])
		rebuild())
	if bool(d["past"]):
		b.modulate = Color(1, 1, 1, 0.55)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 1)
	b.add_child(box)
	var top := UIKit.hbox(2)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var num := UIKit.label(str(int(d["day"])), 13, UIKit.GOLD if bool(d["today"]) else UIKit.TEXT)
	top.add_child(num)
	var icons := ""
	var tr: Dictionary = d["training"]
	if (d["match"] as Dictionary).is_empty():
		icons += str(TRAIN_ICONS.get(str(tr.get("intensity", "")), ""))
	if bool(d["break"]):
		icons += " ✈"
	if bool(d["window"]):
		icons += " ⇄"
	var ic := UIKit.label(icons, 12, UIKit.MUTED)
	ic.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(ic)
	box.add_child(top)
	var m: Dictionary = d["match"]
	if not m.is_empty():
		var stripe := ColorRect.new()
		stripe.color = COMP_COLORS.get(str(m["kind"]), UIKit.MUTED)
		stripe.custom_minimum_size = Vector2(0, 3)
		stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(stripe)
		var line := UIKit.hbox(3)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(UIKit.crest(db(), str(m["opponent"]), 20))
		line.add_child(UIKit.label(Loc.t("CAL2_HOME") if bool(m["home"]) else Loc.t("CAL2_AWAY"), 11, UIKit.MUTED))
		box.add_child(line)
		if str(m["score"]) != "":
			box.add_child(UIKit.label(Loc.ltr(str(m["score"])), 13, RESULT_COLORS.get(str(m["result"]), UIKit.TEXT)))
	if bool(d["today"]):
		var frame := StyleBoxFlat.new()
		frame.bg_color = Color(0.15, 0.2, 0.32)
		frame.border_color = UIKit.GOLD
		frame.set_border_width_all(2)
		frame.set_corner_radius_all(6)
		b.add_theme_stylebox_override("normal", frame)
	return b


# --- side panel and day details ---------------------------------------------------------------------------------

func _side_panel(career: CareerState) -> Control:
	var box := UIKit.vbox(6)
	box.name = "CalSide"
	box.custom_minimum_size = Vector2(240, 0)
	box.add_child(UIKit.label(CareerDate.format(career.date()), 17, UIKit.GOLD))
	var next: Dictionary = {}
	var today := CareerDate.jdn_of(career.season, career.week, career.day)
	for e in CareerCalendar.season_days(career):
		if not bool(e["played"]) and int(e["jdn"]) >= today:
			next = e
			break
	if not next.is_empty():
		box.add_child(UIKit.muted(Loc.t("CAL2_NEXT_COMP")))
		box.add_child(UIKit.label(app().competition_title(str(next["comp_id"])), 15, COMP_COLORS.get(str(next["kind"]), UIKit.TEXT)))
		box.add_child(UIKit.muted(Loc.t("CAL2_NEXT_MATCH")))
		var line := UIKit.hbox(6)
		line.add_child(UIKit.crest(db(), career.club_id, 26))
		line.add_child(UIKit.label("–", 15))
		line.add_child(UIKit.crest(db(), str(next["opponent"]), 26))
		box.add_child(line)
		box.add_child(UIKit.label("%s · %s" % [CareerDate.format(CareerDate.from_jdn(int(next["jdn"])), true),
				Loc.t("CAL2_HOME") if bool(next["home"]) else Loc.t("CAL2_AWAY")], 14))
	var left := TransferMarket.window_days_left(career.season, career.week, career.day)
	if left > 0:
		box.add_child(UIKit.label(Loc.t("CAL2_WINDOW_OPEN"), 15, UIKit.GOOD))
		box.add_child(UIKit.label(Loc.f("CAL2_WINDOW_DAYS", left), 14))
	else:
		box.add_child(UIKit.muted(Loc.t("CAL2_WINDOW_CLOSED")))
	box.add_child(UIKit.label(Loc.f("CAL2_TEAM_FITNESS", _team_fitness(career)), 14))
	return UIKit.panel(box)


func _team_fitness(career: CareerState) -> int:
	var total := 0
	var n := 0
	for p: PlayerData in db().get_squad(career.club_id):
		if p.status != PlayerData.Status.YOUTH and p.status != PlayerData.Status.RETIRED:
			total += p.fitness
			n += 1
	return roundi(float(total) / maxf(n, 1.0))


func _details(career: CareerState, jdn: int) -> Control:
	var box := UIKit.vbox(6)
	box.name = "CalDetails"
	box.add_child(UIKit.label(CareerDate.format(CareerDate.from_jdn(jdn)), 16, UIKit.GOLD))
	var match_e: Dictionary = {}
	for e in CareerCalendar.season_days(career):
		if int(e["jdn"]) == jdn:
			match_e = e
	if match_e.is_empty():
		box.add_child(UIKit.muted(Loc.t("CAL2_NO_MATCH")))
	else:
		var opp: TeamData = db().get_team(str(match_e["opponent"]))
		var line := UIKit.hbox(6)
		line.add_child(UIKit.crest(db(), str(match_e["opponent"]), 24))
		line.add_child(UIKit.label("%s · %s · %s" % [app().competition_title(str(match_e["comp_id"])), Loc.iso(opp.display_name if opp != null else str(match_e["opponent"])),
				Loc.t("CAL2_HOME") if bool(match_e["home"]) else Loc.t("CAL2_AWAY")], 15))
		if str(match_e["score"]) != "":
			line.add_child(UIKit.label(Loc.ltr(str(match_e["score"])), 15, RESULT_COLORS.get(str(match_e["result"]), UIKit.TEXT)))
		box.add_child(line)
	var wd := CareerDate.week_day_of(career.season, jdn)
	if NationalBreaks.is_break(int(wd["week"])):
		box.add_child(UIKit.muted(Loc.t("CAL2_BREAK")))
	# training of the day (editable for days still to come)
	var plan := career.training.day_plan(career, jdn)
	box.add_child(UIKit.label("%s: %s · %s%s" % [Loc.t("CAL2_TRAINING"), Loc.t("CAL2_TRAIN_" + str(plan["intensity"]).to_upper()),
			Loc.t("CAL2_FOCUS_" + str(plan["focus"]).to_upper()), ("  (" + Loc.t("CAL2_TRAIN_AUTO") + ")") if bool(plan["auto"]) else ""], 14))
	var today := CareerDate.jdn_of(career.season, career.week, career.day)
	if jdn > today and not bool(plan["match"]):
		var row := UIKit.hbox(6)
		var items: Array = []
		for i in TrainingPlan.INTENSITIES:
			items.append(Loc.t("CAL2_TRAIN_" + i.to_upper()))
		var cur_i := maxi(TrainingPlan.INTENSITIES.find(str(plan["intensity"])), 0)
		var focus_items: Array = []
		for f in TrainingPlan.FOCUSES:
			focus_items.append(Loc.t("CAL2_FOCUS_" + f.to_upper()))
		var cur_f := maxi(TrainingPlan.FOCUSES.find(str(plan["focus"])), 0)
		var focus_opt: OptionButton
		var int_opt := UIKit.option(items, cur_i, func(idx: int) -> void:
			career.training.set_day(jdn, TrainingPlan.INTENSITIES[idx], TrainingPlan.FOCUSES[focus_opt.selected if focus_opt != null else cur_f])
			rebuild())
		int_opt.name = "CalTrainIntensity"
		row.add_child(int_opt)
		focus_opt = UIKit.option(focus_items, cur_f, func(idx: int) -> void:
			career.training.set_day(jdn, TrainingPlan.INTENSITIES[int_opt.selected], TrainingPlan.FOCUSES[idx])
			rebuild())
		focus_opt.name = "CalTrainFocus"
		row.add_child(focus_opt)
		if not bool(plan["auto"]):
			row.add_child(UIKit.button(Loc.t("CAL2_TRAIN_RESET"), func() -> void:
				career.training.set_day(jdn, "")
				rebuild()))
		box.add_child(row)
		var sim := UIKit.button(Loc.t("CAL2_SIM_TO_DAY"), func() -> void: _run_until(jdn), 200)
		sim.name = "CalSimToDay"
		sim.disabled = _running
		box.add_child(sim)
	return UIKit.panel(box)
