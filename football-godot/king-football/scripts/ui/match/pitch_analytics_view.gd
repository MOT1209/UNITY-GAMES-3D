class_name PitchAnalyticsView
extends Control

## Draws one team's heat map (position-sample counts) or shot map on a pitch in the team's own frame: the team attacks UPWARD,
## left/right as seen facing the opponent's goal. Pure drawing of data from `MatchReport` (heat grid, shot_map); nothing is invented.
## Heat intensity is relative to the busiest cell of the grid. Shots: dot area grows with the (estimated) xG, a goal is filled gold.

enum Mode { HEAT, SHOTS }

const PITCH := Color(0.07, 0.25, 0.12)
const LINE := Color(1, 1, 1, 0.35)
const HEAT := Color(1.0, 0.55, 0.1)

var mode: Mode = Mode.HEAT
var grid: Array = []                 # HEAT: counts, ExpectedGoals.HEAT_COLS * HEAT_ROWS
var shots: Array = []                # SHOTS: report["shot_map"] entries of ONE side


static func heat(counts: Array, size: Vector2) -> PitchAnalyticsView:
	var v := PitchAnalyticsView.new()
	v.mode = Mode.HEAT
	v.grid = counts
	v.custom_minimum_size = size
	return v


static func shot_map(side_shots: Array, size: Vector2) -> PitchAnalyticsView:
	var v := PitchAnalyticsView.new()
	v.mode = Mode.SHOTS
	v.shots = side_shots
	v.custom_minimum_size = size
	return v


## Pixel position of a team-frame point (v left..right, u own goal..opponent goal) inside `r`.
static func to_pixel(f: Vector2, r: Rect2) -> Vector2:
	return Vector2(r.position.x + f.x * r.size.x, r.position.y + (1.0 - f.y) * r.size.y)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, PITCH)
	if mode == Mode.HEAT:
		var cols := ExpectedGoals.HEAT_COLS
		var rows := ExpectedGoals.HEAT_ROWS
		var peak := 0
		for c in grid:
			peak = maxi(peak, int(c))
		if peak > 0 and grid.size() == cols * rows:
			for row in rows:
				for col in cols:
					var n := int(grid[row * cols + col])
					if n == 0:
						continue
					var a := 0.15 + 0.75 * float(n) / float(peak)
					var cw := r.size.x / cols
					var ch := r.size.y / rows
					draw_rect(Rect2(r.position.x + col * cw, r.position.y + (rows - 1 - row) * ch, cw, ch), Color(HEAT.r, HEAT.g, HEAT.b, a))
	# markings: outline, halfway line, both penalty areas (105 x 68 m pitch)
	draw_rect(r, LINE, false, 1.0)
	draw_line(Vector2(0, r.size.y * 0.5), Vector2(r.size.x, r.size.y * 0.5), LINE, 1.0)
	var bw := FootballPitch.PENALTY_AREA_WIDTH / (PitchSpace.HALF_WIDTH * 2.0) * r.size.x
	var bh := FootballPitch.PENALTY_AREA_DEPTH / (PitchSpace.HALF_LENGTH * 2.0) * r.size.y
	draw_rect(Rect2((r.size.x - bw) * 0.5, 0.0, bw, bh), LINE, false, 1.0)
	draw_rect(Rect2((r.size.x - bw) * 0.5, r.size.y - bh, bw, bh), LINE, false, 1.0)
	if mode == Mode.SHOTS:
		for s in shots:
			var f := ExpectedGoals.team_frame(float(s["x"]), float(s["z"]), str(s["side"]), int(s.get("half", 1)))
			var p := to_pixel(f, r)
			var radius := 3.0 + 14.0 * sqrt(clampf(float(s.get("xg", 0.05)), 0.0, 1.0))
			var goal: bool = str(s.get("outcome", "")) == "goal"
			if goal:
				draw_circle(p, radius, Color(1.0, 0.84, 0.2, 0.95))
			else:
				draw_arc(p, radius, 0.0, TAU, 20, Color(1, 1, 1, 0.9), 1.5)
