class_name MatchEnvironment
extends RefCounted

## Applies the match conditions chosen in the setup (`MatchSetup.conditions`) to an arena instance (Phase 8).
## weather:     "clear" | "rain" | "fog"      time_of_day: "day" | "dusk" | "night"
## The environment resource of the arena scene is SHARED by every instance, so it is duplicated before it is changed.
## Returns what was applied so tests can verify it: {fog, rain, sun_energy, ambient, floodlights}.

const WEATHER: Array[String] = ["clear", "rain", "fog"]
const TIMES: Array[String] = ["day", "dusk", "night"]


static func apply(arena_root: Node3D, conditions: Dictionary) -> Dictionary:
	var weather := str(conditions.get("weather", "clear"))
	var time_of_day := str(conditions.get("time_of_day", "day"))
	if not (weather in WEATHER):
		weather = "clear"
	if not (time_of_day in TIMES):
		time_of_day = "day"
	var out := {"weather": weather, "time_of_day": time_of_day, "fog": false, "rain": false, "sun_energy": 0.9, "ambient": 0.4, "floodlights": 0}
	var we := arena_root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	var sun := arena_root.get_node_or_null("Sun") as DirectionalLight3D
	if we == null or we.environment == null:
		return out
	var env: Environment = we.environment.duplicate()
	we.environment = env
	var sun_energy := 0.9
	var ambient := 0.4
	match time_of_day:
		"dusk":
			sun_energy = 0.45
			ambient = 0.25
		"night":
			sun_energy = 0.05
			ambient = 0.12
	if weather != "clear":
		sun_energy *= 0.7
		ambient *= 0.9
	env.ambient_light_energy = ambient
	if sun != null:
		sun.light_energy = sun_energy
		if time_of_day == "dusk":
			sun.rotation.x = -0.25
			sun.light_color = Color(1.0, 0.72, 0.5)
		elif time_of_day == "night":
			sun.light_color = Color(0.5, 0.6, 0.9)
	if weather == "fog":
		env.fog_enabled = true
		env.fog_density = 0.012
		env.fog_light_color = Color(0.7, 0.74, 0.78)
		out["fog"] = true
	elif weather == "rain":
		env.fog_enabled = true
		env.fog_density = 0.004
		env.fog_light_color = Color(0.5, 0.55, 0.6)
		out["fog"] = true
		arena_root.add_child(_rain())
		out["rain"] = true
	if time_of_day != "day":
		var n := _floodlights(arena_root, 1.0 if time_of_day == "night" else 0.5)
		out["floodlights"] = n
	out["sun_energy"] = sun_energy
	out["ambient"] = ambient
	return out


static func _rain() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Rain"
	p.amount = 1500
	p.lifetime = 1.2
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(40.0, 0.5, 60.0)
	p.position = Vector3(0.0, 22.0, 0.0)
	p.direction = Vector3(0.1, -1.0, 0.0)
	p.spread = 3.0
	p.gravity = Vector3(0.0, -18.0, 0.0)
	p.initial_velocity_min = 10.0
	p.initial_velocity_max = 14.0
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.03, 0.5)
	p.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.75, 0.8, 0.9, 0.5)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mesh.material = m
	return p


## Four floodlight towers' worth of light at the pitch corners.
static func _floodlights(arena_root: Node3D, strength: float) -> int:
	var n := 0
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var l := OmniLight3D.new()
			l.name = "Floodlight_%d" % n
			l.position = Vector3(sx * 45.0, 30.0, sz * 62.0)
			l.omni_range = 120.0
			l.light_energy = 2.2 * strength
			l.light_color = Color(1.0, 0.96, 0.88)
			arena_root.add_child(l)
			n += 1
	return n
