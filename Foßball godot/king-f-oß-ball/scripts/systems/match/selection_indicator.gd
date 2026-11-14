class_name SelectionIndicator
extends Node3D

## Marks the human-controlled player: a flat ring in the team colour under his feet, a small arrow
## above his head and a run-direction arrow on the ground. It is parented to the selected player's
## body, so it moves with him and jumps at once on a switch (`attach_to`). Unshaded, no shadows,
## drawn from simple meshes (no textures). Controller slot 1 (second human) uses its own colour.

const SLOT_COLORS: Array[Color] = [Color(1.0, 0.84, 0.25), Color(0.3, 0.85, 1.0)]
const RING_RADIUS := 0.62
const RUN_ARROW_MIN_SPEED := 0.6

var controller_slot := 0
var color := SLOT_COLORS[0]
var _ring: MeshInstance3D
var _run_arrow: MeshInstance3D
var _head: Label3D
var _mat: StandardMaterial3D


func _init(p_slot: int = 0, team_color: Color = Color(0, 0, 0, 0)) -> void:
	name = "SelectionIndicator"
	controller_slot = clampi(p_slot, 0, SLOT_COLORS.size() - 1)
	color = SLOT_COLORS[controller_slot]
	if controller_slot == 0 and team_color.a > 0.0:
		color = readable(team_color)
	_build()


## Kit colours can be dark (navy) or close to the grass: lighten towards white so the ring reads.
static func readable(c: Color) -> Color:
	var out := c.lerp(Color.WHITE, 0.3)
	if out.get_luminance() < 0.45:
		out = out.lerp(Color.WHITE, 0.35)
	if out.g > out.r + 0.15 and out.g > out.b + 0.15:       # green on green
		out = SLOT_COLORS[0]
	out.a = 1.0
	return out


func _build() -> void:
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = Color(color, 0.9)
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.render_priority = 1
	var torus := TorusMesh.new()
	torus.inner_radius = RING_RADIUS - 0.09
	torus.outer_radius = RING_RADIUS
	torus.rings = 24
	torus.ring_segments = 6
	_ring = MeshInstance3D.new()
	_ring.name = "Ring"
	_ring.mesh = torus
	_ring.material_override = _mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.position = Vector3(0.0, 0.04, 0.0)
	_ring.scale = Vector3(1.0, 0.15, 1.0)
	add_child(_ring)
	var prism := PrismMesh.new()
	prism.size = Vector3(0.36, 0.42, 0.04)
	_run_arrow = MeshInstance3D.new()
	_run_arrow.name = "RunArrow"
	_run_arrow.mesh = prism
	_run_arrow.material_override = _mat
	_run_arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_run_arrow.top_level = true            # oriented in world space along the velocity
	_run_arrow.visible = false
	add_child(_run_arrow)
	_head = Label3D.new()
	_head.name = "HeadMarker"
	_head.text = "▼"
	_head.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_head.no_depth_test = true
	_head.fixed_size = true
	_head.pixel_size = 0.0007
	_head.font_size = 36
	_head.outline_size = 8
	_head.modulate = color
	_head.position = Vector3(0.0, 2.35, 0.0)
	add_child(_head)


## Moves the indicator under `body` (instant: no tween, no lag on a switch).
func attach_to(body: Node3D) -> void:
	if body == null:
		return
	if get_parent() != null:
		get_parent().remove_child(self)
	body.add_child(self)
	position = Vector3.ZERO
	rotation = Vector3.ZERO
	visible = true


func _process(_delta: float) -> void:
	var body := get_parent() as CharacterBody3D
	if body == null:
		_run_arrow.visible = false
		return
	var v := Vector3(body.velocity.x, 0.0, body.velocity.z)
	if v.length() < RUN_ARROW_MIN_SPEED:
		_run_arrow.visible = false
		return
	var dir := v.normalized()
	_run_arrow.visible = true
	var base := body.global_position + dir * (RING_RADIUS + 0.3) + Vector3(0.0, 0.05, 0.0)
	# The prism's tip is its local +Y and its thin side local Z: tip along `dir`, lying flat (Z up).
	_run_arrow.global_transform = Transform3D(Basis(dir.cross(Vector3.UP), dir, Vector3.UP), base)
