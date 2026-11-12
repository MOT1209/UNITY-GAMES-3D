class_name ReplayPlayer
extends Node3D

## Plays a `ReplayBuffer` clip with lightweight ghosts (a sphere for the ball, a capsule per player, coloured by team) so the
## live match nodes are never touched. Controls: `speed` (slow motion 0.25..2), `pause`, `seek`, `skip`.
## Emits `finished` when the clip ends or is skipped.

signal finished

var clip_data: Dictionary = {}
var speed: float = 0.6                   # slow motion by default
var paused: bool = false
var time: float = 0.0
var playing: bool = false
var _ghosts: Array[MeshInstance3D] = []
var _colors: Array[Color] = []


## `colors`: one colour per body (ball first). Builds the ghosts and starts playing.
func start(p_clip: Dictionary, colors: Array[Color], p_speed: float = 0.6) -> bool:
	stop(false)
	if (p_clip["frames"] as Array).size() < 2 or colors.size() != int(p_clip["body_count"]):
		return false
	clip_data = p_clip
	speed = clampf(p_speed, 0.25, 2.0)
	_colors = colors
	time = 0.0
	paused = false
	playing = true
	for i in colors.size():
		var ghost := MeshInstance3D.new()
		if i == 0:
			var s := SphereMesh.new()
			s.radius = 0.22
			s.height = 0.44
			ghost.mesh = s
		else:
			var c := CapsuleMesh.new()
			c.radius = 0.35
			c.height = 1.8
			ghost.mesh = c
		var m := StandardMaterial3D.new()
		m.albedo_color = colors[i]
		m.emission_enabled = true
		m.emission = colors[i] * 0.3
		ghost.material_override = m
		add_child(ghost)
		_ghosts.append(ghost)
	_apply(0.0)
	return true


func set_speed(value: float) -> void:
	speed = clampf(value, 0.25, 2.0)


func seek(t: float) -> void:
	time = clampf(t, 0.0, float(clip_data.get("duration", 0.0)))
	_apply(time)


func skip() -> void:
	stop(true)


func stop(emit: bool = false) -> void:
	for g in _ghosts:
		g.queue_free()
	_ghosts.clear()
	var was := playing
	playing = false
	if emit and was:
		finished.emit()


func _process(delta: float) -> void:
	if not playing or paused:
		return
	advance(delta)


## Advances the clip by `delta` real seconds (scaled by `speed`). Public so tests do not depend on frame timing.
func advance(delta: float) -> void:
	if not playing:
		return
	time += delta * speed
	var dur: float = float(clip_data["duration"])
	if time >= dur:
		_apply(dur)
		stop(true)
		return
	_apply(time)


func _apply(t: float) -> void:
	var data := ReplayBuffer.sample(clip_data, t)
	for i in _ghosts.size():
		var o := i * ReplayBuffer.FLOATS_PER_BODY
		var y_off := 0.0 if i == 0 else 0.9
		_ghosts[i].position = Vector3(data[o], data[o + 1] + y_off, data[o + 2])
		_ghosts[i].rotation.y = data[o + 3]
