class_name MatchHud
extends Control

## In-match HUD (UX phase 2): a scoreboard panel on a dark, rounded, semi-transparent background
## (readable over the blue LED boards in follow view) with both crests next to the short names,
## the score, the clock and the half; a notice line (fouls, cards, half time); the stamina of the
## human-controlled player. In Arabic the home team sits on the right (reading order), in LTR
## languages on the left. Pure view: `MatchManager` calls `refresh()` every frame.

const BG := Color(0.03, 0.05, 0.1, 0.78)

var _row: HBoxContainer
var _home_name: Label
var _away_name: Label
var _home_score: Label
var _away_score: Label
var _clock: Label
var _half: Label
var _notice: Label
var _stamina_box: HBoxContainer
var _stamina_name: Label
var _stamina_bar: ProgressBar


## Builds the HUD for a match between `home_id` and `away_id`.
static func create(db: Node, home_id: String, away_id: String) -> MatchHud:
	var hud := MatchHud.new()
	hud.name = "MatchHud"
	hud._build(db, home_id, away_id)
	return hud


func _build(db: Node, home_id: String, away_id: String) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := VBoxContainer.new()
	top.name = "Top"
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.anchor_left = 0.5
	top.anchor_right = 0.5
	top.offset_left = -330.0
	top.offset_right = 330.0
	top.offset_top = 10.0
	top.alignment = BoxContainer.ALIGNMENT_BEGIN
	top.add_theme_constant_override("separation", 4)
	add_child(top)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(center)
	var panel := PanelContainer.new()
	panel.name = "Scoreboard"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _style(BG, 10, Vector2(14, 6)))
	center.add_child(panel)
	_row = HBoxContainer.new()
	_row.name = "HudCrests"           # home first in child order; RTL layout puts it on the right
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", 10)
	panel.add_child(_row)
	var h: TeamData = db.get_team(home_id)
	var a: TeamData = db.get_team(away_id)
	_row.add_child(UIKit.crest(db, home_id, 34, "card"))
	_home_name = _text(Loc.iso(h.short_name if h != null else home_id), 22, UIKit.TEXT)
	_home_name.name = "HomeName"
	_row.add_child(_home_name)
	var score_box := PanelContainer.new()
	score_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	score_box.add_theme_stylebox_override("panel", _style(Color(0.93, 0.75, 0.3, 0.95), 6, Vector2(10, 0)))
	var score_row := HBoxContainer.new()
	score_row.name = "Score"
	score_row.add_theme_constant_override("separation", 8)
	score_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_home_score = _text("0", 24, UIKit.BG)
	_home_score.name = "HomeScore"
	_away_score = _text("0", 24, UIKit.BG)
	_away_score.name = "AwayScore"
	score_row.add_child(_home_score)
	score_row.add_child(_text("-", 22, UIKit.BG))
	score_row.add_child(_away_score)
	score_box.add_child(score_row)
	_row.add_child(score_box)
	_away_name = _text(Loc.iso(a.short_name if a != null else away_id), 22, UIKit.TEXT)
	_away_name.name = "AwayName"
	_row.add_child(_away_name)
	_row.add_child(UIKit.crest(db, away_id, 34, "card"))
	var sep := VSeparator.new()
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(sep)
	_clock = _text("00:00", 22, UIKit.GOLD)
	_clock.name = "Clock"
	_row.add_child(_clock)
	_half = _text("", 15, UIKit.MUTED)
	_half.name = "Half"
	_row.add_child(_half)
	_notice = _text("", 18, UIKit.TEXT)
	_notice.name = "Notice"
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var notice_center := CenterContainer.new()
	notice_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var notice_panel := PanelContainer.new()
	notice_panel.name = "NoticePanel"
	notice_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notice_panel.add_theme_stylebox_override("panel", _style(BG, 8, Vector2(12, 3)))
	notice_panel.add_child(_notice)
	notice_center.add_child(notice_panel)
	top.add_child(notice_center)
	# Stamina of the controlled player (bottom start corner, above the touch stick area on phones).
	var stamina_panel := PanelContainer.new()
	stamina_panel.name = "StaminaPanel"
	stamina_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stamina_panel.add_theme_stylebox_override("panel", _style(BG, 8, Vector2(10, 4)))
	stamina_panel.anchor_top = 0.0
	stamina_panel.offset_left = 16.0
	stamina_panel.offset_top = 10.0
	add_child(stamina_panel)
	_stamina_box = HBoxContainer.new()
	_stamina_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stamina_box.add_theme_constant_override("separation", 8)
	stamina_panel.add_child(_stamina_box)
	_stamina_name = _text("", 15, UIKit.TEXT)
	_stamina_name.name = "StaminaName"
	_stamina_box.add_child(_stamina_name)
	_stamina_bar = ProgressBar.new()
	_stamina_bar.name = "StaminaBar"
	_stamina_bar.min_value = 0
	_stamina_bar.max_value = 100
	_stamina_bar.show_percentage = false
	_stamina_bar.custom_minimum_size = Vector2(120, 12)
	_stamina_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_stamina_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stamina_box.add_child(_stamina_bar)
	stamina_panel.visible = false


static func _style(color: Color, radius: int, margin: Vector2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.content_margin_left = margin.x
	s.content_margin_right = margin.x
	s.content_margin_top = margin.y
	s.content_margin_bottom = margin.y
	return s


func _text(t: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## Updates every value. `notice` = rule notice / half time / full time text ("" hides the line);
## `controlled` = {"name", "stamina"} of the human's player ({} hides the stamina bar).
func refresh(home_goals: int, away_goals: int, clock: String, half: int, notice: String, controlled: Dictionary) -> void:
	_home_score.text = str(home_goals)
	_away_score.text = str(away_goals)
	_clock.text = Loc.ltr(clock)
	_half.text = Loc.f("HUD_HALF_N", half)
	_notice.text = notice
	(_notice.get_parent() as Control).visible = notice != ""
	var panel := _stamina_box.get_parent() as Control
	panel.visible = not controlled.is_empty()
	if not controlled.is_empty():
		_stamina_name.text = str(controlled.get("name", ""))
		_stamina_bar.value = float(controlled.get("stamina", 100.0))
		var low := _stamina_bar.value < 35.0
		_stamina_bar.modulate = UIKit.BAD if low else UIKit.GOOD


## Score as displayed, home value first (tests).
## Phase H1: the competition's name above the scoreboard (the tournament plate; its colour is the competition's).
func set_competition(title: String) -> void:
	var top := get_node_or_null("Top")
	if top == null or title == "":
		return
	var old := top.get_node_or_null("CompetitionPlate")
	if old != null:
		old.queue_free()
	var plate := PanelContainer.new()
	plate.name = "CompetitionPlate"
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_theme_stylebox_override("panel", _style(Color(0.05, 0.08, 0.15, 0.85), 8, Vector2(12, 2)))
	plate.add_child(_text("🏆  " + title, 14, UIKit.GOLD))
	var c := CenterContainer.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(plate)
	top.add_child(c)
	top.move_child(c, 0)


func score_text() -> String:
	return "%s-%s" % [_home_score.text, _away_score.text]
