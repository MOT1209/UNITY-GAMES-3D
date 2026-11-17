class_name MatchQualityProbe
extends Node

## Measures how a live 3D match plays (Phase M0): pass completion and why passes fail, shots, goals, offsides,
## players outside the pitch, players standing still while the ball is in play, how many team-mates crowd the ball
## and how many offer a forward option. Add it as a child of the test scene AFTER `MatchManager.begin()` and call
## `attach(m)`; it reads the match every physics frame and never changes it. `report()` returns the numbers.
## Used by `tools/qa_m3d.tscn` (prints a table) and `tests/match_quality_validation.tscn` (fails out of target).

const SAMPLE_EVERY := 0.5
const OUT_MARGIN := 1.5
const STILL_SPEED := 0.3
const STILL_SECONDS := 3.0
const CROWD_RADIUS := 10.0

var m: MatchManager
var samples := 0
var out_samples := 0                 # player-samples outside the pitch (+ margin) while the ball is in play
var out_by_player: Dictionary = {}   # player_id -> samples outside
var still_samples := 0               # outfield player-samples standing > STILL_SECONDS while the ball is in play
var field_samples := 0
var crowd_sum := 0.0                 # team-mates of the owner within CROWD_RADIUS of the ball
var crowd_n := 0
var human_crowd_sum := 0.0           # same, only while the human side has the ball
var human_crowd_n := 0
var support_ok := 0                  # samples with >= 2 team-mates 10-30 m ahead of the ball (side in possession)
var support_n := 0
var human_support_ok := 0
var human_support_n := 0
## Pass diagnostics: each pass is followed until somebody else owns the ball (or PASS_TIMEOUT).
const PASS_TIMEOUT := 4.0
var pass_log: Array = []             # {side, passer, t, intended, result, receiver_is_target, flyby_speed, min_dist_target}
var _open_pass: Dictionary = {}
var _still_time: Dictionary = {}     # player_id -> seconds below STILL_SPEED
var _acc := 0.0
var _last_owner := ""


func attach(p_m: MatchManager) -> void:
	m = p_m
	m.ball.body_entered.connect(_on_ball_hit)
	for side in ["home", "away"]:
		for e in m.entries[side]:
			var acts := e["actions"] as FootballActions
			if acts == null:
				continue
			var entry: Dictionary = e
			acts.pass_started.connect(func(p: float) -> void: _on_pass(entry, "pass", p))
			acts.lob_started.connect(func(p: float, _l: float) -> void: _on_pass(entry, "lob", p))
			acts.through_started.connect(func(p: float) -> void: _on_pass(entry, "through", p))
			acts.shot_started.connect(func(_p: float, _l: float) -> void: _on_shot(entry))


func _on_pass(e: Dictionary, kind: String, power: float = 0.0) -> void:
	if not _open_pass.is_empty() and _open_pass["side"] == e["side"] and _open_pass["passer"] != e["player_id"]:
		_close_pass("mate", e)                 # first-time pass by the receiver
	elif not _open_pass.is_empty() and _open_pass["passer"] == e["player_id"]:
		_close_pass("again")                   # the passer kicked again (the first kick did not get away)
	else:
		_close_pass("opponent" if not _open_pass.is_empty() else "")
	var intended: Vector3 = e.get("kick_target", Vector3.INF)
	e["kick_target"] = Vector3.INF
	_open_pass = {"side": e["side"], "passer": e["player_id"], "t": m._clock, "kind": kind, "intended": intended,
			"power": power, "result": "", "receiver": "", "flyby_speed": 0.0,
			"min_dist_target": INF, "from": (e["node"] as Node3D).global_position, "dir_err": -1.0, "kick_speed": 0.0, "frames": 0, "hits": []}


## Shots followed to the goal line: where the ball crosses it (or is stopped first) -> on frame / wide / high / blocked.
var shot_log: Array = []
var _open_shot: Dictionary = {}


