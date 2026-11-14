class_name TouchJoystick
extends Control

## Thumb-stick for touch play (P4 mobile foundations). A base circle with a
## knob; dragging inside it produces `output` in the same screen convention as
## the keyboard move actions (`Input.get_vector("move_left", "move_right",
## "move_forward", "move_backward")`): +x = right, −y = up/forward. The
## TouchControls owner polls `output` every physics tick and feeds it to the
## driven `IntentProvider`, so gameplay code cannot tell stick from keyboard.
##
## Handles native touch (InputEventScreenTouch/Drag) and a mouse fallback so
## the stick is testable on desktop; `_update_output` / `_release_pointer` are
## the seams the validation suite drives directly.

const KNOB_RATIO := 0.45            # knob radius relative to the base radius

var radius: float = 90.0
var output: Vector2 = Vector2.ZERO  # screen convention, length clamped to 1

var _pointer: int = -1              # active touch index (-1 = none)
var _knob: Vector2                  # knob position in local coordinates


func _init(p_radius: float = 90.0) -> void:
	radius = p_radius
	custom_minimum_size = Vector2(radius * 2.0, radius * 2.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_knob = Vector2(radius, radius)


func _draw() -> void:
	var centre := Vector2(radius, radius)
	draw_circle(centre, radius, Color(1.0, 1.0, 1.0, 0.10))
	draw_arc(centre, radius, 0.0, TAU, 48, Color(1.0, 1.0, 1.0, 0.25), 2.0)
	draw_circle(_knob, radius * KNOB_RATIO, Color(1.0, 1.0, 1.0, 0.30))
	draw_arc(_knob, radius * KNOB_RATIO, 0.0, TAU, 32, UIKit.GOLD, 2.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_try_grab(event.index, event.position)
		else:
			_release_pointer(event.index)
		accept_event()
	elif event is InputEventScreenDrag:
		if event.index == _pointer:
			_update_output(event.position)
			accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_try_grab(-2, event.position)
		else:
			_release_pointer(-2)
		accept_event()
	elif event is InputEventMouseMotion and _pointer == -2:
		_update_output(event.position)
		accept_event()


func _try_grab(pointer: int, local_pos: Vector2) -> void:
	if _pointer != -1:
		return
	if local_pos.distance_to(Vector2(radius, radius)) > radius * 1.15:
		return                       # forgiveness margin of 15 % around the base
	_pointer = pointer
	_update_output(local_pos)


func _release_pointer(pointer: int) -> void:
	if pointer != _pointer:
		return
	_pointer = -1
	output = Vector2.ZERO
	_knob = Vector2(radius, radius)
	queue_redraw()


## Test seam: drive the stick exactly like a drag would.
func _update_output(local_pos: Vector2) -> void:
	output = ((local_pos - Vector2(radius, radius)) / radius).limit_length(1.0)
	_knob = Vector2(radius, radius) + output * radius
	queue_redraw()


## Test seam: simulate lifting the finger.
func release() -> void:
	_release_pointer(_pointer)
