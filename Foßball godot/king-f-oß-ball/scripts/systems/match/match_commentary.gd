class_name MatchCommentary
extends RefCounted

## Event-driven commentary. A line exists only for an event in `MatchState.events`; wording is picked by the event id
## (deterministic, never random) so the same match always reads the same. Text lives in `translations/commentary.csv`
## (ar / de / en); this class has no strings and no audio. Audio can be attached later by key.

const VARIANTS := {"goal": 3, "own_goal": 2, "save": 2, "foul": 2, "yellow_card": 2, "red_card": 2, "corner": 2,
		"offside": 2, "substitution": 2, "half_time": 1, "full_time": 1}
const SHOW_SECONDS := 4.0

var current: String = ""
var left: float = 0.0
var _seen: int = 0


## Key of the commentary line for `ev`, or "" when this event type has no commentary.
static func key_for(ev: Dictionary) -> String:
	var t := str(ev.get("type", ""))
	if t == "goal" and bool(ev.get("own_goal", false)):
		t = "own_goal"
	if not VARIANTS.has(t):
		return ""
	var n: int = VARIANTS[t]
	var variant := (int(ev.get("id", 0)) % n) + 1
	var name := t.trim_suffix("_card")
	if t == "substitution":
		name = "sub"
	return "COMM_%s_%d" % [name.to_upper(), variant]


## Finished line. `names`: player_id -> display name. Unknown ids give "" for that part, never an invented name.
static func line(ev: Dictionary, names: Dictionary, loc: Node = null) -> String:
	var key := key_for(ev)
	if key == "":
		return ""
	var tr_fn := func(k: String) -> String: return loc.t(k) if loc != null else k
	var text: String = tr_fn.call(key)
	text = text.replace("{player}", str(names.get(str(ev.get("player_id", "")), "")))
	text = text.replace("{victim}", str(names.get(str(ev.get("victim_id", "")), "")))
	text = text.replace("{out}", str(names.get(str(ev.get("out_id", "")), "")))
	if str(ev.get("type", "")) == "goal" and not bool(ev.get("own_goal", false)) and str(ev.get("assist_id", "")) != "":
		text += " " + tr_fn.call("COMM_GOAL_ASSIST").replace("{assist}", str(names.get(str(ev["assist_id"]), "")))
	return text


## Reads new events from the log and shows the latest line for SHOW_SECONDS. Returns the lines produced this call.
func consume(events: Array, names: Dictionary, loc: Node = null) -> Array:
	var out: Array = []
	while _seen < events.size():
		var l := line(events[_seen], names, loc)
		_seen += 1
		if l != "":
			out.append(l)
			current = l
			left = SHOW_SECONDS
	return out


func update(delta: float) -> void:
	if left > 0.0:
		left -= delta
		if left <= 0.0:
			current = ""
