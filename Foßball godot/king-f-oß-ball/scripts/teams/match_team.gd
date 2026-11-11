class_name MatchTeam
extends Node3D

## Spawns the 11 players of a `TeamData` in their kick-off formation.

## The team sheet.
@export var data: TeamData
## -1: attacks toward -Z (own goal at +Z) ; +1: attacks toward +Z.
@export var attack_dir_z := -1.0
@export var team_index := 0

var players: Array[TeamPlayer] = []

const PLAYER_SCENE := "res://scenes/teams/team_player.tscn"
const KEEPER_SCENE := "res://scenes/teams/team_goalkeeper.tscn"


func _ready() -> void:
	if data:
		spawn()


## (Re-)spawns the whole team in the current formation.
func spawn() -> void:
	for p in players:
		p.queue_free()
	players.clear()
	var scene := load(PLAYER_SCENE) as PackedScene
	var slots := Formation.slots(data.formation)
	for i in slots.size():
		var is_keeper: bool = slots[i][0] == "GK"
		var tp := (load(KEEPER_SCENE) if is_keeper else scene) as PackedScene
		var player := tp.instantiate() as TeamPlayer
		add_child(player)
		var kit := data.goalkeeper_kit if is_keeper else data.kit
		var num := data.numbers[i] if i < data.numbers.size() else i + 1
		player.setup(slots[i][0], num, kit,
				Formation.home_position(slots[i], attack_dir_z), attack_dir_z, team_index)
		players.append(player)


## Switches the kick-off formation and re-spawns the team.
func set_formation(id: String) -> void:
	data.formation = id
	spawn()


## The goalkeeper (always slot 0).
func goalkeeper() -> TeamPlayer:
	return players[0] if players.size() > 0 else null