func _on_shot(e: Dictionary) -> void:
	_close_shot("replaced")
	var goal := PitchSpace.opponent_goal(m.frame_side(e["side"]))
	_open_shot = {"side": e["side"], "t": m._clock, "goal_z": goal.z, "from": (e["node"] as Node3D).global_position}


func _close_shot(result: String) -> void:
	if _open_shot.is_empty():
		return
	_open_shot["result"] = result
	shot_log.append(_open_shot)
	_open_shot = {}


func _follow_shot() -> void:
	if _open_shot.is_empty():
		return
	var b := m.ball.global_position
	var gz: float = _open_shot["goal_z"]
	if absf(b.z) >= absf(gz) - 0.1 and signf(b.z) == signf(gz):
		if absf(b.x) <= 3.66 and b.y <= 2.44:
			_close_shot("frame")
		elif absf(b.x) > 3.66:
			_close_shot("wide")
		else:
			_close_shot("high")
	elif m._clock - float(_open_shot["t"]) > 0.15 and Vector2(m.ball.linear_velocity.x, m.ball.linear_velocity.z).dot(Vector2(0, signf(gz))) < 2.0:
		# stopped / turned back before the line: blocked or saved — on frame if the keeper holds it near his goal
		var keeper_near := absf(b.z) > absf(gz) - 6.0 and absf(b.x) < 6.0
		_close_shot("saved_or_frame" if keeper_near else "blocked")
	elif m._clock - float(_open_shot["t"]) > 3.0:
		_close_shot("none")


func _on_ball_hit(body: Node) -> void:
	if _open_pass.is_empty() or not (body is CharacterBody3D):
		return
	var tag := str(body.name).substr(0, 7)
	if str(body.name).find(str(_open_pass["passer"])) >= 0:
		tag += "(self)"
	(_open_pass["hits"] as Array).append("%s@%.2f" % [tag, m._clock - float(_open_pass["t"])])


func _close_pass(result: String, receiver: Dictionary = {}) -> void:
	if _open_pass.is_empty():
		return
	_open_pass["result"] = result
	_open_pass["dt"] = m._clock - float(_open_pass["t"])
	var from: Vector3 = _open_pass["from"]
	_open_pass["travel"] = Vector2(m.ball.global_position.x - from.x, m.ball.global_position.z - from.z).length()
	var intended: Vector3 = _open_pass["intended"]
	_open_pass["pass_len"] = Vector2(intended.x - from.x, intended.z - from.z).length() if intended != Vector3.INF else -1.0
	if not receiver.is_empty():
		_open_pass["receiver"] = receiver["player_id"]
		_open_pass["flyby_speed"] = Vector2(m.ball.linear_velocity.x, m.ball.linear_velocity.z).length()
	pass_log.append(_open_pass)
	_open_pass = {}


