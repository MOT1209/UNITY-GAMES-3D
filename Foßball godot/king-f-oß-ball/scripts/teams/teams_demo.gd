class_name TeamsDemo
extends Node3D

## Kick-off set-up: the stadium arena, the ball and both teams in their
## formation. Keys 1-4 switch the gold team's formation.

const ARENA_SCENE := "res://scenes/stadium/stadium_arena.tscn"
const BALL_SCENE := "res://scenes/ball/football_ball.tscn"

@export var gold: TeamData = preload("res://resources/teams/team_gold.tres")
@export var red: TeamData = preload("res://resources/teams/team_red.tres")

var team_a: MatchTeam
var team_b: MatchTeam
var ball: BallController


func _ready() -> void:
	var arena := (load(ARENA_SCENE) as PackedScene).instantiate()
	add_child(arena)
	# The demo shows the two teams — the arena's own player and its follow
	# camera are removed so the overview camera can show the whole pitch.
	for pc in arena.find_children("*", "PlayerController", true, false):
		pc.queue_free()
	for cam in arena.find_children("*", "GameCamera", true, false):
		cam.queue_free()

	team_a = MatchTeam.new()
	team_a.data = gold.duplicate()
	team_a.attack_dir_z = -1.0
	team_a.team_index = 0
	team_a.name = "TeamA"
	add_child(team_a)

	team_b = MatchTeam.new()
	team_b.data = red.duplicate()
	team_b.attack_dir_z = 1.0
	team_b.team_index = 1
	team_b.name = "TeamB"
	add_child(team_b)

	ball = (load(BALL_SCENE) as PackedScene).instantiate() as BallController
	add_child(ball)
	ball.position = Vector3(0.0, 0.12, 0.0)

	var overview := Camera3D.new()
	overview.name = "OverviewCamera"
	add_child(overview)
	overview.position = Vector3(0.0, 62.0, 78.0)
	overview.look_at(Vector3.ZERO, Vector3.UP)
	overview.current = true


func _unhandled_key_input(e: InputEvent) -> void:
	var k := e as InputEventKey
	if k and k.pressed and k.keycode >= KEY_1 and k.keycode <= KEY_4:
		var names := Formation.names()
		if k.keycode - KEY_1 < names.size():
			team_a.set_formation(names[k.keycode - KEY_1])
