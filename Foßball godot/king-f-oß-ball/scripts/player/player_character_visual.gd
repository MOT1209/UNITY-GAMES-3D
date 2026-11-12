class_name PlayerCharacterVisual
extends Node3D

## Drives the character model's AnimationPlayer and dresses it: team kit,
## shirt number and the individual look (skin / hair / beard / build).
##
## Two ways to drive the animation:
##   - Human player — the parent `PlayerController` pushes its state and
##     speed signals; this node only listens.
##   - Team player (AI) — nobody drives it, so the clip is picked from the
##     speed passed to `set_speed()`.
##
## Animation mapping (assets/models/characters/player.glb, facing -Z):
##   IDLE      → "Idle" (or `idle_animation`, e.g. "Ready" for the keeper)
##   MOVING    → "Walk" below `walk_max_speed`, otherwise "Run"
##   SPRINTING → "Run"
## "Kick" is reserved for Phase 4 — call `play_kick()` from the gameplay layer.
##
## The models ship every hair style as its own mesh (`P_Hair_Short`,
## `P_Hair_Buzz`, `P_Hair_Afro`, `P_Hair_Long`) plus an optional beard
## (`P_Beard`). All of them are visible in the imported file, so this node
## always hides the ones the current look does not use.

## Team colours applied to the model.
@export var kit: TeamKit
## Individual appearance; `null` = short hair, no beard, default build.
@export var look: PlayerLook
## Shirt number on the back; 0 keeps the number baked into the model.
@export_range(0, 99) var number := 0
## The idle clip — the goalkeeper uses its "Ready" stance instead.
@export var idle_animation := "Idle"
## Planar speed (m/s) at which MOVING switches from Walk to Run.
@export_range(1.0, 12.0, 0.1) var walk_max_speed: float = 3.2
## Cross-fade time between locomotion clips (s).
@export var anim_fade: float = 0.18
## Speed the Walk clip was authored for (m/s) — drives the playback rate.
@export var walk_clip_speed: float = 2.2
## Speed the Run clip was authored for (m/s).
@export var run_clip_speed: float = 6.5
## Planar speed (m/s) from which team players use the Sprint clip (human players: SPRINTING state).
@export var sprint_min_speed: float = 7.0
## Speed the generated Sprint clip is meant for (m/s).
@export var sprint_clip_speed: float = 8.5

## Shared 10×10 shirt-number atlas (cell index = number, row-major).
const NUMBER_ATLAS := "res://assets/textures/numbers_atlas.png"
## Clips that must not loop.
const NON_LOOPING := ["Kick", "DiveLeft", "DiveRight", "CatchHigh", "CatchLow", "Throw"]

var _anim: AnimationPlayer
var _current_state: PlayerController.MovementState = \
		PlayerController.MovementState.IDLE
## True while a one-shot clip (Kick, Dive, Catch, Throw) is playing.
var _action_playing := false
var _speed := 0.0
var _dribbling := false


func _ready() -> void:
	_anim = _find_anim_player(self)
	if _anim == null:
		push_warning("PlayerCharacterVisual: no AnimationPlayer found under %s." % name)
		return
	for clip in _anim.get_animation_list():
		_anim.get_animation(clip).loop_mode = \
				Animation.LOOP_NONE if clip in NON_LOOPING else Animation.LOOP_LINEAR
	var skeleton := find_child("Skeleton3D", true, false) as Skeleton3D
	PlayerAnimationLibrary.install(_anim, skeleton)
	for clip in PlayerAnimationLibrary.CLIPS:
		if _anim.has_animation(clip):
			_anim.get_animation(clip).loop_mode = \
					Animation.LOOP_NONE if clip in PlayerAnimationLibrary.ONE_SHOTS else Animation.LOOP_LINEAR
	_anim.animation_finished.connect(_on_animation_finished)

	var controller := get_parent() as PlayerController
	if controller != null:
		controller.movement_state_changed.connect(_on_state_changed)
		controller.speed_changed.connect(_on_speed_changed)

	apply_kit()
	apply_number()
	apply_look()
	_play(idle_animation)


# --- Appearance ---------------------------------------------------------------

## Applies the team colours to the model.
func apply_kit() -> void:
	if kit != null:
		kit.apply_to(self)
	apply_crest()


