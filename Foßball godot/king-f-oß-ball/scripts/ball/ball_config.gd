class_name BallConfig
extends Resource

## Inspector-tunable configuration for the football ball (Phase 3).
## Mirrors the PlayerConfig / CameraConfig resource pattern; the project defaults
## live in `resources/configurations/ball_config.tres` and any ball instance can
## point at its own copy through the `config` export on `BallController`.
##
## Values are tuned for arcade + simulation football gameplay on the Jolt physics
## engine — not for real-world physical perfection. All numbers below were set
## after headless validation (tests/phase3_validation.tscn); see BALL_PHYSICS.md.

@export_group("Dimensions & Mass")
## Ball radius in metres (FIFA size 5 ≈ 0.11 m).
@export_range(0.05, 0.5, 0.005) var radius: float = 0.11
## Ball mass in kilograms (regulation ball ≈ 0.43 kg).
@export_range(0.05, 5.0, 0.005) var mass: float = 0.43

@export_group("Damping")
## Linear (air/rolling) damping in 1/s — how fast the ball loses speed overall.
## Kept low so kicks carry momentum naturally; ground decel comes mostly from
## the friction phase + settle ramp (validated in tests/phase3_validation.tscn).
@export_range(0.0, 5.0, 0.05) var linear_damping: float = 0.15
## Angular damping in 1/s — spin decay while airborne and while rolling
## (rolling decel = linear + angular damping via the friction coupling).
@export_range(0.0, 10.0, 0.05) var angular_damping: float = 0.5

@export_group("Ground Contact")
## Friction coefficient used in the ball's PhysicsMaterial. Jolt combines it
## multiplicatively with the pitch surface, so the sliding-phase deceleration
## is ≈ friction·g — keep it moderate so long passes still carry.
@export_range(0.0, 2.0, 0.05) var friction: float = 0.45
## Bounce restitution 0..1 — energy fraction kept by each bounce (vertical
## bounce apex scales by bounce² each impact). Damped enough to settle quickly.
@export_range(0.0, 1.0, 0.05) var bounce: float = 0.55

@export_group("Behaviour Limits")
## Hard speed ceiling in m/s. Real shots reach ~30 m/s; the ceiling prevents
## solver explosions from stacking impulses while staying realistic.
@export_range(1.0, 120.0, 0.5) var max_ball_speed: float = 30.0
## Below this horizontal speed (m/s) while touching the ground, the rolling
## friction "settle" ramp engages so the ball stops cleanly instead of creeping.
@export_range(0.0, 2.0, 0.01) var settle_speed: float = 0.45
## Default reset height used by `BallController.reset_ball()` without arguments.
@export_range(0.2, 10.0, 0.1) var reset_height: float = 0.5

@export_group("Gravity")
## Gravity multiplier for the ball (1.0 = project gravity, Jolt default 9.8 m/s²).
@export_range(0.1, 3.0, 0.05) var gravity_scale: float = 1.0

@export_group("Stability")
## Continuous collision detection. Football shots reach ~30 m/s ≈ 0.5 m per
## physics step — larger than the ball diameter — so this is justified and
## prevents tunnelling through thin plates (verified in phase 3 validation).
@export var continuous_collision: bool = true
