class_name FootballActions
extends Node3D

## Central player↔ball interaction layer and action-state machine (Phase 4,
## plan §5/§13). Mounted as `BallActions` under the player with a
## `BallDetector` (`BallProximityDetector`) child.
##
## Responsibilities:
##   - The plan §5 reusable queries: `can_interact_with_ball()`,
##     `get_ball_relative_position()`, `get_ball_distance()`,
##     `get_kick_direction()`, `get_action_availability()`.
##   - Input integration for the existing InputMap actions
##     `pass` / `shoot` / `lob_pass` / `dribble` (movement actions untouched).
##   - Kick-power charging (one `KickPowerController` per kick action).
##   - A lightweight, derived action-state machine
##     (IDLE/RECEIVING/PASSING/SHOOTING/LOB_PASSING/DRIBBLING). States are
##     computed from small flags each tick — a locked-up state is impossible.
##   - Delegating the actual physics to the subsystem nodes it creates:
##     PassingSystem, ShootingSystem, LobPassSystem, DribblingSystem,
##     BallControlSystem.
##
## Hard rules (plan §5/§17): the ball is never attached or teleported, every
## kick goes through the Phase 3 `BallController.apply_kick()` API, dribble and
## reception control are per-tick capped `apply_force()` pushes, and gameplay
## works independently of animation availability.

signal action_state_changed(new_state: ActionState)
signal charge_changed(action: StringName, ratio: float)
signal pass_started(power: float)
signal pass_completed
signal shot_started(power: float, lift: float)
signal shot_completed
signal lob_started(power: float, lift: float)
signal through_started(power: float)
signal cross_started(power: float, lift: float)
signal dribble_started
signal dribble_stopped
signal ball_received(ball_speed: float)
## Phase 2 advanced mechanics.
signal skill_move_started(id: StringName, quality: float)
signal skill_move_finished(id: StringName, clean: bool)
## A feint shown to defenders: kind (&"step_over", &"shot", &"pass", ...), fake direction (world), strength 0..1.
signal feint_shown(kind: StringName, world_dir: Vector3, strength: float)
signal shield_changed(active: bool)
signal header_played(kind: StringName, speed: float, quality: float)
## Technique (ShotTechnique.*) and context (volley, half volley, first time, ground) of every shot.
signal shot_technique_used(technique: StringName, context: StringName)

enum ActionState { IDLE, RECEIVING, PASSING, SHOOTING, LOB_PASSING, DRIBBLING }

const ACTION_PASS := "pass"
const ACTION_SHOOT := "shoot"
const ACTION_LOB := "lob_pass"
const ACTION_DRIBBLE := "dribble"
const ACTION_SPRINT := "sprint"
## P3 human actions (the AI gained crosses / through balls first; now the human
## has them too, driven through the same kick systems).
const ACTION_THROUGH := "through_pass"
const ACTION_CROSS := "cross"
## Phase 2: skill moves / feints (tap, see SkillMoveCatalog.INPUT_TABLE; held = finesse modifier for shots / chips)
## and ball shielding (hold; held = low-driven modifier for shots).
const ACTION_SKILL := "skill_move"
const ACTION_SHIELD := "shield"
## Squared-length epsilon for degenerate directions (matches Phase 2 style).
const DEGENERATE_DIR_EPSILON := 0.0004

@export var config: BallActionConfig

## Optional attribute modifiers (Phase T2): scale kick power and add aim error.
## Null keeps the Phase 4 behaviour untouched.
var attribute_modifiers: AttributeModifiers = null

## Optional match-level aim assist (P3) for the through-pass and cross actions.
## Null degrades both actions to plain directional kicks — always safe.
var aim_assist: HumanAimAssist = null
## Where the last assisted ground pass was aimed (the receiver's position; INF = plain kick). Read by the match to
## send the receiver to the ball (Phase M1).
var last_pass_target := Vector3.INF

## Phase 2: nearest opponent of this player (Callable(position: Vector3) -> Vector3, INF = none) and the goals
## (Callable() -> [opponent goal, own goal]). Set by the match; unset = no opponent known (tests, practice scenes).
var nearest_opponent: Callable
var goals: Callable
## Phase 2 subsystems (public so the match rules / AI / tests can read their state).
var skill: SkillMoveSystem
var shielding: ShieldingSystem
var header: HeaderSystem
## Shot statistics by technique and context (tests, tuning).
var shot_log: Array = []
var _skill_pressed_at := -10.0
var _clock := 0.0
var _ground_at := -10.0
var _pending_shot: Dictionary = {}
var _shield_was := false

## Control source (Phase T11); shared with the player's controller by the match
## setup. Default = global Input, i.e. unchanged Phase 4 behaviour.
var intent: IntentProvider = IntentProvider.new()

## Current derived action state (separate from the player's movement state).
var action_state: ActionState = ActionState.IDLE

@onready var ball_detector: BallProximityDetector = $BallDetector

var _player: PlayerController
var _pass_system: PassingSystem
var _shoot_system: ShootingSystem
var _lob_system: LobPassSystem
var _dribble_system: DribblingSystem
var _control_system: BallControlSystem
var _pass_charge: KickPowerController
var _shoot_charge: KickPowerController
var _lob_charge: KickPowerController
var _through_charge: KickPowerController
var _cross_charge: KickPowerController

