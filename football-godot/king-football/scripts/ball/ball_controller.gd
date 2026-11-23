class_name BallController
extends RigidBody3D

## Reusable football ball (Phase 3) — real physics, no gameplay glue.
##
## Responsibilities, kept deliberately small:
##   - RigidBody3D behaviour configured from a `BallConfig` resource
##     (mass, damping, friction, bounce, gravity, speed ceiling, CCD).
##   -Velocity limiting + rolling "settle" ramp inside `_integrate_forces()`
##     — applied once per physics step, never as repeated impulses, and never
##     touching the transform directly during normal simulation.
##   - One-shot force/impulse interfaces used by the test scene now and by the
##     passing/shooting system in Phase 4: `apply_kick()`, `apply_impulse()`,
##     `apply_force()`, `reset_ball()`, `stop_ball()`.
##   - Read-only queries: `get_ball_speed()`, `get_ball_direction()`.
##
## Deliberately NOT implemented here: possession, dribbling, pass/shoot
## gameplay, goal detection, team logic. The interfaces above are exactly the
## integration points documented in docs/archive/PHASE_4_HANDOFF.md.

signal kicked(speed: float)
## Emitted after a successful reset; `position` is the new spawn point.
signal ball_reset(position: Vector3)

const BALL_GROUP := "football_ball"

## Collision layer plan (see docs/archive/PHASE_3_AUDIT.md):
## layer 1 = World/Static (existing, incl. player body for now) → bit value 1,
## layer 3 = Ball → bit value 4.
const LAYER_WORLD_VALUE := 1
const LAYER_BALL_VALUE := 4

@export var config: BallConfig
## Debug visuals parented under `BallDebug` (development only, hidden by default).
@export var debug_enabled: bool = false:
	set(value):
		debug_enabled = value
		if _debug != null:
			_debug.debug_enabled = value

var _debug: BallDebug


func _ready() -> void:
	if config == null:
		config = BallConfig.new()
	add_to_group(BALL_GROUP)
	collision_layer = LAYER_BALL_VALUE
	collision_mask = LAYER_WORLD_VALUE + LAYER_BALL_VALUE
	_apply_config()
	_debug = get_node_or_null("BallDebug") as BallDebug
	if _debug != null:
		_debug.debug_enabled = debug_enabled


func _apply_config() -> void:
	mass = config.mass
	linear_damp = config.linear_damping
	angular_damp = config.angular_damping
	gravity_scale = config.gravity_scale
	continuous_cd = config.continuous_collision
	# Jolt only populates PhysicsDirectBodyState3D contact data (used by the
	# rolling settle ramp in `_integrate_forces`) when contact monitoring is on.
	contact_monitor = true
	max_contacts_reported = 8
	var material := PhysicsMaterial.new()
	material.friction = config.friction
	material.bounce = config.bounce
	physics_material_override = material

	var shape_node: CollisionShape3D = $CollisionShape3D
	if shape_node != null and shape_node.shape is SphereShape3D:
		(shape_node.shape as SphereShape3D).radius = config.radius


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var velocity := state.linear_velocity

	# Speed ceiling: one clamp per physics step, no impulses, keeps the solver
	# stable when something stacks forces or kicks.
	var speed := velocity.length()
	if speed > config.max_ball_speed:
		velocity = velocity * (config.max_ball_speed / speed)

	# Rolling settle ramp: while touching ground and already rolling slowly,
	# bleed horizontal speed quickly so the ball stops cleanly instead of
	# creeping for many seconds. Deterministic single-step filtering, no
	# collision-state misinterpretation at kick speeds.
	if state.get_contact_count() > 0:
		var planar := Vector3(velocity.x, 0.0, velocity.z)
		var planar_speed := planar.length()
		if planar_speed < config.settle_speed:
			var damped := planar * 0.82
			if damped.length() < 0.02:
				damped = Vector3.ZERO
			velocity.x = damped.x
			velocity.z = damped.z

	# Phase 2: sidespin curls the ball in flight (Magnus, vertical-axis spin only — see BallConfig.magnus_coefficient).
	elif config.magnus_coefficient > 0.0:
		var spin_y := state.angular_velocity.y
		if absf(spin_y) > 0.5:
			var planar_v := Vector3(velocity.x, 0.0, velocity.z)
			var curl := Vector3.UP.cross(planar_v) * (config.magnus_coefficient * spin_y)
			velocity += curl * state.step
			var av := state.angular_velocity
			av.y *= maxf(1.0 - config.spin_decay * state.step, 0.0)
			state.angular_velocity = av

	state.linear_velocity = velocity


## Phase 2: a kick with sidespin — `strike()` and then `spin_y` rad/s about the vertical axis (+ curls left of the
## travel direction, - right). Used by finesse shots and curled headers / passes.
func strike_with_spin(direction: Vector3, power: float, lift: float, spin_y: float, keep: float = 0.1) -> void:
	strike(direction, power, lift, keep)
	angular_velocity.y = spin_y