## Points the number material at this player's cell of the shared atlas.
## `number = 0` keeps the number baked into the model.
func apply_number() -> void:
	if number <= 0:
		return
	var atlas := load(NUMBER_ATLAS) as Texture2D
	if atlas == null:
		return
	for mi in find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(s) as StandardMaterial3D
			if mat == null or not mat.resource_name.ends_with("Number"):
				continue
			var own := mat.duplicate() as StandardMaterial3D
			own.albedo_texture = atlas
			own.uv1_scale = Vector3(0.1, 0.1, 1.0)
			own.uv1_offset = Vector3((number % 10) * 0.1, (number / 10) * 0.1, 0.0)
			own.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			m.set_surface_override_material(s, own)


## Applies the individual look (call after the kit: its colours win over the
## kit's skin / hair / boots). Without a look, short hair and no beard.
func apply_look() -> void:
	var model := find_child("*_Rig", true, false) as Node3D
	if model != null and look != null:
		model.scale = Vector3(look.build, look.height, look.build)
	if look != null and look.face_shape >= 0:
		FaceBuilder.apply(self, look)
	var hair_style := look.hair_style if look != null else "Short"
	var beard := look.beard if look != null else false
	for mi in find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var nm := String(mi.name)
		if "_Hair_" in nm:
			m.visible = nm.ends_with("_Hair_" + hair_style)
		elif nm.ends_with("_Beard"):
			m.visible = beard
		if m.mesh == null or look == null:
			continue
		var cols := {"Skin": look.skin, "Hair": look.hair, "Boots": look.boots}
		for s in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(s) as StandardMaterial3D
			if mat == null:
				continue
			for suffix in cols:
				if mat.resource_name.ends_with(suffix):
					var own := mat.duplicate() as StandardMaterial3D
					own.albedo_color = cols[suffix]
					m.set_surface_override_material(s, own)


## Club crest on the left chest, as a small quad on the chest bone so it follows the animation.
## Idempotent; without a crest in the kit (or a skeleton) any old crest is removed.
func apply_crest() -> void:
	var skeleton := find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return
	var old := skeleton.get_node_or_null("KF_Crest")
	if old != null:
		skeleton.remove_child(old)
		old.queue_free()
	if kit == null or kit.crest == null or skeleton.find_bone(CREST_BONE) < 0:
		return
	var attach := BoneAttachment3D.new()
	attach.name = "KF_Crest"
	attach.bone_name = CREST_BONE
	skeleton.add_child(attach)
	var quad := MeshInstance3D.new()
	quad.name = "Badge"
	quad.mesh = _crest_mesh()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = kit.crest
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mat.roughness = 0.9
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	quad.material_override = mat
	quad.position = CREST_OFFSET
	quad.rotation = Vector3(0.0, PI, 0.0)               # the quad faces the front of the shirt
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	attach.add_child(quad)


## Chest bone and where the badge sits relative to it (wearer's left chest, on the shirt surface).
const CREST_BONE := "Chest"
const CREST_OFFSET := Vector3(-0.085, 0.075, -0.138)
const CREST_SIZE := 0.075
static var _crest_quad: QuadMesh


static func _crest_mesh() -> QuadMesh:
	if _crest_quad == null:
		_crest_quad = QuadMesh.new()
		_crest_quad.size = Vector2(CREST_SIZE, CREST_SIZE)
	return _crest_quad


## Captain's armband on the left upper arm (real data: the squad's captain). Idempotent.
func set_captain(on: bool) -> void:
	var skeleton := find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return
	var old := skeleton.get_node_or_null("KF_Armband")
	if old != null:
		skeleton.remove_child(old)
		old.queue_free()
	if not on or skeleton.find_bone("UpperArm_L") < 0:
		return
	var attach := BoneAttachment3D.new()
	attach.name = "KF_Armband"
	attach.bone_name = "UpperArm_L"
	skeleton.add_child(attach)
	var band := MeshInstance3D.new()
	band.name = "Band"
	band.mesh = _armband_mesh()
	band.position = Vector3(0.0, 0.14, 0.0)          # along the bone, mid upper arm
	band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	attach.add_child(band)


static var _armband: CylinderMesh


