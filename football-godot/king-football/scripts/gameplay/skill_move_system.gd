class_name SkillMoveSystem
extends Node

## Executes skill moves and feints (Phase 2 advanced mechanics) from `SkillMoveCatalog`. Mounted by `FootballActions`.
##
## Rules kept from the Phase 4 contract:
##   - The ball is never attached, positioned or teleported. A "touch" sets the ball's velocity through ONE impulse
##     (`BallController.redirect`), and only when the ball is really within reach of the foot (TOUCH_REACH); a touch on a
##     ball that has run away is simply missed and the move fails.
##   - The body moves through `PlayerController.set_motion_override` (a velocity target with bounded acceleration).
##   - A move never locks the player: kicks are allowed again from the exit phase (`kick_window`), and any move ends
##     after its `duration` (or at once when cancelled).
##
## Execution quality (0..1) comes from the player (skill rating vs. the move's `min_skill`, the weak foot when the
## decisive touch uses it, composure under pressure, fitness), the context (speed outside the move's range, an opponent
## very close) and a combo penalty. A roll against the quality decides a clean move; an unclean one gets a heavy or
## mis-directed touch (the ball runs away) — a skill move never guarantees anything.

signal started(id: StringName, exit_world: Vector3, quality: float)
## What defenders are shown: `kind` (&"step_over", &"shot", ...), the fake direction (world, planar) and its strength.
signal feint(kind: StringName, world_dir: Vector3, strength: float)
signal finished(id: StringName, clean: bool)

## Furthest planar distance (m) / height (m) of the ball from the player at which a touch can be played.
const TOUCH_REACH := 1.25
const TOUCH_HEIGHT := 0.6
## A move started during the exit phase of another one is a combo: quality x COMBO_PENALTY per link, at most COMBO_MAX
## links, and only from COMBO_MIN_SKILL (an advanced, high-risk combination).
const COMBO_PENALTY := 0.88
const COMBO_MAX := 3
const COMBO_MIN_SKILL := 0.62
## Pause (s) after a move before the next one can start (combos excepted).
const COOLDOWN := 0.3

var rng := RandomNumberGenerator.new()

var _id: StringName = &""
var _move: Dictionary = {}
var _t := 0.0
var _exit := 1.0
var _f := Vector3.FORWARD
var _r := Vector3.RIGHT
var _quality := 1.0
var _clean := true
var _done_touches := 0
var _done_feints := 0
var _done_body := 0
var _combo := 0
var _cooldown := 0.0
var _touched_at := -1.0
var _face_left := 0.0
var _player: PlayerController
var _ball: BallController
var _mods: AttributeModifiers
## Statistics for tests and tuning (since the node was created).
var stats := {"started": 0, "clean": 0, "failed": 0, "missed_touch": 0}
var last_quality := 0.0
var last_id: StringName = &""


func _init() -> void:
	rng.randomize()


func is_active() -> bool:
	return _id != &""


func current_id() -> StringName:
	return _id


## Exit side of the current / last move in the player's frame (+1 right, -1 left).
func exit_side() -> float:
	return _exit


func progress() -> float:
	return clampf(_t / float(_move.get("duration", 1.0)), 0.0, 1.0) if is_active() else 0.0


## True when the current move allows a kick (its exit phase) — or no move runs.
func kick_allowed() -> bool:
	return not is_active() or progress() >= float(_move.get("kick_window", 0.5))


## How loose the ball is right now (0..1; 0 without a move) — read by the tackle rules.
func exposure() -> float:
	if not is_active():
		return 0.0
	var e := float(_move.get("exposure", 0.0))
	return clampf(e + (1.0 - _quality) * 0.35, 0.0, 1.0)


## How well the body protects the ball right now (0..1).
func protect() -> float:
	return float(_move.get("protect", 0.0)) * _quality if is_active() else 0.0


## The dribble spring must leave the ball alone just after a touch (it would pull it back to the feet).
func ball_free() -> bool:
	return is_active() and _touched_at >= 0.0 and _t - _touched_at < 0.14


func can_start() -> bool:
	return _cooldown <= 0.0 and (not is_active() or kick_allowed())


