class_name BallActionConfig
extends Resource

## Inspector-tunable configuration for the Phase 4 football gameplay systems
## (passing / shooting / lob / dribbling / reception / kick-power charging).
## Mirrors the PlayerConfig / BallConfig resource pattern: project defaults live
## in `resources/configurations/ball_action_config.tres` (which pins nothing —
## the values below are the defaults) and any `FootballActions` instance can
## point at its own copy through the `config` export.
##
## Powers are expressed in the same unit as `BallController.apply_kick()`
## "power": m/s of planned planar speed change. Lifts are upward m/s.

@export_group("Passing")
## Minimum ground-pass power (m/s speed change). Power floor after charging.
@export_range(0.5, 20.0, 0.5) var min_pass_power: float = 4.0
## Maximum ground-pass power.
@export_range(1.0, 40.0, 0.5) var max_pass_power: float = 16.0
## Power used by a quick tap (no meaningful charge time).
@export_range(0.5, 30.0, 0.5) var default_pass_power: float = 9.0
## Blend factor (0..1) between the player's intended direction and the
## direction toward the ball. 0 = pure intent, 1 = always kick exactly at the
## ball. Keeps directional passing responsive while making contact reliable.
@export_range(0.0, 1.0, 0.05) var pass_direction_adjustment: float = 0.35

@export_group("Shooting")
## Minimum shot power.
@export_range(1.0, 30.0, 0.5) var min_shoot_power: float = 10.0
## Maximum shot power (fully charged).
@export_range(1.0, 50.0, 0.5) var max_shoot_power: float = 26.0
## Power used by a quick tap.
@export_range(1.0, 40.0, 0.5) var default_shoot_power: float = 16.0
## Upward m/s applied by a quick (ground-ish) shot.
@export_range(0.0, 8.0, 0.1) var min_shot_lift: float = 0.3
## Upward m/s applied by a fully charged (elevated) shot.
@export_range(0.0, 10.0, 0.1) var max_shot_lift: float = 3.0
## Blend factor between intended direction and direction toward the ball.
@export_range(0.0, 1.0, 0.05) var shoot_direction_adjustment: float = 0.3

@export_group("Lob Passing")
## Minimum lob power (horizontal speed change).
@export_range(0.5, 20.0, 0.5) var min_lob_power: float = 3.0
## Maximum lob power.
@export_range(1.0, 30.0, 0.5) var max_lob_power: float = 12.0
## Power used by a quick tap.
@export_range(0.5, 20.0, 0.5) var default_lob_power: float = 7.0
## Fixed configurable vertical impulse (upward m/s) of a lob. The arc knob.
@export_range(1.0, 12.0, 0.1) var lob_lift: float = 6.5
## Blend factor between intended direction and direction toward the ball.
@export_range(0.0, 1.0, 0.05) var lob_direction_adjustment: float = 0.35

@export_group("Dribbling")
## Planar distance (m) within which dribble control engages (larger than the
## detector's 0.9 m interaction window so the ball can be gathered while
## running onto it).
@export_range(0.3, 4.0, 0.1) var dribble_distance: float = 1.6
## Max vertical offset (m) between host origin and ball centre for control.
@export_range(0.2, 3.0, 0.1) var max_control_height: float = 1.2
## Constant push force (N) applied per physics tick toward the follow spot.
@export_range(0.5, 40.0, 0.5) var dribble_control_strength: float = 7.0
## Force cap (N) for the dribble push + brake combined (stability guarantee).
@export_range(1.0, 80.0, 1.0) var dribble_max_force: float = 14.0
## How far (m) in front of the player the ball is pushed while carrying.
@export_range(0.2, 2.0, 0.05) var dribble_follow_distance: float = 0.55
## Multiplier of the control strength while sprinting.
@export_range(1.0, 3.0, 0.05) var dribble_sprint_boost: float = 1.35
## Brake force (N) applied per m/s of ball speed that overshoots the player's
## speed + `dribble_speed_slack` (keeps the ball from running away).
@export_range(0.0, 30.0, 0.5) var dribble_brake_strength: float = 10.0
## Speed slack (m/s) above the player's speed that is tolerated before braking.
@export_range(0.5, 6.0, 0.1) var dribble_speed_slack: float = 2.0

@export_group("Reception (ball control)")
## Incoming planar speed (m/s) above which an approaching ball triggers
## automatic reception.
@export_range(0.5, 15.0, 0.1) var reception_trigger_speed: float = 2.0
## Planar speed (m/s) below which a reception is complete.
@export_range(0.1, 6.0, 0.1) var reception_complete_speed: float = 1.2
## Exponential damping factor (1/s) applied to the ball's planar velocity
## through a capped, per-tick force — never an instant velocity reset.
@export_range(0.5, 20.0, 0.5) var reception_damping: float = 6.0
## Small constant pull (N) toward the player's feet while receiving, so the
## ball is taken in rather than stopped dead where it is.
@export_range(0.0, 10.0, 0.25) var reception_pull: float = 2.5
## Force cap (N) for the reception damping + pull combined.
@export_range(1.0, 80.0, 1.0) var reception_max_force: float = 26.0
## Planar distance (m) within which reception engages.
@export_range(0.3, 4.0, 0.1) var reception_distance: float = 1.4

@export_group("Kick Power Charging")
## Charge duration (s) from the default power up to the maximum power.
@export_range(0.1, 3.0, 0.05) var charge_time: float = 0.9
## Hold duration (s) below which the release counts as a quick tap
## (default power, no charge ramp).
@export_range(0.01, 0.5, 0.01) var quick_tap_threshold: float = 0.12

@export_group("Timing & Cooldowns")
## Cooldown (s) after a pass during which a new pass cannot start.
@export_range(0.05, 3.0, 0.05) var pass_cooldown: float = 0.35
## Cooldown (s) after a shot.
@export_range(0.05, 3.0, 0.05) var shoot_cooldown: float = 0.5
## Cooldown (s) after a lob.
@export_range(0.05, 3.0, 0.05) var lob_cooldown: float = 0.6
## How long (s) the transient PASSING/SHOOTING/LOB_PASSING action state is
## held before the state machine returns to IDLE/DRIBBLING.
@export_range(0.05, 1.5, 0.05) var state_hold: float = 0.3
