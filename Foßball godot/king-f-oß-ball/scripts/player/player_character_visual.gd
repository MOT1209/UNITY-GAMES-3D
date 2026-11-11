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


func _ready() -> void:
	_anim = _find_anim_player(self)
	if _anim == null:
		push_warning("PlayerCharacterVisual: no AnimationPlayer found under %s." % name)
		return
	for clip in _anim.get_animation_list():
		_anim.get_animation(clip).loop_mode = \
				Animation.LOOP_NONE if clip in NON_LOOPING else Animation.LOOP_LINEAR
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


# --- Animation ---------------------------------------------------------------

## Phase 4 hook: fire the kick animation once (locomotion resumes when the
## clip ends).
func play_kick() -> void:
	if _anim == null or not _anim.has_animation("Kick"):
		return
	_action_playing = true
	_anim.speed_scale = 1.0
	_anim.play("Kick", 0.08)


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
			_play("Run")


func _on_speed_changed(speed: float) -> void:
	_speed = speed
	# Only refine while actually moving — IDLE/SPRINTING have their own clips.
	if _current_state != PlayerController.MovementState.MOVING:
		return
	_play("Run" if speed > walk_max_speed else "Walk")


func _on_animation_finished(anim: StringName) -> void:
	if anim == &"Kick":
		_action_playing = false


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
