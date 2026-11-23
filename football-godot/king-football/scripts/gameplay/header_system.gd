class_name HeaderSystem
extends Node

## Headers and aerial play (Phase 2 advanced mechanics). Mounted by `FootballActions`.
##
## 1. WINDOW. Every tick the incoming ball is predicted (ballistic, no spin) to its closest planar approach to the player.
##    The window is open when that approach is within MAX_MISS m, between `MIN_HEIGHT` and the player's reach (standing
##    head height + his jump), and within MAX_LOOKAHEAD s.
## 2. REQUEST. A shoot / pass / lob press while the window is open asks for a header shot / header pass / clearance
##    (human or AI — the AI presses through its intent like a player). Early presses are buffered: the player jumps
##    when he has to (rise time from his take-off speed) to meet the ball at its height. A late press jumps at once and
##    reaches less height — timing matters.
## 3. CONTACT is geometric and physical: only when the ball really comes within CONTACT_RADIUS of the head point of the
##    (jumping) body is it headed — through ONE impulse (`BallController.redirect`). A ball out of reach is simply missed;
##    nobody heads a ball his body cannot get to.
## 4. CONTESTS. Before the contact the header asks the match's `AerialArbiter` (group "aerial_arbiter"; none in a test
##    scene = always allowed): two players going for the same ball are resolved by heading, jumping, strength, height,
##    timing and position — the loser does not touch the ball and loses his balance for a moment.

signal header_started(kind: StringName)
signal header_played(kind: StringName, speed: float, quality: float)
signal header_missed(kind: StringName)

const MIN_HEIGHT := 1.2
const MAX_MISS := 1.0
const MAX_LOOKAHEAD := 0.95
## Head centre to ball centre at contact: head (~0.11) + ball (0.11) + a little lean / forehead reach.
const CONTACT_RADIUS := 0.28
## The head centre sits at this share of the body height above the feet.
const HEAD_SHARE := 0.93
const GRAVITY := 9.8

const SHOT := &"shot"
const PASS := &"pass"
const CLEAR := &"clear"

var rng := RandomNumberGenerator.new()
## Optional: 3D target of the header (goal / team-mate) that wins over the aim direction (AI / tests). INF = none.
var target := Vector3.INF
## Where a header shot aims when nothing else is set (the opponent goal); set by the match. INF = straight ahead.
var goal_hint := Vector3.INF
## Own goal (for clearances away from it); INF = clear straight ahead.
var own_goal_hint := Vector3.INF

var _ball: BallController
var _window := {}
var _request: StringName = &""
var _aim := Vector3.ZERO
var _jumped := false
var _request_age := 0.0
var _timing_q := 1.0
var _jumped_at := -1.0
## The body capsule ignores the ball while a header is pending and the ball is at head height (the head, not the coarse
## 0.3 m capsule, decides the contact). Removed again when the request ends.
var _excepted: BallController
var _host: PlayerController
var stats := {"requested": 0, "played": 0, "missed": 0, "lost_contest": 0}
var last_kind: StringName = &""
var last_quality := 0.0


func _init() -> void:
	rng.randomize()


func window_open() -> bool:
	return not _window.is_empty()


func window() -> Dictionary:
	return _window


func has_request() -> bool:
	return _request != &""


func request_kind() -> StringName:
	return _request


func cancel(lost: bool = false) -> void:
	if _request != &"":
		if lost:
			stats["lost_contest"] += 1
		_request = &""
		_release_exception()


func _release_exception() -> void:
	if _excepted != null and is_instance_valid(_excepted) and _host != null and is_instance_valid(_host):
		_host.remove_collision_exception_with(_excepted)
	_excepted = null


## Reach of `mods`' player: [standing head height, jump height] in metres.
static func reach_of(mods: AttributeModifiers) -> Array:
	var h := mods.height_m() if mods != null else 1.8
	var jump := 0.25 + 0.45 * (mods.detail("jumping") if mods != null else 0.5)
	return [h * HEAD_SHARE, jump]


