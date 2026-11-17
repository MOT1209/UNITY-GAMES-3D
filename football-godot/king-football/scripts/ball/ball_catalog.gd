class_name BallCatalog
extends RefCounted

## Match balls (cosmetic only: physics is the same for every ball). Each style drives BallVisual's procedural
## pattern: base / panel colours, panel size and an optional glow for night matches.

const DEFAULT_ID := "classic"

const BALLS: Array[Dictionary] = [
	{"id": "classic", "name_key": "BALL_CLASSIC", "base": Color(0.97, 0.97, 0.94), "panes": Color(0.07, 0.07, 0.08), "size": 18.0, "glow": 0.0},
	{"id": "gold", "name_key": "BALL_GOLD", "base": Color(0.93, 0.74, 0.25), "panes": Color(0.1, 0.08, 0.05), "size": 15.0, "glow": 0.0},
	{"id": "winter", "name_key": "BALL_WINTER", "base": Color(1.0, 0.47, 0.08), "panes": Color(0.12, 0.1, 0.25), "size": 18.0, "glow": 0.0},
	{"id": "retro", "name_key": "BALL_RETRO", "base": Color(0.55, 0.33, 0.17), "panes": Color(0.42, 0.24, 0.12), "size": 24.0, "glow": 0.0},
	{"id": "street", "name_key": "BALL_STREET", "base": Color(0.12, 0.35, 0.9), "panes": Color(1.0, 0.85, 0.1), "size": 13.0, "glow": 0.0},
	{"id": "night", "name_key": "BALL_NIGHT", "base": Color(0.85, 1.0, 0.95), "panes": Color(0.05, 0.3, 0.35), "size": 16.0, "glow": 0.6},
]


static func ids() -> Array[String]:
	var out: Array[String] = []
	for b in BALLS:
		out.append(str(b["id"]))
	return out


static func entry(id: String) -> Dictionary:
	for b in BALLS:
		if b["id"] == id:
			return b
	return BALLS[0]


static func display_name(id: String) -> String:
	return Loc.t(str(entry(id)["name_key"]))


## Applies the style to every BallVisual under `ball`. Returns the id applied ("classic" when unknown).
static func apply_to(ball: Node, id: String) -> String:
	var e := entry(id)
	if ball == null:
		return str(e["id"])
	for v in _visuals(ball):
		v.apply_style(e["base"], e["panes"], float(e["size"]), float(e["glow"]))
	return str(e["id"])


static func _visuals(n: Node) -> Array[BallVisual]:
	var out: Array[BallVisual] = []
	if n is BallVisual:
		out.append(n as BallVisual)
	for c in n.get_children():
		out.append_array(_visuals(c))
	return out