func _physics_process(delta: float) -> void:
	if m == null or not is_instance_valid(m) or m.state == null:
		return
	var playing := m.state.phase == MatchState.Phase.PLAYING
	_follow_shot()
	# --- pass follow-up
	if not _open_pass.is_empty():
		var intended: Vector3 = _open_pass["intended"]
		_open_pass["frames"] = int(_open_pass["frames"]) + 1
		if int(_open_pass["frames"]) <= 30 and int(_open_pass["frames"]) % 3 == 0:
			var bp := m.ball.global_position
			var near := ""
			var nd := INF
			for sd in ["home", "away"]:
				for o in m.entries[sd]:
					var op := (o["node"] as Node3D).global_position
					var dd := Vector2(op.x - bp.x, op.z - bp.z).length()
					if dd < nd:
						nd = dd
						near = "%s%d" % [sd.substr(0, 1), int(o["slot"])]
			(_open_pass["hits"] as Array).append("%.1f/%s%.1f/y%.2f" % [Vector2(m.ball.linear_velocity.x, m.ball.linear_velocity.z).length(), near, nd, bp.y])
		if int(_open_pass["frames"]) == 3:
			var bv := Vector3(m.ball.linear_velocity.x, 0.0, m.ball.linear_velocity.z)
			_open_pass["kick_speed"] = bv.length()
			if intended != Vector3.INF:
				var want := Vector3(intended.x - m.ball.global_position.x, 0.0, intended.z - m.ball.global_position.z)
				if bv.length() > 0.5 and want.length() > 0.5:
					_open_pass["dir_err"] = rad_to_deg(bv.angle_to(want))
		if intended != Vector3.INF:
			var b := m.ball.global_position
			_open_pass["min_dist_target"] = minf(float(_open_pass["min_dist_target"]), Vector2(b.x - intended.x, b.z - intended.z).length())
		var owner := m._owner_entry()
		if not owner.is_empty() and owner["player_id"] != _open_pass["passer"]:
			_close_pass("mate" if owner["side"] == _open_pass["side"] else "opponent", owner)
		elif not playing:
			_close_pass("dead")
		elif m._clock - float(_open_pass["t"]) > PASS_TIMEOUT:
			_close_pass("none")
	# --- still players
	for side in ["home", "away"]:
		for e in m.entries[side]:
			var n := e["node"] as CharacterBody3D
			var sp := Vector2(n.velocity.x, n.velocity.z).length()
			var pid: String = e["player_id"]
			_still_time[pid] = (float(_still_time.get(pid, 0.0)) + delta) if (sp < STILL_SPEED and playing) else 0.0
	_acc += delta
	if _acc < SAMPLE_EVERY or not playing:
		return
	_acc = 0.0
	samples += 1
	var ball := m.ball.global_position
	var owner2 := m._owner_entry()
	var owner_side: String = owner2.get("side", "")
	for side in ["home", "away"]:
		for e in m.entries[side]:
			if e.get("sent_off", false) or m.rules.sent_off.has(e["player_id"]):
				continue
			var p := (e["node"] as Node3D).global_position
			if absf(p.x) > PitchSpace.HALF_WIDTH + OUT_MARGIN or absf(p.z) > PitchSpace.HALF_LENGTH + OUT_MARGIN:
				out_samples += 1
				out_by_player[e["player_id"]] = int(out_by_player.get(e["player_id"], 0)) + 1
				if OS.get_cmdline_user_args().has("dump_out") and int(out_by_player[e["player_id"]]) % 10 == 1:
					var lastev: Dictionary = m.state.events[m.state.events.size() - 1] if not m.state.events.is_empty() else {}
					print("  t %.1f half %d last %s@%.1f |" % [m._clock, m.state.half, str(lastev.get("type", "")), float(lastev.get("t", 0.0))], "  OUT %s slot %d pos (%.1f, %.1f) intent %s state %s ball (%.1f, %.1f) charging %s" % [e["player_id"], int(e["slot"]), p.x, p.z,
							str(e.get("intent", "")), (e["actions"] as FootballActions).get_action_state_name() if e["actions"] != null else "GK", ball.x, ball.z, str(e.get("charging", ""))])
			if int(e["slot"]) == 0:
				continue
			field_samples += 1
			if float(_still_time.get(e["player_id"], 0.0)) > STILL_SECONDS and e != owner2:
				still_samples += 1
	if owner_side == "":
		return
	var near := 0
	var ahead := 0
	var goal := PitchSpace.opponent_goal(m.frame_side(owner_side))
	var ball_to_goal := Vector2(goal.x - ball.x, goal.z - ball.z).length()
	for e in m.entries[owner_side]:
		if e == owner2 or int(e["slot"]) == 0:
			continue
		var p := (e["node"] as Node3D).global_position
		var d := Vector2(p.x - ball.x, p.z - ball.z).length()
		if d < CROWD_RADIUS:
			near += 1
		var gain := ball_to_goal - Vector2(goal.x - p.x, goal.z - p.z).length()
		if d >= 10.0 and d <= 30.0 and gain > 0.0:
			ahead += 1
	crowd_sum += near
	crowd_n += 1
	support_n += 1
	support_ok += 1 if ahead >= 2 else 0
	if owner_side == m.setup.human_side:
		human_crowd_sum += near
		human_crowd_n += 1
		human_support_n += 1
		human_support_ok += 1 if ahead >= 2 else 0