## Ballistic closest approach of `ball` to the planar point `at`: {t, miss, height} (empty when it moves away / is slow).
static func predict(ball_pos: Vector3, ball_vel: Vector3, at: Vector3) -> Dictionary:
	var v := Vector2(ball_vel.x, ball_vel.z)
	if v.length() < 1.5:
		return {}
	var p := Vector2(ball_pos.x - at.x, ball_pos.z - at.z)
	var t := -p.dot(v) / v.length_squared()
	if t < 0.0:
		return {}
	var miss := (p + v * t).length()
	var y := ball_pos.y + ball_vel.y * t - 0.5 * GRAVITY * t * t
	return {"t": t, "miss": miss, "height": y}


func physics_tick(delta: float, host: PlayerController, mods: AttributeModifiers) -> void:
	if _ball == null or not is_instance_valid(_ball):
		var found := host.get_tree().get_nodes_in_group(BallController.BALL_GROUP)
		_ball = found[0] as BallController if found.size() > 0 else null
		if _ball == null:
			_window = {}
			return
	var reach := reach_of(mods)
	_window = {}
	if _ball.global_position.y > 0.9:
		var pr := predict(_ball.global_position, _ball.linear_velocity, host.global_position)
		if not pr.is_empty() and float(pr["t"]) <= MAX_LOOKAHEAD and float(pr["miss"]) <= MAX_MISS \
				and float(pr["height"]) >= MIN_HEIGHT and float(pr["height"]) <= float(reach[0]) + float(reach[1]) + 0.15:
			_window = pr
	if _request == &"":
		return
	_request_age += delta
	if _window.is_empty() and not _jumped and _request_age > 0.12:
		_miss()
		return
	var head := host.global_position + Vector3(0.0, float(reach[0]), 0.0) - host.global_transform.basis.z * 0.08
	_host = host
	if _excepted == null and _ball.global_position.y - host.global_position.y > 1.45 \
			and Vector2(_ball.global_position.x - host.global_position.x, _ball.global_position.z - host.global_position.z).length() < 1.6:
		host.add_collision_exception_with(_ball)
		_excepted = _ball
	# Jump timing: take off so the head reaches the ball's height at the predicted contact.
	if not _jumped and not _window.is_empty():
		var need := float(_window["height"]) - float(reach[0])
		if need > 0.05:
			# The body falls with the player's own gameplay gravity (PlayerConfig.gravity, 18 m/s2), not the ball's.
			var g := host.config.gravity if host.config != null else GRAVITY
			var v0 := sqrt(2.0 * g * float(reach[1]))
			var rise := _rise_time(v0, need, g)
			if rise < 0.0:
				rise = v0 / g
			if float(_window["t"]) <= rise + delta:
				_timing_q = clampf(1.0 - maxf(rise - float(_window["t"]), 0.0) * 3.0, 0.3, 1.0)
				host.jump(v0)
				_jumped = true
				_jumped_at = _request_age
	var to_ball := _ball.global_position - head
	# Contact this tick: within the radius now, or reaching it before the next physics step (a fast ball would hit the
	# body capsule in the same step before the head is checked).
	var rel_v := _ball.linear_velocity - host.velocity
	var closing := -rel_v.dot(to_ball.normalized()) if to_ball.length_squared() > 0.0001 else 0.0
	if to_ball.length() <= CONTACT_RADIUS or to_ball.length() - maxf(closing, 0.0) * delta * 1.5 <= CONTACT_RADIUS:
		var arbiter := host.get_tree().get_first_node_in_group(&"aerial_arbiter")
		if arbiter != null and arbiter.has_method("claim") and not arbiter.claim(get_parent(), _ball, _score(host, mods, to_ball.length())):
			stats["lost_contest"] += 1
			host.lose_balance(0.3, 0.7)
			_request = &""
			_release_exception()
			return
		_play(host, mods)
		return
	if _jumped and host.is_on_floor() and _request_age - _jumped_at > 0.12:
		_miss()                                         # came down without meeting the ball (checked after take-off)
	elif _request_age > MAX_LOOKAHEAD + 0.3:
		_miss()


