## Builds resources/theme/main_theme.tres — the game's single UI theme (navy + gold):
##   godot --headless --path . res://tools/build_theme.tscn
## Colours and sizes come from UIKit so code-built and theme-styled controls always agree.
extends Node

const OUT := "res://resources/theme/main_theme.tres"


func _ready() -> void:
	var t := Theme.new()
	t.default_font_size = UIKit.FONT_M
	var normal := _box(UIKit.PANEL.lightened(0.06), Color(0, 0, 0, 0), 0)
	var hover := _box(UIKit.PANEL.lightened(0.14), UIKit.GOLD.darkened(0.3), 1)
	var pressed := _box(UIKit.GOLD.darkened(0.45), UIKit.GOLD, 1)
	var disabled := _box(UIKit.PANEL.darkened(0.2), Color(0, 0, 0, 0), 0)
	var focus := _box(Color(0, 0, 0, 0), UIKit.GOLD, 2)
	focus.draw_center = false
	for cls in ["Button", "OptionButton", "MenuButton", "CheckButton"]:
		t.set_stylebox("normal", cls, normal)
		t.set_stylebox("hover", cls, hover)
		t.set_stylebox("pressed", cls, pressed)
		t.set_stylebox("disabled", cls, disabled)
		t.set_stylebox("focus", cls, focus)
		t.set_color("font_color", cls, UIKit.TEXT)
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_pressed_color", cls, UIKit.GOLD)
		t.set_color("font_disabled_color", cls, UIKit.MUTED.darkened(0.3))
		t.set_color("font_focus_color", cls, Color.WHITE)
	t.set_color("font_color", "Label", UIKit.TEXT)
	var panel := _box(UIKit.PANEL, Color(0, 0, 0, 0), 0)
	panel.set_content_margin_all(UIKit.SPACE_M)
	t.set_stylebox("panel", "PanelContainer", panel)
	var edit := _box(UIKit.BG.lightened(0.04), UIKit.MUTED.darkened(0.3), 1)
	t.set_stylebox("normal", "LineEdit", edit)
	t.set_stylebox("focus", "LineEdit", _box(UIKit.BG.lightened(0.04), UIKit.GOLD, 1))
	t.set_color("font_color", "LineEdit", UIKit.TEXT)
	var bar_bg := _box(UIKit.BG.lightened(0.05), Color(0, 0, 0, 0), 0)
	var bar_fill := _box(UIKit.GOLD.darkened(0.15), Color(0, 0, 0, 0), 0)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fill)
	t.set_constant("separation", "VBoxContainer", UIKit.SPACE_S)
	t.set_constant("separation", "HBoxContainer", UIKit.SPACE_S)
	# Variations (Nov 2026 unified theme): screens set theme_type_variation instead of building style boxes.
	var prim_n := _box(UIKit.GOLD.darkened(0.25), UIKit.GOLD, 2)
	var prim_h := _box(UIKit.GOLD.darkened(0.1), UIKit.GOLD, 2)
	t.set_type_variation(UIKit.V_PRIMARY, "Button")
	for st in ["normal", "focus"]:
		t.set_stylebox(st, UIKit.V_PRIMARY, prim_n)
	t.set_stylebox("hover", UIKit.V_PRIMARY, prim_h)
	t.set_stylebox("pressed", UIKit.V_PRIMARY, prim_h)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(c, UIKit.V_PRIMARY, UIKit.BG)
	t.set_font_size("font_size", UIKit.V_PRIMARY, 18)
	var act := _box(UIKit.PANEL.lightened(0.12), UIKit.GOLD, 2)
	t.set_type_variation(UIKit.V_ACTIVE, "Button")
	for st in ["normal", "hover", "pressed", "focus"]:
		t.set_stylebox(st, UIKit.V_ACTIVE, act)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(c, UIKit.V_ACTIVE, UIKit.GOLD)
	var card := _box(UIKit.PANEL, UIKit.GOLD.darkened(0.2), 2)
	card.set_content_margin_all(UIKit.SPACE_M)
	t.set_type_variation(UIKit.V_CARD_PANEL, "PanelContainer")
	t.set_stylebox("panel", UIKit.V_CARD_PANEL, card)
	t.set_font_size("font_size", "HeaderLarge", UIKit.FONT_L)
	t.set_type_variation("HeaderLarge", "Label")
	t.set_font_size("font_size", "HeaderSmall", UIKit.FONT_S)
	t.set_type_variation("HeaderSmall", "Label")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://resources/theme"))
	var err := ResourceSaver.save(t, OUT)
	print("theme saved: %s (%d)" % [OUT, err])
	get_tree().quit(0 if err == OK else 1)


func _box(bg: Color, border: Color, border_w: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(6)
	s.content_margin_left = UIKit.SPACE_M - 4
	s.content_margin_right = UIKit.SPACE_M - 4
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s
