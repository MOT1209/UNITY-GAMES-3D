class_name PlayerAnimationLibrary
extends RefCounted

## Extra football clips generated IN-ENGINE from the shipped clips (Phase V4).
##
## No external animation asset is used. Every clip is either
##   * DERIVED from an authored clip (`Run` -> Sprint/Dribble, `Kick` -> Pass/Shoot/LongPass):
##     same keys, re-timed, amplitude scaled around the standing pose, with a posture offset; or
##   * KEYFRAMED from the standing pose (`Idle` frame 0) with a few model-space joint offsets
##     (FirstTouch, Celebrate, Disappointed).
## Both outfield and goalkeeper rigs share bone names, so `install()` works for either.
##
## Offsets are in MODEL axes (pitch = about X: for a limb hanging down + is forward, for the spine
## + is backwards-lean; roll = about Z). They are converted to the bone's local frame using the
## parent's rest orientation, because the imported rig has non-identity rest rotations.
##
## Only clips with a real gameplay trigger exist (see docs/PLAYER_ANIMATION_SYSTEM.md): there
## is no tackle/header/injury mechanic in the game, so no such clips are generated.

const CLIPS: Array[String] = ["Sprint", "Dribble", "Pass", "Shoot", "LongPass", "FirstTouch", "Celebrate", "Disappointed"]
## Clips that play once (the visual returns to locomotion afterwards).
const ONE_SHOTS: Array[String] = ["Pass", "Shoot", "LongPass", "FirstTouch", "Celebrate", "Disappointed"]
const REQUIRED_SOURCES: Array[String] = ["Idle", "Run", "Kick"]
const UPPER := Vector3(1, 0, 0)


## Adds every missing clip to `ap`'s default library. Returns the clip names that were added
## (empty when the source clips are missing or everything already exists).
static func install(ap: AnimationPlayer, skeleton: Skeleton3D) -> Array[String]:
	var added: Array[String] = []
	if ap == null or skeleton == null:
		return added
	for src in REQUIRED_SOURCES:
		if not ap.has_animation(src):
			return added
	var lib := ap.get_animation_library(&"")
	if lib == null:
		return added
	var idle := ap.get_animation("Idle")
	var run := ap.get_animation("Run")
	var kick := ap.get_animation("Kick")
	var made := {
		"Sprint": _derive(run, idle, skeleton, 0.78, 1.25, {"Spine": -0.12, "Chest": -0.10, "Head": 0.14}),
		"Dribble": _derive(run, idle, skeleton, 1.0, 0.75, {"Spine": -0.05, "Chest": -0.03, "Head": 0.30}),
		"Pass": _derive(kick, idle, skeleton, 0.72, 0.65, {}),
		"Shoot": _derive(kick, idle, skeleton, 0.90, 1.20, {}),
		"LongPass": _derive(kick, idle, skeleton, 1.0, 1.0, {"Spine": 0.07, "Chest": 0.06}),
		"FirstTouch": _first_touch(idle, skeleton),
		"Celebrate": _celebrate(idle, skeleton),
		"Disappointed": _disappointed(idle, skeleton),
	}
	for clip_name in CLIPS:
		if lib.has_animation(clip_name) or made[clip_name] == null:
			continue
		var a: Animation = made[clip_name]
		a.loop_mode = Animation.LOOP_NONE if clip_name in ONE_SHOTS else Animation.LOOP_LINEAR
		lib.add_animation(clip_name, a)
		added.append(clip_name)
	return added


# --- derivation -------------------------------------------------------------------------------------

static func _bone_of(path: NodePath) -> String:
	return String(path).get_slice(":", 1)


static func _parent_rest(sk: Skeleton3D, bone: String) -> Quaternion:
	var i := sk.find_bone(bone)
	if i < 0:
		return Quaternion.IDENTITY
	var p := sk.get_bone_parent(i)
	return sk.get_bone_global_rest(p).basis.get_rotation_quaternion() if p >= 0 else Quaternion.IDENTITY


## `base` rotated by `euler` (model axes) at the joint of `bone`.
static func _offset(sk: Skeleton3D, bone: String, base: Quaternion, euler: Vector3) -> Quaternion:
	if euler == Vector3.ZERO:
		return base
	var pg := _parent_rest(sk, bone)
	return (pg.inverse() * Quaternion.from_euler(euler) * pg * base).normalized()


