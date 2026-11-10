extends Control

## Minimal probe: verify the text_direction value that yields LTR alignment.
## ALPHA has text_direction = 1, BETA = 2, CENTER = 1. On an ar-locale system
## (RTL), before this fix ALPHA rendered mirrored to the right.

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var left := Label.new()
	left.text = "ALPHA-dir1"
	left.set_anchors_preset(Control.PRESET_FULL_RECT)
	left.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	left.text_direction = 1
	left.layout_direction = 2
	left.add_theme_font_size_override("font_size", 40)
	left.add_theme_color_override("font_color", Color.CYAN)
	add_child(left)

	var right := Label.new()
	right.text = "BETA-dir2(halign=2)"
	right.set_anchors_preset(Control.PRESET_FULL_RECT)
	right.anchor_top = 0.35
	right.anchor_bottom = 0.35
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.text_direction = 2
	right.add_theme_font_size_override("font_size", 40)
	right.add_theme_color_override("font_color", Color.YELLOW)
	add_child(right)

	var center := Label.new()
	center.text = "CENTER-dir1"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.anchor_top = 0.6
	center.anchor_bottom = 0.6
	center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.text_direction = 1
	center.add_theme_font_size_override("font_size", 40)
	center.add_theme_color_override("font_color", Color.WHITE)
	add_child(center)

	var rect := ColorRect.new()
	rect.color = Color(1, 0.2, 0.2)
	add_child(rect)
	rect.position = Vector2(20, 500)
	rect.size = Vector2(300, 60)

	await get_tree().create_timer(0.6).timeout
	var image := get_viewport().get_texture().get_image()
	image.save_png("res://assets/placeholders/validation/mirror_probe.png")
	print("[PROBE] alpha.dir=%d right.dir=%d" % [left.text_direction, right.text_direction])
	get_tree().quit()