var _pass_cooldown := 0.0
var _shoot_cooldown := 0.0
var _lob_cooldown := 0.0
var _through_cooldown := 0.0
var _cross_cooldown := 0.0
var _state_hold := 0.0
var _transient_state: ActionState = ActionState.IDLE
var _receiving := false
var _dribbling := false
var _last_aim := Vector3.ZERO
## Phase M3: for SELF_EXCEPTION_TIME after his own kick the kicker's body does not collide with the ball — the foot is
## in front of the body, but the capsule stood in the way of every pass played across or behind him (measured: the
## ball bounced back at 3-5 m/s, 120-165 degrees off the aim).
const SELF_EXCEPTION_TIME := 0.2
var _self_exception_left := 0.0
var _excepted_ball: BallController
var _charge_ratios := {
	&"pass": 0.0,
	&"shoot": 0.0,
	&"lob": 0.0,
	&"through": 0.0,
	&"cross": 0.0,
}
## (action, controller) pairs for the per-tick charge loop — built once in
## `_build_subsystems()` so `_physics_process` allocates nothing per tick.
var _charge_pairs: Array = []


func _ready() -> void:
	if config == null:
		config = BallActionConfig.new()
	_player = get_parent() as PlayerController
	_build_subsystems()
	add_to_group(&"ball_actions")


func _physics_process(delta: float) -> void:
	# The stick direction is remembered every tick (Phase M1): a kick released after the stick was let go goes where
	# the player last pointed, not where an older kick went.
	var held := intent.move_vector()
	if held != Vector2.ZERO:
		_last_aim = _input_to_world_dir(held)
	_clock += delta
	_update_cooldowns(delta)
	_update_self_exception(delta)
	_track_bounce()
	_update_reception(delta)
	var consumed := _update_header(delta)
	consumed = _handle_skill_input() or consumed
	if not consumed:
		_handle_kick_input(delta)
	_update_pending_shot(delta)
	if _player != null:
		skill.physics_tick(delta)
	_update_shielding(delta)
	_update_dribbling(delta)
	_update_state_hold(delta)
	_update_action_state()


# --- Plan §5 reusable queries ------------------------------------------------

## True when a clean interaction window exists right now (distance + height +
## ball tracked). The single "can trap / kick / shoot?" boolean.
func can_interact_with_ball() -> bool:
	return ball_detector.is_interaction_available()


## Offset from the player's origin to the ball in the player's LOCAL frame
## (+x = right, −z = forward, +y = up). ZERO when no ball is tracked.
func get_ball_relative_position() -> Vector3:
	var ball := get_tracked_ball()
	if ball == null or _player == null:
		return Vector3.ZERO
	var offset := ball.global_position - _player.global_position
	return _player.global_transform.basis.inverse() * offset


## Distance from the player to the tracked ball's centre (0 when none).
func get_ball_distance() -> float:
	return ball_detector.get_distance_to_ball()


## The player's current kick/aim direction (planar): the active movement input
## direction (camera-relative when a camera exists, world axes otherwise) if
## a direction is held, otherwise the last movement intent, otherwise the
## player's current facing. ZERO only in degenerate setups.
func get_kick_direction() -> Vector3:
	if intent.aim != Vector2.ZERO:
		return _input_to_world_dir(intent.aim)
	var input := intent.move_vector()
	if input != Vector2.ZERO:
		_last_aim = _input_to_world_dir(input)
	if _last_aim != Vector3.ZERO:
		return _last_aim
	if _player != null:
		var facing := -_player.global_transform.basis.z
		facing.y = 0.0
		if facing.length_squared() > DEGENERATE_DIR_EPSILON:
			return facing.normalized()
	return Vector3.ZERO


## Snapshot of what each action can do right now (UI + tests read this).
func get_action_availability() -> Dictionary:
	return {
		&"ball_nearby": ball_detector.is_ball_nearby(),
		&"interact": can_interact_with_ball(),
		&"pass": _can_execute(ACTION_PASS),
		&"shoot": _can_execute(ACTION_SHOOT),
		&"lob": _can_execute(ACTION_LOB),
		&"through": _can_execute(ACTION_THROUGH),
		&"cross": _can_execute(ACTION_CROSS),
		&"dribble": get_tracked_ball() != null and _state_hold <= 0.0,
	}


## The currently tracked (nearest) ball, or null.
func get_tracked_ball() -> BallController:
	return ball_detector.get_current_ball() as BallController


func get_action_state_name() -> String:
	match action_state:
		ActionState.IDLE: return "IDLE"
		ActionState.RECEIVING: return "RECEIVING"
		ActionState.PASSING: return "PASSING"
		ActionState.SHOOTING: return "SHOOTING"
		ActionState.LOB_PASSING: return "LOB_PASSING"
		ActionState.DRIBBLING: return "DRIBBLING"
	return "UNKNOWN"


## True while any kick (pass, shot, lob, through ball, cross) is being charged.
func is_charging() -> bool:
	for pair in _charge_pairs:
		if (pair[1] as KickPowerController).is_charging():
			return true
	return false


## Charge ratio (0..1) of an action's power controller, for UI.
func get_charge_ratio(action: StringName) -> float:
	return _charge_ratios.get(action, 0.0)


# --- Input & charging ----------------------------------------------------------

