extends HubScreen

## Phase S2: "live simulation" screen. params: {competition_id, match_id}.
##   * centre: a small 2D pitch seen from above with both elevens (kit colours, shirt numbers) and the ball, whose zone follows
##     the play (possession, goals, attacks);
##   * top: score bar with the competition name and the minute; bottom: the event feed (a short translated line per event
##     with an icon) and live statistics (possession, shots, on target, corners, cards, xG);
##   * controls: 1x / 2x / 4x / to the end, pause, auto-stop on a goal or a red card, mentality and pressing (they change
##     the chances at once, `MatchEventEngine.LiveMatch`), finish = book the result in the career.
## The result is booked through `CareerState.submit_result`; the live record (scorers, assists, cards, ratings) is handed to
## `SeasonStats.record_simulated`, so the statistics show exactly what happened here.

const MINUTE_SECONDS := 0.5                # real seconds per match minute at 1x
const ICONS := {"goal": "⚽", "shot": "·", "save": "🧤", "corner": "⚑", "yellow": "🟨", "red": "🟥", "injury": "✚", "sub": "⇄"}

var live: MatchEventEngine.LiveMatch
var competition_id := ""
var match_id := ""
var speed := 1.0
var paused := false
var to_end := false
var auto_stop := true
var finished := false
var _acc := 0.0
var _pitch: Control
var _feed: VBoxContainer
var _score: Label
var _stats: GridContainer
var _ball := Vector2(0.5, 0.5)
var _ball_target := Vector2(0.5, 0.5)
var _colors := [Color(0.9, 0.2, 0.2), Color(0.2, 0.5, 0.95)]


func build() -> void:
	add_child(UIKit.title(Loc.t("LIVE_TITLE")))
	var career: CareerState = app().career
	competition_id = str(params.get("competition_id", ""))
	match_id = str(params.get("match_id", ""))
	if career == null or not career.competitions.has(competition_id):
		add_child(UIKit.empty_state(Loc.t("CAREER_NO_CAREER_IN_PROGRESS_PICK_A_CLUB")))
		return
	var f: Dictionary = (career.competitions[competition_id] as Competition).get_fixture(match_id)
	if f.is_empty():
		add_child(UIKit.empty_state(Loc.t("TABLE_MATCH_SIMULATED")))
		return
	if live == null:
		live = MatchEventEngine.LiveMatch.new(db(), f["home"], f["away"], hash(match_id))
		live.weather = ["clear", "clear", "clear", "clear", "clear", "rain", "snow"][absi(hash(match_id + "w")) % 7]
		_pick_colors(f["home"], f["away"])
	own_scroll = false
	add_child(_scoreboard())
	_pitch = Control.new()
	_pitch.name = "LivePitch"
	_pitch.custom_minimum_size = Vector2(0, 320)
	_pitch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pitch.draw.connect(_draw_pitch)
	add_child(_pitch)
	add_child(_controls())
	var body := UIKit.hbox(UIKit.SPACE_M)
	_feed = UIKit.vbox(3)
	_feed.name = "LiveFeed"
	_feed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var feed_scroll := UIKit.scroll(_feed)
	feed_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	feed_scroll.custom_minimum_size = Vector2(0, 220)
	var feed_box := UIKit.vbox(4)
	feed_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	feed_box.add_child(UIKit.label(Loc.t("LIVE_FEED"), 15, UIKit.GOLD))
	feed_box.add_child(feed_scroll)
	body.add_child(UIKit.panel(feed_box))
	_stats = GridContainer.new()
	_stats.columns = 3
	_stats.name = "LiveStats"
	_stats.add_theme_constant_override("h_separation", 14)
	_stats.add_theme_constant_override("v_separation", 6)
	_stats.custom_minimum_size = Vector2(280, 0)
	body.add_child(UIKit.panel(_stats))
	add_child(body)
	for ev in live.events:
		_add_feed(ev)
	_refresh()


