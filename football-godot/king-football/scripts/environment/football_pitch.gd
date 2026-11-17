class_name FootballPitch
extends Node3D

## Reusable procedural football pitch component.
##
## Builds a regulation-proportioned pitch (105 m x 68 m) with:
## grass surface with mow stripes, boundary lines, halfway line, center circle,
## center spot, penalty areas, goal areas, penalty spots, penalty arcs ("D")
## and corner arcs. Also generates a ground StaticBody3D for future ball physics.
##
## The pitch center is a (0, 0, 0): length runs along Z (goals at ±52.5),
## width along X (sidelines at ±34). Line marking generation is data-driven
## so future phases can reuse it for different pitch sizes.

signal pitch_built

# --- Regulation dimensions (metres) ------------------------------------
const PITCH_LENGTH := 105.0   # along Z (goal-line to goal-line)
const PITCH_WIDTH := 68.0     # along X (sideline to sideline)
const CENTER_CIRCLE_RADIUS := 9.15
const PENALTY_AREA_DEPTH := 16.5
const PENALTY_AREA_WIDTH := 40.3
const GOAL_AREA_DEPTH := 5.5
const GOAL_AREA_WIDTH := 18.3
const PENALTY_SPOT_DISTANCE := 11.0
const CORNER_ARC_RADIUS := 1.0
const MIN_MARKING_WIDTH := 0.12

# --- Visual tuning -----------------------------------------------------
const MARKING_HEIGHT := 0.02
const LINE_Y := 0.012
const STRIPE_OVERSCAN := 10.0       # grass apron beyond the markings
const STRIPE_COUNT := 14

const GRASS_COLOR := Color(0.16, 0.47, 0.2)
const GRASS_STRIPE_ALT := Color(0.18, 0.54, 0.23)
const APRON_COLOR := Color(0.11, 0.33, 0.16)
const LINE_COLOR := Color(0.95, 0.95, 0.95)

@export var generate_collision := true
@export var generate_mow_stripes := true

var _built := false

var _grass_material: StandardMaterial3D
var _grass_stripe_material: StandardMaterial3D
var _apron_material: StandardMaterial3D
var _line_material: StandardMaterial3D

@onready var markings_root: Node3D = $Markings if has_node("Markings") else null


func _ready() -> void:
	if not _built:
		build()


## Builds (or rebuilds) the whole pitch procedurally.
func build() -> void:
	_built = true
	_make_materials()
	_clear_generated()
	_build_grass()
	if generate_mow_stripes:
		_build_mow_stripes()
	_build_markings()
	if generate_collision:
		_build_ground_collision()
	pitch_built.emit()


# --- Construction ------------------------------------------------------

func _make_materials() -> void:
	_grass_material = StandardMaterial3D.new()
	_grass_material.albedo_color = GRASS_COLOR
	_grass_material.roughness = 0.95

	_grass_stripe_material = StandardMaterial3D.new()
	_grass_stripe_material.albedo_color = GRASS_STRIPE_ALT
	_grass_stripe_material.roughness = 0.95

	_apron_material = StandardMaterial3D.new()
	_apron_material.albedo_color = APRON_COLOR
	_apron_material.roughness = 1.0

	_line_material = StandardMaterial3D.new()
	_line_material.albedo_color = LINE_COLOR
	_line_material.roughness = 0.85


func _clear_generated() -> void:
	for child in get_children():
		child.queue_free()


