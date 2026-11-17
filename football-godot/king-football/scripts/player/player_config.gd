class_name PlayerConfig
extends Resource

## Shared, tweak-in-editor configuration for the reusable player controller.
## Mirrors the CameraConfig pattern: `resources/configurations/player_config.tres`
## holds the project defaults and any player instance can point at its own
## resource copy through the `config` export.

enum MovementReference { CAMERA_RELATIVE, WORLD }

@export_group("Movement Speeds")
## Maximum run speed in m/s (normal play).
@export_range(1.0, 20.0, 0.1) var normal_speed: float = 5.5
## Maximum sprint speed in m/s while the "sprint" action is held.
@export_range(1.0, 30.0, 0.1) var sprint_speed: float = 8.0
## Master switch for the sprint system (stamina arrives in a later phase).
@export var sprint_enabled: bool = true

@export_group("Acceleration")
## Gain (m/s per second) while speeding up or changing direction.
@export_range(1.0, 60.0, 0.1) var acceleration: float = 18.0
## Gain (m/s per second) when no input is held — braking to a stop.
@export_range(1.0, 80.0, 0.1) var deceleration: float = 22.0

@export_group("Rotation")
## Turn responsiveness toward the movement direction (used as exponential
## damping strength, higher = snappier turning).
@export_range(0.5, 30.0, 0.1) var rotation_speed: float = 10.0
## Phase M4: the fastest the body may turn (degrees per second). A sudden 180-degree turn takes a third of a second
## instead of snapping round in four frames.
@export_range(90.0, 2000.0, 10.0) var max_turn_rate_degrees: float = 540.0
## Fraction of `max_turn_rate_degrees` while the player has the ball at his feet (dribbling).
@export_range(0.1, 1.0, 0.05) var dribble_turn_factor: float = 0.67

@export_group("Movement Reference")
## CAMERA_RELATIVE: forward follows the active camera's flattened basis.
## WORLD: forward is always world −Z. When no camera exists the controller
## automatically falls back to WORLD behaviour.
@export var movement_reference: MovementReference = MovementReference.CAMERA_RELATIVE

@export_group("Physics")
## Downward acceleration in m/s² (gameplay gravity, independent of the
## project-level gravity setting).
@export_range(1.0, 50.0, 0.1) var gravity: float = 18.0
## Terminal falling speed in m/s.
@export_range(5.0, 100.0, 1.0) var max_fall_speed: float = 40.0
## Small constant downward velocity while grounded — keeps floor detection
## stable without noticeable sinking (m/s).
@export_range(0.0, 5.0, 0.1) var grounded_downward_bias: float = 0.5
## Distance the body may snap toward the floor over small steps (m).
@export_range(0.0, 2.0, 0.05) var floor_snap_length: float = 1.0
## Maximum slope angle treated as a walkable floor (degrees).
@export_range(5.0, 80.0, 1.0) var floor_max_angle_degrees: float = 45.0