## Dot colours: each side's kit colour; the away side switches to its other kit (or a contrast colour) when both look alike,
## and a white / missing kit never makes both teams white.
func _pick_colors(home_id: String, away_id: String) -> void:
	var cand: Array = [[], []]
	for i in 2:
		var team: TeamData = db().get_team(home_id if i == 0 else away_id)
		if team == null:
			continue
		for slot in (["home", "away", "third"] if i == 0 else ["away", "home", "third"]):
			if team.kits.has(slot):
				cand[i].append(TeamKit.for_team(db(), team, slot).jersey)
		cand[i].append(team.primary_color)
		cand[i].append(team.secondary_color)
	cand[0].append(Color(0.85, 0.15, 0.2))
	cand[1].append(Color(0.15, 0.4, 0.95))
	cand[1].append(Color(0.1, 0.1, 0.12))
	_colors[0] = cand[0][0]
	for c: Color in cand[1]:
		if _color_dist(c, _colors[0]) > 0.35:
			_colors[1] = c
			break
	for i in 2:
		if _color_dist(_colors[i], Color(0.16, 0.5, 0.22)) < 0.2:      # not green on the green pitch
			_colors[i] = Color(0.85, 0.15, 0.2) if i == 0 else Color(0.15, 0.4, 0.95)