func _handle_kick_input(delta: float) -> void:
	# Start charging (mutually exclusive: one kick action at a time).
	var any_charging := _pass_charge.is_charging() or _shoot_charge.is_charging() \
			or _lob_charge.is_charging() or _through_charge.is_charging() \
			or _cross_charge.is_charging()
	if not any_charging:
		if intent.just_pressed(ACTION_PASS) and _can_execute(ACTION_PASS):
			_pass_charge.start()
		elif intent.just_pressed(ACTION_SHOOT) and _can_execute(ACTION_SHOOT):
			_shoot_charge.start()
		elif intent.just_pressed(ACTION_LOB) and _can_execute(ACTION_LOB):
			_lob_charge.start()
		elif intent.just_pressed(ACTION_THROUGH) and _can_execute(ACTION_THROUGH):
			_through_charge.start()
		elif intent.just_pressed(ACTION_CROSS) and _can_execute(ACTION_CROSS):
			_cross_charge.start()

	# Drive the charge clocks and publish ratios for the UI.
	for pair in _charge_pairs:
		var charge: KickPowerController = pair[1]
		var ratio: float = charge.update(delta)
		_charge_ratios[pair[0]] = ratio
		if charge.is_charging():
			charge_changed.emit(pair[0], ratio)

	# Guard: a charge whose interaction window disappears is cancelled.
	if _pass_charge.is_charging() and not _can_execute(ACTION_PASS):
		_pass_charge.cancel()
		_emit_charge_zero(&"pass")
	if _shoot_charge.is_charging() and not _can_execute(ACTION_SHOOT):
		_shoot_charge.cancel()
		_emit_charge_zero(&"shoot")
	if _lob_charge.is_charging() and not _can_execute(ACTION_LOB):
		_lob_charge.cancel()
		_emit_charge_zero(&"lob")
	if _through_charge.is_charging() and not _can_execute(ACTION_THROUGH):
		_through_charge.cancel()
		_emit_charge_zero(&"through")
	if _cross_charge.is_charging() and not _can_execute(ACTION_CROSS):
		_cross_charge.cancel()
		_emit_charge_zero(&"cross")

	# Release executes the action.
	if _pass_charge.is_charging() and intent.just_released(ACTION_PASS):
		var ratio := _pass_charge.get_ratio()
		_execute_pass(_hinted(_pass_charge.release()), ratio)
		_emit_charge_zero(&"pass")
	if _shoot_charge.is_charging() and intent.just_released(ACTION_SHOOT):
		var ratio := _shoot_charge.get_ratio()
		_execute_shot(_shoot_charge.release(), ratio)
		_emit_charge_zero(&"shoot")
	if _lob_charge.is_charging() and intent.just_released(ACTION_LOB):
		var ratio := _lob_charge.get_ratio()
		_execute_lob(_hinted(_lob_charge.release()), ratio)
		_emit_charge_zero(&"lob")
	if _through_charge.is_charging() and intent.just_released(ACTION_THROUGH):
		var ratio := _through_charge.get_ratio()
		_execute_through(_hinted(_through_charge.release()), ratio)
		_emit_charge_zero(&"through")
	if _cross_charge.is_charging() and intent.just_released(ACTION_CROSS):
		var ratio := _cross_charge.get_ratio()
		_execute_cross(_hinted(_cross_charge.release()), ratio)
		_emit_charge_zero(&"cross")


## Publishes the final zero ratio after a release or a cancel so signal-driven
## UI bars don't stay stuck at the last charge value.
## The intent's power override, when set (AI), else the charged power.
func _hinted(power: float) -> float:
	return intent.kick_power if intent.kick_power > 0.0 else power


func _emit_charge_zero(action: StringName) -> void:
	_charge_ratios[action] = 0.0
	charge_changed.emit(action, 0.0)


func _can_execute(action: String) -> bool:
	if _state_hold > 0.0:  # a kick is currently in its transient state
		return false
	if not _pending_shot.is_empty():
		return false
	if skill != null and not skill.kick_allowed():     # Phase 2: no kick in the middle of a skill move (exit phase: yes)
		return false
	match action:
		ACTION_PASS:
			return can_interact_with_ball() and _pass_cooldown <= 0.0
		ACTION_SHOOT:
			return (can_interact_with_ball() or volley_reachable()) and _shoot_cooldown <= 0.0
		ACTION_LOB:
			return can_interact_with_ball() and _lob_cooldown <= 0.0
		ACTION_THROUGH:
			return can_interact_with_ball() and _through_cooldown <= 0.0
		ACTION_CROSS:
			return can_interact_with_ball() and _cross_cooldown <= 0.0
	return false


# --- Kick execution ------------------------------------------------------------

func _execute_pass(power: float, charge_ratio: float) -> void:
	var aim := get_kick_direction()
	last_pass_target = Vector3.INF
	if aim_assist != null and intent.kick_power <= 0.0:
		# Phase M1 (human): the stick picks the receiver (cone), the pass goes into his path and its pace fits the
		# distance; holding the button longer adds up to +35 % on top.
		var stick := intent.move_vector()
		var target := aim_assist.pass_target(_aim_origin(), _input_to_world_dir(stick) if stick != Vector2.ZERO else Vector3.ZERO)
		if not target.is_empty():
			last_pass_target = target["pos"]
			aim = _flat_dir_to(target["pos"])
			var dist := Vector2(last_pass_target.x - _aim_origin().x, last_pass_target.z - _aim_origin().z).length()
			power = clampf(assisted_pass_power(dist) * (1.0 + 0.35 * charge_ratio), config.min_pass_power, config.max_pass_power)
	if attribute_modifiers != null:
		power *= attribute_modifiers.pass_power_multiplier()
	var applied := _pass_system.execute_pass(get_tracked_ball(),
			_with_error(aim, attribute_modifiers.pass_error_degrees() if attribute_modifiers != null else 0.0),
			power, ball_detector.get_direction_to_ball(), config)
	if applied < 0.0:
		return
	_after_kick(ActionState.PASSING, config.pass_cooldown)
	pass_started.emit(applied)
	_play_kick_anim(&"pass")
	# charge_ratio kept for future power-scaled pass lift/fakes.


