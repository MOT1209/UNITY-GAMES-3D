class_name AIDifficulty
extends RefCounted

## Difficulty decision profiles (master-prompt finding F3). Until now the
## difficulty only changed the think interval (`MatchManager.THINK_INTERVAL`),
## the chaser sprint gate (`PlayerAI.decide`) and the manager reaction timing
## (`ManagerAI.decide`). It now also shapes HOW WELL the AI evaluates its
## options — without touching physics, kick power or any random factor, so
## matches stay reproducible (`sim_fingerprint`) and no physical cheating is
## introduced.
##
## Rule: NORMAL (1) must behave bit-identically to the pre-F3 engine, so
## `apply` returns the profile unchanged there and every other hook defaults
## to the old value. EASY (0) narrows the option space (shorter vision, needs
## wider-open receivers, gives the ball away under pressure sooner, shoots
## only from closer, slower keeper). HARD (2) widens it (longer vision, finds
## tighter receivers, keeps the ball under pressure, shoots a bit earlier,
## slightly faster keeper). Everything is deterministic.

const EASY := 0
const NORMAL := 1
const HARD := 2


## Returns a NEW dictionary: the tactics' pass profile adjusted for `difficulty`.
## NORMAL returns the input unchanged (same object); the original is never
## mutated in any case (callers may keep reusing the tactics' own profile).
static func apply(profile: Dictionary, difficulty: int) -> Dictionary:
	var d := clampi(difficulty, 0, 2)
	if d == NORMAL:
		return profile
	var p := profile.duplicate()
	if d == EASY:
		p["max_dist"] = minf(float(p.get("max_dist", 35.0)) * 0.75, 28.0)
		p["cover_radius"] = float(p.get("cover_radius", 3.0)) + 1.5
		p["pressure_radius"] = float(p.get("pressure_radius", 4.0)) + 1.5
	else:
		p["max_dist"] = minf(float(p.get("max_dist", 35.0)) * 1.1, 45.0)
		p["cover_radius"] = maxf(1.0, float(p.get("cover_radius", 3.0)) - 0.8)
		p["pressure_radius"] = maxf(2.0, float(p.get("pressure_radius", 4.0)) - 1.0)
	return p


## Extra metres added to the tactics' shoot range for the AI carrier
## (negative = only shoots from closer). The human's own side is never
## affected: the range reaches the AI only through `MatchAIDriver`.
static func shoot_range_bonus(difficulty: int) -> float:
	match clampi(difficulty, 0, 2):
		EASY:
			return -4.0
		HARD:
			return 3.0
	return 0.0


## Multiplier on the goalkeeper's movement factor (positioning/closing speed).
## 1.0 at NORMAL keeps the pre-F3 keeper exactly as tuned; EASY a bit slower,
## HARD a bit quicker — still far from "excessively powerful" (see the master
## prompt's Phase 3 constraint; measured save rates are tracked separately).
static func keeper_speed_factor(difficulty: int) -> float:
	match clampi(difficulty, 0, 2):
		EASY:
			return 0.9
		HARD:
			return 1.05
	return 1.0


## Metres added to the tactics' pressing trigger distance for the AI team
## (positive = presses later). Applied in `MatchAIDriver` through
## `TeamAI.pressers`; NORMAL adds nothing.
static func press_distance_bonus(difficulty: int) -> float:
	match clampi(difficulty, 0, 2):
		EASY:
			return 3.0
		HARD:
			return -1.5
	return 0.0
