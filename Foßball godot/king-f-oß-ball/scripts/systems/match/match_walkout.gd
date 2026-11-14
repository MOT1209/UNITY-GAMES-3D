class_name MatchWalkout
extends RefCounted

## Pre-match walk-out (UX phase 6, kept out of `MatchManager`): both teams line up side by side by the
## touchline at halfway and walk to their kick-off positions through temporary AI intents (so they move
## with move_and_slide and animate), under the TV camera; then the human gets his player back.


## Both teams line up side by side at the halfway line by the touchline (the tunnel side), then walk to
## their kick-off positions under the TV camera; kick-off follows. Skippable (pause / accept).
static func start(m: MatchManager) -> void:
	m.walkout_left = MatchManager.WALKOUT_SECONDS
	m._pause_left = MatchManager.WALKOUT_SECONDS
	for side in ["home", "away"]:
		var lane_z := -1.6 if side == "home" else 1.6
		for e in m.entries[side]:
			var node := e["node"] as CharacterBody3D
			node.global_position = Vector3(-PitchSpace.HALF_WIDTH - 1.0 + float(e["slot"]) * 1.4, 0.05, lane_z)
			node.velocity = Vector3.ZERO
			node.rotation.y = -PI * 0.5            # facing into the pitch (+X)
			if node is PlayerController:
				var temp := AIIntent.new()
				m._walkout_intents[node] = temp
				node.intent = temp
				if e["actions"] != null:
					(e["actions"] as FootballActions).intent = temp
	if m.camera != null and m.camera.has_method("set_mode"):
		m.camera.set_mode(GameCamera.Mode.BROADCAST)


## Every tick of the walk-out: each player walks (no sprint) towards his kick-off spot.
static func step(m: MatchManager, delta: float) -> void:
	m.walkout_left -= delta
	for side in m.entries:
		for e in m.entries[side]:
			var node := e["node"] as Node3D
			var intent: AIIntent = m._walkout_intents.get(node)
			if intent == null:
				continue
			intent.begin_tick()
			var to := m._kickoff_position(side, int(e["slot"])) - node.global_position
			to.y = 0.0
			intent.set_move_world(to.normalized() * 0.5 if to.length() > 0.6 else Vector3.ZERO)
	if m.walkout_left <= 0.0:
		finish(m)


## Ends the walk-out (time up or skipped): intents back to AI / human, camera back to the saved choice.
static func finish(m: MatchManager) -> void:
	m.walkout_left = 0.0
	m._pause_left = minf(m._pause_left, 0.3)
	for side in m.entries:
		for e in m.entries[side]:
			var node := e["node"] as Node3D
			if not m._walkout_intents.has(node):
				continue
			var ai: AIIntent = e["ai"]
			if ai != null:
				node.intent = ai
				if e["actions"] != null:
					(e["actions"] as FootballActions).intent = ai
	m._walkout_intents.clear()
	if not m.selected.is_empty():
		m._select(m.selected)                           # the human takes his player back
	if m.camera != null and m.camera.has_method("set_mode") and m.setup.human_side != "none" \
			and str(GameSettings.get_value("match", "camera")) == "follow":
		m.camera.set_mode(GameCamera.Mode.FOLLOW)
