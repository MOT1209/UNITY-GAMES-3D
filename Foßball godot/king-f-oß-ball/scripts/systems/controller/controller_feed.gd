class_name KingControllerFeed
extends RefCounted

## PC -> phone match feed: compact `state` frames (score, clock, possession, shots, normalised positions) and
## `event` frames (goal, cards, substitutions, saves). Pure functions over `MatchState` and real entity positions,
## so they are testable without a socket. Nothing is invented: a value is sent only if the match measured it.
## Positions are normalised per viewer: x, y in -1..1 with the viewer's OWN goal at the bottom (y = -1).

const STATE_INTERVAL := 0.2             # seconds between state frames (5 Hz is plenty for a dashboard / mini-map)
const EVENT_TYPES := ["goal", "yellow_card", "red_card", "substitution", "save", "penalty_kick"]
const MAX_FEED_BYTES := 900             # a state frame stays far below any phone-side limit


## Normalises a pitch position for `you_side` (own goal at the bottom).
static func norm(pos: Vector2, you_side: String) -> Array:
	var f := -signf(PitchSpace.side_sign(you_side))
	return [snappedf(clampf(pos.x / PitchSpace.HALF_WIDTH * f, -1.1, 1.1), 0.01),
			snappedf(clampf(pos.y / PitchSpace.HALF_LENGTH * f, -1.1, 1.1), 0.01)]


## `positions`: {"home": Array[Vector2], "away": Array[Vector2]} (x, z in metres), `ball`: Vector2.
static func state_frame(state: MatchState, positions: Dictionary, ball: Vector2, you_side: String) -> Dictionary:
	var other := "away" if you_side == "home" else "home"
	var st: MatchStats = state.stats
	var mine: Array = []
	for p in positions.get(you_side, []):
		mine.append_array(norm(p, you_side))
	var theirs: Array = []
	for p in positions.get(other, []):
		theirs.append_array(norm(p, you_side))
	var t: Dictionary = st.teams[you_side]
	var o: Dictionary = st.teams[other]
	return {"v": KingControllerProtocol.PROTOCOL_VERSION, "type": "state", "you": you_side, "clock": state.clock_text(),
			"half": state.half, "phase": int(state.phase), "score": [int(state.score[you_side]), int(state.score[other])],
			"poss": [snappedf(st.possession_pct(you_side), 1.0), snappedf(st.possession_pct(other), 1.0)],
			"shots": [int(t["shots"]), int(o["shots"])], "sot": [int(t["on_target"]), int(o["on_target"])],
			"cards": [int(t["yellows"]), int(t["reds"]), int(o["yellows"]), int(o["reds"])],
			"ball": norm(ball, you_side), "me": mine, "opp": theirs}


## Phone-side event for a logged event, or {} when this type is not sent. `mine` = the event belongs to the viewer's side.
## `names`: player_id -> display name; an unknown id gives an empty name.
static func event_frame(ev: Dictionary, names: Dictionary, you_side: String) -> Dictionary:
	var kind := str(ev.get("type", ""))
	if not kind in EVENT_TYPES:
		return {}
	var out := {"v": KingControllerProtocol.PROTOCOL_VERSION, "type": "event", "kind": kind, "id": int(ev.get("id", 0)),
			"minute": snappedf(float(ev.get("minute", 0.0)), 0.1), "mine": str(ev.get("side", "")) == you_side,
			"player": str(names.get(str(ev.get("player_id", "")), ""))}
	if kind == "goal":
		out["own_goal"] = bool(ev.get("own_goal", false))
	return out