static func _armband_mesh() -> CylinderMesh:
	if _armband == null:
		_armband = CylinderMesh.new()
		_armband.top_radius = 0.066
		_armband.bottom_radius = 0.066
		_armband.height = 0.075
		_armband.radial_segments = 12
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1.0, 0.84, 0.0)
		m.roughness = 0.8
		_armband.material = m
	return _armband


# --- Animation ---------------------------------------------------------------

## Fires a kick clip once (locomotion resumes when it ends). `kind` selects the clip:
## &"pass" -> Pass, &"shot" -> Shoot, &"lob" -> LongPass, anything else -> the authored Kick.
## Falls back to `Kick` when a generated clip is missing.
func play_kick(kind: StringName = &"Kick") -> void:
	if _anim == null:
		return
	var clip: String = {&"pass": "Pass", &"shot": "Shoot", &"lob": "LongPass"}.get(kind, "Kick")
	if not _anim.has_animation(clip):
		clip = "Kick"
	if not _anim.has_animation(clip):
		return
	_action_playing = true
	_anim.speed_scale = 1.0
	_anim.play(clip, 0.08)


## One-shot whole-body reaction: "FirstTouch" (only when nearly standing, so a running
## player is never frozen), "Celebrate", "Disappointed". Returns true when it started.
func play_reaction(clip: String) -> bool:
	if _anim == null or not _anim.has_animation(clip):
		return false
	if clip == "FirstTouch" and (_speed > 2.0 or _action_playing):
		return false
	_action_playing = true
	_anim.speed_scale = 1.0
	_anim.play(clip, 0.15)
	return true


## True while a one-shot (kick, reaction, dive...) owns the skeleton.
func is_busy() -> bool:
	return _action_playing


## Gameplay tells the visual whether the player is dribbling (ball at feet).
func set_dribbling(value: bool) -> void:
	_dribbling = value


## Manual drive for team players that have no `PlayerController`.
func set_speed(speed: float) -> void:
	_speed = speed
	if _action_playing or _anim == null:
		return
	if speed < 0.15:
		_play(idle_animation)
	elif speed <= walk_max_speed:
		_anim.speed_scale = clampf(speed / walk_clip_speed, 0.5, 1.6)
		_play("Walk")
	elif speed >= sprint_min_speed and _anim.has_animation("Sprint"):
		_anim.speed_scale = clampf(speed / sprint_clip_speed, 0.7, 1.3)
		_play("Sprint")
	elif _dribbling and _anim.has_animation("Dribble"):
		_anim.speed_scale = clampf(speed / run_clip_speed, 0.7, 1.5)
		_play("Dribble")
	else:
		_anim.speed_scale = clampf(speed / run_clip_speed, 0.7, 1.5)
		_play("Run")


func _on_state_changed(new_state: PlayerController.MovementState) -> void:
	_current_state = new_state
	match new_state:
		PlayerController.MovementState.IDLE:
			_play(idle_animation)
		PlayerController.MovementState.MOVING:
			_play("Walk")  # speed refinement arrives with the next speed signal
		PlayerController.MovementState.SPRINTING:
			_play("Sprint" if _anim != null and _anim.has_animation("Sprint") else "Run")


func _on_speed_changed(speed: float) -> void:
	_speed = speed
	if _action_playing or _anim == null:
		return
	if _current_state == PlayerController.MovementState.SPRINTING:
		_anim.speed_scale = clampf(speed / sprint_clip_speed, 0.7, 1.3)
		return
	# Only refine while actually moving — IDLE has its own clip.
	if _current_state != PlayerController.MovementState.MOVING:
		return
	var running := "Dribble" if _dribbling and _anim.has_animation("Dribble") else "Run"
	_play(running if speed > walk_max_speed else "Walk")


func _on_animation_finished(anim: StringName) -> void:
	if anim == &"Kick" or String(anim) in PlayerAnimationLibrary.ONE_SHOTS:
		_action_playing = false
		_resume_locomotion()


## Back to the clip that matches the current movement after a one-shot ended.
func _resume_locomotion() -> void:
	if _anim == null:
		return
	if get_parent() is PlayerController:
		_on_state_changed(_current_state)
		_on_speed_changed(_speed)
	else:
		set_speed(_speed)


func _play(clip: String) -> void:
	if _anim != null and _anim.has_animation(clip):
		_anim.play(clip, anim_fade)


func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_anim_player(child)
		if found != null:
			return found
	return null
