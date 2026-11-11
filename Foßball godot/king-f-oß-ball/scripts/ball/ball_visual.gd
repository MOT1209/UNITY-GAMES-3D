class_name BallVisual
extends Node3D

## Procedural stylized football appearance (Phase 3).
##
## Builds an equirectangular ImageTexture in code — classic soccer pattern of
## black pentagons with panel seams on a white sphere — and applies it to a
## SphereMesh on a child MeshInstance3D. No external assets, no copyrighted
## material; safe to paint over later for cosmetic customization (Phase: visual
## customisation gets its own pass; this class exposes `set_scheme()` already).
##
## Kept fully separate from the physics side: the ball's rotation comes from the
## RigidBody3D itself, this node simply rotates along as a child.

const GOLDEN_RATIO := 1.61803398874

## 12 pentagon centres = normalized icosahedron vertices (truncated-icosahedron
## layout), generated once as static data so every ball reuses them.
static var _pentagon_dirs: Array[Vector3] = []

@export_group("Shape")
## Visual radius (kept equal to the physics radius by default).
@export var visual_radius: float = 0.11
@export_range(8, 64) var radial_segments: int = 32
@export_range(4, 64) var rings: int = 16

@export_group("Colour Scheme")
@export var base_color: Color = Color(0.97, 0.97, 0.94)
@export var pane_color: Color = Color(0.07, 0.07, 0.08)
@export var seam_color: Color = Color(0.32, 0.33, 0.35)

@export_group("Texture")
## Equirectangular texture resolution (width; height = width / 2).
@export_range(64, 1024, 64) var texture_width: int = 256
@export_range(1.0, 45.0, 0.5) var pentagon_size_degrees: float = 18.0
@export_range(5.0, 60.0, 0.5) var seam_inner_degrees: float = 34.0
@export_range(5.0, 60.0, 0.5) var seam_outer_degrees: float = 36.5

@onready var _mesh_instance: MeshInstance3D = $BallMesh


func _ready() -> void:
	build_visual()


## Generates (or regenerates) mesh, texture and material.
func build_visual() -> void:
	if _pentagon_dirs.is_empty():
		_pentagon_dirs = _build_pentagon_directions()

	var mesh := SphereMesh.new()
	mesh.radius = visual_radius
	mesh.height = visual_radius * 2.0
	mesh.radial_segments = radial_segments
	mesh.rings = rings
	var material := StandardMaterial3D.new()
	material.albedo_texture = _generate_pattern_texture()
	material.roughness = 0.45
	material.metallic = 0.0
	mesh.material = material

	_mesh_instance.mesh = mesh


## Swap the colour scheme at runtime (future cosmetic customization hook).
func set_scheme(base: Color, panes: Color) -> void:
	base_color = base
	pane_color = panes
	seam_color = panes.lerp(base_color, 0.35)
	build_visual()


func _build_pentagon_directions() -> Array[Vector3]:
	var dirs: Array[Vector3] = []
	var phi := GOLDEN_RATIO
	var raw: Array[Vector3] = [
		Vector3(0, 1, phi), Vector3(0, 1, -phi),
		Vector3(0, -1, phi), Vector3(0, -1, -phi),
		Vector3(1, phi, 0), Vector3(-1, phi, 0),
		Vector3(1, -phi, 0), Vector3(-1, -phi, 0),
		Vector3(phi, 0, 1), Vector3(phi, 0, -1),
		Vector3(-phi, 0, 1), Vector3(-phi, 0, -1),
	]
	var length := sqrt(1.0 + phi * phi)
	for dir: Vector3 in raw:
		dirs.append(dir / length)
	return dirs


## Rasterized via a per-pixel angular-distance test against the nearest
## pentagon centre, which decides white / seam / black with a little edge
## smoothing.
func _generate_pattern_texture() -> ImageTexture:
	var width := texture_width
	var height := texture_width / 2
	var image := Image.create(width, height, false, Image.FORMAT_RGB8)

	var pentagon_angle := deg_to_rad(pentagon_size_degrees)
	var seam_inner := deg_to_rad(seam_inner_degrees)
	var seam_outer := deg_to_rad(seam_outer_degrees)
	var inv_pi := 1.0 / PI
	var half_pi := PI * 0.5

	for y in height:
		var lat: float = (half_pi - (float(y) + 0.5) * PI / float(height))
		var cos_lat := cos(lat)
		var sin_lat := sin(lat)
		for x in width:
			var lon: float = (float(x) + 0.5) * TAU / float(width) - PI
			var dir := Vector3(cos_lat * sin(lon), sin_lat, cos_lat * cos(lon))

			# Nearest pentagon centre (angular distance).
			var best_angle := 9.0
			for center: Vector3 in _pentagon_dirs:
				var dot := dir.dot(center)
				if dot > 1.0:
					dot = 1.0
				elif dot < -1.0:
					dot = -1.0
				var angle := acos(dot)
				if angle < best_angle:
					best_angle = angle

			var color: Color
			# 0.02 rad edge feather keeps the silhouettes crisp but not jagged.
			if best_angle <= pentagon_angle - 0.01:
				color = pane_color
			elif best_angle <= pentagon_angle + 0.01:
				color = base_color.lerp(pane_color, 0.5)
			elif best_angle >= seam_inner and best_angle <= seam_outer:
				color = seam_color
			else:
				color = base_color
			image.set_pixel(x, y, color)

	var texture := ImageTexture.create_from_image(image)
	return texture
