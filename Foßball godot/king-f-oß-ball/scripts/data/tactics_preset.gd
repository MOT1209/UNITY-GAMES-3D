class_name TacticsPreset
extends RefCounted

## Team instructions (Phase T3). Values feed the team/manager AI (Phase T11)
## through `target_position()`, a pure function so it is fully testable.

enum Mentality { ULTRA_DEFENSIVE, DEFENSIVE, BALANCED, ATTACKING, ULTRA_ATTACKING }
enum BuildUp { SHORT, MIXED, DIRECT }
enum PassingStyle { SAFE, BALANCED, RISKY }

var preset_name: String = "Default"
var mentality: Mentality = Mentality.BALANCED
var pressing: int = 50          # 0–100
var defensive_line: int = 50    # 0–100 (higher = line further up the pitch)
var build_up: BuildUp = BuildUp.MIXED
var passing_style: PassingStyle = PassingStyle.BALANCED
var width: int = 50             # 0–100 (higher = wider shape; lateral spread 0.7x .. 1.3x)


func validate() -> Array[String]:
	var errors: Array[String] = []
	if preset_name.strip_edges() == "":
		errors.append("tactics preset has empty name")
	if pressing < 0 or pressing > 100:
		errors.append("pressing %d out of range 0-100" % pressing)
	if defensive_line < 0 or defensive_line > 100:
		errors.append("defensive line %d out of range 0-100" % defensive_line)
	if width < 0 or width > 100:
		errors.append("width %d out of range 0-100" % width)
	return errors


## Team-relative y offset applied to the whole shape by mentality (−0.10..+0.10).
func mentality_shift() -> float:
	return (int(mentality) - 2) * 0.05


## Where an AI player should stand: formation slot position adjusted by
## mentality, defensive line (defenders only) and ball progress (0..1).
## Returns Vector2(x, y) in team-relative pitch space, y clamped to [0.02, 0.98].
func target_position(formation_id: String, slot_index: int, ball_progress: float = 0.5) -> Vector2:
	var slot: Array = FormationData.slots(formation_id)[slot_index]
	var pos: int = slot[0]
	var y: float = slot[2]
	y += mentality_shift()
	if pos == PlayerData.Position.CB or pos == PlayerData.Position.LB or pos == PlayerData.Position.RB:
		y += (float(defensive_line) - 50.0) / 50.0 * 0.10
	if pos != PlayerData.Position.GK:
		y += (clampf(ball_progress, 0.0, 1.0) - 0.5) * 0.20
	var x: float = clampf(float(slot[1]) * lerpf(0.7, 1.3, float(width) / 100.0), -1.0, 1.0)
	return Vector2(x, clampf(y, 0.02, 0.98))


## Pressing trigger distance (m) used by AI: 6 m at 0 → 26 m at 100.
func press_distance() -> float:
	return lerpf(6.0, 26.0, float(pressing) / 100.0)


## Distance (m) from goal within which a player with the ball shoots: 24 m, +2.5 per mentality step above
## balanced, +3 for risky passing / -3 for safe passing (a safe team shoots only from closer).
func shoot_range() -> float:
	return 24.0 + (int(mentality) - 2) * 2.5 + (int(passing_style) - 1) * 3.0


## How the AI picks and judges passes, derived from build-up and passing style (all values are used by `PlayerAI`):
##   min_dist / max_dist  usable pass length (m); progress_weight vs dist_weight  forward gain vs. short pass preference;
##   min_progress  minimum gain towards goal (negative = backward/sideways passes allowed);
##   cover_radius  a team-mate with an opponent this close is "covered"; pressure_radius  an opponent this close makes
##   the carrier pass instead of dribbling.
func pass_profile() -> Dictionary:
	var prof := {"min_dist": 6.0, "max_dist": 35.0, "progress_weight": 1.0, "dist_weight": 0.2, "min_progress": 0.0,
			"cover_radius": 3.0, "pressure_radius": 4.0}
	match build_up:
		BuildUp.SHORT:
			prof["max_dist"] = 20.0
			prof["progress_weight"] = 0.6
			prof["dist_weight"] = 0.5
		BuildUp.DIRECT:
			prof["min_dist"] = 12.0
			prof["max_dist"] = 45.0
			prof["progress_weight"] = 1.6
			prof["dist_weight"] = 0.05
	match passing_style:
		PassingStyle.SAFE:
			prof["cover_radius"] = 5.5
			prof["pressure_radius"] = 6.0
			prof["min_progress"] = -6.0
		PassingStyle.RISKY:
			prof["cover_radius"] = 1.5
			prof["pressure_radius"] = 2.5
			prof["min_progress"] = 4.0
	return prof


func to_dict() -> Dictionary:
	return {"name": preset_name, "mentality": Mentality.keys()[mentality], "pressing": pressing,
			"defensive_line": defensive_line, "build_up": BuildUp.keys()[build_up],
			"passing_style": PassingStyle.keys()[passing_style], "width": width}


static func from_dict(d: Dictionary) -> TacticsPreset:
	var t := TacticsPreset.new()
	t.preset_name = str(d.get("name", "Default"))
	var m := str(d.get("mentality", "BALANCED"))
	t.mentality = Mentality[m] if Mentality.has(m) else Mentality.BALANCED
	t.pressing = int(d.get("pressing", 50))
	t.defensive_line = int(d.get("defensive_line", 50))
	var b := str(d.get("build_up", "MIXED"))
	t.build_up = BuildUp[b] if BuildUp.has(b) else BuildUp.MIXED
	var p := str(d.get("passing_style", "BALANCED"))
	t.passing_style = PassingStyle[p] if PassingStyle.has(p) else PassingStyle.BALANCED
	t.width = clampi(int(d.get("width", 50)), 0, 100)
	return t