func _execute_shot(power: float, charge_ratio: float) -> void:
	var technique := current_shot_technique()
	var prof := ShotTechnique.profile(technique, attribute_modifiers)
	if float(prof["windup"]) > 0.0 and _pending_shot.is_empty():
		# Phase 2 power shot: the strike comes POWER_WINDUP s after the release; the ball can be taken meanwhile.
		_pending_shot = {"power": power, "ratio": charge_ratio, "technique": technique, "left": float(prof["windup"])}
		_play_kick_anim(&"shot")
		return
	_strike_shot(power, charge_ratio, technique)


## Phase 2: the technique of the shot being released: the AI's choice (intent), else the human modifiers held at the
## release (skill_move = finesse, shield = low driven, both = power).
func current_shot_technique() -> StringName:
	if intent.shot_technique != &"":
		return intent.shot_technique
	var sk := intent.is_pressed(ACTION_SKILL)
	var sh := intent.is_pressed(ACTION_SHIELD)
	if sk and sh:
		return ShotTechnique.POWER
	if sk:
		return ShotTechnique.FINESSE
	if sh:
		return ShotTechnique.LOW_DRIVEN
	return ShotTechnique.NORMAL


func _update_pending_shot(delta: float) -> void:
	if _pending_shot.is_empty():
		return
	_pending_shot["left"] = float(_pending_shot["left"]) - delta
	if float(_pending_shot["left"]) > 0.0:
		return
	var ps := _pending_shot
	_pending_shot = {}
	if not (can_interact_with_ball() or volley_reachable()):
		shot_log.append({"technique": ps["technique"], "context": &"lost_in_windup", "power": 0.0})
		return                                     # the ball was taken / ran away during the wind-up
	_strike_shot(float(ps["power"]), float(ps["ratio"]), ps["technique"])


## The strike of a shot with a technique and the context of the ball (Phase 2). Normal ground shots keep the Phase 4
## numbers except for the weak foot and balance, which now count for every shot.
func _strike_shot(power: float, charge_ratio: float, technique: StringName) -> void:
	var ball := get_tracked_ball()
	if ball == null:
		return
	var mods := attribute_modifiers
	var prof := ShotTechnique.profile(technique, mods)
	var height := ball.global_position.y - ball.config.radius
	var pv := _player.velocity if _player != null else Vector3.ZERO
	var context := ShotTechnique.context_of(height, ball.linear_velocity, pv, _clock - _ground_at, _dribbling or _receiving)
	var rel := Vector3(ball.linear_velocity.x - pv.x, 0.0, ball.linear_velocity.z - pv.z).length()
	var ce := ShotTechnique.context_effect(context, mods, height, rel)
	var foot_q := mods.foot_quality(_ball_side(ball)) if mods != null else 1.0
	if mods != null:
		power *= mods.shot_power_multiplier()
	power *= float(prof["power"]) * float(ce["power"]) * (0.85 + 0.15 * foot_q)
	var spread := shot_spread_degrees(charge_ratio) * float(prof["error"]) * float(ce["error"]) / pow(foot_q, 1.5)
	if _player != null and _player.is_off_balance():
		spread *= 1.4
	var lift := lerpf(config.min_shot_lift, config.max_shot_lift, charge_ratio) * float(prof["lift"]) + float(ce["lift_add"])
	var aim := get_kick_direction()
	var spin := 0.0
	if technique == ShotTechnique.CHIP:
		var dist := _goal_distance()
		var ck := ShotTechnique.chip_kick(dist if dist > 0.0 else 18.0)
		power = float(ck["power"])
		lift = float(ck["lift"])
	elif technique == ShotTechnique.FINESSE:
		var bend := 0.0
		var g := _goals()
		if not g.is_empty() and _player != null:
			var to_goal := Vector3(g[0].x - _player.global_position.x, 0.0, g[0].z - _player.global_position.z)
			bend = signf(aim.cross(to_goal).y)
		spin = ShotTechnique.curl_sign(mods, bend) * float(prof["spin"])
	elif technique == ShotTechnique.LOW_DRIVEN:
		lift = 0.15 + maxf(float(ce["lift_add"]), 0.0)
	lift = maxf(lift, 0.0)
	var dir := _with_error(aim, spread)
	if spin != 0.0:
		var d := _goal_distance()
		dir = dir.rotated(Vector3.UP, ShotTechnique.curl_compensation(spin, d if d > 0.0 else 18.0, power, ball.config.magnus_coefficient))
	var applied := _shoot_system.execute_shot_ex(ball, dir, power, lift, spin, ball_detector.get_direction_to_ball(), config,
			technique == ShotTechnique.CHIP)
	if applied < 0.0:
		return
	shot_log.append({"technique": technique, "context": context, "power": applied, "lift": lift, "spin": spin,
			"spread": spread, "foot_q": foot_q})
	_after_kick(ActionState.SHOOTING, config.shoot_cooldown)
	shot_started.emit(applied, lift)
	shot_technique_used.emit(technique, context)
	if technique != ShotTechnique.POWER:
		_play_kick_anim(&"shot")


## +1 when the ball is on the player's right (struck with the right foot), -1 left, 0 straight in front.
func _ball_side(ball: BallController) -> float:
	if _player == null:
		return 0.0
	var local := _player.global_transform.basis.inverse() * (ball.global_position - _player.global_position)
	return 0.0 if absf(local.x) < 0.08 else signf(local.x)


## Phase 2 volley gate: a shot can be struck at a ball in the air up to ShotTechnique.VOLLEY_MAX_HEIGHT (the normal
## interaction window ends at the detector's height gate).
func volley_reachable() -> bool:
	var ball := get_tracked_ball()
	if ball == null or _player == null:
		return false
	var off := ball.global_position - _player.global_position
	return Vector2(off.x, off.z).length() <= ball_detector.interaction_distance + 0.05 \
			and off.y > ball_detector.max_interaction_height and off.y <= ShotTechnique.VOLLEY_MAX_HEIGHT + ball.config.radius


