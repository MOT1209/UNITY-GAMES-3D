class_name BallProximityDetector
extends Node3D

## Reusable proximity layer between a host (typically the Phase 2 player) and
## football balls (Phase 3). Detection only — this intentionally does NOT
## possess, attach or teleport the ball. Phase 4 (dribbling/passing) reads the
## exact same state and signals, so this component is the integration point.
##
## Drop this node under any Node3D host (e.g. the player). If the host node is
## the parent, the detector samples the host's origin. Optionally it draws its
## interaction rings as a dev-only overlay (`show_rings`), used by the ball
## test scene only.

signal ball_detected(ball: Node3D)
signal ball_lost
## Emitted whenever "a clean interaction window exists" flips on or off.
signal ball_interaction_available(available: bool)

@export_group("Detection")
## Group scanned for balls; matches `BallController.BALL_GROUP`.
@export var ball_group: StringName = &"football_ball"
## Radius in which the ball is considered "nearby" (m).
@export_range(0.5, 10.0, 0.1) var detection_radius: float = 2.5
## Distance within which a real interaction (trap/kick/shoot in Phase 4) is
## possible (m, planar distance).
@export_range(0.1, 5.0, 0.1) var interaction_distance: float = 0.9
## Max vertical offset between host origin and ball centre for a valid
## interaction (rejects balls down hills / corny airborne "phantom traps" for
## early versions).
@export_range(0.1, 3.0, 0.1) var max_interaction_height: float = 1.0

@export_group("Debug")
## Development-only: draws the two rings once per physics tick.
@export var show_rings: bool = false

var _ball: Node3D
var _interaction: bool = false
var _lines: MeshInstance3D
var _mesh: ImmediateMesh
## Per-surface materials — Godot 4.7 ImmediateMesh has no per-vertex colours.
var _ring_material: StandardMaterial3D
var _interaction_material: StandardMaterial3D
var _link_material: StandardMaterial3D


func _ready() -> void:
	if show_rings:
		_build_ring_drawables()


func _physics_process(_delta: float) -> void:
	# Frees a tracked ball that got removed this frame.
	if _ball != null and not is_instance_valid(_ball):
		_ball = null
		ball_lost.emit()

	var closest := _find_closest_ball()
	var now_available := false

	if closest != null:
		var offset := closest.global_position - global_position
		var planar := Vector3(offset.x, 0.0, offset.z)
		var planar_distance := planar.length()
		now_available = planar_distance <= interaction_distance \
				and offset.y <= max_interaction_height

		# Detection (re)gained — either a first ball appearing or a switch to a
		# different (closer) ball.
		if _ball != closest:
			ball_detected.emit(closest)
		_ball = closest
	else:
		if _ball != null:
			ball_lost.emit()
		_ball = null

	if now_available != _interaction:
		_interaction = now_available
		ball_interaction_available.emit(_interaction)

	if show_rings and _lines != null:
		_redraw_rings()


# --- Queries ---------------------------------------------------------------

## Currently tracked (nearest) ball, or null when none is nearby.
func get_current_ball() -> Node3D:
	if _ball != null and not is_instance_valid(_ball):
		_ball = null                  # the ball was freed (match torn down): never hand out a dead reference
	return _ball


## Is a ball inside the detection radius right now?
func is_ball_nearby() -> bool:
	return _ball != null


## Distance to the tracked ball's centre (0 if none tracked).
func get_distance_to_ball() -> float:
	if _ball == null or not is_instance_valid(_ball):
		return 0.0
	return global_position.distance_to(_ball.global_position)


## Normalized horizontal direction from the host toward the tracked ball
## (ZERO when no ball is tracked).
func get_direction_to_ball() -> Vector3:
	if _ball == null or not is_instance_valid(_ball):
		return Vector3.ZERO
	var offset := _ball.global_position - global_position
	var planar := Vector3(offset.x, 0.0, offset.z)
	if planar.length_squared() < 0.0001:
		return Vector3.ZERO
	return planar.normalized()


## True when within the interaction window (distance + height + ball present).
## This is the single boolean Phase 4 gameplay ("can trap / kick / shoot?").
func is_interaction_available() -> bool:
	return _interaction


# --- Internals ---------------------------------------------------------------

func _find_closest_ball() -> Node3D:
	var closest: Node3D = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group(ball_group):
		var as_node3d := node as Node3D
		if as_node3d == null:
			continue
		# Planar distance: a lobbed ball above the host still belongs to this
		# host's field of play — only "interaction" applies a height gate, so
		# detection must not drop and re-grab the ball mid-air (that would emit
		# a bogus `ball_lost`/`ball_detected` pair per bounce).
		var offset := as_node3d.global_position - global_position
		var planar_distance := Vector3(offset.x, 0.0, offset.z).length()
		if planar_distance <= detection_radius and planar_distance < best_distance:
			best_distance = planar_distance
			closest = as_node3d
	return closest


func _build_ring_drawables() -> void:
	_mesh = ImmediateMesh.new()
	_ring_material = _make_line_material(Color(0.3, 0.85, 1.0))
	_interaction_material = _make_line_material(Color(0.4, 1.0, 0.45))
	_link_material = _make_line_material(Color(1.0, 0.9, 0.2))
	_lines = MeshInstance3D.new()
	_lines.name = "DebugRings"
	_lines.top_level = true  # keep rings upright regardless of host rotation/local y
	_lines.mesh = _mesh
	add_child(_lines)


func _make_line_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.no_depth_test = true
	return material


## Rings are drawn in world space around the host's ground footprint.
func _redraw_rings() -> void:
	_mesh.clear_surfaces()
	var center := global_position
	_draw_ring(center, detection_radius, _ring_material, 48)
	_draw_ring(center, interaction_distance, _interaction_material, 32)

	if _ball != null and is_instance_valid(_ball):
		_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _link_material)
		_mesh.surface_add_vertex(center)
		_mesh.surface_add_vertex(_ball.global_position)
		_mesh.surface_end()


func _draw_ring(center: Vector3, radius: float, material: StandardMaterial3D,
		segments: int) -> void:
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for i in segments:
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		_mesh.surface_add_vertex(center + Vector3(cos(a0), 0.0, sin(a0)) * radius)
		_mesh.surface_add_vertex(center + Vector3(cos(a1), 0.0, sin(a1)) * radius)
	_mesh.surface_end()
