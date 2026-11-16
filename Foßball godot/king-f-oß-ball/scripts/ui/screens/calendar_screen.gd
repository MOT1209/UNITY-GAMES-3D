extends HubScreen

## Career phase C9.4: the season calendar, a month (4 weeks) at a time: the user's matches with opponent crest and result,
## transfer windows, the current week. Tapping a week shows its details.

const WEEKS_PER_MONTH := 4
var month := -1
var selected_week := 0


func build() -> void:
	add_child(UIKit.title(Loc.t("SCREEN_CALENDAR")))
	var career: CareerState = app().career
	if career == null:
		add_child(UIKit.empty_state(Loc.t("CAREER_NO_CAREER_IN_PROGRESS_PICK_A_CLUB")))
		return
	var weeks := CareerCalendar.season_weeks(career)
	var months := int(ceil(float(weeks.size()) / WEEKS_PER_MONTH))
	if month < 0:
		month = clampi((maxi(career.week, 1) - 1) / WEEKS_PER_MONTH, 0, months - 1)
	var nav := UIKit.hbox(UIKit.SPACE_S)
	var prev := UIKit.button("<", _move.bind(-1), 48)
	prev.name = "CalPrev"
	prev.disabled = month == 0
	nav.add_child(prev)
	var title := UIKit.label(Loc.f("CAL_MONTH", [month + 1, months]), 16, UIKit.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.name = "CalTitle"
	nav.add_child(title)
	var nxt := UIKit.button(">", _move.bind(1), 48)
	nxt.name = "CalNext"
	nxt.disabled = month >= months - 1
	nav.add_child(nxt)
	add_child(nav)
	for i in range(month * WEEKS_PER_MONTH, mini((month + 1) * WEEKS_PER_MONTH, weeks.size())):
		add_child(_week_row(career, weeks[i]))
	if selected_week > 0 and selected_week <= weeks.size():
		add_child(_details(career, weeks[selected_week - 1]))


func _week_row(career: CareerState, e: Dictionary) -> Control:
	var row := UIKit.hbox(UIKit.SPACE_S)
	var b := Button.new()
	b.name = "CalWeek_%d" % int(e["week"])
	b.custom_minimum_size = Vector2(0, 56)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.toggle_mode = true
	b.button_pressed = int(e["week"]) == selected_week
	b.pressed.connect(_select.bind(int(e["week"])))
	var parts: Array = [Loc.f("CAL_WEEK", int(e["week"]))]
	for m in e["matches"]:
		var opp: TeamData = db().get_team(str(m["opponent"]))
		var name_text := opp.display_name if opp != null else str(m["opponent"])
		parts.append("%s %s%s" % ["vs" if m["home"] else "@", Loc.iso(name_text), (" " + Loc.ltr(str(m["score"]))) if str(m["score"]) != "" else ""])
	if bool(e["window"]):
		parts.append(Loc.t("CAL_WINDOW"))
	if bool(e["is_now"]):
		parts.append(Loc.t("CAL_NOW"))
	b.text = "  ·  ".join(parts)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(b)
	return row


func _details(career: CareerState, e: Dictionary) -> Control:
	var box := UIKit.vbox(4)
	box.name = "CalDetails"
	box.add_child(UIKit.label(Loc.f("CAL_WEEK", int(e["week"])), 16, UIKit.GOLD))
	if (e["matches"] as Array).is_empty():
		box.add_child(UIKit.muted(Loc.t("CAL_NO_MATCH")))
	for m in e["matches"]:
		var opp: TeamData = db().get_team(str(m["opponent"]))
		var line := Loc.f("CAL_MATCH_LINE", [app().competition_title(str(m["comp_id"])), Loc.iso(opp.display_name if opp != null else str(m["opponent"])),
				Loc.t("CAL_HOME") if m["home"] else Loc.t("CAL_AWAY")])
		if str(m["score"]) != "":
			line += "  " + Loc.ltr(str(m["score"]))
		box.add_child(UIKit.label(line, 15))
	if bool(e["window"]):
		box.add_child(UIKit.muted(Loc.t("CAL_WINDOW_OPEN")))
	return UIKit.panel(box)


func _move(delta: int) -> void:
	month += delta
	rebuild()


func _select(week: int) -> void:
	selected_week = 0 if selected_week == week else week
	rebuild()
