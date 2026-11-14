class_name MatchReferee
extends Node3D

## The referee on the pitch (UX phase 6): the `referee.glb` model follows play at a sensible distance —
## diagonally behind the ball, inside the pitch — walking or running with the model's own clips, facing the
## ball, and shows a card on bookings. Pure presentation: no collision body (it can never block the ball
## or a player); the decisions remain in `MatchRules`.

const MODEL := "res://assets/models/characters/referee.glb"
const FOLLOW_DISTANCE := 11.0
const RUN_SPEED := 6.5
const WALK_SPEED := 2.2
const EDGE_MARGIN := 2.0

var model: Node3D
var _anim: AnimationPlayer
var _speed := 0.0
var _gesture_left := 0.0


func _init() -> void:
	name = "Referee"


func _ready() -> void:
	if ResourceLoader.exists(MODEL):
		model = (load(MODEL) as PackedScene).instantiate() as Node3D
		add_child(model)                # the model faces -Z like the node (look_at)
		# The model ships alternative hair meshes and a beard, all visible: keep one hair style
		# (fewer draw calls, and no hair stacked through hair).
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			var nm := String(mi.name)
			if ("_Hair_" in nm and not nm.ends_with("_Hair_Short")) or nm.ends_with("_Beard"):
				(mi as MeshInstance3D).visible = false
		var found := model.find_children("*", "AnimationPlayer", true, false)
		_anim = found[0] as AnimationPlayer if not found.is_empty() else null
		if _anim != null:
			for clip in ["Idle", "Run", "Walk"]:
				if _anim.has_animation(clip):
					_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	_play("Idle")


## Where the referee wants to stand for a ball at `ball`: on the diagonal behind the play, inside the pitch.
static func wanted_position(ball: Vector3) -> Vector3:
	var lateral := -1.0 if ball.x >= 0.0 else 1.0               # the side away from the ball's touchline
	var along := -signf(ball.z) if absf(ball.z) > 1.0 else 1.0   # a step towards the centre
	var p := Vector3(ball.x + lateral * FOLLOW_DISTANCE * 0.6, 0.0, ball.z + along * FOLLOW_DISTANCE * 0.8)
	p.x = clampf(p.x, -PitchSpace.HALF_WIDTH + EDGE_MARGIN, PitchSpace.HALF_WIDTH - EDGE_MARGIN)
	p.z = clampf(p.z, -PitchSpace.HALF_LENGTH + EDGE_MARGIN, PitchSpace.HALF_LENGTH - EDGE_MARGIN)
	return p


## Moves towards the wanted spot (kinematic, capped speed) and faces the ball.
func follow(ball: Vector3, delta: float) -> void:
	var target := wanted_position(ball)
	var to := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
	var dist := to.length()
	var max_speed := RUN_SPEED if dist > 6.0 else WALK_SPEED
	_speed = minf(max_speed, dist / maxf(delta, 0.001))
	if dist > 0.05:
		global_position += to / dist * minf(dist, max_speed * delta)
	var look := Vector3(ball.x, global_position.y, ball.z)
	if look.distance_to(global_position) > 0.5:
		look_at(look, Vector3.UP)
	if _gesture_left > 0.0:
		_gesture_left -= delta
		return
	if _speed > 3.0:
		_play("Run")
	elif _speed > 0.3:
		_play("Walk")
	else:
		_play("Idle")


## Whistle / card gesture (fouls, cards, goals); the follow animation resumes afterwards.
func gesture(kind: String) -> void:
	_play("ShowCard" if kind == "card" else "Whistle")
	_gesture_left = 1.2


func current_animation() -> String:
	return _anim.current_animation if _anim != null else ""


func _play(clip: String) -> void:
	if _anim != null and _anim.has_animation(clip) and _anim.current_animation != clip:
		_anim.play(clip, 0.2)
