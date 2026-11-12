class_name StadiumArena
extends Node3D

## Loads the Blender-made stadium (assets/models/stadium/stadium.glb) and turns
## its helper objects into gameplay nodes at runtime:
##
##   COL_*            -> StaticBody3D with a trimesh shape (mesh removed)
##   TRIGGER_Goal_N/S -> Area3D goal volume, emits `goal_entered`
##   SPAWN_*          -> stored in `spawn_points` (Transform3D)
##
## Conventions match FootballPitch: centre (0,0,0), length along Z,
## goal lines at z = ±52.5, grass top at y = 0.
## Goal "N" is the -Z end, goal "S" is the +Z end.

signal goal_entered(goal_id: StringName, body: Node3D)
signal arena_built

const DEFAULT_MODEL_PATH := "res://assets/models/stadium/stadium.glb"
const PREFIX_COLLISION := "COL_"
const PREFIX_TRIGGER := "TRIGGER_Goal_"
const PREFIX_SPAWN := "SPAWN_"

## Leave empty to use DEFAULT_MODEL_PATH.
@export var model: PackedScene
@export var show_trees := true
@export_flags_3d_physics var collision_layer := 1
## Goal triggers must see the real ball, which lives on physics layer 3 (value 4,
## see football_ball.tscn) — with only layer 1 no real shot ever counted as a goal.
@export_flags_3d_physics var trigger_mask := 5
## Multiplier for emissive parts (LED ribbons, ad boards, screens, roof lights).
@export_range(0.0, 3.0, 0.05) var emission_scale := 0.45
## Multiplies the grass texture colour (darker / richer pitch when < 1).
@export var pitch_tint := Color(0.72, 0.8, 0.72)
## When set, only bodies in this group fire `goal_entered` (e.g. &"ball").
@export var goal_body_group: StringName = &""

var spawn_points: Dictionary = {}   # StringName -> Transform3D
var goal_areas: Dictionary = {}     # StringName -> Area3D
var collision_bodies: Array[StaticBody3D] = []
var model_root: Node3D


func _ready() -> void:
	build()


func build() -> void:
	var scene := model if model != null else load(DEFAULT_MODEL_PATH) as PackedScene
	if scene == null:
		push_error("StadiumArena: cannot load %s" % DEFAULT_MODEL_PATH)
		return
	model_root = scene.instantiate()
	model_root.name = "Model"
	add_child(model_root)

	for node: Node in model_root.find_children("*", "", true, false):
		var n := String(node.name)
		if n.begins_with(PREFIX_COLLISION):
			_make_collision(node as MeshInstance3D)
		elif n.begins_with(PREFIX_TRIGGER):
			_make_goal_trigger(node as MeshInstance3D, StringName(n.trim_prefix(PREFIX_TRIGGER)))
		elif n.begins_with(PREFIX_SPAWN):
			spawn_points[StringName(n.trim_prefix(PREFIX_SPAWN))] = (node as Node3D).global_transform
		elif n == "Trees":
			(node as Node3D).visible = show_trees
		elif n == "Pitch" or n == "Plaza":
			(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if n == "Pitch":
				_tint_pitch(node as MeshInstance3D)
		if node is MeshInstance3D and n.begins_with("Goal_"):
			_fix_net_material(node)
		if node is MeshInstance3D and not n.begins_with(PREFIX_COLLISION) \
				and not n.begins_with(PREFIX_TRIGGER):
			_scale_emission(node)
	arena_built.emit()


## Returns the stored spawn transform, or identity when the id is unknown.
func get_spawn(id: StringName) -> Transform3D:
	return spawn_points.get(id, Transform3D.IDENTITY)


func _make_collision(mesh_node: MeshInstance3D) -> void:
	if mesh_node == null or mesh_node.mesh == null:
		return
	var body := StaticBody3D.new()
	body.name = mesh_node.name
	body.collision_layer = collision_layer
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.shape = mesh_node.mesh.create_trimesh_shape()
	body.add_child(shape)
	add_child(body)
	body.global_transform = mesh_node.global_transform
	collision_bodies.append(body)
	mesh_node.queue_free()


func _make_goal_trigger(mesh_node: MeshInstance3D, goal_id: StringName) -> void:
	if mesh_node == null or mesh_node.mesh == null:
		return
	var area := Area3D.new()
	area.name = "GoalTrigger_%s" % goal_id
	area.collision_layer = 0
	area.collision_mask = trigger_mask
	area.monitorable = false
	var shape := CollisionShape3D.new()
	shape.shape = mesh_node.mesh.create_convex_shape()
	area.add_child(shape)
	add_child(area)
	area.global_transform = mesh_node.global_transform
	area.body_entered.connect(_on_goal_body_entered.bind(goal_id))
	goal_areas[goal_id] = area
	mesh_node.queue_free()


func _on_goal_body_entered(body: Node3D, goal_id: StringName) -> void:
	if goal_body_group != &"" and not body.is_in_group(goal_body_group):
		return
	goal_entered.emit(goal_id, body)


var _emissive_copies: Dictionary = {}


func _tint_pitch(mesh_node: MeshInstance3D) -> void:
	if mesh_node == null or pitch_tint == Color.WHITE:
		return
	var src := mesh_node.mesh.surface_get_material(0) as BaseMaterial3D
	if src == null:
		return
	var grass := src.duplicate() as BaseMaterial3D
	grass.albedo_color = src.albedo_color * pitch_tint
	mesh_node.set_surface_override_material(0, grass)


func _scale_emission(mesh_node: MeshInstance3D) -> void:
	if is_equal_approx(emission_scale, 1.0) or mesh_node.mesh == null:
		return
	for i in mesh_node.mesh.get_surface_count():
		var src := mesh_node.mesh.surface_get_material(i) as BaseMaterial3D
		if src == null or not src.emission_enabled:
			continue
		if not _emissive_copies.has(src):
			var copy := src.duplicate() as BaseMaterial3D
			copy.emission_energy_multiplier = src.emission_energy_multiplier * emission_scale
			_emissive_copies[src] = copy
		mesh_node.set_surface_override_material(i, _emissive_copies[src])


## The net texture has holes: render it with alpha scissor (no sorting
## problems, casts proper shadows) and from both sides.
func _fix_net_material(mesh_node: MeshInstance3D) -> void:
	for i in mesh_node.mesh.get_surface_count():
		var src := mesh_node.mesh.surface_get_material(i) as BaseMaterial3D
		if src == null or not src.resource_name.contains("net"):
			continue
		var net := StandardMaterial3D.new()
		net.resource_name = "M_net_scissor"
		net.albedo_texture = src.albedo_texture
		net.albedo_color = Color.WHITE
		net.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		net.alpha_scissor_threshold = 0.5
		net.cull_mode = BaseMaterial3D.CULL_DISABLED
		net.roughness = 0.8
		mesh_node.set_surface_override_material(i, net)
