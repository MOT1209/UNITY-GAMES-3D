class_name MatchStats
extends RefCounted

## Measured match statistics (Phase 7.3). Pure bookkeeping, no scene access, JSON-safe.
## It is OWNED by `MatchState` and fed only through `MatchState` methods, so there is a single
## authoritative event pipeline. Everything here is derived from real engine events:
##   * passes  - a pass is started by `FootballActions` (pass/lob); it is SUCCESSFUL when the next
##               player to get the ball is a different team-mate, a FAILURE when an opponent gets it
##               first (or nobody within PASS_WINDOW seconds);
##   * shots   - started by `FootballActions`; ON TARGET when it ends in a goal or a keeper save,
##               otherwise off target / blocked (after SHOT_WINDOW seconds or a possession change);
##   * saves   - the keeper holds the ball while a shot of the other side is pending;
##   * assists - the scorer received a completed pass from a team-mate within ASSIST_WINDOW seconds;
##   * possession - seconds the ball was owned by each side (owner within POSSESSION_RADIUS) while PLAYING.
##   * fouls / cards - recorded by `MatchRules` when a tackle is resolved as a foul; a second yellow card is a red card.
##   * corners / throw-ins / goal kicks / offsides - recorded by `MatchRestarts` when the ball leaves the pitch or an
##     offside pass is received.
## NOT measured (no such mechanic exists): injuries.

const PASS_WINDOW := 4.0
const SHOT_WINDOW := 3.5
const ASSIST_WINDOW := 8.0
## Keys the results screen may show (anything else is not measured and must not be displayed).
const MEASURED: Array[String] = ["score", "scorers", "possession", "shots", "shots_on_target", "passes",
		"pass_accuracy", "saves", "substitutions", "ratings", "fouls", "cards", "corners", "throw_ins", "offsides"]

var teams: Dictionary = {"home": _new_team(), "away": _new_team()}
var players: Dictionary = {}              # player_id -> counters (see _new_player)
var _pending_pass: Dictionary = {}        # {side, player_id, t}
var _pending_shot: Dictionary = {}        # {side, player_id, t}
var _last_completed_pass: Dictionary = {} # {from, to, side, t}


static func _new_team() -> Dictionary:
	return {"possession": 0.0, "shots": 0, "on_target": 0, "passes": 0, "passes_ok": 0, "saves": 0, "subs": 0, "fouls": 0, "yellows": 0, "reds": 0, "corners": 0, "throw_ins": 0, "goal_kicks": 0, "offsides": 0}


static func _new_player(side: String) -> Dictionary:
	return {"side": side, "goals": 0, "own_goals": 0, "assists": 0, "shots": 0, "on_target": 0, "passes": 0,
			"passes_ok": 0, "saves": 0, "subbed_in": false, "fouls": 0, "fouled": 0, "yellow": 0, "red": 0, "offsides": 0}


func register_player(player_id: String, side: String) -> void:
	if not players.has(player_id):
		players[player_id] = _new_player(side)


func _p(player_id: String, side: String) -> Dictionary:
	register_player(player_id, side)
	return players[player_id]


# --- events -----------------------------------------------------------------------------------

func add_possession(side: String, dt: float) -> void:
	if teams.has(side):
		teams[side]["possession"] += maxf(dt, 0.0)


## A pass/lob was played. Resolves an older unresolved pass as incomplete first.
func pass_started(side: String, player_id: String, t: float) -> void:
	if not teams.has(side):
		return
	_resolve_pass(false)
	_pending_pass = {"side": side, "player_id": player_id, "t": t}
	teams[side]["passes"] += 1
	_p(player_id, side)["passes"] += 1


## The ball is now owned by `player_id` of `side` (called on every change of owner).
func owner_changed(side: String, player_id: String, t: float) -> void:
	if not _pending_pass.is_empty() and player_id != _pending_pass["player_id"]:
		if side == _pending_pass["side"]:
			_resolve_pass(true, player_id, t)
		else:
			_resolve_pass(false)
	if not _pending_shot.is_empty() and side != _pending_shot["side"]:
		_pending_shot = {}                 # an opponent got the ball: blocked / cleared, off target