func report() -> Dictionary:
	var st := m.state.stats
	var passes := int(st.teams["home"]["passes"]) + int(st.teams["away"]["passes"])
	var ok := int(st.teams["home"]["passes_ok"]) + int(st.teams["away"]["passes_ok"])
	var shots := int(st.teams["home"]["shots"]) + int(st.teams["away"]["shots"])
	var on_t := int(st.teams["home"]["on_target"]) + int(st.teams["away"]["on_target"])
	var by_result := {}
	var flyby := 0
	var to_target := 0
	var with_target := 0
	for p in pass_log:
		by_result[p["result"]] = int(by_result.get(p["result"], 0)) + 1
		if p["result"] == "opponent" and float(p["flyby_speed"]) > 6.0:
			flyby += 1
		if p["intended"] != Vector3.INF:
			with_target += 1
			if float(p["min_dist_target"]) < 2.0:
				to_target += 1
	var shot_res := {}
	for sh in shot_log:
		shot_res[sh["result"]] = int(shot_res.get(sh["result"], 0)) + 1
	var framed := int(shot_res.get("frame", 0)) + int(shot_res.get("saved_or_frame", 0))
	var errs: Array = []
	var speeds: Array = []
	for p in pass_log:
		if float(p["dir_err"]) >= 0.0:
			errs.append(float(p["dir_err"]))
		speeds.append(float(p["kick_speed"]))
	errs.sort()
	var worst := ""
	var worst_n := 0
	for pid in out_by_player:
		if int(out_by_player[pid]) > worst_n:
			worst_n = int(out_by_player[pid])
			worst = pid
	return {"passes": passes, "passes_ok": ok, "pass_pct": 100.0 * ok / maxf(passes, 1.0),
			"home_pass_pct": st.pass_accuracy("home"), "away_pass_pct": st.pass_accuracy("away"),
			"probe_pass_pct": 100.0 * int(by_result.get("mate", 0)) / maxf(pass_log.size(), 1.0),
			"pass_results": by_result, "flyby_losses": flyby, "reached_target_pct": 100.0 * to_target / maxf(with_target, 1.0),
			"dir_err_median": errs[errs.size() / 2] if not errs.is_empty() else -1.0,
			"dir_err_p90": errs[int(errs.size() * 0.9)] if not errs.is_empty() else -1.0,
			"kick_speed_avg": _avg(speeds),
			"shot_results": shot_res, "frame_pct": 100.0 * framed / maxf(shot_log.size(), 1.0),
			"shots": shots, "on_target": on_t, "on_target_pct": 100.0 * on_t / maxf(shots, 1.0),
			"goals": int(m.state.score["home"]) + int(m.state.score["away"]),
			"score": "%d-%d" % [int(m.state.score["home"]), int(m.state.score["away"])],
			"offsides": int(st.teams["home"]["offsides"]) + int(st.teams["away"]["offsides"]),
			"out_samples": out_samples, "worst_out": "%s:%d" % [worst, worst_n],
			"still_pct": 100.0 * still_samples / maxf(field_samples, 1.0),
			"crowd": crowd_sum / maxf(crowd_n, 1.0), "human_crowd": human_crowd_sum / maxf(human_crowd_n, 1.0),
			"support_pct": 100.0 * support_ok / maxf(support_n, 1.0),
			"human_support_pct": 100.0 * human_support_ok / maxf(human_support_n, 1.0), "samples": samples}


static func _avg(a: Array) -> float:
	var s := 0.0
	for v in a:
		s += float(v)
	return s / maxf(a.size(), 1.0)
