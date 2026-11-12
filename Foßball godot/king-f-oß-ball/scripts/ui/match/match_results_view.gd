class_name MatchResultsView
extends PanelContainer

## Post-match results screen (Phase 7.2). Shows ONLY what the `MatchReport` contains:
## score, scorers with minutes, and — when the report lists them as `measured` — possession, shots,
## shots on target, passes, pass accuracy, saves, substitutions, player ratings and the man of the
## match. A report of a quick-simulated match has only the score, so nothing else is shown.

signal continue_pressed

var report: Dictionary = {}
var _db: Node


static func create(p_report: Dictionary, db: Node) -> MatchResultsView:
	var v := MatchResultsView.new()
	v.report = p_report
	v._db = db
	v.name = "MatchResultsView"
	v._build()
	return v


func _team_name(side: String) -> String:
	var t: TeamData = _db.get_team(report["home_id" if side == "home" else "away_id"])
	return t.display_name if t != null else "?"


func _player_name(player_id: String) -> String:
	var p: PlayerData = _db.get_player(player_id)
	return p.display_name if p != null else player_id


func _measured(key: String) -> bool:
	return key in (report.get("measured", []) as Array)


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.05, 0.1, 1.0)        # opaque: the arena's own HUD text must not show through
	add_theme_stylebox_override("panel", style)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var col := UIKit.vbox(10)
	col.custom_minimum_size = Vector2(620, 0)
	center.add_child(col)
	# headline: outcome for the human side, else just "Full time"
	var outcome: String = report.get("outcome_human", "")
	var head := UIKit.label(Loc.t("RESULT_" + outcome.to_upper()) if outcome != "" else Loc.t("HUD_FULL_TIME"), 30,
			{"win": UIKit.GOOD, "loss": UIKit.BAD}.get(outcome, UIKit.GOLD))
	head.name = "OutcomeLabel"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(head)
	# scoreboard: home left, away right in every language
	var board := HBoxContainer.new()
	board.layout_direction = Control.LAYOUT_DIRECTION_LTR
	board.alignment = BoxContainer.ALIGNMENT_CENTER
	board.add_theme_constant_override("separation", 24)
	var h := UIKit.label(Loc.iso(_team_name("home")), 22)
	h.custom_minimum_size = Vector2(200, 0)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var score := UIKit.label("%d - %d" % [int(report["home_goals"]), int(report["away_goals"])], 44, CardCategory.GOLD)
	score.name = "ScoreLabel"
	# Regression (found on an Arabic screenshot): under an RTL language the label reordered the digits
	# around the dash and showed "0 - 1" for a 1 - 0 win. Scores are always laid out left-to-right.
	score.text_direction = Control.TEXT_DIRECTION_LTR
	score.language = "en"
	var a := UIKit.label(Loc.iso(_team_name("away")), 22)
	a.custom_minimum_size = Vector2(200, 0)
	for n in [UIKit.crest(_db, report["home_id"], 44, "card"), h, score, a, UIKit.crest(_db, report["away_id"], 44, "card")]:
		board.add_child(n)
	col.add_child(board)
	if report.has("home_pens"):
		var pens := UIKit.muted(Loc.f("RESULT_PENALTIES", [int(report["home_pens"]), int(report["away_pens"])]))
		pens.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(pens)
	if report.get("source", "") == "simulation":
		col.add_child(UIKit.muted(Loc.t("RESULT_SIMULATED_NOTE")))
	if _measured("scorers"):
		col.add_child(_scorers())
	if _measured("possession"):
		col.add_child(_team_stats())
	if _measured("ratings") and not (report["players"] as Array).is_empty():
		col.add_child(_ratings())
	var cont := UIKit.button(Loc.t("COMMON_CONTINUE"), func() -> void: continue_pressed.emit(), 220)
	cont.name = "ContinueButton"
	cont.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(cont)
	cont.grab_focus.call_deferred()


func _scorers() -> Control:
	var box := UIKit.vbox(2)
	box.name = "Scorers"
	box.add_child(UIKit.label(Loc.t("RESULT_GOALS"), 16, UIKit.GOLD))
	if (report["scorers"] as Array).is_empty():
		box.add_child(UIKit.muted(Loc.t("RESULT_NO_GOALS")))
	for g in report["scorers"]:
		var text := "%d'  %s" % [int(g["minute"]), Loc.iso(_player_name(g["player_id"]) if g["player_id"] != "" else "—")]
		if g["own_goal"]:
			text += "  " + Loc.t("RESULT_OWN_GOAL")
		elif g["assist_id"] != "":
			text += "  (" + Loc.f("RESULT_ASSIST", Loc.iso(_player_name(g["assist_id"]))) + ")"
		var row := UIKit.label(text, 15)
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if g["side"] == "home" else HORIZONTAL_ALIGNMENT_RIGHT
		box.add_child(row)
	return UIKit.panel(box)