## Asks for a header of `kind` along the planar `aim` (world; ZERO = face / hints). Only while the window is open.
func request(kind: StringName, aim: Vector3) -> bool:
	if _window.is_empty() or _request != &"":
		return false
	_request = kind
	_aim = Vector3(aim.x, 0.0, aim.z)
	_jumped = false
	_request_age = 0.0
	_timing_q = 1.0
	stats["requested"] += 1
	header_started.emit(kind)
	return true


## Contest score for the arbiter (higher = wins the ball); `contact_dist` = head-to-ball distance (m).
func contest_score(host: PlayerController, mods: AttributeModifiers, contact_dist: float) -> float:
	return _score(host, mods, minf(contact_dist, CONTACT_RADIUS))


func _score(host: PlayerController, mods: AttributeModifiers, contact_dist: float) -> float:
	var s := 0.0
	if mods != null:
		s += mods.detail("heading") * 0.3 + mods.detail("jumping") * 0.3 + mods.detail("strength") * 0.2
		s += clampf((mods.height_m() - 1.65) / 0.35, 0.0, 1.0) * 0.15
	else:
		s += 0.45
	s += _timing_q * 0.15 + clampf(1.0 - contact_dist / CONTACT_RADIUS, 0.0, 1.0) * 0.1
	if host.is_off_balance():
		s -= 0.2
	return s


func _rise_time(v0: float, height: float, g: float = GRAVITY) -> float:
	var disc := v0 * v0 - 2.0 * g * height
	if disc < 0.0:
		return -1.0
	return (v0 - sqrt(disc)) / g


func _play(host: PlayerController, mods: AttributeModifiers) -> void:
	var kind := _request
	_request = &""
	var heading := mods.detail("heading") if mods != null else 0.5
	var strength := mods.detail("strength") if mods != null else 0.5
	var q := clampf(heading * 0.7 + 0.3 * _timing_q, 0.05, 1.0) * _timing_q
	var dir := _direction(host, kind)
	var err := (1.0 - heading) * 16.0 + (1.0 - _timing_q) * 15.0
	dir = dir.rotated(Vector3.UP, deg_to_rad(rng.randf_range(-err, err)))
	var power := 0.0
	var vy := 0.0
	var incoming := Vector3(_ball.linear_velocity.x, 0.0, _ball.linear_velocity.z).length()
	match kind:
		SHOT:
			power = (9.0 + 7.0 * (heading * 0.6 + strength * 0.4)) * (0.75 + 0.25 * _timing_q) + incoming * 0.15
			vy = rng.randf_range(-2.5, 0.5) + (1.0 - q) * rng.randf_range(0.0, 3.0)    # down towards the goal, a bad one goes over
		PASS:
			power = 7.0 + 4.0 * heading
			vy = 1.5 + rng.randf_range(-0.5, 0.8)
		_:
			power = 12.0 + 6.0 * strength
			vy = 5.0 + 2.0 * heading
	var out := dir * power
	out.y = vy
	_ball.redirect(out, Vector3.ZERO)
	_release_exception()                               # FootballActions keeps the kicker's short self-exception after it
	stats["played"] += 1
	last_kind = kind
	last_quality = q
	header_played.emit(kind, out.length(), q)


func _direction(host: PlayerController, kind: StringName) -> Vector3:
	var from := host.global_position
	var t := target
	if t == Vector3.INF and kind == SHOT:
		t = goal_hint
	if t != Vector3.INF and (kind != SHOT or _aim == Vector3.ZERO):
		var d := Vector3(t.x - from.x, 0.0, t.z - from.z)
		if d.length() > 0.5:
			return d.normalized()
	if _aim.length_squared() > 0.01:
		return _aim.normalized()
	if kind == CLEAR and own_goal_hint != Vector3.INF:
		var away := Vector3(from.x - own_goal_hint.x, 0.0, from.z - own_goal_hint.z)
		if away.length() > 0.5:
			return away.normalized()
	var f := -host.global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length_squared() > 0.0001 else Vector3.FORWARD


func _miss() -> void:
	var kind := _request
	_request = &""
	_release_exception()
	stats["missed"] += 1
	header_missed.emit(kind)