func _goals() -> Array:
	if goals.is_valid():
		return goals.call()
	return []


func _goal_distance() -> float:
	var g := _goals()
	if g.is_empty() or _player == null:
		return -1.0
	return Vector2(g[0].x - _player.global_position.x, g[0].z - _player.global_position.z).length()


func _threat() -> Vector3:
	if nearest_opponent.is_valid() and _player != null:
		return nearest_opponent.call(_player.global_position)
	return Vector3.INF


func _track_bounce() -> void:
	var ball := get_tracked_ball()
	if ball != null and ball.global_position.y <= ball.config.radius + 0.04:
		_ground_at = _clock


## Rotates a planar direction by a random error of up to `max_degrees`.
## Phase M2: the +- spread of a shot in degrees (see `BallActionConfig.shot_base_error`).
func shot_spread_degrees(charge_ratio: float) -> float:
	var deg := config.shot_base_error + (attribute_modifiers.shot_error_degrees() if attribute_modifiers != null else 0.0)
	deg *= 1.0 + config.shot_charge_error * clampf(charge_ratio, 0.0, 1.0)
	if aim_assist != null and _player != null and is_instance_valid(_player):
		var q := aim_assist.pressure_quality(_player.global_position)          # 1.0 free .. 0.8 tightly marked
		deg *= 1.0 + config.shot_pressure_error * (1.0 - q) / 0.2
	return deg


## Pace of an assisted ground pass over `dist` metres (same rule as the AI: arrives at about 5.5 m/s).
static func assisted_pass_power(dist: float) -> float:
	return clampf(5.5 + dist * 0.22, 6.0, 16.0)


func _with_error(dir: Vector3, max_degrees: float) -> Vector3:
	if max_degrees <= 0.0 or dir == Vector3.ZERO:
		return dir
	return dir.rotated(Vector3.UP, deg_to_rad(randf_range(-max_degrees, max_degrees)))


func _execute_lob(power: float, charge_ratio: float) -> void:
	if intent.is_pressed(ACTION_SKILL) and intent.shot_technique == &"":
		# Phase 2: skill_move held + lob = chip shot (through the shot pipeline: technique CHIP, shot statistics).
		_strike_shot(config.default_shoot_power, charge_ratio, ShotTechnique.CHIP)
		return
	var lift := config.lob_lift
	var applied := _lob_system.execute_lob(get_tracked_ball(), get_kick_direction(),
			power, ball_detector.get_direction_to_ball())
	if applied < 0.0:
		return
	_after_kick(ActionState.LOB_PASSING, config.lob_cooldown)
	lob_started.emit(applied, lift)
	_play_kick_anim(&"lob")


## Human through pass (P3): a pass-family kick aimed into a team-mate's run.
## The `HumanAimAssist` (wired by the MatchManager) picks the most goal-advanced
## team-mate inside the human's aim cone and aims at `PlayerAI.lead_point` —
## the exact logic the AI uses. Without an assist (or with no candidate) it
## degrades to a plain directional pass, so the action is always safe.
func _execute_through(power: float, charge_ratio: float) -> void:
	if attribute_modifiers != null:
		power *= attribute_modifiers.pass_power_multiplier()
	var aim := get_kick_direction()
	if aim_assist != null:
		var target := aim_assist.through_target(_aim_origin(), aim)
		if target != Vector3.INF:
			aim = _flat_dir_to(target)
	var applied := _pass_system.execute_pass(get_tracked_ball(),
			_with_error(aim, attribute_modifiers.pass_error_degrees() if attribute_modifiers != null else 0.0),
			power, ball_detector.get_direction_to_ball(), config)
	if applied < 0.0:
		return
	_after_kick(ActionState.PASSING, config.through_cooldown, &"through")
	through_started.emit(applied)
	_play_kick_anim(&"pass")


## Human cross (P3): a lob-family kick into the opponent box, aimed by
## `PlayerAI.cross_target` through the assist (free team-mate in the box),
## falling back to the plain lob direction when nobody is free.
func _execute_cross(power: float, charge_ratio: float) -> void:
	var lift := config.lob_lift
	if attribute_modifiers != null:
		# A cross is a passing action in attribute terms: the passing rating
		# scales its power (no dedicated lob multiplier exists in Phase T2).
		power *= attribute_modifiers.pass_power_multiplier()
	var aim := get_kick_direction()
	if aim_assist != null:
		var target := aim_assist.cross_target_for(_aim_origin())
		if target != Vector3.INF:
			aim = _flat_dir_to(target)
	var applied := _lob_system.execute_lob(get_tracked_ball(),
			_with_error(aim, attribute_modifiers.pass_error_degrees() if attribute_modifiers != null else 0.0),
			power, ball_detector.get_direction_to_ball())
	if applied < 0.0:
		return
	_after_kick(ActionState.LOB_PASSING, config.cross_cooldown, &"cross")
	cross_started.emit(applied, lift)
	_play_kick_anim(&"lob")


## The assist works in world coordinates: the kicker's position.
func _aim_origin() -> Vector3:
	if _player != null and is_instance_valid(_player):
		return _player.global_position
	return global_position


## Planar normalized direction from the kicker to a world target.
func _flat_dir_to(target: Vector3) -> Vector3:
	var rel := target - _aim_origin()
	rel.y = 0.0
	return rel.normalized() if rel.length_squared() > 0.0001 else get_kick_direction()