static func _color_dist(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


static func _ink(c: Color) -> Color:
	return Color(0.05, 0.05, 0.08) if c.get_luminance() > 0.55 else Color.WHITE


## Scoreboard: crest + name of each side, the score in the middle (always left-to-right home - away), competition and minute.
func _scoreboard() -> Control:
	var h: TeamData = db().get_team(live.home_id)
	var a: TeamData = db().get_team(live.away_id)
	var row := HBoxContainer.new()
	row.name = "LiveScoreboard"
	row.layout_direction = Control.LAYOUT_DIRECTION_LTR           # home always on the left, like the pitch
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	for i in 2:
		var team := h if i == 0 else a
		var side := UIKit.hbox(8)
		side.layout_direction = Control.LAYOUT_DIRECTION_LTR
		side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		side.alignment = BoxContainer.ALIGNMENT_END if i == 0 else BoxContainer.ALIGNMENT_BEGIN
		var chip := ColorRect.new()
		chip.color = _colors[i]
		chip.custom_minimum_size = Vector2(6, 34)
		var nm := UIKit.label(Loc.iso(team.display_name if team != null else ""), 18)
		nm.clip_text = true
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if i == 0 else HORIZONTAL_ALIGNMENT_LEFT
		var cr := UIKit.crest(db(), team.id if team != null else "", 40)
		if i == 0:
			side.add_child(nm)
			side.add_child(cr)
			side.add_child(chip)
		else:
			side.add_child(chip)
			side.add_child(cr)
			side.add_child(nm)
		row.add_child(side)
		if i == 0:
			var mid := UIKit.vbox(0)
			mid.alignment = BoxContainer.ALIGNMENT_CENTER
			_score = UIKit.label("", 30, UIKit.GOLD)
			_score.name = "LiveScore"
			_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_score.custom_minimum_size = Vector2(120, 0)
			mid.add_child(_score)
			_minute = UIKit.label("", 13, UIKit.MUTED)
			_minute.name = "LiveMinute"
			_minute.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			mid.add_child(_minute)
			row.add_child(mid)
	return UIKit.panel(row)


var _minute: Label


func _controls() -> Control:
	var row := UIKit.hbox(6)
	row.name = "LiveControls"
	for s in [1, 2, 4]:
		var b := UIKit.button("%dx" % s, func() -> void:
			speed = float(s)
			to_end = false, 60)
		b.name = "LiveSpeed_%d" % s
		row.add_child(b)
	var end_b := UIKit.button(Loc.t("LIVE_TO_END"), func() -> void: to_end = true, 120)
	end_b.name = "LiveToEnd"
	row.add_child(end_b)
	var pause := UIKit.button(Loc.t("LIVE_PAUSE"), Callable(), 110)
	pause.name = "LivePause"
	pause.pressed.connect(func() -> void:
		paused = not paused
		pause.text = Loc.t("LIVE_PLAY_ON") if paused else Loc.t("LIVE_PAUSE"))
	row.add_child(pause)
	var auto := CheckBox.new()
	auto.text = Loc.t("LIVE_AUTO_STOP")
	auto.button_pressed = auto_stop
	auto.toggled.connect(func(v: bool) -> void: auto_stop = v)
	row.add_child(auto)
	var me := _my_side()
	var ment_items: Array = []
	for m in [-1, 0, 1]:
		ment_items.append(Loc.t("LIVE_MENT_N1" if m == -1 else "LIVE_MENT_%d" % m))
	var ment := UIKit.option(ment_items, int(live.mentality[me]) + 1, func(i: int) -> void: live.mentality[me] = i - 1)
	ment.name = "LiveMentality"
	row.add_child(UIKit.label(Loc.t("LIVE_MENTALITY"), 14, UIKit.MUTED))
	row.add_child(ment)
	var press := HSlider.new()
	press.min_value = 0
	press.max_value = 100
	press.value = live.pressing[me]
	press.custom_minimum_size = Vector2(110, 0)
	press.value_changed.connect(func(v: float) -> void: live.pressing[me] = int(v))
	row.add_child(UIKit.label(Loc.t("LIVE_PRESSING"), 14, UIKit.MUTED))
	row.add_child(press)
	row.add_child(_subs_row(me))
	var to3d := UIKit.button(Loc.t("LIVE_PLAY_3D_FROM_HERE"), _play_3d, 220)
	to3d.name = "LivePlay3D"
	row.add_child(to3d)
	var fin := UIKit.button(Loc.t("LIVE_FINISH"), _finish, 220)
	fin.name = "LiveFinish"
	row.add_child(fin)
	return row


## Substitution: pick the player to take off and the bench player to bring on (max 5; acts on the chances at once).
func _subs_row(side: String) -> Control:
	var row := UIKit.hbox(4)
	row.name = "LiveSubs"
	var out_opt := OptionButton.new()
	var in_opt := OptionButton.new()
	var on: Array = []
	for p: PlayerData in live.xi[side]:
		if p.position != PlayerData.Position.GK:
			out_opt.add_item("%s %s" % [PlayerData.Position.keys()[p.position], p.display_name])
			on.append(p.id)
	var bench: Array = []
	var on_ids: Array = (live.xi[side] as Array).map(func(p: PlayerData) -> String: return p.id)
	for p: PlayerData in db().get_squad(app().career.club_id):
		if p.status == PlayerData.Status.ACTIVE and not (p.id in on_ids) and p.position != PlayerData.Position.GK:
			in_opt.add_item("%s %s" % [PlayerData.Position.keys()[p.position], p.display_name])
			bench.append(p.id)
	row.add_child(out_opt)
	row.add_child(UIKit.label("⇄", 14))
	row.add_child(in_opt)
	var go_b := UIKit.button("OK", func() -> void:
		if out_opt.selected < 0 or in_opt.selected < 0:
			return
		var err := live.substitute(side, str(on[out_opt.selected]), str(bench[in_opt.selected]))
		if err != "":
			say(err, true)
			return
		_add_feed(live.events[live.events.size() - 1])
		_refresh(), 44)
	row.add_child(go_b)
	return row


## "Play on in 3D from here": the 3D match of this fixture starts at this minute with the same score, goals and cards.
func _play_3d() -> void:
	var career: CareerState = app().career
	var f: Dictionary = (career.competitions[competition_id] as Competition).get_fixture(match_id)
	app().pending_resume = {"minute": live.minute, "score": live.score.duplicate(), "events": live.events.duplicate(true), "stats": live.stats.duplicate(true)}
	var err: String = app().play_fixture(competition_id, f)
	if err != "":
		app().pending_resume = {}
		say(err, true)


func _my_side() -> String:
	return "home" if live.home_id == app().career.club_id else "away"


func _process(delta: float) -> void:
	if live == null or finished or paused or _pitch == null:
		return
	_acc += delta * speed * (30.0 if to_end else 1.0)
	while _acc >= MINUTE_SECONDS and not live.finished():
		_acc -= MINUTE_SECONDS
		var evs := live.step()
		for ev in evs:
			_add_feed(ev)
			_ball_target = Vector2(1.0 if ev["side"] == "home" else 0.0, 0.5) if str(ev["type"]) == "goal" else _ball_target
			if auto_stop and (str(ev["type"]) == "goal" or str(ev["type"]) == "red"):
				paused = true
				to_end = false
				var pb := find_child("LivePause", true, false) as Button
				if pb != null:
					pb.text = Loc.t("LIVE_PLAY_ON")
		_drift_ball()
		_refresh()
		if paused:
			break
	_ball = _ball.lerp(_ball_target, clampf(delta * 3.0, 0.0, 1.0))
	_pitch.queue_redraw()
	if live.finished() and not finished:
		finished = true
		_refresh()


func _drift_ball() -> void:
	var share := float(live.stats["home"]["possession"]) / 100.0
	var x := clampf(0.5 + (share - 0.5) * 0.9 + randf_range(-0.28, 0.28), 0.05, 0.95)
	_ball_target = Vector2(x, randf_range(0.15, 0.85))


func _add_feed(ev: Dictionary) -> void:
	var text := MatchEventEngine.describe(db(), ev)
	if str(ev["type"]) == "sub":
		var pin: PlayerData = db().get_player(str(ev["player_id"]))
		text = Loc.f("LIVE_EV_SUB", pin.display_name if pin != null else "")
	if text == "" or str(ev["type"]) in ["shot", "corner"] and _feed.get_child_count() > 30:
		return
	var color: Color = _colors[0] if ev["side"] == "home" else _colors[1]
	var big := str(ev["type"]) in ["goal", "red", "yellow"]
	var row := UIKit.hbox(6)
	var chip := ColorRect.new()
	chip.color = color
	chip.custom_minimum_size = Vector2(4, 0)
	row.add_child(chip)
	var mn := UIKit.label(Loc.ltr("%d'" % int(ev["minute"])), 14, UIKit.GOLD)
	mn.custom_minimum_size = Vector2(34, 0)
	row.add_child(mn)
	row.add_child(UIKit.label(str(ICONS.get(str(ev["type"]), "")), 14))
	var l := UIKit.label(text, 15 if big else 14, UIKit.TEXT if big else Color(0.8, 0.83, 0.88))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	_feed.add_child(row)
	_feed.move_child(row, 0)
	while _feed.get_child_count() > 40:
		_feed.get_child(_feed.get_child_count() - 1).queue_free()


func _refresh() -> void:
	if _score == null or live == null:
		return
	var h: TeamData = db().get_team(live.home_id)
	var a: TeamData = db().get_team(live.away_id)
	_score.text = Loc.ltr("%d - %d" % [int(live.score["home"]), int(live.score["away"])])
	_score.tooltip_text = "%s - %s" % [Loc.iso(h.display_name), Loc.iso(a.display_name)]
	if _minute != null:
		_minute.text = "%s  ·  %s" % [app().competition_title(competition_id), Loc.ltr("%d'" % live.minute) if not live.finished() else Loc.t("LIVE_FULL_TIME")]
	for c in _stats.get_children():
		_stats.remove_child(c)
		c.queue_free()
	var rows := [["LIVE_POSSESSION", "possession", "%"], ["LIVE_SHOTS", "shots", ""], ["LIVE_ON_TARGET", "on_target", ""], ["LIVE_CORNERS", "corners", ""]]
	_stats.layout_direction = Control.LAYOUT_DIRECTION_LTR          # home column on the left, like the scoreboard
	for r in rows:
		_stat_row(Loc.ltr("%d%s" % [int(live.stats["home"][r[1]]), r[2]]), Loc.t(r[0]), Loc.ltr("%d%s" % [int(live.stats["away"][r[1]]), r[2]]))
	_stat_row(Loc.ltr("%d / %d" % [int(live.stats["home"]["yellows"]), int(live.stats["home"]["reds"])]), Loc.t("LIVE_CARDS"),
			Loc.ltr("%d / %d" % [int(live.stats["away"]["yellows"]), int(live.stats["away"]["reds"])]))
	if live.stats["home"].has("xg"):
		_stat_row(Loc.ltr("%.2f" % float(live.stats["home"]["xg"])), "xG", Loc.ltr("%.2f" % float(live.stats["away"]["xg"])))


func _stat_row(home_text: String, title: String, away_text: String) -> void:
	var hl := UIKit.label(home_text, 16, _colors[0].lightened(0.25) if _colors[0].get_luminance() < 0.25 else _colors[0])
	hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hl.custom_minimum_size = Vector2(56, 0)
	_stats.add_child(hl)
	var tl := UIKit.label(title, 13, UIKit.MUTED)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats.add_child(tl)
	var al := UIKit.label(away_text, 16, _colors[1].lightened(0.25) if _colors[1].get_luminance() < 0.25 else _colors[1])
	al.custom_minimum_size = Vector2(56, 0)
	_stats.add_child(al)


## Both elevens as kit-coloured shirts with their numbers in a 4-4-2 shape, shifted towards the ball's zone, on a striped
## pitch with boxes, spots and goals; the ball moves smoothly. Home always plays left to right.
func _draw_pitch() -> void:
	var s := _pitch.size
	var pad := 12.0
	var r := Rect2(Vector2(pad, pad), s - Vector2(pad, pad) * 2.0)
	_pitch.draw_rect(Rect2(Vector2.ZERO, s), Color(0.09, 0.3, 0.14))
	var stripes := 12
	for i in stripes:
		var w := r.size.x / float(stripes)
		_pitch.draw_rect(Rect2(r.position + Vector2(w * i, 0), Vector2(w + 0.5, r.size.y)), Color(0.17, 0.52, 0.24) if i % 2 == 0 else Color(0.14, 0.46, 0.21))
	var line := Color(1, 1, 1, 0.8)
	_pitch.draw_rect(r, line, false, 2.0)
	var cx := r.position.x + r.size.x / 2.0
	_pitch.draw_line(Vector2(cx, r.position.y), Vector2(cx, r.end.y), line, 2.0)
	_pitch.draw_arc(r.get_center(), r.size.y * 0.15, 0.0, TAU, 48, line, 2.0)
	_pitch.draw_circle(r.get_center(), 3.0, line)
	for side_i in 2:
		var x0 := r.position.x if side_i == 0 else r.end.x
		var dir := 1.0 if side_i == 0 else -1.0
		var box_w := r.size.x * 0.16
		var box_h := r.size.y * 0.6
		var six_w := r.size.x * 0.055
		var six_h := r.size.y * 0.28
		var cy := r.get_center().y
		_pitch.draw_rect(Rect2(Vector2(x0 if dir > 0 else x0 - box_w, cy - box_h / 2.0), Vector2(box_w, box_h)), line, false, 2.0)
		_pitch.draw_rect(Rect2(Vector2(x0 if dir > 0 else x0 - six_w, cy - six_h / 2.0), Vector2(six_w, six_h)), line, false, 2.0)
		_pitch.draw_circle(Vector2(x0 + dir * r.size.x * 0.11, cy), 2.5, line)
		var goal_h := r.size.y * 0.14
		_pitch.draw_rect(Rect2(Vector2(x0 - (8.0 if dir > 0 else 0.0), cy - goal_h / 2.0), Vector2(8.0, goal_h)), Color(1, 1, 1, 0.9), false, 2.0)
	var font := ThemeDB.fallback_font
	var rad := clampf(r.size.y * 0.04, 9.0, 13.0)
	for side_i in 2:
		var side := "home" if side_i == 0 else "away"
		var xi: Array = live.xi[side]
		var col: Color = _colors[side_i]
		var ink := _ink(col)
		for i in xi.size():
			var slot := _slot(i)
			var fx: float = slot.x * 0.5 if side_i == 0 else 1.0 - slot.x * 0.5          # home defends the left half
			fx = lerpf(fx, _ball.x, 0.22)
			var fy: float = lerpf(slot.y, _ball.y, 0.12)
			var pos := r.position + Vector2(fx, fy) * r.size
			var p: PlayerData = xi[i]
			var c := col
			if p.position == PlayerData.Position.GK:
				c = Color(0.95, 0.8, 0.1) if side_i == 0 else Color(0.2, 0.85, 0.85)   # keepers wear their own colour
			_pitch.draw_circle(pos + Vector2(1.5, 2.0), rad, Color(0, 0, 0, 0.35))      # shadow
			_pitch.draw_circle(pos, rad, c)
			_pitch.draw_arc(pos, rad, 0.0, TAU, 24, _ink(c).lerp(c, 0.4), 2.0)
			var shirt := str(p.shirt_number if p.shirt_number > 0 else i + 1)
			var fs := int(rad * 1.05)
			var tw := font.get_string_size(shirt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			_pitch.draw_string(font, pos + Vector2(-tw / 2.0, fs * 0.36), shirt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, _ink(c) if p.position == PlayerData.Position.GK else ink)
	var bp := r.position + _ball * r.size
	_pitch.draw_circle(bp + Vector2(1.5, 2.0), 5.0, Color(0, 0, 0, 0.4))
	_pitch.draw_circle(bp, 5.5, Color.WHITE)
	_pitch.draw_arc(bp, 5.5, 0.0, TAU, 14, Color.BLACK, 1.2)


## Slot of the i-th player in own-half coordinates (x 0 = own goal .. 1 = halfway, y 0..1).
func _slot(i: int) -> Vector2:
	const SHAPE := [Vector2(0.03, 0.5), Vector2(0.28, 0.12), Vector2(0.24, 0.37), Vector2(0.24, 0.63), Vector2(0.28, 0.88),
			Vector2(0.55, 0.15), Vector2(0.5, 0.4), Vector2(0.5, 0.6), Vector2(0.55, 0.85), Vector2(0.85, 0.35), Vector2(0.85, 0.65)]
	return SHAPE[mini(i, SHAPE.size() - 1)]


func _finish() -> void:
	var career: CareerState = app().career
	if career == null or live == null:
		return
	while not live.finished():
		live.step()
	career.live_records[match_id] = live.record()
	var f: Dictionary = (career.competitions[competition_id] as Competition).get_fixture(match_id)
	var res := live.result(match_id)
	if (str(f.get("stage", "")) == "ko" or str(f.get("stage", "")) == "third") and res.home_goals == res.away_goals:
		var hr: int = db().get_team_rating(live.home_id) + 4
		var ar: int = db().get_team_rating(live.away_id)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(match_id)
		var pens := PenaltyShootout.resolve(hr, ar, rng)
		res = MatchResult.make(match_id, live.home_id, live.away_id, res.home_goals, res.away_goals, pens[0], pens[1])
	var err := career.submit_result(competition_id, res)
	app().state_changed.emit()
	if err != "":
		say(err, true)
		return
	app()._auto_trigger()
	say(Loc.t("TABLE_MATCH_SIMULATED"))
	go("career")
