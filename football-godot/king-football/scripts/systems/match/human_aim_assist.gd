class_name HumanAimAssist
extends RefCounted

## Human-player aim assist for the through-pass and cross actions (P3 gameplay
## feel pass). The AI already uses `PlayerAI.lead_point` (through balls) and
## `PlayerAI.cross_target` (crosses); this class exposes the same intelligence
## to the human actions, so the human plays with the same ball physics and
## target logic instead of a second implementation.
##
## Match context is injected as one Callable (dependency-injection per the
## architecture rules — no manager references) returning
## `{teammates: Array[Vector3], opponents: Array[Vector3], goal: Vector3}`.
## Every INF return means "no assisted target": the caller falls back to the
## plain kick direction, so the action always degrades gracefully.

## Context provider, wired by the MatchManager to the live match state.
var context: Callable

const THROUGH_CONE_DEG := 55.0        # how wide the aim cone for through balls is
const SELF_EXCLUDE_M := 0.6           # ignore the passer himself in the teammate list
const CROSS_MIN_ADVANCE_M := 0.0


## Best through-pass aim for `pos` when the human aims along `aim` (planar):
## the most goal-advanced teammate inside the aim cone, aimed into his run via
## PlayerAI.lead_point. Vector3.INF when no candidate fits (fallback).
func through_target(pos: Vector3, aim: Vector3) -> Vector3:
	if not context.is_valid() or aim.length_squared() < 0.0001:
		return Vector3.INF
	var ctx: Dictionary = context.call()
	var goal: Vector3 = ctx["goal"]
	var aim_flat := _flat(aim)
	if aim_flat.length_squared() < 0.0001:
		return Vector3.INF
	aim_flat = aim_flat.normalized()
	var best := Vector3.INF
	var best_advance := -INF
	for t: Vector3 in ctx.get("teammates", []):
		var rel := _flat(t - pos)
		if rel.length() < SELF_EXCLUDE_M:
			continue
		if rel.normalized().dot(aim_flat) < cos(deg_to_rad(THROUGH_CONE_DEG)):
			continue
		var advance := _flat(goal - pos).length() - _flat(goal - t).length()
		if advance > best_advance:
			best_advance = advance
			best = t
	if best == Vector3.INF:
		return Vector3.INF
	return PlayerAI.lead_point(pos, best, goal, ctx.get("opponents", []))


## Cross aim for `pos` (used when wide in the final third): the free teammate
## in the opponent box closest to the goal, slightly ahead of him. The same
## `PlayerAI.cross_target` the AI uses. Vector3.INF when nobody is free.
func cross_target_for(pos: Vector3) -> Vector3:
	if not context.is_valid():
		return Vector3.INF
	var ctx: Dictionary = context.call()
	return PlayerAI.cross_target({"goal": ctx["goal"],
			"teammates": ctx.get("teammates", []), "opponents": ctx.get("opponents", [])})


## DLS-style pressured first touch (P3): an opponent inside
## `PRESSURE_RADIUS` degrades the touch quality linearly down to
## `PRESSURE_FLOOR`; without an assist context the touch is neutral (1.0).
const PRESSURE_RADIUS := 4.0
const PRESSURE_FLOOR := 0.8


func pressure_quality(pos: Vector3) -> float:
	if not context.is_valid():
		return 1.0
	var ctx: Dictionary = context.call()
	var quality := 1.0
	for o: Vector3 in ctx.get("opponents", []):
		var d := _flat(o - pos).length()
		if d < PRESSURE_RADIUS:
			quality = minf(quality, lerpf(PRESSURE_FLOOR, 1.0, d / PRESSURE_RADIUS))
	return quality


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