func _team_stats() -> Control:
	var grid := GridContainer.new()
	grid.name = "TeamStats"
	grid.columns = 3
	grid.layout_direction = Control.LAYOUT_DIRECTION_LTR
	grid.add_theme_constant_override("h_separation", 20)
	var ts: Dictionary = report["team_stats"]
	var rows: Array = [
		["possession", "RESULT_POSSESSION", func(s: Dictionary) -> String: return "%s%%" % str(s["possession"])],
		["shots", "RESULT_SHOTS", func(s: Dictionary) -> String: return str(s["shots"])],
		["shots_on_target", "RESULT_SHOTS_ON_TARGET", func(s: Dictionary) -> String: return str(s["shots_on_target"])],
		["passes", "RESULT_PASSES", func(s: Dictionary) -> String: return "%d (%d)" % [int(s["passes"]), int(s["passes_ok"])]],
		["pass_accuracy", "RESULT_PASS_ACCURACY", func(s: Dictionary) -> String: return "%s%%" % str(s["pass_accuracy"])],
		["saves", "RESULT_SAVES", func(s: Dictionary) -> String: return str(s["saves"])],
		["substitutions", "RESULT_SUBSTITUTIONS", func(s: Dictionary) -> String: return str(s["substitutions"])],
		["fouls", "RESULT_FOULS", func(s: Dictionary) -> String: return str(int(s.get("fouls", 0)))],
		["corners", "RESULT_CORNERS", func(s: Dictionary) -> String: return str(int(s.get("corners", 0)))],
		["throw_ins", "RESULT_THROW_INS", func(s: Dictionary) -> String: return str(int(s.get("throw_ins", 0)))],
		["offsides", "RESULT_OFFSIDES", func(s: Dictionary) -> String: return str(int(s.get("offsides", 0)))],
		["cards", "RESULT_CARDS", func(s: Dictionary) -> String: return "%d / %d" % [int(s.get("yellows", 0)), int(s.get("reds", 0))]],
	]
	for r in rows:
		if not _measured(r[0]):
			continue
		var hl := UIKit.label(r[2].call(ts["home"]), 16)
		hl.text_direction = Control.TEXT_DIRECTION_LTR
		hl.custom_minimum_size = Vector2(110, 0)
		hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var mid := UIKit.label(Loc.t(r[1]), 14, UIKit.MUTED)
		mid.custom_minimum_size = Vector2(190, 0)
		mid.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var al := UIKit.label(r[2].call(ts["away"]), 16)
		al.text_direction = Control.TEXT_DIRECTION_LTR
		al.custom_minimum_size = Vector2(110, 0)
		grid.add_child(hl)
		grid.add_child(mid)
		grid.add_child(al)
	return UIKit.panel(grid)


func _ratings() -> Control:
	var box := UIKit.vbox(2)
	box.name = "Ratings"
	box.add_child(UIKit.label(Loc.t("RESULT_RATINGS"), 16, UIKit.GOLD))
	var motm: String = report.get("motm", "")
	if motm != "":
		var m := UIKit.label(Loc.f("RESULT_MOTM", Loc.iso(_player_name(motm))), 18, CardCategory.GOLD)
		m.name = "ManOfTheMatch"
		box.add_child(m)
	var cols := HBoxContainer.new()
	cols.layout_direction = Control.LAYOUT_DIRECTION_LTR
	cols.add_theme_constant_override("separation", 30)
	for side in ["home", "away"]:
		var c := UIKit.vbox(1)
		c.custom_minimum_size = Vector2(280, 0)
		c.add_child(UIKit.label(Loc.iso(_team_name(side)), 14, UIKit.MUTED))
		var n := 0
		for p in report["players"]:
			if p["side"] != side or n >= 6:
				continue
			n += 1
			var line := UIKit.label("%.1f  %s" % [float(p["rating"]), Loc.iso(_player_name(p["player_id"]))], 14,
					CardCategory.GOLD if p["player_id"] == motm else UIKit.TEXT)
			c.add_child(line)
		cols.add_child(c)
	box.add_child(cols)
	return UIKit.panel(box)
