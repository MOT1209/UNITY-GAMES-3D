class_name PlayerPreview
extends SubViewportContainer

## Live, slowly rotating 3D preview of one player (Phase 7.7): the SAME model, kit, number and stored
## appearance as in a match. One SubViewport with its own World3D per preview; it only renders while
## visible (`UPDATE_WHEN_VISIBLE`) and is freed with the control, so a screen that is left costs nothing.
## Drag horizontally to turn the player; it rotates by itself otherwise.

const SPIN_SPEED := 0.7            # rad/s
const DRAG_SENSITIVITY := 0.012

var card: PlayerCardData
var model: PlayerCharacterVisual
var viewport: SubViewport
var camera: Camera3D
var _drag := false
var _spin := true


func _init(size_px: Vector2 = Vector2(260, 340)) -> void:
	custom_minimum_size = size_px
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	layout_direction = Control.LAYOUT_DIRECTION_LTR


## Builds (or rebuilds) the preview for `p_card`. Returns false if the model scene is unavailable.
func setup(p_card: PlayerCardData, db: Node) -> bool:
	card = p_card
	if viewport == null:
		_build_stage()
	if model != null:
		model.queue_free()
		model = null
	if card == null:
		return false
	var path := PlayerPortraitRenderer.KEEPER_SCENE if card.is_goalkeeper else PlayerPortraitRenderer.OUTFIELD_SCENE
	var packed := load(path) as PackedScene
	if packed == null:
		return false
	model = packed.instantiate() as PlayerCharacterVisual
	viewport.add_child(model)
	PlayerPortraitRenderer.dress(model, card, db)
	var h: float = model.look.height
	# full body, facing the camera (the models face -Z, the camera is on the -Z side)
	camera.look_at_from_position(Vector3(0.0, 1.0 * h, -4.4), Vector3(0.0, 0.92 * h, 0.0))   # works before entering the tree
	return true


func _build_stage() -> void:
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(viewport)
	camera = Camera3D.new()
	camera.fov = 26.0
	camera.current = true
	viewport.add_child(camera)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.82, 0.84, 0.9)
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	viewport.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 30, 0)
	key.light_energy = 1.1
	viewport.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15, 200, 0)
	rim.light_color = Color(1.0, 0.9, 0.7)
	rim.light_energy = 0.5
	viewport.add_child(rim)


func _process(delta: float) -> void:
	if model != null and _spin and not _drag:
		model.rotation.y = wrapf(model.rotation.y + SPIN_SPEED * delta, -PI, PI)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_drag = event.pressed
		accept_event()
	elif event is InputEventMouseMotion and _drag and model != null:
		model.rotation.y += (event as InputEventMouseMotion).relative.x * DRAG_SENSITIVITY
		accept_event()