func _resolve_pass(ok: bool, receiver_id: String = "", t: float = 0.0) -> void:
	if _pending_pass.is_empty():
		return
	if ok:
		var side: String = _pending_pass["side"]
		teams[side]["passes_ok"] += 1
		_p(_pending_pass["player_id"], side)["passes_ok"] += 1
		_last_completed_pass = {"from": _pending_pass["player_id"], "to": receiver_id, "side": side, "t": t}
	_pending_pass = {}


func shot_started(side: String, player_id: String, t: float) -> void:
	if not teams.has(side):
		return
	_pending_shot = {"side": side, "player_id": player_id, "t": t}
	teams[side]["shots"] += 1
	_p(player_id, side)["shots"] += 1


## The keeper of `keeper_side` held the ball. Counts a save only if an opposing shot was pending.
## Returns the shooter's id of the saved shot ("" if this was not a save).
func keeper_hold(keeper_side: String, keeper_id: String) -> String:
	if _pending_shot.is_empty() or _pending_shot["side"] == keeper_side:
		return ""
	var shooter: String = _pending_shot["player_id"]
	var shot_side: String = _pending_shot["side"]
	teams[shot_side]["on_target"] += 1
	_p(shooter, shot_side)["on_target"] += 1
	teams[keeper_side]["saves"] += 1
	_p(keeper_id, keeper_side)["saves"] += 1
	_pending_shot = {}
	return shooter


## A goal for `side` by `scorer_id` (own goal when the scorer plays for the other side).
## Returns {"assist": id or "", "own_goal": bool}.
func goal(side: String, scorer_id: String, scorer_side: String, t: float) -> Dictionary:
	var own := scorer_id != "" and scorer_side != "" and scorer_side != side
	var out := {"assist": "", "own_goal": own}
	if own:
		_p(scorer_id, scorer_side)["own_goals"] += 1
		_pending_shot = {}
		return out
	if scorer_id != "":
		_p(scorer_id, side)["goals"] += 1
	if not _pending_shot.is_empty() and _pending_shot["side"] == side and _pending_shot["player_id"] == scorer_id:
		teams[side]["on_target"] += 1
		_p(scorer_id, side)["on_target"] += 1
	elif scorer_id != "":
		# a goal without a registered shot (deflection / dribbled in) still is a shot on target
		teams[side]["shots"] += 1
		teams[side]["on_target"] += 1
		_p(scorer_id, side)["shots"] += 1
		_p(scorer_id, side)["on_target"] += 1
	_pending_shot = {}
	_pending_pass = {}
	var lp := _last_completed_pass
	if scorer_id != "" and not lp.is_empty() and lp["to"] == scorer_id and lp["side"] == side \
			and lp["from"] != scorer_id and t - float(lp["t"]) <= ASSIST_WINDOW:
		out["assist"] = lp["from"]
		_p(lp["from"], side)["assists"] += 1
	_last_completed_pass = {}
	return out


## A foul by `player_id` (side `side`) on `victim_id` (the other side).
func foul(side: String, player_id: String, victim_id: String) -> void:
	if not teams.has(side):
		return
	var other := "away" if side == "home" else "home"
	teams[side]["fouls"] += 1
	_p(player_id, side)["fouls"] += 1
	if victim_id != "":
		_p(victim_id, other)["fouled"] += 1


## Counts a restart of `kind` ("corners", "throw_ins", "goal_kicks") for `side`, the side that takes it.
func restart(side: String, kind: String) -> void:
	if teams.has(side) and teams[side].has(kind):
		teams[side][kind] += 1


## `player_id` of `side` was caught offside.
func offside(side: String, player_id: String) -> void:
	if teams.has(side):
		teams[side]["offsides"] += 1
		_p(player_id, side)["offsides"] += 1


## Shows a yellow card to `player_id`. A second yellow becomes a red card. Returns "yellow" or "red".
func card(side: String, player_id: String) -> String:
	var p := _p(player_id, side)
	p["yellow"] += 1
	teams[side]["yellows"] += 1
	if p["yellow"] >= 2:
		p["red"] = 1
		teams[side]["reds"] += 1
		return "red"
	return "yellow"


