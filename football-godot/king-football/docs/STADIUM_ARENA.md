# KING FOOTBALL — Stadium Arena (Blender GLB)

The match scene now uses a real stadium model made in Blender
(`assets/models/stadium/stadium.glb`, ~32k triangles, textures embedded).
`GameManager.start_match()` opens `scenes/stadium/stadium_arena.tscn`.
The Phase 1 prototype is kept untouched (`GameManager.SCENE_STADIUM_PROTOTYPE`)
and its validation suite still passes.

## Files

| File | Role |
|---|---|
| `assets/models/stadium/stadium.glb` | Stadium model (pitch, two-tier bowl, facade, roof, goals, boards, scoreboards, plaza) |
| `scripts/environment/stadium_arena.gd` | `StadiumArena`: loads the GLB, builds collision, goal triggers, spawn points |
| `scenes/stadium/stadium_arena.tscn` | Playable scene: arena + player + GameCamera + HUD |
| `resources/configurations/arena_camera_config.tres` | Broadcast camera under the roof (offset 54, 15, 0 · fov 50) |
| `tests/stadium_arena_validation.tscn` | Headless suite (29 checks) |

## Naming contract inside the GLB

| Object name | Becomes at runtime |
|---|---|
| `COL_*` | `StaticBody3D` with a trimesh shape; the mesh is removed |
| `TRIGGER_Goal_N` / `TRIGGER_Goal_S` | `Area3D` → signal `goal_entered(goal_id, body)` |
| `SPAWN_Kickoff`, `SPAWN_Home_Bench`, `SPAWN_Away_Bench`, `SPAWN_Tunnel` | `arena.get_spawn(&"Kickoff")` … |

Goal **N** is the −Z end (same place as `GoalA` in the prototype), goal **S** the +Z end.
Coordinates follow the Phase 1 convention: centre (0,0,0), length along Z,
goal lines at z = ±52.5, grass top at y = 0.

## Inspector options (`Arena` node)

- `show_trees`, `pitch_tint`, `emission_scale` (LED / boards / screens brightness)
- `collision_layer`, `trigger_mask`
- `goal_body_group`: set to `&"ball"` in Phase 3 so only the ball scores.

## Phase 3 hook (ball)

```gdscript
@onready var arena: StadiumArena = %Arena

func _ready() -> void:
	arena.goal_entered.connect(_on_goal)

func _on_goal(goal_id: StringName, body: Node3D) -> void:
	print("GOAL in ", goal_id)
```

## Environment note

`ambient_light_source = 3` (SKY). In Godot 4.7 the value `2` means COLOR, whose
default colour is black — that is why shaded stands looked black in the
Phase 1 captures (`stadium_prototype.tscn` and `player_controller_test.tscn`
still use `2`).

## Validate

```text
godot --headless --path . res://tests/stadium_arena_validation.tscn
# Expected: "=== Validation summary: 29 passed, 0 failed ==="
godot --path . res://tests/screenshot_runner.tscn -- arena
godot --path . res://tests/screenshot_runner.tscn -- arena_follow
```