static func _neutral(idle: Animation, bone: String, fallback: Quaternion) -> Quaternion:
	for t in idle.get_track_count():
		if idle.track_get_type(t) == Animation.TYPE_ROTATION_3D and _bone_of(idle.track_get_path(t)) == bone \
				and idle.track_get_key_count(t) > 0:
			return idle.track_get_key_value(t, 0)
	return fallback


static func _derive(src: Animation, idle: Animation, sk: Skeleton3D, time_scale: float,
		amplitude: float, pitch: Dictionary) -> Animation:
	var a := src.duplicate(true) as Animation
	for t in a.get_track_count():
		var type := a.track_get_type(t)
		var bone := _bone_of(a.track_get_path(t))
		var n := a.track_get_key_count(t)
		for k in n:
			a.track_set_key_time(t, k, a.track_get_key_time(t, k) * time_scale)
			if type != Animation.TYPE_ROTATION_3D:
				continue
			var q: Quaternion = a.track_get_key_value(t, k)
			var neutral := _neutral(idle, bone, q)
			if not is_equal_approx(amplitude, 1.0):
				q = neutral.slerp(q, amplitude)
			q = _offset(sk, bone, q, Vector3(float(pitch.get(bone, 0.0)), 0, 0))
			a.track_set_key_value(t, k, q)
	a.length = src.length * time_scale
	return a


# --- keyframed clips -----------------------------------------------------------------------------------

## spec: {"length": s, "bones": {bone: [[time, Vector3 model-space euler], ...]}, "hips": [[time, dy], ...]}
static func _keyframed(idle: Animation, sk: Skeleton3D, spec: Dictionary) -> Animation:
	var a := Animation.new()
	var length: float = spec["length"]
	a.length = length
	var bones: Dictionary = spec["bones"]
	var prefix := ""
	for t in idle.get_track_count():
		var bone := _bone_of(idle.track_get_path(t))
		prefix = String(idle.track_get_path(t)).get_slice(":", 0)
		if idle.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			var base: Quaternion = _neutral(idle, bone, Quaternion.IDENTITY)
			var tr := a.add_track(Animation.TYPE_ROTATION_3D)
			a.track_set_path(tr, idle.track_get_path(t))
			a.track_set_interpolation_type(tr, Animation.INTERPOLATION_CUBIC)
			var keys: Array = bones.get(bone, [])
			if keys.is_empty() or float(keys[0][0]) > 0.0:
				a.rotation_track_insert_key(tr, 0.0, base)
			for kv in keys:
				a.rotation_track_insert_key(tr, float(kv[0]), _offset(sk, bone, base, kv[1]))
			if keys.is_empty() or float(keys[keys.size() - 1][0]) < length:
				a.rotation_track_insert_key(tr, length, base if keys.is_empty() else _offset(sk, bone, base, Vector3.ZERO))
		elif idle.track_get_type(t) == Animation.TYPE_POSITION_3D and bone == "Hips":
			var base_pos: Vector3 = idle.track_get_key_value(t, 0)
			var tp := a.add_track(Animation.TYPE_POSITION_3D)
			a.track_set_path(tp, idle.track_get_path(t))
			a.track_set_interpolation_type(tp, Animation.INTERPOLATION_CUBIC)
			a.position_track_insert_key(tp, 0.0, base_pos)
			for kv in spec.get("hips", []):
				a.position_track_insert_key(tp, float(kv[0]), base_pos + Vector3(0, float(kv[1]), 0))
			a.position_track_insert_key(tp, length, base_pos)
	var _p := prefix
	return a


static func _first_touch(idle: Animation, sk: Skeleton3D) -> Animation:
	return _keyframed(idle, sk, {"length": 0.7, "bones": {
		"UpperLeg_R": [[0.0, Vector3.ZERO], [0.16, Vector3(0.85, 0, 0)], [0.34, Vector3(0.55, 0, 0)], [0.7, Vector3.ZERO]],
		"LowerLeg_R": [[0.0, Vector3.ZERO], [0.16, Vector3(-0.55, 0, 0)], [0.34, Vector3(-0.75, 0, 0)], [0.7, Vector3.ZERO]],
		"Spine": [[0.0, Vector3.ZERO], [0.2, Vector3(-0.10, 0, 0)], [0.7, Vector3.ZERO]],
		"UpperArm_L": [[0.0, Vector3.ZERO], [0.2, Vector3(0, 0, -0.35)], [0.7, Vector3.ZERO]],
		"UpperArm_R": [[0.0, Vector3.ZERO], [0.2, Vector3(0, 0, 0.35)], [0.7, Vector3.ZERO]],
	}, "hips": [[0.2, -0.03]]})


