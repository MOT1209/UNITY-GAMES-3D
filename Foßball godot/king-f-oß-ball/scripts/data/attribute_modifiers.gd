class_name AttributeModifiers
extends RefCounted

## Converts a PlayerData's 1–99 attributes into gameplay multipliers (Phase T2).
## Every multiplier is 1.0 at rating 50 ("neutral"), so a player without
## modifiers behaves exactly like the Phase 2–4 defaults. Ranges are kept
## narrow so ratings matter without breaking tuned feel.

var data: PlayerData

func _init(p: PlayerData = null) -> void:
	data = p


static func _scale(rating: int, span: float) -> float:
	# 50 -> 1.0, 1 -> 1-span, 99 -> 1+span
	return 1.0 + clampf((float(rating) - 50.0) / 49.0, -1.0, 1.0) * span


## Run/sprint speed multiplier (pace). ±12 %.
func speed_multiplier() -> float:
	return _scale(data.pace, 0.12) if data else 1.0


## Acceleration multiplier (pace, small physical contribution). ±20 %.
func acceleration_multiplier() -> float:
	return _scale(int((data.pace * 3 + data.physical) / 4), 0.20) if data else 1.0


## Kick power multiplier (shooting). ±10 %.
func shot_power_multiplier() -> float:
	return _scale(data.shooting, 0.10) if data else 1.0


## Pass power multiplier (passing). ±8 %.
func pass_power_multiplier() -> float:
	return _scale(data.passing, 0.08) if data else 1.0


## Maximum random aim error in degrees for a shot: 0.5° at 99 → 9° at 1;
## fitness below 100 adds up to 30 % more. Neutral (50) ≈ 4.8°.
func shot_error_degrees() -> float:
	if data == null:
		return 0.0
	var base := lerpf(9.0, 0.5, (float(data.shooting) - 1.0) / 98.0)
	return base * (1.0 + (100 - data.fitness) / 100.0 * 0.3)


## Maximum random aim error in degrees for a pass (passing).
func pass_error_degrees() -> float:
	if data == null:
		return 0.0
	var base := lerpf(7.0, 0.3, (float(data.passing) - 1.0) / 98.0)
	return base * (1.0 + (100 - data.fitness) / 100.0 * 0.3)


## Reception radius multiplier (dribbling = ball control). ±15 %.
func reception_radius_multiplier() -> float:
	return _scale(data.dribbling, 0.15) if data else 1.0


## Strength used for physical duels, 0.5–1.5 (physical).
func duel_strength() -> float:
	return _scale(data.physical, 0.5) if data else 1.0


## Defensive effectiveness 0.5–1.5 (defending).
func defending_factor() -> float:
	return _scale(data.defending, 0.5) if data else 1.0


## Goalkeeper save strength 0.5–1.5 (goalkeeping).
func goalkeeping_factor() -> float:
	return _scale(data.goalkeeping, 0.5) if data else 1.0
