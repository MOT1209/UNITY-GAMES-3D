class_name MatchPresentation
extends RefCounted

## Match presentation (UX phases 5.4 / 6, split out of `MatchManager`): the referee following play and
## gesturing on events, the spectators' excitement, the kit colours they wear. Pure presentation — it
## reads the match, it never changes the simulation.


## Referee movement / gestures and the stands' excitement (pure presentation).
static func update(m: MatchManager, delta: float) -> void:
	if m.stand_crowd != null:
		if not m.stand_crowd.built:
			var phone := str(GameSettings.get_value("graphics", "shadows")) != "high"
			m.stand_crowd.build(m.get_world_3d().direct_space_state, m.crowd.attendance * (0.6 if phone else 1.0), kit_colors(m),
					m.setup.rng_seed, StandCrowd.MAX_SPECTATORS_LOW if phone else StandCrowd.MAX_SPECTATORS)
		m.stand_crowd.set_excitement(1.0 if m.crowd.mood == "cheer" else m.crowd.loudness() * 0.45)
	if m.referee == null:
		return
	if m.state.phase == MatchState.Phase.PLAYING or m.state.phase == MatchState.Phase.KICKOFF:
		m.referee.follow(m.ball.global_position, delta)
	while m._referee_seen < m.state.events.size():
		var t := str((m.state.events[m._referee_seen] as Dictionary).get("type", ""))
		m._referee_seen += 1
		if t in ["yellow", "red", "card", "yellow_card", "red_card"]:
			m.referee.gesture("card")
		elif t in ["foul", "goal", "half_time", "full_time"]:
			m.referee.gesture("whistle")


static func kit_colors(m: MatchManager) -> Array:
	var out: Array = []
	for side in ["home", "away"]:
		var c := Color(0.6, 0.6, 0.6)
		for e in m.entries[side]:
			if int(e["slot"]) != 0:
				c = (e["kit"] as TeamKit).jersey
				break
		out.append(c)
	return out


## Jersey colour of the human side (the indicator ring's colour); transparent when unknown.
static func human_kit_color(m: MatchManager) -> Color:
	return side_kit_color(m, m.setup.human_side)


static func side_kit_color(m: MatchManager, side: String) -> Color:
	for e in m.entries.get(side, []):
		if int(e["slot"]) != 0:
			return (e["kit"] as TeamKit).jersey
	return Color(0, 0, 0, 0)
