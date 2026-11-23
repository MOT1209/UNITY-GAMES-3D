class_name ShotTechnique
extends RefCounted

## Shooting techniques and shot contexts (Phase 2 advanced mechanics). Pure numbers + helpers; the kick itself still
## goes through `ShootingSystem` / `BallController`.
##
## A TECHNIQUE is the player's choice (input modifiers or the AI): normal, finesse, power, low driven, chip.
## A CONTEXT follows from the ball when it is struck: volley (in the air), half volley (just bounced, rising),
## first time (arriving at pace, not controlled). Context and technique combine.
##
## Every technique trades something (no technique is simply better):
##   finesse     placed and curled (sidespin, the keeper's read is off by the curl) / slower, worse from range
##   power       faster / wider spread, a 0.2 s wind-up in which the ball can be taken, bad off balance
##   low_driven  stays under the bar, a little more accurate / less pace, easy to block and to hold low
##   chip        lifted over a keeper who is off his line / slow, distance hard to judge
## Multipliers: power (of the charged power), lift (of the charged lift), error (of the shot spread).

const NORMAL := &"normal"
const FINESSE := &"finesse"
const POWER := &"power"
const LOW_DRIVEN := &"low_driven"
const CHIP := &"chip"
const TECHNIQUES: Array[StringName] = [NORMAL, FINESSE, POWER, LOW_DRIVEN, CHIP]

const VOLLEY := &"volley"
const HALF_VOLLEY := &"half_volley"
const FIRST_TIME := &"first_time"
const GROUND := &"ground"

## Wind-up of a power shot (s): the strike happens this long after the release.
const POWER_WINDUP := 0.2
## Highest ball (m above the ground) that can still be volleyed; above it only a header reaches it.
const VOLLEY_MAX_HEIGHT := 1.25
const VOLLEY_MIN_HEIGHT := 0.35
## Relative ball speed (m/s) from which an uncontrolled ball is struck first time.
const FIRST_TIME_SPEED := 5.0


## {power, lift, error, spin, windup} for a technique and the shooter. `mods` may be null (neutral player).
static func profile(technique: StringName, mods: AttributeModifiers) -> Dictionary:
	var curve := mods.detail("curve") if mods != null else 0.5
	var spow := mods.detail("shot_power") if mods != null else 0.5
	var fin := mods.detail("finishing") if mods != null else 0.5
	match technique:
		FINESSE:
			return {"power": 0.8, "lift": 0.75, "error": 1.12 - 0.5 * curve, "spin": 6.0 + 9.0 * curve, "windup": 0.0}
		POWER:
			return {"power": 1.12, "lift": 1.1, "error": 1.5 - 0.45 * spow, "spin": 0.0, "windup": POWER_WINDUP}
		LOW_DRIVEN:
			return {"power": 0.93, "lift": 0.0, "error": 0.88, "spin": 0.0, "windup": 0.0}
		CHIP:
			return {"power": 1.0, "lift": 1.0, "error": 1.25 - 0.45 * fin, "spin": 0.0, "windup": 0.0}
	return {"power": 1.0, "lift": 1.0, "error": 1.0, "spin": 0.0, "windup": 0.0}


## Context of a shot at a ball with `ball_vel` at `height` m, `since_bounce` s after it last touched the ground, for a
## player moving at `player_vel`.
static func context_of(height: float, ball_vel: Vector3, player_vel: Vector3, since_bounce: float, controlled: bool) -> StringName:
	if height > VOLLEY_MIN_HEIGHT:
		return VOLLEY
	if since_bounce >= 0.0 and since_bounce < 0.18 and ball_vel.y > 0.5:
		return HALF_VOLLEY
	var rel := Vector3(ball_vel.x - player_vel.x, 0.0, ball_vel.z - player_vel.z)
	if not controlled and rel.length() > FIRST_TIME_SPEED:
		return FIRST_TIME
	return GROUND


## {error, power, lift_add} for a context. `rel_speed` = speed of the ball relative to the shooter (m/s).
static func context_effect(ctx: StringName, mods: AttributeModifiers, height: float, rel_speed: float) -> Dictionary:
	var vol := mods.detail("volleys") if mods != null else 0.5
	var comp := mods.detail("composure") if mods != null else 0.5
	var bal := mods.detail("balance") if mods != null else 0.5
	var fin := mods.detail("finishing") if mods != null else 0.5
	match ctx:
		VOLLEY:
			var q := vol * 0.6 + comp * 0.2 + bal * 0.2
			# a high contact without technique gets under the ball and skies it
			return {"error": 1.85 - 1.0 * q, "power": 1.0 + 0.08 * q, "lift_add": maxf(height - 0.45, 0.0) * 2.2 * (1.0 - q)}
		HALF_VOLLEY:
			var hq := vol * 0.5 + comp * 0.3 + bal * 0.2
			return {"error": 1.45 - 0.6 * hq, "power": 1.05, "lift_add": -0.3}
		FIRST_TIME:
			return {"error": 1.0 + 0.03 * rel_speed * (1.0 - fin), "power": 1.0 + minf(rel_speed, 12.0) * 0.012, "lift_add": 0.0}
	return {"error": 1.0, "power": 1.0, "lift_add": 0.0}


## Sidespin direction for a curled shot: the strong foot's natural bend (a right foot curls right-to-left, + spin);
## a two-footed player bends it towards the goal centre (`bend_hint`: +1 / -1, 0 = none).
static func curl_sign(mods: AttributeModifiers, bend_hint: float = 0.0) -> float:
	var strong := mods.strong_side() if mods != null else 1.0
	if strong == 0.0:
		return signf(bend_hint) if bend_hint != 0.0 else 1.0
	return strong


## Launch-angle correction (radians, about UP) so a curled shot that bends by Magnus still arrives on its aim:
## lateral drift ~ 0.5 * k * spin * D / v (small-angle), so the ball starts that much outside the aim.
static func curl_compensation(spin_y: float, distance: float, speed: float, magnus_k: float) -> float:
	if speed < 1.0:
		return 0.0
	return -0.5 * magnus_k * spin_y * distance / speed


## Chip: lift and planar power that drop the ball near `distance` m (simple drag allowance). Lift 7.2 .. 9 m/s: the
## apex (2.6 .. 4.1 m) has to clear a keeper standing up (catch height 2.2 m, reach with a jump ~2.6 m).
static func chip_kick(distance: float) -> Dictionary:
	var lift := clampf(6.0 + distance * 0.1, 7.2, 9.0)
	var flight := 2.0 * lift / 9.8
	var power := clampf(distance / flight * 1.08, 8.0, 18.0)
	return {"lift": lift, "power": power}
