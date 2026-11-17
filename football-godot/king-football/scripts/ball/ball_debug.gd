class_name BallDebug
extends Node3D

## Development-only ball debug overlay (Phase 3).
##
## Draws the ball's velocity vector as a red ImmediateMesh arrow anchored at the
## ball centre (top-level so it does not rotate with the ball). Never enabled in
## normal gameplay — it must be turned on from code or the Inspector; the ball
## test scene enables it while shipping scenes leave it off.

@export var debug_enabled: bool = false:
	set(value):
		debug_enabled = value
		if _root != null:
			_root.visible = value

## Metres of arrow per m/s of velocity.
@export var velocity_scale: float = 0.25
## Upper clamp to the arrow length in metres.
@export_range(0.5, 30.0, 0.5) var max_arrow_length: float = 10.0
@export var velocity_color: Color = Color(1.0, 0.25, 0.2)

var _root: MeshInstance3D
var _mesh: ImmediateMesh
## Godot 4.7 ImmediateMesh carries no per-vertex colors — the arrow colour comes
## from the per-surface material passed to `surface_begin()`.
var _main_material: StandardMaterial3D
var _arrow_material: StandardMaterial3D


func _ready() -> void:
	_mesh = ImmediateMesh.new()
	_main_material = _make_line_material(velocity_color)
	_arrow_material = _make_line_material(Color(1.0, 0.55, 0.2))

	_root = MeshInstance3D.new()
	_root.name = "DebugLines"
	_root.top_level = true
	_root.mesh = _mesh
	_root.visible = debug_enabled
	add_child(_root)


func _make_line_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.no_depth_test = true
	return material


func _physics_process(_delta: float) -> void:
	if not debug_enabled or _root == null:
		return
	var ball := get_parent() as BallController
	if ball == null or not is_instance_valid(ball):
		return
	_redraw(ball)


## Redraws the whole overlay in global coordinates (the line mesh is top-level,
## so the arrow does not visually spin with the ball). Each coloured group is
## its own surface; ImmediateMesh supports one primitive + material per surface.
func _redraw(ball: BallController) -> void:
	_mesh.clear_surfaces()

	var origin := ball.global_position
	var velocity := clampf(ball.get_ball_speed() * velocity_scale, 0.0, max_arrow_length)

	# Main velocity line (red) — arrow length scales with speed.
	if velocity > 0.05:
		var direction := ball.get_ball_direction()
		var tip := origin + direction * velocity
		_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _main_material)
		_mesh.surface_add_vertex(origin)
		_mesh.surface_add_vertex(tip)
		_mesh.surface_end()

		# Arrowhead: three short ticks fanning back from the tip.
		var back := origin + direction * (velocity - 0.18)
		var tick_dir := direction.cross(Vector3.UP)
		if tick_dir.length_squared() < 0.001:
			tick_dir = Vector3(0.0, 0.0, 1.0)
		tick_dir = tick_dir.normalized()
		_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _arrow_material)
		for offset: Vector3 in [
			tick_dir * 0.12, -tick_dir * 0.12, direction * -0.12,
		]:
			_mesh.surface_add_vertex(tip)
			_mesh.surface_add_vertex(back + offset)
		_mesh.surface_end()
	else:
		# Rest marker: small "X" so a stopped ball is still identifiable.
		_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _main_material)
		for offset: Vector3 in [Vector3(0.12, 0.0, 0.0), Vector3(0.0, 0.0, 0.12)]:
			_mesh.surface_add_vertex(origin - offset)
			_mesh.surface_add_vertex(origin + offset)
		_mesh.surface_end()
