class_name MatchState
extends RefCounted

## Pure match bookkeeping (Phase T11): score, clock, halves, events,
## stamina, result creation. No scene dependencies, fully testable.

enum Phase { KICKOFF, PLAYING, HALF_TIME, FINISHED }
const DISPLAY_MINUTES := 90.0

var home_id: String = ""
var away_id: String = ""
var duration_seconds: float = 600.0     # real seconds for the whole match
var elapsed: float = 0.0
var phase: Phase = Phase.KICKOFF
var half: int = 1
var score: Dictionary = {"home": 0, "away": 0}
var events: Array = []                  # {minute, type, side, player_id}
var stamina: Dictionary = {}            # player_id -> 0..100
var subs_used: Dictionary = {"home": 0, "away": 0}
var match_id: String = ""


static func create(p_home: String, p_away: String, minutes: int, p_match_id: String = "") -> MatchState:
	var s := MatchState.new()
	s.home_id = p_home
	s.away_id = p_away
	s.duration_seconds = maxf(float(minutes) * 60.0, 1.0)
	s.match_id = p_match_id
	return s


func kick_off() -> void:
	if phase == Phase.KICKOFF:
		phase = Phase.PLAYING


## Advances the clock while PLAYING. Ends the first half / the match on time.
func tick(delta: float) -> void:
	if phase != Phase.PLAYING:
		return
	elapsed = minf(elapsed + delta, duration_seconds)
	if half == 1 and elapsed >= duration_seconds / 2.0:
		phase = Phase.HALF_TIME
	elif elapsed >= duration_seconds:
		phase = Phase.FINISHED
		events.append({"minute": DISPLAY_MINUTES, "type": "full_time", "side": "", "player_id": ""})


func start_second_half() -> bool:
	if phase != Phase.HALF_TIME:
		return false
	half = 2
	phase = Phase.KICKOFF
	return true


## Registers a goal for `side` ("home"/"away"). Ignored unless the ball is in play.
func goal(side: String, scorer_id: String = "") -> bool:
	if phase != Phase.PLAYING or not score.has(side):
		return false
	score[side] += 1
	events.append({"minute": display_minute(), "type": "goal", "side": side, "player_id": scorer_id})
	phase = Phase.KICKOFF          # play restarts from the centre
	return true


func is_finished() -> bool:
	return phase == Phase.FINISHED


## Match minute on the 0–90 scale shown to the player.
func display_minute() -> float:
	return clampf(elapsed / duration_seconds * DISPLAY_MINUTES, 0.0, DISPLAY_MINUTES)


func clock_text() -> String:
	var m := int(display_minute())
	var s := int((display_minute() - m) * 60.0)
	return "%02d:%02d" % [m, s]


func goal_difference(side: String) -> int:
	return int(score[side]) - int(score["away" if side == "home" else "home"])


func init_stamina(player_ids: Array) -> void:
	for pid in player_ids:
		stamina[pid] = 100.0


## Drains stamina for one player (rate depends on running speed ratio 0..1 and
## the player's `physical` rating). Returns the new value.
func drain_stamina(player_id: String, delta: float, speed_ratio: float, physical: int) -> float:
	if not stamina.has(player_id):
		return 0.0
	var rate := (0.25 + 1.0 * clampf(speed_ratio, 0.0, 1.0)) * lerpf(1.3, 0.7, float(physical) / 99.0)
	# rate is "stamina points per 100 s of full-time-scaled match clock"
	var per_match_second := DISPLAY_MINUTES * 60.0 / duration_seconds
	stamina[player_id] = maxf(float(stamina[player_id]) - rate * delta * per_match_second / 60.0, 0.0)
	return stamina[player_id]


## Final result for competitions. Knockout draws need `rng` for penalties.
func to_result(knockout: bool = false, rng: RandomNumberGenerator = null,
		home_rating: int = 60, away_rating: int = 60) -> MatchResult:
	var hg: int = score["home"]
	var ag: int = score["away"]
	if knockout and hg == ag:
		var pens := PenaltyShootout.resolve(home_rating, away_rating, rng)
		return MatchResult.make(match_id, home_id, away_id, hg, ag, pens[0], pens[1])
	return MatchResult.make(match_id, home_id, away_id, hg, ag)