func _after_kick(state: ActionState, cooldown: float, kind: StringName = &"") -> void:
	_ignore_own_ball()
	_transient_state = state
	_state_hold = config.state_hold
	# A kick interrupts reception/dribble control immediately.
	_receiving = false
	_set_dribbling(false)
	if skill != null:
		skill.end_by_kick()
	if shielding != null and shielding.is_active():
		shielding.release()
	match kind:
		&"through":
			_through_cooldown = cooldown
		&"cross":
			_cross_cooldown = cooldown
		_:
			match state:
				ActionState.PASSING: _pass_cooldown = cooldown
				ActionState.SHOOTING: _shoot_cooldown = cooldown
				ActionState.LOB_PASSING: _lob_cooldown = cooldown


## Animation integration point (plan §14): the character visual already
## reserves `play_kick()`. Gameplay is fully independent of this succeeding.
func _ignore_own_ball() -> void:
	var ball := get_tracked_ball()
	if ball == null or _player == null:
		return
	if _excepted_ball != null and is_instance_valid(_excepted_ball) and _excepted_ball != ball:
		_player.remove_collision_exception_with(_excepted_ball)
	_player.add_collision_exception_with(ball)
	_excepted_ball = ball
	_self_exception_left = SELF_EXCEPTION_TIME


func _update_self_exception(delta: float) -> void:
	if _self_exception_left <= 0.0:
		return
	_self_exception_left -= delta
	if _self_exception_left <= 0.0:
		if _excepted_ball != null and is_instance_valid(_excepted_ball) and _player != null:
			_player.remove_collision_exception_with(_excepted_ball)
		_excepted_ball = null


func _play_kick_anim(kind: StringName = &"Kick") -> void:
	var visual := _visual()
	if visual != null and visual.has_method("play_kick"):
		visual.play_kick(kind)


func _visual() -> Node:
	if _player == null or not is_instance_valid(_player):
		return null
	return _player.get_node_or_null("VisualRoot")


# --- Dribbling -----------------------------------------------------------------

func _update_dribbling(_delta: float) -> void:
	if skill != null and skill.is_active():
		# Phase 2: during a skill move the touches move the ball; between them the spring keeps it close along the body's
		# own motion, never right after a touch (it would pull the ball back).
		var b := get_tracked_ball()
		if b != null and not skill.ball_free() and _player != null:
			var bv := Vector3(_player.velocity.x, 0.0, _player.velocity.z)
			_dribble_system.physics_tick(b, _player, bv if bv.length() > 0.5 else Vector3.ZERO,
					_player.get_current_speed(), false, config)
		_set_dribbling(b != null)
		return
	if shielding != null and shielding.is_active():
		_set_dribbling(false)
		return
	if _state_hold > 0.0 or _receiving \
			or not intent.is_pressed(ACTION_DRIBBLE):
		_set_dribbling(false)
		return
	var ball := get_tracked_ball()
	if ball == null:
		_set_dribbling(false)
		return
	# Raw movement input as the carry direction (ZERO when standing still →
	# the dribbling system holds the ball close instead of shoving it along
	# the last aim). `get_kick_direction()` stays kick-only.
	var carry := _input_to_world_dir(intent.move_vector())
	var engaged := _dribble_system.physics_tick(ball, _player, carry,
			_player.get_current_speed() if _player != null else 0.0,
			intent.is_pressed(ACTION_SPRINT), config)
	_set_dribbling(engaged)


func _set_dribbling(value: bool) -> void:
	if _dribbling == value:
		return
	_dribbling = value
	if _player != null:
		_player.with_ball = value
	var vis := _visual()
	if vis != null and vis.has_method("set_dribbling"):
		vis.set_dribbling(value)
	if _dribbling:
		dribble_started.emit()
	else:
		dribble_stopped.emit()


# --- Reception -----------------------------------------------------------------

func _update_reception(_delta: float) -> void:
	var ball := get_tracked_ball()
	if ball == null:
		_set_receiving(false)
		return

	if _receiving:
		var speed := _control_system.physics_tick(ball, _player, config,
				_reception_quality())
		var offset := _player.global_position - ball.global_position
		var planar := Vector3(offset.x, 0.0, offset.z)
		if speed < config.reception_complete_speed:
			_set_receiving(false)
			ball_received.emit(speed)
			var vis := _visual()
			if vis != null and vis.has_method("play_reaction"):
				vis.play_reaction("FirstTouch")
		elif planar.length() > config.reception_escape_distance:
			_set_receiving(false)  # ball escaped the control radius
		return

	# Trigger: an approaching ball near the player while no kick is busy. Phase M3: never while he dribbles it — a
	# dribbled ball "approaches" its player in every turn, and reception switched the dribble off (ball lost).
	if action_state != ActionState.IDLE:
		return
	var vel := Vector3(ball.linear_velocity.x, 0.0, ball.linear_velocity.z)
	var speed := vel.length()
	if speed < config.reception_trigger_speed:
		return
	var offset := _player.global_position - ball.global_position
	var planar := Vector3(offset.x, 0.0, offset.z)
	if planar.length() > config.reception_distance:
		return
	# Phase 2 fix: `offset` is player - ball, so a ball ABOVE the player has a negative y and the old check
	# (`offset.y > max_control_height`) never rejected it: every high ball passing within 1.4 m was braked by the
	# reception force in mid-air (measured 9 -> 5 m/s over a player's head, which also spoiled headers).
	if -offset.y > config.max_control_height:
		return
	if vel.normalized().dot(planar.normalized()) <= 0.0:
		return  # moving away from the player
	_set_receiving(true)


func _set_receiving(value: bool) -> void:
	if _receiving == value:
		return
	_receiving = value


