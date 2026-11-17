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
## A fresh viewport (or a model whose meshes / shaders are still loading) can render an empty first
## frame; such a frame is re-rendered up to this many times and never cached.
const MAX_RENDER_ATTEMPTS := 4

## Emitted when a portrait has been rendered and cached (cards that are waiting refresh themselves).
signal portrait_ready(key: String, texture: Texture2D)
## Same event by player id, for screens that track players instead of portrait keys.
signal player_portrait_ready(player_id: String, texture: Texture2D)

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
		portrait_ready.emit(key, result)
		player_portrait_ready.emit(card.player_id, result)
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


## Poses and frames `card`'s player on the stage without rendering (also used by the headless tests):
## returns {visual, camera, head (world position of the Head bone)}.
func stage(card: PlayerCardData, db: Node) -> Dictionary:
	_ensure_stage()
	var path := KEEPER_SCENE if card.is_goalkeeper else OUTFIELD_SCENE
	var visual := _model(path)
	for other: PlayerCharacterVisual in _models.values():
		other.visible = other == visual
	dress(visual, card, db)
	_freeze_pose(visual)
	var head := head_position(visual)
	frame_camera(_camera, head)
	return {"visual": visual, "camera": _camera, "head": head}


## World position of the Head bone in the current pose (after `_freeze_pose`).
static func head_position(visual: PlayerCharacterVisual) -> Vector3:
	var sk := visual.find_child("Skeleton3D", true, false) as Skeleton3D
	if sk == null or sk.find_bone("Head") < 0:
		return visual.global_position + Vector3(0, 1.56, 0)
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head")).origin


## Camera anchored on the head / neck: head and shoulders down to mid-chest, the head in the upper part of
## the picture with room for tall hair; slightly from the player's right like a studio portrait. The same
## framing for every player (the camera follows the head, so a tall or short player is framed alike).
static func frame_camera(cam: Camera3D, head: Vector3) -> void:
	var target := head + Vector3(0.0, -0.035, 0.0)
	cam.fov = PORTRAIT_FOV
	cam.position = target + PORTRAIT_OFFSET
	cam.look_at(target)


const PORTRAIT_FOV := 26.0
const PORTRAIT_OFFSET := Vector3(-0.26, 0.05, -1.62)


func _render(card: PlayerCardData, db: Node) -> Texture2D:
	stage(card, db)
	for attempt in MAX_RENDER_ATTEMPTS:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		var img := _viewport.get_texture().get_image()
		renders += 1
		if img != null and not img.is_empty() and not is_blank(img):
			return ImageTexture.create_from_image(img)
	return null


## True when the centre of a portrait holds no visible model (a frame rendered before the model was ready).
static func is_blank(img: Image) -> bool:
	var w := img.get_width()
	var h := img.get_height()
	var hits := 0
	for yi in range(int(h * 0.2), int(h * 0.9), 12):
		for xi in range(int(w * 0.3), int(w * 0.7), 12):
			if img.get_pixel(xi, yi).a > 0.5:
				hits += 1
				if hits >= 6:
					return false
	return true


## Dresses a character visual exactly as the match does (club kit incl. pattern, number, stored appearance).
## Shared by portraits and the live 3D preview, so both always show the same player.
static func dress(visual: PlayerCharacterVisual, card: PlayerCardData, db: Node) -> void:
	visual.kit = card.kit(db)
	visual.fabric_folds = true                   # close-up only (not in matches)
	visual.number = card.shirt_number
	visual.look = PlayerAppearance.to_look(card.appearance)
	visual.apply_kit()
	visual.apply_number()
	visual.apply_look()


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
	_camera.fov = PORTRAIT_FOV
	_camera.current = true
	# Fixed exposure: no auto exposure, linear tone mapping, so every card is lit the same way.
	var attrs := CameraAttributesPractical.new()
	attrs.auto_exposure_enabled = false
	attrs.exposure_multiplier = 1.0
	_camera.attributes = attrs
	_viewport.add_child(_camera)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.82, 0.92)
	env.ambient_light_energy = 0.28                     # light ambient: the three lights shape the face
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	_viewport.add_child(we)
	for spec in LIGHTS:
		var l := DirectionalLight3D.new()
		l.name = str(spec["name"])
		l.rotation_degrees = spec["rot"]
		l.light_color = spec["color"]
		l.light_energy = spec["energy"]
		l.shadow_enabled = false
		_viewport.add_child(l)


func _model(path: String) -> PlayerCharacterVisual:
	if _models.has(path):
		return _models[path]
	var visual := (load(path) as PackedScene).instantiate() as PlayerCharacterVisual
	_viewport.add_child(visual)
	visual.rotation.y = deg_to_rad(-12.0)
	_models[path] = visual
	return visual


## Three-point portrait lighting (round 3, D2). The models face -Z and the camera sits on the -Z side, so a
## light whose yaw is near 180 degrees shines onto the face. Key: warm, high, from the camera's left. Fill:
## cool and weak from the right. Rim: from behind and above, outlining hair and shoulders.
const LIGHTS := [
	{"name": "Key", "rot": Vector3(-32, -145, 0), "color": Color(1.0, 0.92, 0.82), "energy": 1.35},
	{"name": "Fill", "rot": Vector3(-12, 140, 0), "color": Color(0.74, 0.84, 1.0), "energy": 0.38},
	{"name": "Rim", "rot": Vector3(-28, 15, 0), "color": Color(1.0, 0.97, 0.92), "energy": 1.1},
]


## Deterministic pose: the static `PortraitIdle` clip (arms relaxed, both rigs), animation stopped.
func _freeze_pose(visual: PlayerCharacterVisual) -> void:
	for n in visual.find_children("*", "AnimationPlayer", true, false):
		var ap := n as AnimationPlayer
		var clip: String = PlayerAnimationLibrary.PORTRAIT_CLIP if ap.has_animation(PlayerAnimationLibrary.PORTRAIT_CLIP) \
				else (visual.idle_animation if ap.has_animation(visual.idle_animation) else "Idle")
		if ap.has_animation(clip):
			ap.play(clip)
			ap.seek(0.0, true)
			ap.pause()
