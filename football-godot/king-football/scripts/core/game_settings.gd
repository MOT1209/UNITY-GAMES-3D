class_name GameSettings
extends RefCounted

## Persisted game options in the shared `user://settings.cfg` (the file the language and input
## settings already use; one section per group, every other key is kept on save). Static and
## dependency-free: menus write, the match / audio / graphics systems read.
##
##   match    camera ("follow" | "broadcast"), switch_mode ("auto" | "semi" | "manual")
##   audio    master, crowd, effects (0..1)
##   graphics shadows ("off" | "low" | "high"), msaa (0, 2, 4), fps_cap (30 | 60), render_scale (0.5..1)
##   controls aim_assist, vibration, touch_button_scale (0.8..1.4)

const CAMERA_MODES: Array[String] = ["follow", "broadcast"]
const SWITCH_MODES: Array[String] = ["auto", "semi", "manual"]
const SHADOW_LEVELS: Array[String] = ["off", "low", "high"]
const MSAA_LEVELS: Array[int] = [0, 2, 4]
const FPS_CAPS: Array[int] = [30, 60]
## Viewport.mesh_lod_threshold (pixels of allowed error) per graphics level: higher = simpler meshes sooner.
const MESH_LOD_THRESHOLD := {"off": 6.0, "low": 4.0, "high": 1.0}

const DEFAULTS := {
	"match": {"camera": "follow", "switch_mode": "auto", "radar": true, "radar_opacity": 0.85},
	"audio": {"master": 1.0, "crowd": 0.8, "effects": 0.9},
	"graphics": {"shadows": "high", "msaa": 2, "fps_cap": 60, "render_scale": 1.0},
	"controls": {"aim_assist": true, "vibration": true, "touch_button_scale": 1.0},
	"developer": {"enabled": false},
	"ui": {"nav_hidden": false},
}

## Phones start lighter (cooler, longer battery); players can raise it in the settings.
const MOBILE_DEFAULTS := {"graphics": {"shadows": "low", "msaa": 0, "fps_cap": 60, "render_scale": 0.75}}

static var settings_path: String = "user://settings.cfg"
## Tests set this to check the phone defaults on a desktop.
static var force_mobile := false


## Default of `section/key` for this device (phone defaults where they differ).
static func default_of(section_name: String, key: String) -> Variant:
	if force_mobile or OS.has_feature("mobile"):
		var m: Dictionary = MOBILE_DEFAULTS.get(section_name, {})
		if m.has(key):
			return m[key]
	return (DEFAULTS.get(section_name, {}) as Dictionary).get(key)


## Saved value of `section/key`, or its default (unknown keys return null).
static func get_value(section: String, key: String) -> Variant:
	var fallback: Variant = default_of(section, key)
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) != OK:
		return fallback
	var v: Variant = cfg.get_value(section, key, fallback)
	return _sanitize(section, key, v)


## Stores one value (validated; an invalid value is replaced by the default). Returns the stored value.
static func set_value(section: String, key: String, value: Variant) -> Variant:
	var clean: Variant = _sanitize(section, key, value)
	var cfg := ConfigFile.new()
	cfg.load(settings_path)                  # keep the other sections (language, input ...)
	cfg.set_value(section, key, clean)
	cfg.save(settings_path)
	return clean


## Every setting of `section` (saved or default).
static func section(section_name: String) -> Dictionary:
	var out := {}
	for key in (DEFAULTS.get(section_name, {}) as Dictionary):
		out[key] = get_value(section_name, key)
	return out


static func _sanitize(section_name: String, key: String, v: Variant) -> Variant:
	var fallback: Variant = default_of(section_name, key)
	if fallback == null:
		return v
	match "%s/%s" % [section_name, key]:
		"match/camera":
			return v if str(v) in CAMERA_MODES else fallback
		"match/switch_mode":
			return v if str(v) in SWITCH_MODES else fallback
		"graphics/shadows":
			return v if str(v) in SHADOW_LEVELS else fallback
		"graphics/msaa":
			return int(v) if int(v) in MSAA_LEVELS else fallback
		"graphics/fps_cap":
			return int(v) if int(v) in FPS_CAPS else fallback
		"graphics/render_scale":
			return clampf(float(v), 0.5, 1.0)
		"controls/touch_button_scale":
			return clampf(float(v), 0.8, 1.4)
	if fallback is float:
		return clampf(float(v), 0.0, 1.0)
	if fallback is bool:
		return bool(v)
	return v


# --- applying ----------------------------------------------------------------------------------

## Audio bus names: the match's crowd ambience / chants and its effects (whistle, kicks) play on
## these; both send to Master. Created on demand, so no bus layout resource is required.
const BUS_CROWD := "Crowd"
const BUS_EFFECTS := "Effects"


## Applies every saved group (boot, and after a change in the settings screen).
static func apply_all(root: Viewport) -> void:
	apply_audio()
	apply_graphics(root)
	apply_controls()


static func ensure_bus(bus_name: String) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		return idx
	AudioServer.add_bus()
	idx = AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")
	return idx


static func apply_audio() -> void:
	var a := section("audio")
	AudioServer.set_bus_volume_db(0, _db(float(a["master"])))
	AudioServer.set_bus_volume_db(ensure_bus(BUS_CROWD), _db(float(a["crowd"])))
	AudioServer.set_bus_volume_db(ensure_bus(BUS_EFFECTS), _db(float(a["effects"])))


static func _db(linear: float) -> float:
	return linear_to_db(maxf(linear, 0.0001))


## Anti-aliasing, frame cap and 3D resolution scale (shadow quality is applied per match by
## `MatchEnvironment.apply_shadow_quality`).
## Low-performance mode = the lowest graphics level (shadows "off"): optional eye candy such as the animated
## card gloss (CardFrame) is switched off.
static func is_low_performance() -> bool:
	return str(get_value("graphics", "shadows")) == "off"


static func apply_graphics(root: Viewport) -> void:
	var g := section("graphics")
	Engine.max_fps = int(g["fps_cap"])
	if root == null:
		return
	match int(g["msaa"]):
		4:
			root.msaa_3d = Viewport.MSAA_4X
		2:
			root.msaa_3d = Viewport.MSAA_2X
		_:
			root.msaa_3d = Viewport.MSAA_DISABLED
	root.scaling_3d_scale = float(g["render_scale"])
	# Mesh LOD (players, goalkeepers, referee and stadium import with generated LODs): on the phone
	# quality level the engine switches to simpler meshes earlier.
	root.mesh_lod_threshold = MESH_LOD_THRESHOLD.get(str(g["shadows"]), 1.0)


## Vibration is the same switch as the input settings' rumble (one source of truth for the motor).
static func apply_controls() -> void:
	var on := bool(get_value("controls", "vibration"))
	if bool(InputSettings.get_value("rumble")) != on:
		InputSettings.set_value("rumble", on)
