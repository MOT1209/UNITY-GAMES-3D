class_name CameraTestTarget
extends Node3D

## Phase 1 only: a visible test target that orbits the pitch so the Dynamic
## (follow) camera's behavior can be verified without any player controller.
## Not gameplay — pure camera validation, kept under scripts/debug.

@export var orbit_radius := 14.0
@export var orbit_speed_radians := 0.5   # rad/s → slower, readable motion
@export var start_angle := 0.0
@export var enabled := true

var _angle := 0.0


func _ready() -> void:
	_angle = start_angle


func _process(delta: float) -> void:
	if not enabled:
		return
	_angle += orbit_speed_radians * delta
	position = Vector3(cos(_angle), 0.0, sin(_angle)) * orbit_radius
