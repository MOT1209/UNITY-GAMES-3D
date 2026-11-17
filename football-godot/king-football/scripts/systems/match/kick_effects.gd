class_name KickEffects
extends Node3D

## Kick dust (pure presentation): a small puff of grass and dust where the ball is kicked, sized by the
## ball's speed. A fixed pool of one-shot emitters is reused round-robin, so a kick never allocates and a
## second kick does not cut the first puff. Off on the lowest graphics level; it never touches the simulation.

const POOL_SIZE := 4
const MIN_SPEED := 3.0            # slower touches (dribbling) make no puff
const FULL_SPEED := 28.0          # speed at which the puff reaches full size
const MAX_HEIGHT := 0.6           # the ball is on the ground only below this height (m)
const PUFF_COLOR := Color(0.55, 0.62, 0.38, 0.8)
const TRAIL_SPEED := 20.0         # m/s: above this the ball leaves a short light trail (hard shots, long balls)

var _pool: Array[CPUParticles3D] = []
var _next := 0
var _ball: BallController
var _trail: CPUParticles3D
var _low_performance := false


## Connects the puff to the ball's `kicked` signal.
func setup(ball: BallController) -> void:
	_ball = ball
	if not ball.kicked.is_connected(_on_kicked):
		ball.kicked.connect(_on_kicked)


func _ready() -> void:
	_low_performance = GameSettings.is_low_performance()
	_trail = _make_trail()
	add_child(_trail)
	for i in POOL_SIZE:
		var p := _make_emitter()
		add_child(p)
		_pool.append(p)


func _physics_process(_delta: float) -> void:
	if _trail == null:
		return
	if _ball == null or not is_instance_valid(_ball) or _low_performance:
		_trail.emitting = false
		return
	_trail.global_position = _ball.global_position
	_trail.emitting = _ball.get_ball_speed() >= TRAIL_SPEED


func _on_kicked(_speed: float) -> void:
	if _ball == null or not is_inside_tree():
		return
	# `kicked` is emitted right after the impulse; the velocity is up to date one physics frame later.
	await get_tree().physics_frame
	if _ball == null or not is_instance_valid(_ball):
		return
	spawn_puff(_ball.global_position, _ball.get_ball_speed())


## Starts one puff at `pos` for a ball moving at `speed` m/s. Returns true when a puff was started.
func spawn_puff(pos: Vector3, speed: float) -> bool:
	if _pool.is_empty() or speed < MIN_SPEED or pos.y > MAX_HEIGHT or GameSettings.is_low_performance():
		return false
	var t := clampf(speed / FULL_SPEED, 0.0, 1.0)
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.global_position = Vector3(pos.x, 0.04, pos.z)
	p.amount = int(lerpf(6.0, 22.0, t))
	p.initial_velocity_min = lerpf(0.4, 1.0, t)
	p.initial_velocity_max = lerpf(1.0, 2.6, t)
	p.restart()
	p.emitting = true
	return true


func _make_emitter() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.6
	p.amount = 12
	p.direction = Vector3.UP
	p.spread = 70.0
	p.gravity = Vector3(0.0, -4.0, 0.0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	p.local_coords = false
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 1.0, 1.0, 0.8))
	ramp.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	p.color_ramp = ramp
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.14, 0.14)
	var m := StandardMaterial3D.new()
	m.albedo_color = PUFF_COLOR
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	mesh.material = m
	p.mesh = mesh
	return p


func _make_trail() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Trail"
	p.emitting = false
	p.amount = 24
	p.lifetime = 0.22
	p.explosiveness = 0.0
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 180.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 0.15
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 1.0, 1.0, 0.55))
	ramp.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	p.color_ramp = ramp
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.1, 0.1)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	mesh.material = m
	p.mesh = mesh
	return p