func _build_grass() -> void:
	# Main playing surface.
	var surface := MeshInstance3D.new()
	var surface_mesh := BoxMesh.new()
	surface_mesh.size = Vector3(PITCH_WIDTH, 0.1, PITCH_LENGTH)
	surface.mesh = surface_mesh
	surface.material_override = _grass_material
	surface.position.y = -0.05
	surface.name = "PitchSurface"
	add_child(surface)

	# Surrounding apron so the pitch reads clearly against the stadium floor.
	var apron := MeshInstance3D.new()
	var apron_mesh := BoxMesh.new()
	apron_mesh.size = Vector3(
		PITCH_WIDTH + STRIPE_OVERSCAN * 2.0,
		0.06,
		PITCH_LENGTH + STRIPE_OVERSCAN * 2.0
	)
	apron.mesh = apron_mesh
	apron.material_override = _apron_material
	apron.position.y = -0.06
	apron.name = "PitchApron"
	add_child(apron)

	# Wide outer grounds so the horizon does not fall into the sky's dark bottom.
	var outer := MeshInstance3D.new()
	var outer_mesh := BoxMesh.new()
	outer_mesh.size = Vector3(240.0, 0.1, 230.0)
	outer.mesh = outer_mesh
	outer.material_override = _apron_material
	outer.position.y = -0.075
	outer.name = "OuterGround"
	add_child(outer)


func _build_mow_stripes() -> void:
	# Alternating light/dark bands across the pitch width (along Z).
	var stripe_depth := PITCH_LENGTH / float(STRIPE_COUNT)
	for i in STRIPE_COUNT:
		if i % 2 == 0:
			continue
		var stripe := MeshInstance3D.new()
		var stripe_mesh := BoxMesh.new()
		stripe_mesh.size = Vector3(PITCH_WIDTH, 0.01, stripe_depth)
		stripe.mesh = stripe_mesh
		stripe.material_override = _grass_stripe_material
		stripe.position = Vector3(0.0, 0.001, -PITCH_LENGTH * 0.5 + (i + 0.5) * stripe_depth)
		stripe.name = "MowStripe%d" % i
		add_child(stripe)


func _build_markings() -> void:
	var root := Node3D.new()
	root.name = "Markings"
	add_child(root)

	var half_len := PITCH_LENGTH * 0.5
	var half_width := PITCH_WIDTH * 0.5

	# Boundary lines.
	_line(root, Vector2(-half_width, -half_len), Vector2(half_width, -half_len))  # Z-
	_line(root, Vector2(-half_width, half_len), Vector2(half_width, half_len))    # side Z+
	_line(root, Vector2(-half_width, -half_len), Vector2(-half_width, half_len))  # X-
	_line(root, Vector2(half_width, -half_len), Vector2(half_width, half_len))    # X+

	# Halfway line.
	_line(root, Vector2(-half_width, 0.0), Vector2(half_width, 0.0))

	# Center circle ring.
	_ring(root, Vector2.ZERO, CENTER_CIRCLE_RADIUS)
	# Center spot.
	_spot(root, Vector2.ZERO)

	# One set of markings per goal line.
	for goal_sign: int in [-1, 1]:
		var goal_z := half_len * goal_sign
		var inward: int = -goal_sign

		# Penalty area (16.5 m deep, 40.3 m wide).
		var pen_front := goal_z + inward * PENALTY_AREA_DEPTH
		var pen_half := PENALTY_AREA_WIDTH * 0.5
		_line(root, Vector2(-pen_half, goal_z), Vector2(-pen_half, pen_front))
		_line(root, Vector2(pen_half, goal_z), Vector2(pen_half, pen_front))
		_line(root, Vector2(-pen_half, pen_front), Vector2(pen_half, pen_front))

		# Goal area (5.5 m deep, 18.3 m wide).
		var goal_front := goal_z + inward * GOAL_AREA_DEPTH
		var goal_half := GOAL_AREA_WIDTH * 0.5
		_line(root, Vector2(-goal_half, goal_z), Vector2(-goal_half, goal_front))
		_line(root, Vector2(goal_half, goal_z), Vector2(goal_half, goal_front))
		_line(root, Vector2(-goal_half, goal_front), Vector2(goal_half, goal_front))

		# Penalty spot.
		var spot_z := goal_z + inward * PENALTY_SPOT_DISTANCE
		_spot(root, Vector2(0.0, spot_z))

		# Penalty arc ("D"): the part of a 9.15 m circle beyond the penalty area front.
		var arc_center := Vector2(0.0, spot_z)
		var sagitta := goal_z + inward * PENALTY_AREA_DEPTH - spot_z  # distance into the "D"
		var angle := acos(clampf(sagitta / CENTER_CIRCLE_RADIUS, -1.0, 1.0))
		_arc(root, arc_center, CENTER_CIRCLE_RADIUS, angle, inward, 24)

	# Corner arcs in each of the 4 corners (quarter circles, 1 m).
	var corner_angle := PI / 2.0
	for corner_x: int in [-1, 1]:
		for corner_z: int in [-1, 1]:
			var corner := Vector2(half_width * corner_x, half_len * corner_z)
			var corner_inward := Vector2(-float(corner_x), -float(corner_z))
			var base_angle := corner_inward.angle()
			_arc_segment(root, corner, CORNER_ARC_RADIUS, base_angle - corner_angle * 0.5, base_angle + corner_angle * 0.5, 8)


