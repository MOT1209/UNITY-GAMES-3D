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
		for i in 2:
			var team: TeamData = db().get_team(f["home"] if i == 0 else f["away"])
			var kit := TeamKit.for_team(db(), team, "home" if i == 0 else "away")
			if kit != null:
				_colors[i] = kit.jersey
	own_scroll = false
	_score = UIKit.label("", 22, UIKit.GOLD)
	_score.name = "LiveScore"
	_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_score)
	_pitch = Control.new()
	_pitch.name = "LivePitch"
	_pitch.custom_minimum_size = Vector2(0, 300)
	_pitch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pitch.draw.connect(_draw_pitch)
	add_child(_pitch)
	add_child(_controls())
	var body := UIKit.hbox(UIKit.SPACE_M)
	_feed = UIKit.vbox(2)
	_feed.name = "LiveFeed"
	_feed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_feed)
	_stats = GridContainer.new()
	_stats.columns = 3
	_stats.name = "LiveStats"
	body.add_child(UIKit.panel(_stats))
	add_child(body)
	for ev in live.events:
		_add_feed(ev)
	_refresh()


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
	var l := UIKit.label("%d'  %s  %s" % [int(ev["minute"]), str(ICONS.get(str(ev["type"]), "")), text], 14, color if str(ev["type"]) in ["goal", "red", "yellow"] else UIKit.TEXT)
	_feed.add_child(l)
	_feed.move_child(l, 0)
	while _feed.get_child_count() > 40:
		_feed.get_child(_feed.get_child_count() - 1).queue_free()


func _refresh() -> void:
	if _score == null or live == null:
		return
	var h: TeamData = db().get_team(live.home_id)
	var a: TeamData = db().get_team(live.away_id)
	_score.text = "%s  %s  %s   ·   %s   %d'" % [Loc.iso(h.display_name), Loc.ltr("%d - %d" % [int(live.score["home"]), int(live.score["away"])]), Loc.iso(a.display_name),
			app().competition_title(competition_id), live.minute]
	for c in _stats.get_children():
		_stats.remove_child(c)
		c.queue_free()
	var rows := [["LIVE_POSSESSION", "possession", "%"], ["LIVE_SHOTS", "shots", ""], ["LIVE_ON_TARGET", "on_target", ""], ["LIVE_CORNERS", "corners", ""]]
	for r in rows:
		_stats.add_child(UIKit.label("%d%s" % [int(live.stats["home"][r[1]]), r[2]], 14))
		_stats.add_child(UIKit.label(Loc.t(r[0]), 13, UIKit.MUTED))
		_stats.add_child(UIKit.label("%d%s" % [int(live.stats["away"][r[1]]), r[2]], 14))
	_stats.add_child(UIKit.label("%d / %d" % [int(live.stats["home"]["yellows"]), int(live.stats["home"]["reds"])], 14))
	_stats.add_child(UIKit.label(Loc.t("LIVE_CARDS"), 13, UIKit.MUTED))
	_stats.add_child(UIKit.label("%d / %d" % [int(live.stats["away"]["yellows"]), int(live.stats["away"]["reds"])], 14))


## Both elevens as dots in a 4-4-2 / 4-3-3 shape, shifted towards the ball's zone; the ball moves smoothly.
func _draw_pitch() -> void:
	var s := _pitch.size
	var pad := 10.0
	var r := Rect2(Vector2(pad, pad), s - Vector2(pad, pad) * 2.0)
	_pitch.draw_rect(r, Color(0.16, 0.5, 0.22))
	var line := Color(1, 1, 1, 0.7)
	_pitch.draw_rect(r, line, false, 2.0)
	_pitch.draw_line(Vector2(r.position.x + r.size.x / 2.0, r.position.y), Vector2(r.position.x + r.size.x / 2.0, r.end.y), line, 2.0)
	_pitch.draw_arc(r.get_center(), r.size.y * 0.16, 0.0, TAU, 40, line, 2.0)
	for side_i in 2:
		var side := "home" if side_i == 0 else "away"
		var xi: Array = live.xi[side]
		for i in xi.size():
			var slot := _slot(i)
			var fx: float = slot.x * 0.5 if side_i == 0 else 1.0 - slot.x * 0.5          # home defends the left half
			fx = lerpf(fx, _ball.x, 0.22)
			var fy: float = lerpf(slot.y, _ball.y, 0.12)
			var pos := r.position + Vector2(fx, fy) * r.size
			_pitch.draw_circle(pos, 9.0, _colors[side_i])
			_pitch.draw_arc(pos, 9.0, 0.0, TAU, 16, Color(1, 1, 1, 0.8), 1.5)
			var shirt := str(i + 1)
			_pitch.draw_string(ThemeDB.fallback_font, pos + Vector2(-4.0 * shirt.length(), 4.0), shirt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
	var bp := r.position + _ball * r.size
	_pitch.draw_circle(bp, 5.0, Color.WHITE)
	_pitch.draw_arc(bp, 5.0, 0.0, TAU, 12, Color.BLACK, 1.0)


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
