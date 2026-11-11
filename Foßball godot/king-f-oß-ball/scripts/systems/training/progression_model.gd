class_name ProgressionModel
extends RefCounted

## Player progression (Phase T5). Pure functions — no randomness, so growth is
## gradual, consistent and testable. Growth is bounded by the 99 attribute
## cap AND by potential: an attribute point is only granted if the resulting
## overall rating stays ≤ potential.

const BASE_WEEKLY_POINTS := 0.35
const MIN_AGE_FACTOR := 0.25


static func age_factor(age: int) -> float:
	return clampf(1.0 - (age - 14) * 0.08, MIN_AGE_FACTOR, 1.0)


static func trait_factor(p: PlayerData) -> float:
	var f := 1.0
	if "Fast Learner" in p.traits:
		f *= 1.25
	if "Hard Worker" in p.traits:
		f *= 1.10
	if "Late Bloomer" in p.traits:
		f *= 0.7 if p.age <= 17 else 1.3
	return f


## Headroom factor 0..1: shrinks as overall approaches potential.
static func room_factor(p: PlayerData) -> float:
	return clampf(float(p.potential - p.get_overall()) / 30.0, 0.0, 1.0)


## Fractional attribute points earned this week by training `attr`.
static func weekly_points(p: PlayerData, attr: String, facility_quality: float,
		intensity: float) -> float:
	if not (attr in PlayerData.ATTRIBUTES):
		return 0.0
	var current := p.get_attribute(attr)
	if current >= PlayerData.MAX_RATING:
		return 0.0
	var diminishing := 1.0 - float(current) / 110.0
	var fitness := maxf(float(p.fitness), 50.0) / 100.0
	var facility := 0.7 + 0.6 * clampf(facility_quality, 0.0, 1.0)
	return BASE_WEEKLY_POINTS * age_factor(p.age) * room_factor(p) * trait_factor(p) \
			* fitness * facility * clampf(intensity, 0.0, 1.0) * diminishing


## Applies one week of training for `attr`. Returns the number of whole
## attribute points gained (0 or 1+). Records history entries.
static func train_week(p: PlayerData, attr: String, facility_quality: float,
		intensity: float, week: int) -> int:
	var gained := 0
	var progress: float = float(p.growth_progress.get(attr, 0.0)) \
			+ weekly_points(p, attr, facility_quality, intensity)
	while progress >= 1.0 and p.get_attribute(attr) < PlayerData.MAX_RATING:
		var before := p.get_attribute(attr)
		p.set(attr, before + 1)
		if p.get_overall() > p.potential:      # potential cap — undo and stop
			p.set(attr, before)
			progress = 0.99
			break
		p.development_history.append({"event": "train", "week": week, "attribute": attr,
				"from": before, "to": before + 1, "overall": p.get_overall()})
		progress -= 1.0
		gained += 1
	p.growth_progress[attr] = progress
	# Fitness: heavy training tires, light training recovers.
	p.fitness = clampi(p.fitness + roundi(5.0 - 6.0 * clampf(intensity, 0.0, 1.0)), 0, 100)
	p.experience += 1
	return gained


static func development_report(p: PlayerData) -> Dictionary:
	var start_overall := p.get_overall()
	var gains := {}
	for h in p.development_history:
		if h.get("event", "") == "generated":
			start_overall = int(h.get("overall", start_overall))
		elif h.get("event", "") == "train":
			var a := str(h["attribute"])
			gains[a] = int(gains.get(a, 0)) + 1
	return {"player_id": p.id, "age": p.age, "overall": p.get_overall(),
			"overall_gain": p.get_overall() - start_overall, "potential": p.potential,
			"attribute_gains": gains, "recent": p.development_history.slice(-5)}