## Straight red card.
func red_card(side: String, player_id: String) -> void:
	var p := _p(player_id, side)
	if p["red"] == 0:
		p["red"] = 1
		teams[side]["reds"] += 1


func substitution(side: String, out_id: String, in_id: String) -> void:
	if not teams.has(side):
		return
	teams[side]["subs"] += 1
	_p(in_id, side)["subbed_in"] = true


## Expires unresolved passes / shots whose window has passed.
func tick(t: float) -> void:
	if not _pending_pass.is_empty() and t - float(_pending_pass["t"]) > PASS_WINDOW:
		_resolve_pass(false)
	if not _pending_shot.is_empty() and t - float(_pending_shot["t"]) > SHOT_WINDOW:
		_pending_shot = {}


# --- derived values -------------------------------------------------------------------------

func possession_pct(side: String) -> float:
	var h: float = teams["home"]["possession"]
	var a: float = teams["away"]["possession"]
	if h + a <= 0.0:
		return 50.0
	return 100.0 * float(teams[side]["possession"]) / (h + a)


func pass_accuracy(side: String) -> float:
	var n: int = teams[side]["passes"]
	return 100.0 * float(teams[side]["passes_ok"]) / float(n) if n > 0 else 0.0


## Player rating 3.0..10.0, a deterministic function of MEASURED events only:
## 6.0 base; +1.0 per goal, +0.6 per assist, +0.15 per shot on target, +0.35 per save (keepers),
## ±0.03 per completed/failed pass, -1.0 per own goal; +0.3 / -0.3 for the team's win / loss.
func rating(player_id: String, team_outcome: int) -> float:
	if not players.has(player_id):
		return 6.0
	var p: Dictionary = players[player_id]
	var r := 6.0 + float(p["goals"]) * 1.0 + float(p["assists"]) * 0.6 + float(p["on_target"]) * 0.15 \
			+ float(p["saves"]) * 0.35 + float(p["passes_ok"]) * 0.03 - float(int(p["passes"]) - int(p["passes_ok"])) * 0.03 \
			- float(p["own_goals"]) * 1.0 + 0.3 * float(team_outcome)
	return snappedf(clampf(r, 3.0, 10.0), 0.1)


# --- persistence ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"teams": teams.duplicate(true), "players": players.duplicate(true), "pending_pass": _pending_pass.duplicate(),
			"pending_shot": _pending_shot.duplicate(), "last_pass": _last_completed_pass.duplicate()}


static func from_dict(d: Dictionary) -> MatchStats:
	var s := MatchStats.new()
	for side in ["home", "away"]:
		var t: Dictionary = (d.get("teams", {}) as Dictionary).get(side, {})
		for k in s.teams[side]:
			s.teams[side][k] = float(t.get(k, 0)) if k == "possession" else int(t.get(k, 0))
	for pid in (d.get("players", {}) as Dictionary):
		var src: Dictionary = d["players"][pid]
		var p := _new_player(str(src.get("side", "home")))
		for k in ["goals", "own_goals", "assists", "shots", "on_target", "passes", "passes_ok", "saves", "fouls", "fouled", "yellow", "red", "offsides"]:
			p[k] = int(src.get(k, 0))
		p["subbed_in"] = bool(src.get("subbed_in", false))
		s.players[str(pid)] = p
	s._pending_pass = _pending_from(d.get("pending_pass", {}))
	s._pending_shot = _pending_from(d.get("pending_shot", {}))
	var lp: Dictionary = d.get("last_pass", {})
	if not lp.is_empty():
		s._last_completed_pass = {"from": str(lp.get("from", "")), "to": str(lp.get("to", "")),
				"side": str(lp.get("side", "")), "t": float(lp.get("t", 0.0))}
	return s


static func _pending_from(d: Variant) -> Dictionary:
	if not (d is Dictionary) or (d as Dictionary).is_empty():
		return {}
	return {"side": str(d.get("side", "")), "player_id": str(d.get("player_id", "")), "t": float(d.get("t", 0.0))}
