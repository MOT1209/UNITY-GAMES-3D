class_name CrowdSystem
extends RefCounted

## The crowd's mood, driven ONLY by real match events (Phase 8). Pure bookkeeping, no scene access.
## `loudness` (0..1) is the base atmosphere (attendance and importance) plus an excitement that jumps with events and fades
## over time. `mood` is the reaction of the HOME crowd to the latest event: "cheer", "groan", "boo", "tense" or "calm".
## Events come from `MatchState.events`: goal, shot, foul, yellow_card, red_card, corner, throw_in, goal_kick, offside.

const DECAY_PER_SECOND := 0.25
const MOOD_SECONDS := 3.0

var attendance: float = 0.8              # 0..1 (how full the stadium is)
var importance: float = 1.0              # derby / final multiplier (>= 1)
var excitement: float = 0.0
var mood: String = "calm"
var _mood_left: float = 0.0
var _seen: int = 0


func _init(p_attendance: float = 0.8, p_importance: float = 1.0) -> void:
	attendance = clampf(p_attendance, 0.0, 1.0)
	importance = maxf(p_importance, 1.0)


func base_loudness() -> float:
	return clampf(attendance * 0.35 * importance, 0.0, 0.6)


func loudness() -> float:
	return clampf(base_loudness() + excitement, 0.0, 1.0)


## Reacts to one event; `home_side` is the side whose supporters fill the stadium ("home").
func on_event(ev: Dictionary, home_side: String = "home") -> void:
	var mine: bool = ev.get("side", "") == home_side
	var boost := 0.0
	var new_mood := ""
	match str(ev.get("type", "")):
		"goal":
			boost = 0.7 * importance
			new_mood = "cheer" if mine else "groan"
			if bool(ev.get("own_goal", false)):
				new_mood = "groan" if mine else "cheer"
		"shot":
			boost = 0.2
			new_mood = "tense"
		"foul":
			boost = 0.15
			new_mood = "boo" if not mine else "groan"
		"yellow_card", "red_card":
			boost = 0.3 if ev["type"] == "red_card" else 0.15
			new_mood = "boo" if not mine else "groan"
		"offside", "corner":
			boost = 0.1
			new_mood = "tense"
	if boost > 0.0:
		excitement = clampf(excitement + boost, 0.0, 1.0 - base_loudness())
		mood = new_mood
		_mood_left = MOOD_SECONDS


func update(delta: float) -> void:
	excitement = maxf(excitement - DECAY_PER_SECOND * delta, 0.0)
	_mood_left -= delta
	if _mood_left <= 0.0:
		mood = "calm"


## Feeds the events not yet seen (the list only grows during a match).
func consume(events: Array, home_side: String = "home") -> int:
	var n := 0
	while _seen < events.size():
		on_event(events[_seen], home_side)
		_seen += 1
		n += 1
	return n


## Procedural crowd noise (no audio assets exist): `frames` mono samples of band-limited noise whose level follows `loud`, with a
## slow swell. Returns a PackedFloat32Array in -1..1. Deterministic for a given seed.
static func noise(frames: int, loud: float, seed_value: int = 1) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out := PackedFloat32Array()
	out.resize(frames)
	var lp := 0.0
	for i in frames:
		var white := rng.randf() * 2.0 - 1.0
		lp += (white - lp) * 0.12            # one-pole low-pass: a rumble rather than hiss
		var swell := 0.8 + 0.2 * sin(float(i) * 0.0004)
		out[i] = clampf(lp * 2.4 * loud * swell, -1.0, 1.0)
	return out