## Execution quality 0..1 of `id` for this player in this context (pure; tests read it).
## ctx: speed (m/s), pressure (distance of the nearest opponent, INF = none), combo (links), foot_side (+1/-1/0).
static func quality_for(id: StringName, mods: AttributeModifiers, ctx: Dictionary) -> float:
	var move := SkillMoveCatalog.get_move(id)
	if move.is_empty():
		return 0.0
	var skill := mods.skill_rating() if mods != null else 0.5
	var q := clampf(0.78 + (skill - float(move["min_skill"])) * 1.6, 0.12, 1.0)
	if mods != null:
		q *= mods.foot_quality(float(ctx.get("foot_side", 0.0)))
		if mods.data != null:
			q *= 0.86 + 0.14 * clampf(float(mods.data.fitness) / 100.0, 0.0, 1.0)
	var speed := float(ctx.get("speed", 0.0))
	var lo: float = move["speed"][0]
	var hi: float = move["speed"][1]
	var off := maxf(lo - speed, 0.0) + maxf(speed - hi, 0.0)
	q *= clampf(1.0 - off * 0.12, 0.6, 1.0)
	var pressure := float(ctx.get("pressure", INF))
	if pressure < 1.2:
		var composure := mods.detail("composure") if mods != null else 0.5
		q *= 1.0 - (1.2 - pressure) / 1.2 * 0.35 * (1.0 - composure * 0.5)
	q *= pow(COMBO_PENALTY, int(ctx.get("combo", 0)))
	return clampf(q, 0.05, 1.0)


## Starts `id` towards `exit_side` (+1 = the player's right, -1 = left, 0 = pick: away from `threat` (world position,
## INF = none), else the strong-foot side). Returns false when the move cannot start now.
func start(id: StringName, exit_side: float, player: PlayerController, ball: BallController,
		mods: AttributeModifiers, threat: Vector3 = Vector3.INF) -> bool:
	if not SkillMoveCatalog.has(id) or player == null or ball == null or not can_start():
		return false
	var combo := 0
	if is_active():                                  # in the exit phase of the previous move: a combination
		if mods != null and mods.skill_rating() < COMBO_MIN_SKILL or _combo >= COMBO_MAX:
			return false
		combo = _combo + 1
		_finish(_clean)
	_player = player
	_ball = ball
	_mods = mods
	_f = -player.global_transform.basis.z
	_f.y = 0.0
	_f = _f.normalized() if _f.length_squared() > 0.0001 else Vector3.FORWARD
	_r = _f.cross(Vector3.UP).normalized()
	_exit = signf(exit_side)
	if _exit == 0.0:
		_exit = _pick_side(threat, mods)
	_move = SkillMoveCatalog.get_move(id)
	_id = id
	_t = 0.0
	_done_touches = 0
	_done_feints = 0
	_done_body = 0
	_touched_at = -1.0
	_combo = combo
	var pressure := INF
	if threat != Vector3.INF:
		pressure = Vector2(threat.x - player.global_position.x, threat.z - player.global_position.z).length()
	_quality = quality_for(id, mods, {"speed": player.get_current_speed(), "pressure": pressure, "combo": combo,
			"foot_side": _foot_side()})
	_clean = rng.randf() < clampf(_quality * 1.05, 0.15, 0.98)
	last_quality = _quality
	last_id = id
	stats["started"] += 1
	started.emit(id, _world(Vector2(1.0, 0.4)).normalized(), _quality)
	return true


## True while a just-started move has not touched the ball yet (a second tap may still turn it into its double-tap
## variant without the first one having done anything to the ball).
func can_upgrade() -> bool:
	return is_active() and _t <= SkillMoveCatalog.DOUBLE_TAP and _done_touches == 0


## Drops the current move without counting it (the double-tap upgrade), so `start` can run at once.
func discard() -> void:
	if not is_active():
		return
	stats["started"] -= 1
	_id = &""
	_cooldown = 0.0
	if _player != null and is_instance_valid(_player):
		_player.clear_motion_override()
		_player.facing_override = Vector3.ZERO
	_face_left = 0.0


## A kick played out of the exit phase ends the move with its own result.
func end_by_kick() -> void:
	if is_active():
		_finish(_clean)


## Ends the move now (a tackle, possession lost). Body control returns to the stick at once.
func cancel() -> void:
	if is_active():
		_finish(false)


