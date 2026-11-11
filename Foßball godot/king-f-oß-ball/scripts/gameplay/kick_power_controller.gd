class_name KickPowerController
extends Node

## Optional power-charging system for one kick action (Phase 4, plan §11).
## Starts charging on `start()`, ramps the power from `default_power` up to
## `max_power` over `charge_time` while `update()` is driven by the owner each
## physics tick, and returns the final power on `release()`.
##
## Guarantees:
##   - Power is clamped to [min_power, max_power] (minimum enforced).
##   - A hold shorter than `quick_tap_threshold` is a quick tap → default power.
##   - `cancel()` cleanly resets the charge (e.g. when the interaction is lost).
## One instance per action (pass / shoot / lob) so each can have its own
## settings; the orchestrator creates and drives them.

signal charge_started
## Emitted on a successful release; `power` is the final kick power.
signal charge_released(power: float)
signal charge_cancelled

## Power floor for the released value (m/s).
@export_range(0.5, 20.0, 0.5) var min_power: float = 4.0
## Power ceiling for the released value (m/s).
@export_range(1.0, 50.0, 0.5) var max_power: float = 16.0
## Power of a quick tap / the charge ramp start point.
@export_range(0.5, 30.0, 0.5) var default_power: float = 9.0
## Seconds from `default_power` up to `max_power`.
@export_range(0.1, 3.0, 0.05) var charge_time: float = 0.9
## Holds shorter than this are quick taps (s).
@export_range(0.01, 0.5, 0.01) var quick_tap_threshold: float = 0.12

var _charging := false
var _elapsed := 0.0


func start() -> void:
	if _charging:
		return
	_charging = true
	_elapsed = 0.0
	charge_started.emit()


func is_charging() -> bool:
	return _charging


## Progress as a 0..1 ratio (0 for a quick tap that has not crossed the
## threshold yet). UI reads this every tick while charging.
func get_ratio() -> float:
	if not _charging:
		return 0.0
	if _elapsed < quick_tap_threshold:
		return 0.0
	var ramp := _elapsed - quick_tap_threshold
	return clampf(ramp / maxf(charge_time, 0.01), 0.0, 1.0)


## Drives the charge clock; call once per physics tick while the action is
## held. Returns the current 0..1 ratio for convenience.
func update(delta: float) -> float:
	if _charging:
		_elapsed += delta
	return get_ratio()


## Releases the charge and returns the final power in m/s. Quick taps get the
## default power; charged holds ramp linearly from default to max. Always
## clamped to [min_power, max_power].
func release() -> float:
	var power: float
	if not _charging:
		power = clampf(default_power, min_power, max_power)
	elif _elapsed < quick_tap_threshold:
		power = clampf(default_power, min_power, max_power)
	else:
		var ratio := clampf((_elapsed - quick_tap_threshold) / maxf(charge_time, 0.01), 0.0, 1.0)
		power = lerpf(clampf(default_power, min_power, max_power), max_power, ratio)
		power = clampf(power, min_power, max_power)
	_reset()
	charge_released.emit(power)
	return power


## Aborts the charge without executing an action.
func cancel() -> void:
	var was := _charging
	_reset()
	if was:
		charge_cancelled.emit()


func _reset() -> void:
	_charging = false
	_elapsed = 0.0