## Phase 2: sets the ball's velocity to `target` through one impulse (a header can send the ball DOWN, which
## `strike()` never does). Physical: the change goes through `apply_central_impulse`, the ball is never moved.
func redirect(target: Vector3, spin: Vector3 = Vector3.ZERO) -> void:
	if target.length() > config.max_ball_speed:
		target = target * (config.max_ball_speed / target.length())
	sleeping = false
	apply_central_impulse((target - linear_velocity) * mass)
	angular_velocity = spin
	kicked.emit(target.length())


# --- Kick & integration interfaces (Phase 4 entry points) ------------------

## Configurable kick: `direction` (any length, flattened), `power` (m/s of
## planned planar speed change, i.e. a mass-scaled impulse), `lift` (upward
## m/s boost) and optional `spin` (rad/s added to angular velocity).
## The resulting speed never exceeds `config.max_ball_speed`.
func apply_kick(direction: Vector3, power: float, lift: float = 0.0,
		spin: Vector3 = Vector3.ZERO) -> void:
	if direction.length_squared() < 0.0001:
		push_warning("BallController.apply_kick: zero-length direction ignored.")
		return
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.0001:
		flat = -global_transform.basis.z
	flat = flat.normalized()

	# Compute the target velocity up-front so the speed ceiling applies to the
	# actual result, not only to the impulse magnitude.
	var current := linear_velocity
	var target := current + flat * power + Vector3.UP * lift
	var target_speed := target.length()
	if target_speed > config.max_ball_speed:
		target = target * (config.max_ball_speed / target_speed)

	sleeping = false  # one-shot kick must wake a settled ball
	apply_central_impulse((target - current) * mass)
	if spin.length_squared() > 0.0:
		angular_velocity += spin
	kicked.emit(get_ball_speed())


## NOTE on the Phase 4 integration surface: `apply_impulse()` and
## `apply_force()` are used *inherited* from RigidBody3D — wrapping them in
## same-name GDScript overrides is forbidden by the engine's native-method
## override rule, and the inherited versions are the real physics interfaces.
## Two engine-level caveats gameplay code must respect:
##   1. They do not wake a sleeping ball; `apply_kick()` is the wake-safe
##      one-shot kick used for gameplay actions.
##   2. `apply_force()` is consumed after one physics step — a sustained push
##      (e.g. dribbling) re-applies it every physics tick.


## Teleports the ball safely (freeze cycle, no raw client/server writes while
## simulating) and clears all motion. Without arguments the ball returns to
## the centre spot slightly above the pitch.
## A foot strike (Phase M1): unlike `apply_kick` (which ADDS the change to the ball's velocity, right for nudges), a
## pass or shot replaces what the ball was doing — only `keep` (0..1) of its previous velocity survives the contact.
## Before this a pass played while dribbling at 6 m/s left the foot up to 35 degrees off its aim.
func strike(direction: Vector3, power: float, lift: float = 0.0, keep: float = 0.1) -> void:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.0001:
		push_warning("BallController.strike: zero-length direction ignored.")
		return
	flat = flat.normalized()
	var current := linear_velocity
	var target := current * clampf(keep, 0.0, 1.0) + flat * power + Vector3.UP * lift
	target.y = maxf(target.y, lift)
	if target.length() > config.max_ball_speed:
		target = target * (config.max_ball_speed / target.length())
	sleeping = false
	apply_central_impulse((target - current) * mass)
	# A struck ground ball rolls at once (topspin matching its speed): without it the ball slid off the foot and the
	# grass took half its speed in 0.75 s (measured 10 -> 5.3 m/s), so every pass died short of its man.
	var planar := Vector3(target.x, 0.0, target.z)
	if lift < 1.0:
		angular_velocity = Vector3.UP.cross(planar) / maxf(config.radius, 0.01)
	else:
		angular_velocity *= clampf(keep, 0.0, 1.0)
	kicked.emit(target.length())


func reset_ball(to_position: Vector3 = Vector3.INF) -> void:
	var target := to_position
	if target == Vector3.INF:
		target = Vector3(0.0, config.reset_height, 0.0)
	sleeping = false
	freeze = true   # static for one tick → safe teleport
	global_position = target
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = false
	ball_reset.emit(global_position)


## Stops all motion and lets the ball rest immediately (safe because it keeps
## gravity off while asleep — sleeping bodies do not fall).
func stop_ball() -> void:
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	sleeping = true


# --- Read-only queries ------------------------------------------------------

## Current speed in m/s.
func get_ball_speed() -> float:
	return linear_velocity.length()


## Normalized (3D) travel direction; ZERO when effectively at rest.
func get_ball_direction() -> Vector3:
	var speed := get_ball_speed()
	if speed < 0.05:
		return Vector3.ZERO
	return linear_velocity / speed
