class_name StadiumStands
extends Node3D

## Prototype stadium surroundings: 4 grandstands built as stepped tier staircases,
## a simple roof, and 4 floodlight masts. Stylized-lightweight on purpose —
## expensive decorative assets come in later phases.

const SIDES: Array[Vector3] = [
	Vector3(1, 0, 0),   # +X sideline
	Vector3(-1, 0, 0),  # -X sideline
	Vector3(0, 0, 1),   # +X endline... actually +Z endline
	Vector3(0, 0, -1),
]

const SIDE_STAND_LENGTH := 96.0   # along the outrunning axis X
const END_STAND_LENGTH := 76.0    # along the outrunning axis Z
const ROW_COUNT := 8
const ROW_HEIGHT := 0.9
const ROW_DEPTH := 1.8
const ROW_WIDTH := 1.0            # footprint per row block
const BASE_GAP := 6.0             # stands' front wall distance beyond the pitch edge

const COLOR_BODY := Color(0.42, 0.44, 0.5)
const COLOR_SEAT := Color(0.18, 0.3, 0.52)
const COLOR_ROOF := Color(0.75, 0.76, 0.8)

var _body_material: StandardMaterial3D
var _seat_material: StandardMaterial3D
var _roof_material: StandardMaterial3D
var _light_material: StandardMaterial3D


func _ready() -> void:
	_make_materials()
	build()


func build() -> void:
	_build_stand(Vector3(1, 0, 0), SideLength.SIDE)   # +X
	_build_stand(Vector3(-1, 0, 0), SideLength.SIDE)  # -X
	_build_stand(Vector3(0, 0, 1), SideLength.END)    # +Z
	_build_stand(Vector3(0, 0, -1), SideLength.END)   # -Z
	_build_floodlights()


func _make_materials() -> void:
	_body_material = StandardMaterial3D.new()
	_body_material.albedo_color = COLOR_BODY
	_body_material.roughness = 0.9

	_seat_material = StandardMaterial3D.new()
	_seat_material.albedo_color = COLOR_SEAT
	_seat_material.roughness = 0.9

	_roof_material = StandardMaterial3D.new()
	_roof_material.albedo_color = COLOR_ROOF
	_roof_material.roughness = 0.6
	_roof_material.metallic = 0.2

	_light_material = StandardMaterial3D.new()
	_light_material.albedo_color = Color(1, 1, 1)
	_light_material.emission_enabled = true
	_light_material.emission = Color(1, 1, 0.92)
	_light_material.emission_energy_multiplier = 2.5


func _make_box_mesh_instance(size: Vector3, material: Material, location: String) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.material_override = material
	mesh_instance.name = location
	return mesh_instance


enum SideLength { SIDE, END }


func _build_stand(direction: Vector3, length_kind: SideLength) -> void:
	var stand := Node3D.new()
	stand.name = "Stand_%s" % direction
	add_child(stand)

	# Build the stand facing -Z locally (toward the pitch), then orient it.
	var length: float = SIDE_STAND_LENGTH if length_kind == SideLength.SIDE else END_STAND_LENGTH
	var half_length := length * 0.5

	# Front wall.
	var front := _make_box_mesh_instance(Vector3(length, 1.2, 0.4), _body_material, "FrontWall")
	front.position = Vector3(0.0, 0.6, 0.0)
	stand.add_child(front)

	# Tier staircase: rows step "up +y, back +z" so -Z faces the pitch.
	for row in ROW_COUNT:
		var row_mesh := _make_box_mesh_instance(
			Vector3(length, ROW_HEIGHT, ROW_DEPTH + ROW_WIDTH),
			_seat_material if row % 2 == 0 else _body_material_timeline_fix(row),
			"TierRow%d" % row
		)
		row_mesh.position = Vector3(
			0.0,
			1.2 + ROW_HEIGHT * 0.5 + row * ROW_HEIGHT,
			ROW_DEPTH * 0.5 + ROW_WIDTH * 0.5 + row * ROW_DEPTH
		)
		stand.add_child(row_mesh)

	# Roof slab above the top tier.
	var top_y := 1.2 + ROW_COUNT * ROW_HEIGHT
	var roof := _make_box_mesh_instance(Vector3(length + 4.0, 0.5, ROW_COUNT * ROW_DEPTH + 5.0), _roof_material, "Roof")
	roof.position = Vector3(0.0, top_y + 3.2, ROW_COUNT * ROW_DEPTH * 0.5 + 1.5)
	stand.add_child(roof)

	# Place and orient: rows recede along LOCAL +Z, so rotate each stand so
	# that local +Z points AWAY from the pitch (front wall then faces the field).
	var offset_distance := BASE_GAP
	match direction.x:
		1.0:
			stand.position = Vector3(half_width_edge() + offset_distance, 0.0, 0.0)
			stand.rotation.y = PI * 0.5
		-1.0:
			stand.position = Vector3(-half_width_edge() - offset_distance, 0.0, 0.0)
			stand.rotation.y = -PI * 0.5
		_:
			var end_distance := PITCH_HALF_LENGTH() + offset_distance
			if direction.z > 0.0:
				stand.position = Vector3(0.0, 0.0, end_distance)
				stand.rotation.y = 0.0
			else:
				stand.position = Vector3(0.0, 0.0, -end_distance)
				stand.rotation.y = PI


# Helpers so numbers stay in sync with FootballPitch dimensions.
func half_width_edge() -> float:
	return FootballPitch.PITCH_WIDTH * 0.5 + STRIPE_OVERSCAN_M


func PITCH_HALF_LENGTH() -> float:
	return FootballPitch.PITCH_LENGTH * 0.5 + STRIPE_OVERSCAN_M


const STRIPE_OVERSCAN_M := FootballPitch.STRIPE_OVERSCAN


func _body_material_timeline_fix(_row: int) -> StandardMaterial3D:
	# Every other row gets the body-coloured walkway; kept as an explicit helper
	# so tier visuals remain easy to tweak in later phases.
	return _body_material


# --- Floodlights --------------------------------------------------------

func _build_floodlights() -> void:
	var corners := [
		Vector3(44.0, 0.0, 62.0),
		Vector3(-44.0, 0.0, 62.0),
		Vector3(44.0, 0.0, -62.0),
		Vector3(-44.0, 0.0, -62.0),
	]
	for i in corners.size():
		var mast := Node3D.new()
		mast.name = "FloodlightMast%d" % i
		mast.position = corners[i]
		add_child(mast)

		mast.look_at(Vector3.ZERO, Vector3.UP)

		var pole := _make_cylinder(0.35, 24.0, _body_material)
		pole.position.y = 12.0
		mast.add_child(pole)

		var head := _make_box_mesh_instance(Vector3(5.0, 2.0, 0.6), _light_material, "LampPanel")
		head.position = Vector3(0.0, 24.0, -0.5)
		mast.add_child(head)


func _make_cylinder(radius: float, height: float, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = height
	cylinder.radial_segments = 12
	mesh_instance.mesh = cylinder
	mesh_instance.material_override = material
	return mesh_instance
