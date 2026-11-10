class_name CameraConfig
extends Resource

## Shared, tweak-in-editor configuration for the reusable GameCamera system.
## `resources/configurations/game_camera_config.tres` provides the project defaults.
## A future Resource for broadcast/follow variants can extend this file.

@export_group("Broadcast Camera")
## World point the broadcast camera keeps centered.
@export var broadcast_look_target: Vector3 = Vector3.ZERO
## Camera position = look target + this offset (sideline, elevated).
## Keep the Y component above the stand roofs (~15 m) so the camera never
## sits inside stadium geometry.
@export var broadcast_position_offset: Vector3 = Vector3(56.0, 38.0, 0.0)
@export var broadcast_fov: float = 40.0

@export_group("Dynamic (Follow) Camera")
@export var follow_fov: float = 65.0
## Horizontal distance the camera sits behind/side of the follow target.
@export var follow_distance: float = 16.0
@export var follow_height: float = 9.0
## Height offset applied to the point the camera looks at.
@export var follow_look_height: float = 0.4
## Smoothing strength. Higher = snappier. Applied as exponential damping.
@export_range(0.5, 20.0, 0.1) var follow_speed: float = 5.0
