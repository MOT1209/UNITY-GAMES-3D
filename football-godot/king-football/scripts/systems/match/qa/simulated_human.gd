class_name SimulatedHuman
extends Node

## A scripted "human" for match measurements (Phase M0): drives `MatchManager.human_intent` in driven, world-space
## mode the way a simple keyboard player would — run with the ball towards goal (dribble + sprint), pass every
## 3-5 s to the closest free team-mate (stick pointed at him, quick tap), shoot inside the box; without the ball
## run at it and tackle when close. It only presses inputs; everything else is the real match engine.

var m: MatchManager
var rng := RandomNumberGenerator.new()
var dribble_only := false            # never pass / shoot (dribble tests)
var _next_pass_at := 0.0
var _release_at := -1.0
var _held: StringName = &""


func attach(p_m: MatchManager, seed_value: int = 1) -> void:
	m = p_m
	rng.seed = seed_value
	m.human_intent.set_driven(true)
	m.human_intent.world_space = true


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _physics_process(_delta: float) -> void:
	if m == null or not is_instance_valid(m) or m.state == null or m.selected.is_empty():
		return
	var hi := m.human_intent
	hi.begin_tick()
	if m.state.phase != MatchState.Phase.PLAYING:
		hi.release_all()
		hi.set_move(Vector2.ZERO)
		return
	var me: Dictionary = m.selected
	var pos := (me["node"] as Node3D).global_position
	var ball := m.ball.global_position
	if _held != &"":
		if m._clock >= _release_at:
			hi.release(_held)
			_held = &""
		return
	var owner := m._owner_entry()
	var side: String = m.setup.human_side
	var goal := PitchSpace.opponent_goal(m.frame_side(side))
	if not owner.is_empty() and owner["player_id"] == me["player_id"]:
		var to_goal := _flat(goal - pos)
		hi.press(&"dribble")
		hi.press(&"sprint")
		var dir := to_goal.normalized()
		hi.set_move(Vector2(dir.x, dir.z))
		if dribble_only:
			return
		if to_goal.length() < 18.0 and m._clock > _next_pass_at - 2.0:
			_kick(&"shoot", dir, 0.05)
			return
		if m._clock >= _next_pass_at:
			var mate := _closest_free_mate(pos)
			if mate != Vector3.INF:
				var d := _flat(mate - pos).normalized()
				_kick(&"pass", d, 0.05)
			_next_pass_at = m._clock + rng.randf_range(3.0, 5.0)
		return
	if _next_pass_at <= 0.0:
		_next_pass_at = m._clock + rng.randf_range(3.0, 5.0)
	hi.release(&"dribble")
	var to_ball := _flat(ball - pos)
	hi.set_move(Vector2(to_ball.normalized().x, to_ball.normalized().z) if to_ball.length() > 0.3 else Vector2.ZERO)
	if to_ball.length() > 6.0:
		hi.press(&"sprint")
	else:
		hi.release(&"sprint")
	if not owner.is_empty() and owner["side"] != side and to_ball.length() < 2.0 and rng.randf() < 0.05:
		hi.press(&"tackle")
	else:
		hi.release(&"tackle")


func _kick(action: StringName, dir: Vector3, hold: float) -> void:
	var hi := m.human_intent
	hi.release(&"dribble")
	hi.set_move(Vector2(dir.x, dir.z))
	hi.press(action)
	_held = action
	_release_at = m._clock + hold


func _closest_free_mate(pos: Vector3) -> Vector3:
	var side: String = m.setup.human_side
	var other := "away" if side == "home" else "home"
	var best := Vector3.INF
	var best_d := INF
	for e in m.entries[side]:
		if e == m.selected or int(e["slot"]) == 0:
			continue
		var p := (e["node"] as Node3D).global_position
		var d := _flat(p - pos).length()
		if d < 5.0 or d > 30.0:
			continue
		var free := true
		for o in m.entries[other]:
			if _flat((o["node"] as Node3D).global_position - p).length() < 3.0:
				free = false
				break
		if free and d < best_d:
			best_d = d
			best = p
	return best
