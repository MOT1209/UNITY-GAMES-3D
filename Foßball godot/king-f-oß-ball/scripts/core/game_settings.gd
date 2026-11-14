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

const DEFAULTS := {
	"match": {"camera": "follow", "switch_mode": "auto"},
	"audio": {"master": 1.0, "crowd": 0.8, "effects": 0.9},
	"graphics": {"shadows": "high", "msaa": 2, "fps_cap": 60, "render_scale": 1.0},
	"controls": {"aim_assist": true, "vibration": true, "touch_button_scale": 1.0},
	"developer": {"enabled": false},
}

static var settings_path: String = "user://settings.cfg"


## Saved value of `section/key`, or its default (unknown keys return null).
static func get_value(section: String, key: String) -> Variant:
	var fallback: Variant = (DEFAULTS.get(section, {}) as Dictionary).get(key)
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
	var fallback: Variant = (DEFAULTS.get(section_name, {}) as Dictionary).get(key)
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
