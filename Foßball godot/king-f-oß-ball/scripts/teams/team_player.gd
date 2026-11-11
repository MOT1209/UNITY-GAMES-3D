class_name TeamPlayer
extends CharacterBody3D

## One squad member. Holds its role, shirt number and formation home position
## and dresses the model (kit, number, individual look). Outfield movement AI
## is not part of this phase — the player stands on its slot until the team
## AI arrives.

var role := "CM"
var number := 1
## Formation home position in world space.
var home := Vector3.ZERO
var team_index := 0
var is_goalkeeper := false

@onready var visual: PlayerCharacterVisual = $VisualRoot/PlayerModel


## Places and dresses the player. Called by `MatchTeam` right after the node
## entered the tree.
func setup(r: String, n: int, kit: TeamKit, home_pos: Vector3,
		facing_z: float, team_idx: int) -> void:
	role = r
	number = n
	home = home_pos
	team_index = team_idx
	is_goalkeeper = r == "GK"
	name = "%s_%d" % [r, n]
	position = home_pos
	rotation.y = 0.0 if facing_z < 0.0 else PI
	visual.kit = kit
	visual.number = n
	visual.look = PlayerLook.random(team_idx * 1000 + n * 17 + 5, is_goalkeeper)
	visual.apply_kit()
	visual.apply_number()
	visual.apply_look()
	add_to_group(&"team_%d" % team_idx)
	add_to_group(&"field_players")
