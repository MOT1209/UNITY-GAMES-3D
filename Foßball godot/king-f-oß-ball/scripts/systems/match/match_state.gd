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
## Unique id of this match run (also for friendlies); the key that makes result handling idempotent.
var uid: String = ""
## Measured statistics. Fed ONLY through the methods below (single event pipeline).
var stats: MatchStats = MatchStats.new()
## Set once the result of this match was handed to the career / competition (exactly-once guard).
var result_processed: bool = false


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
	stats.tick(elapsed)
	if half == 1 and elapsed >= duration_seconds / 2.0:
		phase = Phase.HALF_TIME
		events.append({"minute": DISPLAY_MINUTES / 2.0, "type": "half_time", "side": "", "player_id": ""})
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
	var scorer_side: String = stats.players.get(scorer_id, {}).get("side", "")
	var info := stats.goal(side, scorer_id, scorer_side, elapsed)
	events.append({"minute": display_minute(), "type": "goal", "side": side, "player_id": scorer_id,
			"assist_id": info["assist"], "own_goal": info["own_goal"]})
	phase = Phase.KICKOFF          # play restarts from the centre
	return true


## Engine events (each call records exactly one event / counter update).
func record_pass(side: String, player_id: String) -> void:
	if phase == Phase.PLAYING:
		stats.pass_started(side, player_id, elapsed)


func record_shot(side: String, player_id: String) -> void:
	if phase == Phase.PLAYING:
		stats.shot_started(side, player_id, elapsed)
		events.append({"minute": display_minute(), "type": "shot", "side": side, "player_id": player_id})


## A foul. Ignored unless the ball is in play. `kind` of the card ("", "yellow", "red") is decided by `MatchRules`.
func record_foul(side: String, player_id: String, victim_id: String, card_kind: String) -> String:
	if phase != Phase.PLAYING:
		return ""
	stats.foul(side, player_id, victim_id)
	events.append({"minute": display_minute(), "type": "foul", "side": side, "player_id": player_id, "victim_id": victim_id})
	var shown := ""
	if card_kind == "yellow":
		shown = stats.card(side, player_id)
	elif card_kind == "red":
		stats.red_card(side, player_id)
		shown = "red"
	if shown != "":
		events.append({"minute": display_minute(), "type": shown + "_card", "side": side, "player_id": player_id})
	return shown


func record_owner(side: String, player_id: String) -> void:
	if phase == Phase.PLAYING:
		stats.owner_changed(side, player_id, elapsed)


func record_keeper_hold(keeper_side: String, keeper_id: String) -> void:
	if phase != Phase.PLAYING:
		return
	var shooter := stats.keeper_hold(keeper_side, keeper_id)
	if shooter != "":
		events.append({"minute": display_minute(), "type": "save", "side": keeper_side, "player_id": keeper_id,
				"shooter_id": shooter})


func record_substitution(side: String, out_id: String, in_id: String) -> void:
	stats.substitution(side, out_id, in_id)
	subs_used[side] = int(subs_used.get(side, 0)) + 1
	events.append({"minute": display_minute(), "type": "substitution", "side": side, "player_id": in_id, "out_id": out_id})


func record_possession(side: String, delta: float) -> void:
	if phase == Phase.PLAYING:
		stats.add_possession(side, delta)


func register_players(side: String, ids: Array) -> void:
	for pid in ids:
		stats.register_player(pid, side)


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


# --- persistence (match save) ---------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"home_id": home_id, "away_id": away_id, "duration": duration_seconds, "elapsed": elapsed,
			"phase": int(phase), "half": half, "score": score.duplicate(), "events": events.duplicate(true),
			"stamina": stamina.duplicate(), "subs_used": subs_used.duplicate(), "match_id": match_id, "uid": uid,
			"stats": stats.to_dict(), "result_processed": result_processed}


## Restores a saved state into this object (the teams/duration must match the created match).
func apply_dict(d: Dictionary) -> void:
	elapsed = float(d.get("elapsed", 0.0))
	phase = clampi(int(d.get("phase", 0)), 0, 3) as Phase
	half = clampi(int(d.get("half", 1)), 1, 2)
	score = {"home": int((d.get("score", {}) as Dictionary).get("home", 0)), "away": int((d.get("score", {}) as Dictionary).get("away", 0))}
	events = []
	for e in d.get("events", []):
		var ev: Dictionary = (e as Dictionary).duplicate(true)
		ev["minute"] = float(ev.get("minute", 0.0))
		events.append(ev)
	stamina = {}
	for k in (d.get("stamina", {}) as Dictionary):
		stamina[str(k)] = float(d["stamina"][k])
	subs_used = {"home": int((d.get("subs_used", {}) as Dictionary).get("home", 0)), "away": int((d.get("subs_used", {}) as Dictionary).get("away", 0))}
	match_id = str(d.get("match_id", match_id))
	uid = str(d.get("uid", uid))
	stats = MatchStats.from_dict(d.get("stats", {}))
	result_processed = bool(d.get("result_processed", false))
