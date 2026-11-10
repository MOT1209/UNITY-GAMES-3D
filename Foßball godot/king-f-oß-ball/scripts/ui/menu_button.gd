class_name MenuItemButton
extends Button

## Reusable styled menu button:
##   - centered pivot + press/hover scale feedback (no per-menu styling copies)
##   - disabled buttons get the shared "coming soon" tooltip note

@export var disabled_note := "Coming soon in a later phase"

var _tween: Tween


func _ready() -> void:
	pivot_offset = size * 0.5
	resized.connect(func() -> void: pivot_offset = size * 0.5)

	mouse_entered.connect(_set_zoom.bind(1.03))
	mouse_exited.connect(_set_zoom.bind(1.0))
	focus_entered.connect(_set_zoom.bind(1.03))
	focus_exited.connect(_set_zoom.bind(1.0))
	button_down.connect(_set_zoom.bind(0.97))
	button_up.connect(_set_zoom.bind(1.0))

	if disabled and disabled_note != "":
		tooltip_text = disabled_note


func _set_zoom(target: float) -> void:
	scale = Vector2.ONE * target
