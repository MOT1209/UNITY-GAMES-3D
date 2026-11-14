class_name StandCrowd
extends MultiMeshInstance3D

## Spectators in the stands (UX phase 6): camera-facing silhouette cards (`stand_crowd.gdshader`) placed
## on the real stand geometry — rays cast down onto the stadium's collision find the steps — in the
## home colours (most), away colours and neutral clothes. The crowd model's loudness / mood drives the
## shader's `excitement`, so the stands jump when a goal is scored. One draw call for the whole crowd.

const SHADER := "res://resources/shaders/stand_crowd.gdshader"
const CARD_SIZE := Vector2(0.55, 0.95)
const STEP := 1.15                     # metres between ray columns (density)
const PITCH_KEEP_OUT := Vector2(37.0, 55.5)
const MAX_SPECTATORS := 4000

var spectators := 0
## Where every spectator stands (kept on the node: headless rendering does not return MultiMesh data).
var positions := PackedVector3Array()
var built := false
var _mat: ShaderMaterial


func _init() -> void:
	name = "StandCrowd"
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Casts rays over the stadium footprint and fills the stand steps. `attendance` 0..1 thins the crowd;
## `colors` = [home jersey, away jersey]. Needs the stadium collision in the physics space.
func build(space: PhysicsDirectSpaceState3D, attendance: float, colors: Array, seed_value: int = 1) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var spots: Array[Vector3] = []
	var x := -78.0
	while x <= 78.0:
		var z := -97.0
		while z <= 97.0:
			if absf(x) > PITCH_KEEP_OUT.x or absf(z) > PITCH_KEEP_OUT.y:
				var q := PhysicsRayQueryParameters3D.create(Vector3(x, 40.0, z), Vector3(x, 0.3, z))
				var hit := space.intersect_ray(q)
				if not hit.is_empty() and (hit["normal"] as Vector3).y > 0.6 and (hit["position"] as Vector3).y > 0.6 \
						and rng.randf() < attendance:
					spots.append((hit["position"] as Vector3) + Vector3(rng.randf_range(-0.2, 0.2), 0.0, rng.randf_range(-0.2, 0.2)))
			z += STEP
		x += STEP
	if spots.size() > MAX_SPECTATORS:
		spots.shuffle()
		spots.resize(MAX_SPECTATORS)
	var quad := QuadMesh.new()
	quad.size = CARD_SIZE
	quad.center_offset = Vector3(0.0, CARD_SIZE.y * 0.5, 0.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = spots.size()
	var home: Color = colors[0] if colors.size() > 0 else Color(0.8, 0.2, 0.2)
	var away: Color = colors[1] if colors.size() > 1 else Color(0.2, 0.3, 0.8)
	for i in spots.size():
		mm.set_instance_transform(i, Transform3D(Basis(), spots[i]))
		var r := rng.randf()
		var c: Color = home if r < 0.62 else (away if r < 0.82 else Color.from_hsv(rng.randf(), 0.25, rng.randf_range(0.3, 0.85)))
		c = c.lerp(Color.WHITE, rng.randf_range(0.0, 0.15))
		mm.set_instance_custom_data(i, Color(c.r, c.g, c.b, rng.randf()))
	multimesh = mm
	_mat = ShaderMaterial.new()
	_mat.shader = load(SHADER)
	material_override = _mat
	spectators = spots.size()
	positions = PackedVector3Array(spots)
	built = true
	return spectators


## 0 = calm, 1 = goal celebration.
func set_excitement(value: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter("excitement", clampf(value, 0.0, 1.0))


func excitement() -> float:
	return float(_mat.get_shader_parameter("excitement")) if _mat != null else 0.0