# --- Line helpers ------------------------------------------------------

func _line(parent: Node3D, a: Vector2, b: Vector2) -> void:
	# a/b are (x, z) coordinates; produces a thin flat box between them.
	var diff := b - a
	var length := diff.length()
	if length <= 0.0:
		return
	var center: Vector2 = (a + b) * 0.5
	var along_x := absf(diff.x) >= absf(diff.y)
	var size: Vector3
	if along_x:
		size = Vector3(length + MIN_MARKING_WIDTH, MARKING_HEIGHT, MIN_MARKING_WIDTH)
	else:
		size = Vector3(MIN_MARKING_WIDTH, MARKING_HEIGHT, length + MIN_MARKING_WIDTH)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _line_material
	mesh.position = Vector3(center.x, LINE_Y, center.y)
	parent.add_child(mesh)


func _ring(parent: Node3D, center: Vector2, radius: float) -> void:
	var segments := 72
	var step := TAU / segments
	for i in segments:
		var a0 := i * step
		var a1 := (i + 1) * step
		var p0 := center + Vector2(cos(a0), sin(a0)) * radius
		var p1 := center + Vector2(cos(a1), sin(a1)) * radius
		_line(parent, p0, p1)


func _arc(parent: Node3D, center: Vector2, radius: float, half_angle: float, inward_sign: int, segments: int) -> void:
	# Direction of the "D" bulge is ±Z axis (y component of Vector2).
	var bulge := Vector2(0.0, float(inward_sign))
	for i in segments:
		var t0 := lerpf(-half_angle, half_angle, float(i) / float(segments))
		var t1 := lerpf(-half_angle, half_angle, float(i + 1) / float(segments))
		var p0 := center + bulge.rotated(t0) * radius
		var p1 := center + bulge.rotated(t1) * radius
		_line(parent, p0, p1)


func _arc_segment(parent: Node3D, center: Vector2, radius: float, from_angle: float, to_angle: float, segments: int) -> void:
	for i in segments:
		var a0 := lerpf(from_angle, to_angle, float(i) / float(segments))
		var a1 := lerpf(from_angle, to_angle, float(i + 1) / float(segments))
		var p0 := center + Vector2(cos(a0), sin(a0)) * radius
		var p1 := center + Vector2(cos(a1), sin(a1)) * radius
		_line(parent, p0, p1)


func _spot(parent: Node3D, at: Vector2) -> void:
	var disc := MeshInstance3D.new()
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = 0.15
	disc_mesh.bottom_radius = 0.15
	disc_mesh.height = MARKING_HEIGHT
	disc_mesh.radial_segments = 16
	disc.mesh = disc_mesh
	disc.material_override = _line_material
	disc.position = Vector3(at.x, LINE_Y + MARKING_HEIGHT * 0.5, at.y)
	parent.add_child(disc)


# --- Physics seed for later phases -------------------------------------

func _build_ground_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "GroundCollision"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(PITCH_WIDTH + STRIPE_OVERSCAN * 2.0, 1.0, PITCH_LENGTH + STRIPE_OVERSCAN * 2.0)
	shape.shape = box
	shape.position.y = -0.53  # top face at y = -0.03, just under the grass surface
	body.add_child(shape)
	add_child(body)