func physics_tick(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _face_left > 0.0:
		_face_left -= delta
		if _face_left <= 0.0 and _player != null and is_instance_valid(_player):
			_player.facing_override = Vector3.ZERO
	if not is_active():
		return
	if _player == null or not is_instance_valid(_player) or _ball == null or not is_instance_valid(_ball):
		_finish(false)
		return
	_t += delta
	var feints: Array = _move["feints"]
	while _done_feints < feints.size() and _t >= float(feints[_done_feints]["t"]):
		var fe: Dictionary = feints[_done_feints]
		feint.emit(fe["kind"], _world(fe["dir"]).normalized(), float(fe["strength"]) * _quality)
		_done_feints += 1
	var body: Array = _move["body"]
	while _done_body < body.size() and _t >= float(body[_done_body]["t"]):
		_apply_body(body[_done_body])
		_done_body += 1
	var touches: Array = _move["touches"]
	while _done_touches < touches.size() and _t >= float(touches[_done_touches]["t"]):
		_apply_touch(touches[_done_touches], _done_touches == touches.size() - 1)
		_done_touches += 1
	if _t >= float(_move["duration"]):
		_finish(_clean)


# --- internals -------------------------------------------------------------------------------------------------

func _world(local: Vector2) -> Vector3:
	return _r * (local.x * _exit) + _f * local.y


func _foot_side() -> float:
	match str(_move.get("foot", "strong")):
		"exit": return _exit
		"feint": return -_exit
	return 0.0


func _pick_side(threat: Vector3, mods: AttributeModifiers) -> float:
	if threat != Vector3.INF and _player != null:
		var rel := threat - _player.global_position
		var lateral := rel.dot(_r)
		if absf(lateral) > 0.15:
			return -signf(lateral)
	var strong := mods.strong_side() if mods != null else 1.0
	return strong if strong != 0.0 else 1.0


func _apply_body(b: Dictionary) -> void:
	var dir: Vector2 = b["dir"]
	var speed := float(b["speed"]) * _player.config.normal_speed
	if _mods != null:
		speed *= lerpf(0.9, 1.1, _mods.detail("agility"))
	var v := _world(dir).normalized() * speed if dir != Vector2.ZERO else Vector3.ZERO
	_player.set_motion_override(v, float(b["dur"]), float(b.get("accel", 1.0)))
	if b.get("face", false) and dir != Vector2.ZERO:
		_player.facing_override = _world(dir).normalized()
		_face_left = float(b["dur"])


func _apply_touch(tch: Dictionary, decisive: bool) -> void:
	var offset := _ball.global_position - _player.global_position
	if Vector2(offset.x, offset.z).length() > TOUCH_REACH or offset.y > TOUCH_HEIGHT:
		stats["missed_touch"] += 1
		_clean = false                                  # the ball ran away before the foot got to it
		return
	var dir: Vector2 = tch["dir"]
	var speed := float(tch["speed"])
	var world := _world(dir).normalized() if dir != Vector2.ZERO else Vector3.ZERO
	# Precision: a clean move still has a small error that grows as quality drops; the decisive touch of an unclean
	# move is heavy (the ball runs 60-120 % too far) or mis-directed (up to 35 degrees off).
	var err_deg := (1.0 - _quality) * 14.0
	var speed_mult := 1.0 + rng.randf_range(-1.0, 1.0) * (1.0 - _quality) * 0.25
	if decisive and not _clean:
		if rng.randf() < 0.5:
			speed_mult *= rng.randf_range(1.6, 2.2)
		else:
			err_deg = rng.randf_range(20.0, 35.0)
	if world != Vector3.ZERO:
		world = world.rotated(Vector3.UP, deg_to_rad(rng.randf_range(-err_deg, err_deg)))
	var pv := _player.velocity
	pv.y = 0.0
	var target := world * speed * speed_mult + pv * float(tch.get("carry", 0.0))
	target.y = minf(_ball.linear_velocity.y, 0.0)
	var planar := Vector3(target.x, 0.0, target.z)
	var spin := Vector3.UP.cross(planar) / maxf(_ball.config.radius, 0.01) if planar.length() > 0.05 else Vector3.ZERO
	_ball.redirect(target, spin)
	_touched_at = _t


func _finish(clean: bool) -> void:
	var id := _id
	_id = &""
	_cooldown = COOLDOWN
	if _player != null and is_instance_valid(_player):
		_player.clear_motion_override()
		if _face_left > 0.0:
			_player.facing_override = Vector3.ZERO
			_face_left = 0.0
	stats["clean" if clean else "failed"] += 1
	finished.emit(id, clean)