## P3 first-touch quality: the dribbling rating scales the control force and
## opponent pressure degrades it (1.0 when neither applies).
func _reception_quality() -> float:
	var quality := 1.0
	if attribute_modifiers != null:
		quality *= attribute_modifiers.control_multiplier()
	if aim_assist != null and _player != null and is_instance_valid(_player):
		quality *= aim_assist.pressure_quality(_player.global_position)
	return quality


# --- State machine (derived each tick — lockup-proof) ----------------------------

func _update_cooldowns(delta: float) -> void:
	_pass_cooldown = maxf(_pass_cooldown - delta, 0.0)
	_shoot_cooldown = maxf(_shoot_cooldown - delta, 0.0)
	_lob_cooldown = maxf(_lob_cooldown - delta, 0.0)
	_through_cooldown = maxf(_through_cooldown - delta, 0.0)
	_cross_cooldown = maxf(_cross_cooldown - delta, 0.0)


func _update_state_hold(delta: float) -> void:
	if _state_hold <= 0.0:
		return
	_state_hold = maxf(_state_hold - delta, 0.0)
	if _state_hold == 0.0:
		_emit_transient_completed()


func _emit_transient_completed() -> void:
	match _transient_state:
		ActionState.PASSING:
			pass_completed.emit()
		ActionState.SHOOTING:
			shot_completed.emit()
		ActionState.LOB_PASSING:
			pass  # plan §14 defines no lob_completed
		_:
			pass


func _update_action_state() -> void:
	var new_state := ActionState.IDLE
	if _state_hold > 0.0:
		new_state = _transient_state
	elif _receiving:
		new_state = ActionState.RECEIVING
	elif _dribbling:
		new_state = ActionState.DRIBBLING
	if new_state != action_state:
		action_state = new_state
		action_state_changed.emit(new_state)


# --- Aim helper (mirrors the Phase 2 controller's mapping) ----------------------

func _input_to_world_dir(input: Vector2) -> Vector3:
	if input == Vector2.ZERO:
		return Vector3.ZERO
	if intent.world_space:
		return Vector3(input.x, 0.0, input.y)
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		var basis := camera.global_transform.basis
		var forward := -basis.z
		var right := basis.x
		forward.y = 0.0
		right.y = 0.0
		if forward.length_squared() > DEGENERATE_DIR_EPSILON \
				and right.length_squared() > DEGENERATE_DIR_EPSILON:
			return (right.normalized() * input.x
					- forward.normalized() * input.y)
	# No camera (or fully vertical basis): world axes — forward is −Z.
	return Vector3(input.x, 0.0, input.y)


# --- Phase 2: skill moves, shielding, headers -------------------------------------------------------------------

## Skill-move input. Human: a `skill_move` tap starts the move the stick asks for (SkillMoveCatalog.INPUT_TABLE); a
## second tap within DOUBLE_TAP s turns a move that has not touched the ball yet into its double-tap variant; a tap
## while a pass / shot charges cancels the kick into a fake pass / fake shot. AI: `intent.skill_request`.
## Returns true when it consumed this tick's input.
func _handle_skill_input() -> bool:
	if _player == null or skill == null:
		return false
	var ball := get_tracked_ball()
	var requested := intent.skill_request
	var side := intent.skill_side
	intent.skill_request = &""
	if requested == &"":
		if not intent.just_pressed(ACTION_SKILL):
			return false
		if _shoot_charge.is_charging() or _pass_charge.is_charging():
			requested = &"fake_shot" if _shoot_charge.is_charging() else &"fake_pass"
			_shoot_charge.cancel()
			_pass_charge.cancel()
			_emit_charge_zero(&"shoot")
			_emit_charge_zero(&"pass")
			side = _local_stick().x
		else:
			var tap := 2 if intent.is_pressed(ACTION_SPRINT) else 0
			if _clock - _skill_pressed_at <= SkillMoveCatalog.DOUBLE_TAP and skill.can_upgrade():
				tap = 1
				skill.discard()
			_skill_pressed_at = _clock
			var pick := SkillMoveCatalog.move_for_input(_local_stick(), tap, _player.get_current_speed())
			requested = pick[0]
			side = pick[1]
	if ball == null or not _ball_at_feet(ball):
		return false
	if skill.start(requested, side, _player, ball, attribute_modifiers, _threat()):
		_receiving = false
		return true
	return false


## The stick in the player's own frame (x = right, y = forward).
func _local_stick() -> Vector2:
	var world := _input_to_world_dir(intent.move_vector())
	if world == Vector3.ZERO or _player == null:
		return Vector2.ZERO
	var f := -_player.global_transform.basis.z
	f.y = 0.0
	f = f.normalized()
	var r := f.cross(Vector3.UP).normalized()
	return Vector2(world.dot(r), world.dot(f))


func _ball_at_feet(ball: BallController) -> bool:
	var off := ball.global_position - _player.global_position
	return Vector2(off.x, off.z).length() <= config.dribble_distance and off.y <= SkillMoveSystem.TOUCH_HEIGHT


## Shielding while `shield` is held and the ball is close (not during a skill move or a kick).
func _update_shielding(_delta: float) -> void:
	if shielding == null or _player == null:
		return
	var want := intent.is_pressed(ACTION_SHIELD) and _state_hold <= 0.0 and _pending_shot.is_empty() \
			and not (skill != null and skill.is_active()) and not _any_charging()
	var on := false
	if want:
		var ball := get_tracked_ball()
		if ball != null:
			var carry := _input_to_world_dir(intent.move_vector())
			on = shielding.physics_tick(ball, _player, _threat(), carry, attribute_modifiers, _let_run(ball, carry))
	elif shielding.is_active():
		shielding.release()
	if on != _shield_was:
		_shield_was = on
		shield_changed.emit(on)


