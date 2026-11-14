class_name InputSettings
extends RefCounted

## Persisted input settings (P2 input hardening) in the project's existing
## `user://settings.cfg` (same file the language setting uses, separate
## `input` section). Static and dependency-free on purpose: gameplay systems
## call it, nothing here reaches into autoloads.
##
## - Deadzones: applied to the live InputMap at runtime so analog sticks feel
##   right on every physical controller (per-action, movement vs. buttons).
## - Rumble: `Input.start_joy_vibration` pulses on match events, gated by the
##   saved setting and only on connected joypads.

const DEFAULTS := {
	"move_deadzone": 0.2,
	"button_deadzone": 0.5,
	"rumble": true,
}

static var settings_path: String = "user://settings.cfg"

const MOVE_ACTIONS: Array[StringName] = [&"move_left", &"move_right", &"move_forward", &"move_backward"]
const BUTTON_ACTIONS: Array[StringName] = [&"sprint", &"pass", &"shoot", &"lob_pass", &"dribble",
		&"tackle", &"switch_player", &"camera_toggle", &"pause", &"through_pass", &"cross"]


## Loads the saved values and applies them to the live InputMap. Call once at
## boot (GameManager) so saved deadzones are active before any match.
static func apply_saved() -> void:
	var values := _load()
	_set_map_deadzones(MOVE_ACTIONS, float(values["move_deadzone"]))
	_set_map_deadzones(BUTTON_ACTIONS, float(values["button_deadzone"]))


static func _load() -> Dictionary:
	var out := DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) == OK:
		for key in out.keys():
			var v: Variant = cfg.get_value("input", key, out[key])
			if v != null:
				out[key] = v
	return out


static func get_value(key: String) -> Variant:
	return _load()[key]


## Persists one value and applies deadzone changes to the live InputMap.
static func set_value(key: String, value: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load(settings_path)                     # keep every other section/key
	cfg.set_value("input", key, value)
	cfg.save(settings_path)
	match key:
		"move_deadzone":
			_set_map_deadzones(MOVE_ACTIONS, float(value))
		"button_deadzone":
			_set_map_deadzones(BUTTON_ACTIONS, float(value))


static func _set_map_deadzones(actions: Array[StringName], value: float) -> void:
	for action in actions:
		if InputMap.has_action(action):
			InputMap.action_set_deadzone(action, clampf(value, 0.0, 0.95))


## Rumble pulse on every connected joypad. No-op when rumble is disabled, when
## no joypad is connected, or in headless runs (where start_joy_vibration is
## simply harmless). Never throws.
static func pulse(weak: float, strong: float, duration_ms: int) -> void:
	if not bool(get_value("rumble")):
		return
	for device in Input.get_connected_joypads():
		Input.start_joy_vibration(device, clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), float(duration_ms) / 1000.0)
