class_name ReplayDirector
extends Camera3D

## Goal replay from several angles (UX phase 6): while the `ReplayPlayer` plays the clip, this camera
## takes over and cuts between three shots of the ghost ball — the high TV angle, a low view from behind
## the goal that conceded, and a close tracking shot — one third of the clip each. The match camera is
## made current again when the replay ends or is skipped.

enum Angle { TV, BEHIND_GOAL, CLOSE }

var player: ReplayPlayer
var goal_z := 52.5                 # z of the goal the ball went into
var angle: Angle = Angle.TV
var cuts := 0                      # how many times the shot changed (tests)
var _previous: Camera3D


func _init() -> void:
	name = "ReplayDirector"
	fov = 50.0


## Starts directing `p_player`; `p_goal_z` = the scoring goal's z. Remembers the camera to restore.
func direct(p_player: ReplayPlayer, p_goal_z: float) -> void:
	player = p_player
	goal_z = p_goal_z
	cuts = 0
	angle = Angle.TV
	_previous = get_viewport().get_camera_3d() if get_viewport() != null else null
	current = true
	if not player.finished.is_connected(release):
		player.finished.connect(release, CONNECT_ONE_SHOT)
	_update()


## Gives the view back to the match camera.
func release() -> void:
	current = false
	if _previous != null and is_instance_valid(_previous):
		_previous.current = true
	player = null


## Angle for a point of the clip (0..1): three equal parts.
static func angle_at(progress_ratio: float) -> Angle:
	if progress_ratio < 1.0 / 3.0:
		return Angle.TV
	if progress_ratio < 2.0 / 3.0:
		return Angle.BEHIND_GOAL
	return Angle.CLOSE


func _process(_delta: float) -> void:
	if player != null and player.playing:
		_update()


func _update() -> void:
	var b := player.ball_position()
	if b == Vector3.INF:
		return
	var wanted := angle_at(player.progress())
	if wanted != angle:
		angle = wanted
		cuts += 1
	var pos: Vector3
	match angle:
		Angle.TV:
			pos = Vector3(b.x + 30.0, 20.0, b.z)
		Angle.BEHIND_GOAL:
			pos = Vector3(b.x * 0.3, 3.5, goal_z + signf(goal_z) * 8.0)
		_:
			pos = Vector3(b.x + 6.0, 2.2, b.z - signf(goal_z) * 6.0)
	if not pos.is_equal_approx(b):
		look_at_from_position(pos, b, Vector3.UP)
