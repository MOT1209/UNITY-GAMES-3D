class_name MenuStadium
extends SubViewportContainer

## Live 3D background of the main menu: the real match stadium (the managed club's own stadium when a career exists)
## under floodlights, seen by a camera that circles slowly above the stands. Only the arena is loaded — no players,
## ball, HUD or match logic — so it stays light. Used only where 3D can render (not in headless runs).

const ARENA_SCENE := "res://scenes/stadium/stadium_arena.tscn"
const ORBIT_RADIUS := 64.0
const ORBIT_HEIGHT := 17.0
const ORBIT_SPEED := 0.035          # radians per second: one lap in about three minutes

var _camera: Camera3D
var _angle := 0.6


func _init(stadium_id: String = StadiumCatalog.DEFAULT_ID) -> void:
	name = "LiveStadium"
	stretch = true
	stretch_shrink = 2 if OS.has_feature("mobile") else 1
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var vp := SubViewport.new()
	vp.name = "View"
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_2X
	add_child(vp)
	var arena := (load(ARENA_SCENE) as PackedScene).instantiate() as Node3D
	arena.set_script(null)                          # the stand-alone prototype controller is not wanted here
	for n in ["Player", "GameCamera", "HUD"]:
		var c := arena.get_node_or_null(n)
		if c != null:
			arena.remove_child(c)
			c.free()
	StadiumCatalog.apply_to(arena.get_node_or_null("Arena"), stadium_id)
	vp.add_child(arena)
	MatchEnvironment.apply(arena, {"time_of_day": "dusk", "weather": "clear"})
	_camera = Camera3D.new()
	_camera.fov = 48.0
	_camera.far = 900.0
	vp.add_child(_camera)
	_camera.current = true
	_place_camera()


func _process(delta: float) -> void:
	_angle = fmod(_angle + ORBIT_SPEED * delta, TAU)
	_place_camera()


func _place_camera() -> void:
	if _camera == null:
		return
	_camera.position = Vector3(sin(_angle) * ORBIT_RADIUS, ORBIT_HEIGHT, cos(_angle) * ORBIT_RADIUS)
	if _camera.is_inside_tree():
		_camera.look_at(Vector3(0, 3.0, 0), Vector3.UP)
