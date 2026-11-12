class_name PlayerPortraitRenderer
extends Node

## Renders the REAL player model (same GLB, kit, number and stored appearance
## as in a match) into a texture for cards and profile screens (Phase V6).
##
## - ONE shared SubViewport with its own 3D world, so it never touches (or
##   is slowed by) the live match scene. Created lazily, freed with `release()`.
## - Requests are serialised; the viewport renders a single frame per portrait
##   (UPDATE_ONCE) and is otherwise idle.
## - Results are cached as ImageTextures under `PlayerCardData.portrait_key()`
##   (player id + appearance + kit + number), LRU-limited to MAX_CACHE entries.
##   A kit or appearance change produces a new key, so cards never show a stale
##   portrait; nothing is written to disk or to saves.
## - Without a rendering device (headless/dummy driver) `request()` returns null
##   and the card shows its fallback silhouette instead of crashing.

const OUTFIELD_SCENE := "res://scenes/player/player_model.tscn"
const KEEPER_SCENE := "res://scenes/player/goalkeeper_model.tscn"
const SIZE := Vector2i(300, 360)
const MAX_CACHE := 96

static var _instance: PlayerPortraitRenderer

var _viewport: SubViewport
var _camera: Camera3D
var _models: Dictionary = {}                 # scene path -> PlayerCharacterVisual
var _cache: Dictionary = {}                  # key -> ImageTexture (insertion order = LRU order)
var _busy := false
var renders := 0                             # statistics for tests / profiling
var cache_hits := 0


## Shared renderer attached to the scene tree root (created on first use).
static func shared(tree: SceneTree) -> PlayerPortraitRenderer:
	if _instance == null or not is_instance_valid(_instance):
		_instance = PlayerPortraitRenderer.new()
		_instance.name = "PlayerPortraitRenderer"
		tree.root.add_child.call_deferred(_instance)
	return _instance


static func can_render() -> bool:
	return DisplayServer.get_name() != "headless" \
			and RenderingServer.get_video_adapter_name() != ""


func cached(card: PlayerCardData, db: Node) -> Texture2D:
	return _cache.get(card.portrait_key(db))


## Returns the portrait texture (cached) or null when rendering is unavailable.
func request(card: PlayerCardData, db: Node) -> Texture2D:
	if card == null:
		return null
	var key := card.portrait_key(db)
	if _cache.has(key):
		cache_hits += 1
		var tex: Texture2D = _cache[key]
		_cache.erase(key)
		_cache[key] = tex                      # most recently used
		return tex
	if not can_render():
		return null
	var guard := 0
	while not is_inside_tree() and guard < 30:      # created deferred by shared(): wait for the tree
		guard += 1
		await Engine.get_main_loop().process_frame
	if not is_inside_tree():
		return null
	while _busy:                                # one render at a time
		await get_tree().process_frame
	if _cache.has(key):
		return _cache[key]
	_busy = true
	var result := await _render(card, db)
	_busy = false
	if result != null:
		_cache[key] = result
		while _cache.size() > MAX_CACHE:
			_cache.erase(_cache.keys()[0])
	return result


func cache_size() -> int:
	return _cache.size()


func clear_cache() -> void:
	_cache.clear()


## Frees the viewport and all models (cache kept unless `drop_cache`).
func release(drop_cache := false) -> void:
	if _viewport != null:
		_viewport.queue_free()
		_viewport = null
		_camera = null
		_models.clear()
	if drop_cache:
		_cache.clear()


func _render(card: PlayerCardData, db: Node) -> Texture2D:
	_ensure_stage()
	var path := KEEPER_SCENE if card.is_goalkeeper else OUTFIELD_SCENE
	var visual := _model(path)
	for other: PlayerCharacterVisual in _models.values():
		other.visible = other == visual
	visual.kit = card.kit(db)
	visual.number = card.shirt_number
	visual.look = PlayerAppearance.to_look(card.appearance)
	visual.apply_kit()
	visual.apply_number()
	visual.apply_look()
	_freeze_pose(visual)
	var h: float = visual.look.height
	# The models face -Z, so the camera sits on the -Z side, slightly to the left.
	_camera.position = Vector3(-0.28, 1.60 * h, -2.1)
	_camera.look_at(Vector3(0.0, 1.47 * h, 0.0))
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img := _viewport.get_texture().get_image()
	renders += 1
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)


func _ensure_stage() -> void:
	if _viewport != null:
		return
	_viewport = SubViewport.new()
	_viewport.size = SIZE
	_viewport.own_world_3d = true                # isolated from the match world
	_viewport.transparent_bg = true              # no background artefacts
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_camera = Camera3D.new()
	_camera.fov = 24.0
	_camera.current = true
	_viewport.add_child(_camera)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.82, 0.84, 0.9)
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	_viewport.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 30, 0)
	key.light_energy = 1.1
	_viewport.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15, 200, 0)
	rim.light_color = Color(1.0, 0.9, 0.7)
	rim.light_energy = 0.5
	_viewport.add_child(rim)


func _model(path: String) -> PlayerCharacterVisual:
	if _models.has(path):
		return _models[path]
	var visual := (load(path) as PackedScene).instantiate() as PlayerCharacterVisual
	_viewport.add_child(visual)
	visual.rotation.y = deg_to_rad(-12.0)
	_models[path] = visual
	return visual


## Deterministic pose: first frame of the idle clip, animation stopped.
func _freeze_pose(visual: PlayerCharacterVisual) -> void:
	for n in visual.find_children("*", "AnimationPlayer", true, false):
		var ap := n as AnimationPlayer
		var clip: String = visual.idle_animation if ap.has_animation(visual.idle_animation) else "Idle"
		if ap.has_animation(clip):
			ap.play(clip)
			ap.seek(0.0, true)
			ap.pause()