func _any_charging() -> bool:
	for pair in _charge_pairs:
		if (pair[1] as KickPowerController).is_charging():
			return true
	return false


## Near a touch / goal line with the ball running out and no stick input: only screen it, do not touch it.
func _let_run(ball: BallController, carry: Vector3) -> bool:
	if carry != Vector3.ZERO:
		return false
	var p := ball.global_position
	var v := ball.linear_velocity
	var hx := FootballPitch.PITCH_WIDTH * 0.5
	var hz := FootballPitch.PITCH_LENGTH * 0.5
	var out_x := absf(p.x) > hx - 2.5 and signf(v.x) == signf(p.x) and absf(v.x) > 0.6
	var out_z := absf(p.z) > hz - 2.5 and signf(v.z) == signf(p.z) and absf(v.z) > 0.6
	return out_x or out_z


## Header window + header requests (shoot = header shot, pass / through = header pass, lob / cross = clearance).
## Returns true when a press was used for a header this tick.
func _update_header(delta: float) -> bool:
	if header == null or _player == null:
		return false
	var g := _goals()
	if not g.is_empty():
		header.goal_hint = g[0]
		header.own_goal_hint = g[1]
	header.physics_tick(delta, _player, attribute_modifiers)
	if not header.window_open() or header.has_request():
		return false
	var kind: StringName = &""
	if intent.just_pressed(ACTION_SHOOT):
		kind = HeaderSystem.SHOT
	elif intent.just_pressed(ACTION_PASS) or intent.just_pressed(ACTION_THROUGH):
		kind = HeaderSystem.PASS
	elif intent.just_pressed(ACTION_LOB) or intent.just_pressed(ACTION_CROSS):
		kind = HeaderSystem.CLEAR
	if kind == &"":
		return false
	var aim := _input_to_world_dir(intent.aim) if intent.aim != Vector2.ZERO else _input_to_world_dir(intent.move_vector())
	return header.request(kind, aim)


func _play_skill_clip(id: StringName) -> void:
	var vis := _visual()
	if vis == null or not vis.has_method("play_move"):
		return
	var clip: String = SkillMoveCatalog.get_move(id).get("clip", "")
	if clip == "TurnSide":
		clip = "TurnRight" if skill.exit_side() > 0.0 else "TurnLeft"
	if clip == "Shoot" or clip == "Pass":
		vis.play_move(clip, 0.22)                    # the wind-up only: the kick never comes
	elif clip != "":
		vis.play_move(clip)


# --- Setup ---------------------------------------------------------------------

func _build_subsystems() -> void:
	_pass_system = PassingSystem.new()
	_pass_system.name = "PassingSystem"
	_shoot_system = ShootingSystem.new()
	_shoot_system.name = "ShootingSystem"
	_lob_system = LobPassSystem.new()
	_lob_system.name = "LobPassSystem"
	_lob_system.config = config
	_dribble_system = DribblingSystem.new()
	_dribble_system.name = "DribblingSystem"
	_control_system = BallControlSystem.new()
	_control_system.name = "BallControlSystem"
	skill = SkillMoveSystem.new()
	skill.name = "SkillMoveSystem"
	shielding = ShieldingSystem.new()
	shielding.name = "ShieldingSystem"
	header = HeaderSystem.new()
	header.name = "HeaderSystem"
	for node: Node in [_pass_system, _shoot_system, _lob_system, _dribble_system, _control_system, skill, shielding, header]:
		add_child(node)
	skill.started.connect(func(id: StringName, _exit: Vector3, q: float) -> void:
		skill_move_started.emit(id, q)
		_play_skill_clip(id))
	skill.finished.connect(func(id: StringName, clean: bool) -> void: skill_move_finished.emit(id, clean))
	skill.feint.connect(func(kind: StringName, d: Vector3, st: float) -> void: feint_shown.emit(kind, d, st))
	header.header_played.connect(func(kind: StringName, sp: float, q: float) -> void:
		header_played.emit(kind, sp, q)
		_ignore_own_ball())
	header.header_started.connect(func(_k: StringName) -> void:
		var vis := _visual()
		if vis != null and vis.has_method("play_move"):
			vis.play_move("Header"))

	_pass_charge = _make_charge(config.min_pass_power, config.max_pass_power,
			config.default_pass_power)
	_pass_charge.name = "PassCharge"
	_shoot_charge = _make_charge(config.min_shoot_power, config.max_shoot_power,
			config.default_shoot_power)
	_shoot_charge.name = "ShootCharge"
	_lob_charge = _make_charge(config.min_lob_power, config.max_lob_power,
			config.default_lob_power)
	_lob_charge.name = "LobCharge"
	# P3 human actions: a through pass is a ground pass family kick (pass power
	# range), a cross is a lob family kick (lob power range).
	_through_charge = _make_charge(config.min_pass_power, config.max_pass_power,
			config.default_pass_power)
	_through_charge.name = "ThroughCharge"
	_cross_charge = _make_charge(config.min_lob_power, config.max_lob_power,
			config.default_lob_power)
	_cross_charge.name = "CrossCharge"

	_charge_pairs = [[&"pass", _pass_charge], [&"shoot", _shoot_charge],
			[&"lob", _lob_charge], [&"through", _through_charge],
			[&"cross", _cross_charge]]


func _make_charge(minimum: float, maximum: float, default_power: float) -> KickPowerController:
	var charge := KickPowerController.new()
	charge.min_power = minimum
	charge.max_power = maximum
	charge.default_power = default_power
	charge.charge_time = config.charge_time
	charge.quick_tap_threshold = config.quick_tap_threshold
	add_child(charge)
	return charge