static func _celebrate(idle: Animation, sk: Skeleton3D) -> Animation:
	var up := 2.7
	return _keyframed(idle, sk, {"length": 2.3, "bones": {
		"UpperArm_L": [[0.0, Vector3.ZERO], [0.35, Vector3(0, 0, -up)], [1.9, Vector3(0, 0, -up)], [2.3, Vector3.ZERO]],
		"UpperArm_R": [[0.0, Vector3.ZERO], [0.35, Vector3(0, 0, up)], [1.9, Vector3(0, 0, up)], [2.3, Vector3.ZERO]],
		"LowerArm_L": [[0.0, Vector3.ZERO], [0.35, Vector3(0, 0, 0.25)], [1.9, Vector3(0, 0, 0.25)], [2.3, Vector3.ZERO]],
		"LowerArm_R": [[0.0, Vector3.ZERO], [0.35, Vector3(0, 0, -0.25)], [1.9, Vector3(0, 0, -0.25)], [2.3, Vector3.ZERO]],
		"Spine": [[0.0, Vector3.ZERO], [0.35, Vector3(0.14, 0, 0)], [1.9, Vector3(0.14, 0, 0)], [2.3, Vector3.ZERO]],
		"Head": [[0.0, Vector3.ZERO], [0.35, Vector3(0.18, 0, 0)], [1.9, Vector3(0.18, 0, 0)], [2.3, Vector3.ZERO]],
		"LowerLeg_L": [[0.0, Vector3.ZERO], [0.30, Vector3(-0.5, 0, 0)], [0.55, Vector3.ZERO], [0.9, Vector3(-0.5, 0, 0)], [1.15, Vector3.ZERO], [1.5, Vector3(-0.5, 0, 0)], [1.75, Vector3.ZERO]],
		"LowerLeg_R": [[0.0, Vector3.ZERO], [0.30, Vector3(-0.5, 0, 0)], [0.55, Vector3.ZERO], [0.9, Vector3(-0.5, 0, 0)], [1.15, Vector3.ZERO], [1.5, Vector3(-0.5, 0, 0)], [1.75, Vector3.ZERO]],
	}, "hips": [[0.30, 0.20], [0.55, 0.0], [0.9, 0.20], [1.15, 0.0], [1.5, 0.20], [1.75, 0.0]]})


static func _disappointed(idle: Animation, sk: Skeleton3D) -> Animation:
	return _keyframed(idle, sk, {"length": 2.2, "bones": {
		"Head": [[0.0, Vector3.ZERO], [0.5, Vector3(-0.55, 0, 0)], [1.8, Vector3(-0.50, 0, 0)], [2.2, Vector3.ZERO]],
		"Spine": [[0.0, Vector3.ZERO], [0.5, Vector3(-0.22, 0, 0)], [1.8, Vector3(-0.20, 0, 0)], [2.2, Vector3.ZERO]],
		"Chest": [[0.0, Vector3.ZERO], [0.5, Vector3(-0.12, 0, 0)], [1.8, Vector3(-0.10, 0, 0)], [2.2, Vector3.ZERO]],
		"UpperArm_L": [[0.0, Vector3.ZERO], [0.5, Vector3(0, 0, -0.45)], [1.8, Vector3(0, 0, -0.45)], [2.2, Vector3.ZERO]],
		"UpperArm_R": [[0.0, Vector3.ZERO], [0.5, Vector3(0, 0, 0.45)], [1.8, Vector3(0, 0, 0.45)], [2.2, Vector3.ZERO]],
		"LowerArm_L": [[0.0, Vector3.ZERO], [0.5, Vector3(0.9, 0, 0)], [1.8, Vector3(0.9, 0, 0)], [2.2, Vector3.ZERO]],
		"LowerArm_R": [[0.0, Vector3.ZERO], [0.5, Vector3(0.9, 0, 0)], [1.8, Vector3(0.9, 0, 0)], [2.2, Vector3.ZERO]],
	}, "hips": [[0.5, -0.03], [1.8, -0.03]]})
