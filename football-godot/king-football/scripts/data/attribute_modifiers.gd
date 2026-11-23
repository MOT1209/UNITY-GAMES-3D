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


## First-touch control multiplier (dribbling rating). ±10 %. Scales the
## reception damping/pull force, so a high-dribbling player kills the ball
## faster while a poor one lets it run on (P3 gameplay feel).
func control_multiplier() -> float:
	return _scale(data.dribbling, 0.10) if data else 1.0


## Maximum random aim error in degrees for a shot: 0.5° at 99 → 9° at 1;
## fitness below 100 adds up to 30 % more. Neutral (50) ≈ 4.8°.
func shot_error_degrees() -> float:
	if data == null:
		return 0.0
	# Phase M5: the rating carries the spread (83 -> ~6 deg, 74 -> ~8 deg, 60 -> ~11 deg); was 9..0.5, which a fixed
	# base spread drowned, so a 9-point stronger side barely shot better.
	var base := lerpf(24.0, 1.5, (float(data.shooting) - 1.0) / 98.0)
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


# --- Phase 2 advanced mechanics -------------------------------------------------------------------------------
# Read from the stored / derived DETAILED attributes (`DetailedAttributes.value`), never written. Every value below is
# a 0..1 rating (rating 50 -> 0.5); without player data everything is the neutral 0.5, so a modifier-less player
# behaves like an average one.

## A detailed attribute as 0..1 (0.5 without data or for an unknown name).
func detail(attr: String) -> float:
	if data == null:
		return 0.5
	var v := DetailedAttributes.value(data, attr)
	return clampf(float(v) / 100.0, 0.01, 0.99) if v > 0 else 0.5


## Technical skill-move rating 0..1: dribbling skill, ball control, agility and balance.
func skill_rating() -> float:
	return detail("dribbling_skill") * 0.4 + detail("ball_control") * 0.25 + detail("agility") * 0.2 + detail("balance") * 0.15


## Weak-foot rating 1..5. The database has no weak-foot field: a two-footed player (`Foot.BOTH`) is 5, everyone else
## gets a stable derived value of 2..4 (from his id), +1 with ball control of 80 or more. Never stored (saves unchanged).
func weak_foot_stars() -> int:
	if data == null:
		return 3
	if data.preferred_foot == PlayerData.Foot.BOTH:
		return 5
	var base := 2 + int((hash(data.id + ":weak_foot") & 0x7fffffff) % 3)
	return clampi(base + (1 if DetailedAttributes.value(data, "ball_control") >= 80 else 0), 1, 5)


## Execution quality of a weak-foot touch / kick compared with the strong foot (1.0 = as good).
func weak_foot_quality() -> float:
	return [0.5, 0.58, 0.68, 0.79, 0.9, 1.0][weak_foot_stars()]


## Side of the strong foot in the player's own frame: +1 right, -1 left, 0 two-footed.
func strong_side() -> float:
	if data == null:
		return 1.0
	match data.preferred_foot:
		PlayerData.Foot.LEFT: return -1.0
		PlayerData.Foot.BOTH: return 0.0
	return 1.0


## Quality multiplier for a touch / kick played with the foot on `side` of the body (+1 right, -1 left, 0 = either).
func foot_quality(side: float) -> float:
	var strong := strong_side()
	if strong == 0.0 or side == 0.0 or signf(side) == signf(strong):
		return 1.0
	return weak_foot_quality()


## Body height (m) and mass (kg) for aerial reach and physical contact.
func height_m() -> float:
	return float(data.get_height_cm()) / 100.0 if data != null else 1.80


func mass_kg() -> float:
	return float(data.get_weight_kg()) if data != null else 76.0
