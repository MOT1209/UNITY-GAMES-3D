class_name PassTargetMarker
extends Node3D

## Small white ring under the team-mate a human ground pass will go to (Phase M1), shown while the pass button is
## held: the receiver is the one `HumanAimAssist.pass_target` picks for the current stick direction.

const RADIUS := 0.75

var target_name := ""             # node name of the marked player ("" = hidden)
var _ring: MeshInstance3D


func _init() -> void:
	name = "PassTargetMarker"
	top_level = true
	visible = false
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1, 1, 1, 0.85)
	mat.render_priority = 1
	var torus := TorusMesh.new()
	torus.inner_radius = RADIUS - 0.07
	torus.outer_radius = RADIUS
	torus.rings = 24
	torus.ring_segments = 6
	_ring = MeshInstance3D.new()
	_ring.mesh = torus
	_ring.material_override = mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.scale = Vector3(1.0, 0.15, 1.0)
	add_child(_ring)


## Shows the ring under `body` (null hides it).
func show_on(body: Node3D) -> void:
	if body == null:
		visible = false
		target_name = ""
		return
	visible = true
	target_name = str(body.name)
	global_position = Vector3(body.global_position.x, 0.05, body.global_position.z)
