class_name MatchManager
extends Node3D

## Match engine (Phase T11). Builds a real match from a `MatchSetup`: arena,
## ball, 22 players (existing `player.tscn` + `FootballActions`) positioned
## from the squads' formations, player attributes applied through
## `AttributeModifiers`, three AI layers (PlayerAI / TeamAI / ManagerAI),
## goals, clock, half-time, full time and a `MatchResult` for competitions.
## It reuses the existing player controller, ball physics and arena; it adds
## no second implementation of any of them.

signal goal_scored(side: String, scorer_id: String)
signal match_finished(result: MatchResult)
## Emitted when the player leaves the results screen (Continue).
signal results_closed
## Emitted when the player restarts or quits from the pause menu (the match is abandoned, no result).
signal restart_requested(new_setup: MatchSetup)
signal quit_requested

const ARENA_SCENE := "res://scenes/stadium/stadium_arena.tscn"
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const KEEPER_SCENE := "res://scenes/teams/team_goalkeeper.tscn"
const KEEPER_SPRINT_SPEED := 6.0
const BALL_SCENE := "res://scenes/ball/football_ball.tscn"
const THINK_INTERVAL: Array[float] = [0.30, 0.18, 0.10]   # by difficulty
const POSSESSION_RADIUS := 1.5
const GOAL_PAUSE := 2.5
const HALF_TIME_PAUSE := 3.0
const MANAGER_INTERVAL := 5.0
const REPLAY_SECONDS := 5.0              # length of the clip shown after a goal
const REPLAY_SPEED := 0.6                # slow motion
const CHARGE_TIME := {&"shoot": 0.10, &"pass": 0.15, &"lob_pass": 0.25}   # shoot: a quick tap (default power) leaves the ball no time to drift

@export var return_to_menu_on_finish: bool = true

var setup: MatchSetup
var db: Node
var state: MatchState
var sides: Dictionary = {}               # "home"/"away" -> MatchSetup.build_side() dict
var entries: Dictionary = {"home": [], "away": []}   # per side: Array of entry Dictionaries
var ball: BallController
var arena_root: Node3D
var camera: Node
var selected: Dictionary = {}            # entry controlled by the human
## The single human intent channel (P2 input hardening): created once, shared
## by every selection, and read for gameplay actions (switch_player). Raw mode
## reads the global Input exactly as before; a touch UI or a remote controller
## (KING CONTROLLER) later flips it to driven mode and feeds it directly, so
## gameplay code never changes again.
var human_intent := IntentProvider.new()
var last_toucher_id: String = ""
## Ring / arrow under the human-controlled player (null when nobody is human-controlled).
var selection_indicator: SelectionIndicator
## Second human (P10): a friend on a second KING CONTROLLER phone (slot 2) takes over the OPPOSING side. It is
## seat-based and dynamic: while no second phone is connected the side is plain AI, exactly as before. Seat 2 has
## its own intent, selected player, indicator (slot colour 2), auto-switch policy and aim assist.
var human_intent2 := IntentProvider.new()
var selected2: Dictionary = {}
var selection_indicator2: SelectionIndicator
var switch_policy2: AutoSwitchPolicy
var _assist2: HumanAimAssist
var _seat2_wanted := false
var _seat_ready := false                # set once the match is fully built (seat 2 is never filled earlier)
## Automatic switching (pass receiver / loss of possession), see `AutoSwitchPolicy`.
var switch_policy: AutoSwitchPolicy
## Aim assist for the human (settings: controls / aim_assist). Read once when the match is built.
var aim_assist_enabled := true
## Presentation (UX phase 6): the referee model following play and the animated spectators.
var referee: MatchReferee
var stand_crowd: StandCrowd
var _referee_seen := 0
var _possession_side: String = ""        # side that last controlled the ball (possession statistic)

## Setup as it was at kick-off (copy with its own squads): used by restart and match saves.
var initial_setup_dict: Dictionary = {}
var report: Dictionary = {}              # MatchReport of the finished match
var rules: MatchRules
## Event-driven commentary text (shown in the HUD notice when nothing more urgent is displayed).
var commentary := MatchCommentary.new()
var _commentary_events: int = 0
var crowd: CrowdSystem
var _assist: HumanAimAssist
var replay_buffer: ReplayBuffer
var replay_player: ReplayPlayer
var replay_director: ReplayDirector
## Seconds of the pre-match walk-out still to play (0 = none / finished).
const WALKOUT_SECONDS := 5.0
var walkout_left := 0.0
## Shoot-out on the pitch for level knockout matches (human playing, or forced by tests).
var penalty_duel: PenaltyDuel
var force_3d_shootout := false
var _shootout_done := false
var _walkout_intents: Dictionary = {}     # node -> temporary AIIntent while the teams walk out
var last_replay_seconds: float = 0.0     # real seconds the last goal replay lasts (clip length / slow-motion speed)
var _crowd_audio: CrowdAudio
var _sounds: MatchSounds
var results_view: MatchResultsView
var pause_menu: PauseMenu
var _device_monitor: InputDeviceMonitor
## Ring under the expected receiver while the human charges a pass (Phase M1).
var pass_marker: PassTargetMarker
## Mini-map at the bottom centre (Phase H1).
var radar: MatchRadar
## F8 bug report / F9 debug view (Phase M0).
var debug_tools: MatchDebugTools
var abandoned := false                   # the player quit/restarted: no result may be recorded

var _hud_layer: CanvasLayer
var hud: MatchHud
var _touch: TouchControls
var _pause_left: float = 0.5
var _needs_reset: bool = true
var _half_handled: bool = false
var _manager_timer: float = 0.0
var _heat_timer: float = 0.0
var _finished_emitted: bool = false
var _clock: float = 0.0
var _rng := RandomNumberGenerator.new()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and rules != null:
		rules.release()          # rules <-> restarts reference each other


## Builds the match. Returns "" or an error text (nothing is spawned on error).
func begin(p_setup: MatchSetup, p_db: Node) -> String:
	var problems := p_setup.validate(p_db)
	if not problems.is_empty():
		return problems[0]
	db = p_db
	# The match plays on its OWN copy of the squads: manager-AI substitutions must never rewrite the
	# career's lineups. `initial_setup_dict` keeps the kick-off state for restarts and saves.
	setup = p_setup.duplicate_for_match(p_db)
	initial_setup_dict = setup.to_dict().duplicate(true)      # deep: the live squads are mutated later
	_rng.seed = setup.rng_seed
	state = MatchState.create(setup.home_id, setup.away_id, setup.duration_minutes, setup.match_id)
	state.uid = "mu_%d_%d" % [int(Time.get_unix_time_from_system()), setup.rng_seed]
	for side in ["home", "away"]:
		sides[side] = setup.build_side(db, side)
	# P3: one aim assist for the human side, fed from the live match state via
	# a bound Callable (dependency injection — the assist never reaches into
	# the manager). AI players keep their own context and are untouched.
	_assist = HumanAimAssist.new()
	_assist.context = _aim_context.bind(setup.human_side)
	rules = MatchRules.new(self)
	_build_arena()
	MatchEnvironment.apply(arena_root, setup.conditions)
	replay_buffer = ReplayBuffer.new(23, 10.0)
	var home_rep: int = db.get_team(setup.home_id).reputation
	crowd = CrowdSystem.new(clampf(0.55 + float(home_rep) / 250.0, 0.3, 1.0), 1.3 if setup.knockout else 1.0)
	if DisplayServer.get_name() != "headless":
		if MatchSounds.available():
			_sounds = MatchSounds.new()
			_sounds.crowd = crowd
			_sounds.state = state
			add_child(_sounds)
		else:
			_crowd_audio = CrowdAudio.new()             # no recorded files: the synthesized bed
			_crowd_audio.crowd = crowd
			add_child(_crowd_audio)
	_spawn_ball()
	for side in ["home", "away"]:
		_spawn_team(side)
	referee = MatchReferee.new()
	add_child(referee)
	referee.global_position = Vector3(-6.0, 0.0, 8.0)
	stand_crowd = StandCrowd.new()
	add_child(stand_crowd)        # filled on the first physics tick (needs the stadium collision)
	var ids: Array = []
	for side in ["home", "away"]:
		for e in entries[side]:
			ids.append(e["player_id"])
	state.init_stamina(ids)
	for side in ["home", "away"]:
		state.register_players(side, entries[side].map(func(e: Dictionary) -> String: return e["player_id"]))
	_build_hud()
	debug_tools = MatchDebugTools.new(self)
	add_child(debug_tools)
	radar = MatchRadar.new(self)                         # Phase H1
	_hud_layer.add_child(radar)
	if hud != null and setup.competition_id != "":
		var hub := get_node_or_null("/root/AppHub")
		hud.set_competition(str(hub.competition_title(setup.competition_id)) if hub != null and hub.career != null else setup.competition_id)
	aim_assist_enabled = bool(GameSettings.get_value("controls", "aim_assist"))
	if setup.human_side != "none":
		var mode := setup.switch_mode if setup.switch_mode in GameSettings.SWITCH_MODES \
				else str(GameSettings.get_value("match", "switch_mode"))
		switch_policy = AutoSwitchPolicy.new(mode, setup.human_side)
		selection_indicator = SelectionIndicator.new(0, _human_kit_color())
		_select(_closest_to_ball(setup.human_side, -1))
		if camera != null and camera.has_method("set_mode") and str(GameSettings.get_value("match", "camera")) == "follow":
			camera.set_mode(GameCamera.Mode.FOLLOW)
	if camera != null and camera.has_method("track_ball"):
		camera.track_ball(ball)
	if setup.walkout:
		_start_walkout()
	_apply_resume()
	_seat_ready = true
	_sync_seat2()                    # a second phone that paired before the match starts playing at once
	return ""


## Phase S2 (the other direction): "simulate the rest" — the event engine plays the remaining minutes from the current score
## and the match ends at once (goals are logged with their scorers, the normal full-time flow follows).
func simulate_rest() -> void:
	if state == null or state.phase == MatchState.Phase.FINISHED:
		return
	var minute := int(state.display_minute())
	var live := MatchEventEngine.LiveMatch.new(db, setup.home_id, setup.away_id, setup.rng_seed + minute)
	live.minute = minute
	live.weather = str(setup.conditions.get("weather", "clear"))
	live.score = {"home": int(state.score["home"]), "away": int(state.score["away"])}
	var before: Dictionary = live.score.duplicate()
	while not live.finished():
		for ev in live.step():
			if str(ev["type"]) == "goal":
				state.stats.register_player(str(ev["player_id"]), str(ev["side"]))
				state.stats.players[str(ev["player_id"])]["goals"] += 1
				state.stats.teams[str(ev["side"])]["shots"] += 1
				state.stats.teams[str(ev["side"])]["on_target"] += 1
				state.log_event({"minute": float(ev["minute"]), "type": "goal", "side": str(ev["side"]), "player_id": str(ev["player_id"]),
						"assist_id": str(ev["assist_id"]), "own_goal": false})
	state.score = {"home": int(live.score["home"]), "away": int(live.score["away"])}
	state.elapsed = state.duration_seconds
	state.phase = MatchState.Phase.FINISHED
	if get_tree().paused:
		resume_match()


## Phase S2 "play from this minute": takes the minute, score, cards and goals of a live simulation (`AppHub.pending_resume`).
func _apply_resume() -> void:
	var hub := get_node_or_null("/root/AppHub")
	if hub == null or (hub.pending_resume as Dictionary).is_empty():
		return
	var r: Dictionary = hub.pending_resume
	hub.pending_resume = {}
	var minute := clampi(int(r.get("minute", 0)), 0, 89)
	state.elapsed = float(minute) / MatchState.DISPLAY_MINUTES * state.duration_seconds
	for side in ["home", "away"]:
		state.score[side] = int((r.get("score", {}) as Dictionary).get(side, 0))
		for k in ["shots", "on_target", "corners", "fouls", "yellows", "reds"]:
			if state.stats.teams[side].has(k) and (r.get("stats", {}) as Dictionary).has(side):
				state.stats.teams[side][k] = int(r["stats"][side].get(k, 0))
	state.stats.teams["home"]["possession"] = float(r.get("stats", {}).get("home", {}).get("possession", 50))
	state.stats.teams["away"]["possession"] = float(r.get("stats", {}).get("away", {}).get("possession", 50))
	for ev in r.get("events", []):
		if str(ev.get("type", "")) == "goal":
			var sc := str(ev["player_id"])
			state.stats.register_player(sc, str(ev["side"]))
			state.stats.players[sc]["goals"] += 1
			if str(ev.get("assist_id", "")) != "":
				state.stats.register_player(str(ev["assist_id"]), str(ev["side"]))
				state.stats.players[str(ev["assist_id"])]["assists"] += 1
			state.log_event({"minute": float(ev["minute"]), "type": "goal", "side": str(ev["side"]), "player_id": sc, "assist_id": str(ev.get("assist_id", "")), "own_goal": false})
	if minute >= 45:
		state.half = 2
		state.phase = MatchState.Phase.KICKOFF
		_needs_reset = true


func _start_walkout() -> void:
	MatchWalkout.start(self)


func walkout_active() -> bool:
	return walkout_left > 0.0


func _step_walkout(delta: float) -> void:
	MatchWalkout.step(self, delta)


## Ends the walk-out (time up or skipped).
func end_walkout() -> void:
	MatchWalkout.finish(self)


## Referee, spectators (see `MatchPresentation`).
func _update_presentation(delta: float) -> void:
	MatchPresentation.update(self, delta)


func _human_kit_color() -> Color:
	return MatchPresentation.human_kit_color(self)


# --- construction# --- construction -------------------------------------------------------------------------

func _build_arena() -> void:
	arena_root = (load(ARENA_SCENE) as PackedScene).instantiate()
	add_child(arena_root)
	if arena_root.has_method("embed_in_match"):
		arena_root.embed_in_match()               # regression: Esc used to drop straight to the menu; texts are localized
	var default_player := arena_root.get_node_or_null("Player")
	if default_player != null:
		default_player.queue_free()          # the match spawns its own players
	camera = arena_root.get_node_or_null("GameCamera")
	var arena := arena_root.get_node_or_null("Arena")
	if arena != null and arena.has_signal("goal_entered"):
		arena.goal_entered.connect(_on_goal_entered)


func _spawn_ball() -> void:
	ball = (load(BALL_SCENE) as PackedScene).instantiate()
	add_child(ball)
	ball.global_position = Vector3(0.0, 0.3, 0.0)
	var kick_fx := KickEffects.new()
	kick_fx.name = "KickEffects"
	add_child(kick_fx)
	kick_fx.setup(ball)


func _spawn_team(side: String) -> void:
	MatchTeamBuilder.spawn_team(self, side)


func _entry_id(side: String, slot: int) -> String:
	return MatchTeamBuilder.entry_id(self, side, slot)


func _dress(node: Node, pdata: PlayerData, kit: TeamKit, slot: int) -> void:
	MatchTeamBuilder.dress(self, node, pdata, kit, slot)


## Geometry frame of `side`.## Geometry frame of `side`. The teams change ends for the second half, so every
## attack-direction / goal / formation calculation uses the opposite frame then;
## ownership (score, squads, kits) always stays with the real side.
func frame_side(side: String) -> String:
	if state == null or state.half == 1:
		return side
	return "away" if side == "home" else "home"


func _kickoff_position(side: String, slot: int) -> Vector3:
	var data: Dictionary = sides[side]
	var rel: Vector2 = (data["tactics"] as TacticsPreset).target_position(data["formation"], slot, 0.5)
	rel.y = minf(rel.y, 0.46)                 # everybody in their own half
	return PitchSpace.to_world(rel, frame_side(side))


func _place_team(side: String, face_forward: bool = false) -> void:
	for e in entries[side]:
		var node: CharacterBody3D = e["node"]
		var pos := _kickoff_position(side, e["slot"]) + Vector3(0.0, 0.05, 0.0)
		var facing_z := 1.0 if frame_side(side) == "away" else -1.0     # direction of attack
		if node is TeamGoalkeeper:
			(node as TeamGoalkeeper).reset_to(pos, facing_z)
			continue
		node.global_position = pos
		node.velocity = Vector3.ZERO
		node.rotation.y = PI if facing_z > 0.0 else 0.0                 # face the opponent's goal
		if e["ai"] != null:               # null = human-controlled slot
			(e["ai"] as AIIntent).release_all()


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	_hud_layer = layer
	add_child(layer)
	hud = MatchHud.create(db, setup.home_id, setup.away_id)     # RTL: home on the right
	layer.add_child(hud)
	_device_monitor = InputDeviceMonitor.new()
	_device_monitor.attach(layer)
	add_child(_device_monitor)
	# P4: touch layer drives the shared human intent in driven mode on touch
	# devices (inert on desktop unless tests force it).
	_touch = TouchControls.new()
	add_child(_touch)
	_touch.attach(human_intent)
	_touch.pause_pressed.connect(func() -> void:
		if pause_menu == null and results_view == null and state != null \
				and state.phase != MatchState.Phase.FINISHED:
			pause_match())
	# P5: if a KING CONTROLLER server was started from the pairing screen,
	# feed slot 0 into the shared human intent (driven mode).
	var gm := get_node_or_null("/root/GameManager")
	if gm != null and gm.king_controller_server != null and is_instance_valid(gm.king_controller_server):
		var srv: KingControllerServer = gm.king_controller_server
		controller_hub = KingControllerHub.new()
		controller_hub.name = "KingControllerHub"
		add_child(controller_hub)
		controller_hub.pause_requested.connect(func(_slot: int) -> void: toggle_pause_from_controller())
		controller_hub.controller_active_changed.connect(_on_controller_active_changed)
		controller_hub.setup(srv, {0: human_intent, 1: human_intent2})
		if srv.match_data == null:
			srv.attach_match(self)
	_update_hud()


## player_id -> display name for everyone on the pitch or the bench entries (commentary text).
func _player_names() -> Dictionary:
	var out := {}
	for side in ["home", "away"]:
		for e in entries[side]:
			if e.has("pdata") and e["pdata"] != null:
				out[str(e["player_id"])] = (e["pdata"] as PlayerData).display_name
	return out


func _update_hud() -> void:
	if hud == null:
		return
	var notice := ""
	if rules != null and rules.notice_left > 0.0:
		notice = rules.notice
	if state.phase == MatchState.Phase.HALF_TIME:
		notice = Loc.t("HUD_HALF_TIME")
	elif penalty_duel != null and penalty_duel.active():
		notice = penalty_duel.tally_text()
	elif state.phase == MatchState.Phase.FINISHED:
		notice = Loc.t("HUD_FULL_TIME")
	if notice == "":
		notice = commentary.current
	var controlled := {}
	if not selected.is_empty():
		controlled = {"name": (selected["pdata"] as PlayerData).display_name,
				"stamina": float(state.stamina.get(selected["player_id"], 100.0))}
	hud.refresh(int(state.score["home"]), int(state.score["away"]), state.clock_text(), state.half, notice, controlled)


# --- human control ------------------------------------------------------------------------------

func _closest_to_ball(side: String, exclude_slot: int) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for e in entries[side]:
		if e["slot"] == 0 or e["slot"] == exclude_slot or e.get("sent_off", false):
			continue
		var d := ((e["node"] as Node3D).global_position - ball.global_position).length()
		if d < best_d:
			best_d = d
			best = e
	return best


func _select(entry: Dictionary) -> void:
	if entry.is_empty():
		return
	if not selected.is_empty():
		var old_ai := AIIntent.new()
		selected["ai"] = old_ai
		selected["node"].intent = old_ai
		selected["actions"].intent = old_ai
	var human := human_intent
	entry["node"].intent = human
	entry["actions"].intent = human
	entry["actions"].aim_assist = _assist if aim_assist_enabled else null
	entry["ai"] = null
	selected = entry
	if selection_indicator != null:
		selection_indicator.attach_to(entry["node"])
	if camera != null and camera.has_method("set_follow_target"):
		camera.set_follow_target(entry["node"])


## Hands control to the human-side player closest to the ball.
func switch_player() -> void:
	if setup.human_side == "none" or selected.is_empty():
		return
	var cur_acts := selected.get("actions") as FootballActions
	if cur_acts != null and cur_acts.is_charging():
		return                                   # Phase M6: no switch while a pass / shot is being charged
	var next := _closest_to_ball(setup.human_side, selected["slot"])
	if not next.is_empty():
		_select(next)
		if switch_policy != null:
			switch_policy.note_switch(_clock)


## Automatic switch after a change of ball owner (see `AutoSwitchPolicy`).
func _auto_switch(owner: Dictionary) -> void:
	if switch_policy == null or selected.is_empty():
		return
	var acts := selected.get("actions") as FootballActions
	var charging := acts != null and acts.is_charging()
	match switch_policy.on_owner(owner, str(selected["player_id"]), charging, _clock):
		"receiver":
			_select(owner)
		"closest":
			var next := _closest_to_ball(setup.human_side, -1)
			if not next.is_empty() and next != selected:
				_select(next)


# --- simulation ------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if state == null or ball == null:
		return
	if human_intent.just_pressed(&"switch_player"):
		switch_player()
	if not selected2.is_empty() and human_intent2.just_pressed(&"switch_player"):
		switch_player2()
	_clock += delta
	if state.phase != MatchState.Phase.PLAYING and not rules.advantage.is_empty():
		rules.end_advantage("played_on")           # the ball went dead (goal, out of play, whistle): the advantage is over
	match state.phase:
		MatchState.Phase.KICKOFF:
			if walkout_left > 0.0:
				_step_walkout(delta)
			_step_kickoff(delta)
		MatchState.Phase.PLAYING:
			state.set_ball_position(ball.global_position.x, ball.global_position.z)
			state.tick(delta)
			_update_possession()
			rules.update(delta)
			if state.phase != MatchState.Phase.PLAYING:
				# Phase M4: a restart (ball out, foul, offside) stopped play inside `rules.update`. The AI must not run
				# this frame: it re-applied every player's last move after the restart had released them, and that move
				# then stayed on for the whole pause — players walked off the pitch and the taker pushed the ball out
				# again (measured: endless throw-in loops, up to 223 player-samples off the pitch per match).
				_reset_ai_commands()
			else:
				replay_buffer.tick(delta, _sample_bodies)
				if _possession_side != "":
					state.record_possession(_possession_side, delta)
				_update_ai(delta)
				_update_stamina(delta)
				_sample_heat(delta)
				_update_managers(delta)
		MatchState.Phase.HALF_TIME:
			_step_half_time(delta)
		MatchState.Phase.FINISHED:
			_finish()
	crowd.consume(state.events, "home")
	crowd.update(delta)
	if state.events.size() != _commentary_events:
		_commentary_events = state.events.size()
		commentary.consume(state.events, _player_names(), get_node_or_null("/root/Loc"))
	commentary.update(delta)
	_update_presentation(delta)
	_update_pass_marker()
	_update_hud()


func _step_kickoff(delta: float) -> void:
	_pause_left -= delta
	if _pause_left > 0.0:
		return
	if _needs_reset:
		_place_team("home")
		_place_team("away")
		ball.reset_ball(Vector3(0.0, 0.3, 0.0))
		_needs_reset = false
		_pause_left = 1.0
	else:
		state.kick_off()


func _step_half_time(delta: float) -> void:
	if not _half_handled:
		_half_handled = true
		_pause_left = HALF_TIME_PAUSE
		for side in entries:
			for e in entries[side]:
				if e["ai"] != null:
					(e["ai"] as AIIntent).release_all()
	_pause_left -= delta
	if _pause_left <= 0.0:
		state.start_second_half()
		_half_handled = false
		_needs_reset = true
		_pause_left = 0.5


## The player who has the ball: the closest one within POSSESSION_RADIUS (planar). Phase M1: a ball travelling faster
## than FAST_BALL m/s relative to a player only belongs to him once it is within his touch (FAST_BALL_RADIUS) — before,
## a pressing opponent 1.2 m from the passer "owned" every pass the moment it left the foot (counted as a failed pass,
## cleared the offside check and triggered the auto-switch).
const FAST_BALL := 6.0
const FAST_BALL_RADIUS := 0.8
var _owner_cache: Dictionary = {}
## The ground pass / lob in flight and its intended receiver ({receiver_id, passer_id, t}; {} = none). Set by
## `MatchAIDriver` when an AI kick is released (and by the human pass), read by the receiver's AI (Phase M1).
var incoming_pass: Dictionary = {}
var _owner_cache_frame := -1


## While the human holds the pass button, the ring marks the team-mate the pass will go to (Phase M1).
func _update_pass_marker() -> void:
	if selected.is_empty() or _assist == null or not aim_assist_enabled:
		if pass_marker != null:
			pass_marker.show_on(null)
		return
	var acts := selected.get("actions") as FootballActions
	if acts == null or acts.get_charge_ratio(&"pass") <= 0.0 and not human_intent.is_pressed(&"pass"):
		if pass_marker != null:
			pass_marker.show_on(null)
		return
	if pass_marker == null:
		pass_marker = PassTargetMarker.new()
		add_child(pass_marker)
	var stick := human_intent.move_vector()
	var origin := (selected["node"] as Node3D).global_position
	var t := _assist.pass_target(origin, acts._input_to_world_dir(stick) if stick != Vector2.ZERO else Vector3.ZERO)
	var body: Node3D = null
	if not t.is_empty():
		var best_d := 1.0
		for e in entries[setup.human_side]:
			var p := (e["node"] as Node3D).global_position
			var d := Vector2(p.x - (t["pos"] as Vector3).x, p.z - (t["pos"] as Vector3).z).length()
			if d < best_d:
				best_d = d
				body = e["node"]
	pass_marker.show_on(body)


## Play stopped: every AI player stands still with no pending command or kick, and thinks afresh on the restart.
func _reset_ai_commands() -> void:
	incoming_pass = {}
	for side in entries:
		for e in entries[side]:
			e["cmd"] = {}
			e["charging"] = &""
			e["think"] = 0.0
			if e["ai"] != null:
				(e["ai"] as AIIntent).release_all()


## An assisted human pass was played towards `target`: the team-mate standing there becomes the ball's intended
## receiver, so his AI runs onto it exactly as for an AI pass (Phase M1).
func note_human_pass(side: String, slot: int, target: Vector3) -> void:
	if target == Vector3.INF:
		return
	var passer: Dictionary = {}
	var best: Dictionary = {}
	var best_d := 2.0
	for e in entries[side]:
		if int(e["slot"]) == slot:
			passer = e
			continue
		var p := (e["node"] as Node3D).global_position
		var d := Vector2(p.x - target.x, p.z - target.z).length()
		if d < best_d:
			best_d = d
			best = e
	if not best.is_empty() and not passer.is_empty() and passer["ai"] == null:
		incoming_pass = {"receiver_id": best["player_id"], "passer_id": passer["player_id"], "t": _clock}


func _owner_entry() -> Dictionary:
	var frame := Engine.get_physics_frames()
	if frame == _owner_cache_frame and (_owner_cache.is_empty() or is_instance_valid(_owner_cache.get("node"))):
		return _owner_cache
	var best: Dictionary = {}
	var best_d := POSSESSION_RADIUS
	var bp := ball.global_position
	var bv := Vector2(ball.linear_velocity.x, ball.linear_velocity.z)
	for side in entries:
		for e in entries[side]:
			var n := e["node"] as CharacterBody3D
			var d := Vector2(n.global_position.x - bp.x, n.global_position.z - bp.z).length()
			if d >= best_d:
				continue
			if d > FAST_BALL_RADIUS and (bv - Vector2(n.velocity.x, n.velocity.z)).length() > FAST_BALL:
				continue
			best_d = d
			best = e
	_owner_cache_frame = frame
	_owner_cache = best
	return best


func _update_possession() -> void:
	var owner := _owner_entry()
	if not owner.is_empty():
		if owner["player_id"] != last_toucher_id:
			state.record_owner(owner["side"], owner["player_id"], int(owner["slot"]) == 0)
			rules.restarts.on_owner(owner)
			_auto_switch(owner)
			_auto_switch2(owner)
		last_toucher_id = owner["player_id"]
		_possession_side = owner["side"]


## Live aim-assist context for the human side (bound Callable target, P3).
## Mirror of the AI context in `_update_ai`: team-mate positions (the selected
## human carrier excluded — the assist has its own self filter as a second
## guard), opponent positions and the opponent goal in the current half frame.
func _aim_context(side: String) -> Dictionary:
	var mates: Array[Vector3] = []
	for e in entries.get(side, []):
		if e == selected:
			continue
		mates.append((e["node"] as Node3D).global_position)
	return {
		"teammates": mates,
		"opponents": _positions("away" if side == "home" else "home"),
		"goal": PitchSpace.opponent_goal(frame_side(side)),
	}


func _positions(side: String) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for e in entries[side]:
		out.append((e["node"] as Node3D).global_position)
	return out


func _update_ai(delta: float) -> void:
	MatchAIDriver.update(self, delta)


func _update_stamina(delta: float) -> void:
	for side in entries:
		for e in entries[side]:
			var ratio: float
			if e["node"] is PlayerController:
				var node: PlayerController = e["node"]
				ratio = node.get_current_speed() / maxf(node.config.sprint_speed, 0.1)
			else:
				ratio = (e["node"] as CharacterBody3D).velocity.length() / KEEPER_SPRINT_SPEED
			var pd: PlayerData = e["pdata"]
			state.drain_stamina(e["player_id"], delta, ratio, pd.physical)


## Position samples for the heat maps: every MatchStats.HEAT_INTERVAL seconds of play, one sample per player on the pitch.
func _sample_heat(delta: float) -> void:
	_heat_timer += delta
	if _heat_timer < MatchStats.HEAT_INTERVAL:
		return
	_heat_timer = fmod(_heat_timer, MatchStats.HEAT_INTERVAL)
	for side in entries:
		for e in entries[side]:
			if rules.sent_off.has(e["player_id"]):
				continue
			var pos := (e["node"] as Node3D).global_position
			state.stats.add_heat(e["player_id"], side, pos.x, pos.z, state.half)


func _update_managers(delta: float) -> void:
	_manager_timer += delta
	if _manager_timer < MANAGER_INTERVAL:
		return
	_manager_timer = 0.0
	for side in ["home", "away"]:
		var data: Dictionary = sides[side]
		var orders := ManagerAI.decide(state, side, data["squad"], data["tactics"], db, _manager_difficulty(side))
		if orders.is_empty():
			continue
		var subs := ManagerAI.apply(orders, side, state, data["squad"], data["tactics"], db)
		for o in subs:
			_swap_player(side, o["slot"], o["in_id"])


## The AI manager of the human's opponent plays at the match difficulty; the human's own side is not auto-managed
## beyond what it already did (normal).
func _manager_difficulty(side: String) -> int:
	return setup.difficulty if side != setup.human_side else 1


## Replaces the on-pitch player in `slot` with a new squad member (substitution).
func _swap_player(side: String, slot: int, new_player_id: String) -> void:
	for e in entries[side]:
		if e["slot"] == slot:
			var pdata: PlayerData = db.get_player(new_player_id)
			e["player_id"] = new_player_id
			e["pdata"] = pdata
			e["mods"] = AttributeModifiers.new(pdata)
			_dress(e["node"], pdata, e["kit"], slot)          # new shirt number and look
			if e["node"] is TeamGoalkeeper:
				(e["node"] as TeamGoalkeeper).attribute_modifiers = e["mods"]
			else:
				(e["node"] as PlayerController).attribute_modifiers = e["mods"]
				(e["actions"] as FootballActions).attribute_modifiers = e["mods"]
			return


# --- save / restore ----------------------------------------------------------------------------------

## Snapshot of the running match (see `MatchSnapshot` and `MatchSave`).
func capture() -> Dictionary:
	return MatchSnapshot.capture(self)


## Saves to `path` (atomic, keeps a .bak). Returns "" or an error text.
func save_match(path: String = MatchSave.DEFAULT_PATH) -> String:
	if state == null or state.phase == MatchState.Phase.FINISHED or state.result_processed:
		return Loc.t("MATCH_SAVE_FINISHED")
	return MatchSave.write(capture(), path)


## Rebuilds the match from a validated save (`MatchSave.read`); call in place of `begin()`.
func restore(data: Dictionary, p_db: Node) -> String:
	return MatchSnapshot.restore(self, data, p_db)


# --- replay -------------------------------------------------------------------------------------

## Ball first, then the home players, then the away players: x, y, z and facing of each.
func _sample_bodies() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var bp := ball.global_position
	out.append_array(PackedFloat32Array([bp.x, bp.y, bp.z, 0.0]))
	for side in ["home", "away"]:
		for e in entries[side]:
			var n := e["node"] as Node3D
			var p := n.global_position
			out.append_array(PackedFloat32Array([p.x, p.y, p.z, n.global_rotation.y]))
	return out


## Slow-motion replay of the last seconds before the goal, played with ghosts during the goal pause. The restart waits for it.
func _start_goal_replay() -> void:
	var clip := replay_buffer.clip(REPLAY_SECONDS)
	if (clip["frames"] as Array).size() < 4:
		return
	var colors: Array[Color] = [Color.WHITE]
	for side in ["home", "away"]:
		for e in entries[side]:
			colors.append((e["kit"] as TeamKit).jersey if int(e["slot"]) != 0 else Color(0.2, 0.9, 0.3))
	if replay_player == null:
		replay_player = ReplayPlayer.new()
		add_child(replay_player)
	if replay_player.start(clip, colors, REPLAY_SPEED):
		last_replay_seconds = float(clip["duration"]) / REPLAY_SPEED
		_pause_left = maxf(_pause_left, last_replay_seconds + 0.5)
		replay_player.finished.connect(_on_replay_finished, CONNECT_ONE_SHOT)
		if replay_director == null:
			replay_director = ReplayDirector.new()
			add_child(replay_director)
		var goal_z := signf(ball.global_position.z) * PitchSpace.HALF_LENGTH if absf(ball.global_position.z) > 1.0 else PitchSpace.HALF_LENGTH
		replay_director.direct(replay_player, goal_z)      # TV, behind the goal, close-up


func _on_replay_finished() -> void:
	_pause_left = minf(_pause_left, 0.8)


func skip_replay() -> void:
	if replay_player != null and replay_player.playing:
		replay_player.skip()


# --- goals / end -------------------------------------------------------------------------------------

## During the goal pause the scoring side celebrates and the conceding side is dejected
## (outfield players; the keepers keep their stance). The clips are shorter than GOAL_PAUSE.
func _goal_reactions(scoring_side: String) -> void:
	for s in entries:
		for e in entries[s]:
			if e["node"] is TeamGoalkeeper:
				continue
			var vis := (e["node"] as Node).get_node_or_null("VisualRoot")
			if vis != null and vis.has_method("play_reaction"):
				vis.play_reaction("Celebrate" if s == scoring_side else "Disappointed")


## A level knockout match: the shoot-out is played on the pitch (`PenaltyDuel`).
func _start_shootout() -> void:
	penalty_duel = PenaltyDuel.new(self)
	add_child(penalty_duel)
	penalty_duel.finished.connect(func(h: int, a: int) -> void:
		state.forced_pens = [h, a]
		_shootout_done = true)
	penalty_duel.begin()
	if camera != null and camera.has_method("set_mode"):
		camera.set_mode(GameCamera.Mode.BROADCAST)    # the TV camera follows the ball to the goal


func _on_goal_entered(goal_id: StringName, body: Node3D) -> void:
	if state == null or body != ball:
		return
	if penalty_duel != null and penalty_duel.active():
		penalty_duel.on_goal()
		return
	var frame_scorer := PitchSpace.scoring_side(goal_id)     # who attacks this goal in the current half
	var side := frame_scorer if state.half == 1 else ("away" if frame_scorer == "home" else "home")
	if state.goal(side, last_toucher_id):
		goal_scored.emit(side, last_toucher_id)
		InputSettings.pulse(0.6, 1.0, 350)        # goal rumble on physical controllers (setting-gated)
		_needs_reset = true
		_pause_left = GOAL_PAUSE
		_goal_reactions(side)
		if camera != null and camera.has_method("punch_zoom"):
			camera.punch_zoom(6.0)        # a short push-in on the goal
		_start_goal_replay()
		for s in entries:
			for e in entries[s]:
				if e["ai"] != null:
					(e["ai"] as AIIntent).release_all()


func _finish() -> void:
	if _finished_emitted:
		return
	if penalty_duel != null and penalty_duel.active():
		return                                    # the shoot-out is still being played
	if not _shootout_done and setup.knockout and int(state.score["home"]) == int(state.score["away"]) \
			and (setup.human_side != "none" or force_3d_shootout):
		_start_shootout()
		return
	_finished_emitted = true
	var home_rating: int = db.get_team_rating(setup.home_id)
	var away_rating: int = db.get_team_rating(setup.away_id)
	var result := state.to_result(setup.knockout, _rng, home_rating, away_rating)
	# Match fatigue carries over to the next game.
	for side in entries:
		for e in entries[side]:
			var pd: PlayerData = e["pdata"]
			var lost := int((100.0 - float(state.stamina.get(e["player_id"], 100.0))) * 0.4)
			pd.fitness = clampi(pd.fitness - lost, 30, 100)
			pd.experience += 1
	state.result_processed = true
	report = MatchReport.build(state, db, setup.human_side, result)
	report["competition_id"] = setup.competition_id
	report["uid"] = state.uid
	var gm := get_node_or_null("/root/GameManager")
	if gm != null:
		gm.set("last_match_report", report)       # BEFORE the signals: listeners read it
	match_finished.emit(result)
	if gm != null:
		gm.set("last_match_result", result)
		if gm.has_signal("match_finished"):
			gm.emit_signal("match_finished", result)
	_show_results()


func _show_results() -> void:
	if get_tree().paused:
		get_tree().paused = false
	if _hud_layer != null:
		_hud_layer.visible = false
	results_view = MatchMenus.show_results(self, report, db)


func _on_results_continue() -> void:
	results_closed.emit()
	var gm := get_node_or_null("/root/GameManager")
	if return_to_menu_on_finish and gm != null:
		gm.return_to_menu()


# --- pause ---------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if replay_player != null and replay_player.playing and (event.is_action_pressed("ui_accept") or event.is_action_pressed("pass")):
		skip_replay()
		return
	if walkout_left > 0.0 and (event.is_action_pressed("ui_accept") or event.is_action_pressed("pass")):
		end_walkout()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause") and pause_menu == null and results_view == null \
			and state != null and state.phase != MatchState.Phase.FINISHED:
		get_viewport().set_input_as_handled()
		pause_match()


func is_paused() -> bool:
	return pause_menu != null


## KING CONTROLLER bridge of this match (null without a controller server).
var controller_hub: KingControllerHub


## The phone's Pause button: pauses (opens the pause menu) or resumes through the same functions the keyboard
## uses. Ignored once the match is over (results screen) — Pause is a match-control action, never a player action.
func toggle_pause_from_controller() -> bool:
	if state == null or state.phase == MatchState.Phase.FINISHED or results_view != null:
		return false
	if pause_menu != null:
		resume_match()
	else:
		pause_match()
	return true


## While a phone controller drives the player, the on-screen touch layer steps aside (both would write the
## same intent every tick); it returns when the phone is gone, on touch devices only. Slot 2 is the second human
## (P10): it takes / gives back the opposing side.
func _on_controller_active_changed(slot: int, active: bool) -> void:
	if slot == 1:
		_seat2_wanted = active
		_sync_seat2()
		return
	if _touch == null:
		return
	if active:
		_touch.set_active(false)
	elif DisplayServer.is_touchscreen_available():
		_touch.set_active(true)


## The side the second human plays: always the opponent of the first one (versus play).
func seat2_side() -> String:
	if setup == null or not (setup.human_side in ["home", "away"]):
		return ""
	return "away" if setup.human_side == "home" else "home"


## True while a second human controls a player.
func seat2_active() -> bool:
	return not selected2.is_empty()


## Brings seat 2 in line with the phone (connected -> controls the player closest to the ball, lost -> AI again).
func _sync_seat2() -> void:
	if not _seat_ready or state == null or ball == null or (entries["home"] as Array).is_empty():
		return
	var side := seat2_side()
	if side == "":
		return
	if _seat2_wanted and selected2.is_empty():
		var mode := setup.switch_mode if setup.switch_mode in GameSettings.SWITCH_MODES \
				else str(GameSettings.get_value("match", "switch_mode"))
		_assist2 = HumanAimAssist.new()
		_assist2.context = _aim_context.bind(side)
		switch_policy2 = AutoSwitchPolicy.new(mode, side)
		selection_indicator2 = SelectionIndicator.new(1, MatchPresentation.side_kit_color(self, side))
		_select2(_closest_to_ball(side, -1))
		if camera != null and camera.has_method("set_mode"):
			camera.set_mode(GameCamera.Mode.BROADCAST)      # one camera cannot follow two players
	elif not _seat2_wanted and not selected2.is_empty():
		_release_seat2()


func _select2(entry: Dictionary) -> void:
	if entry.is_empty():
		return
	if not selected2.is_empty():
		var old_ai := AIIntent.new()
		selected2["ai"] = old_ai
		selected2["node"].intent = old_ai
		selected2["actions"].intent = old_ai
		selected2["actions"].aim_assist = null
	entry["node"].intent = human_intent2
	entry["actions"].intent = human_intent2
	entry["actions"].aim_assist = _assist2 if aim_assist_enabled else null
	entry["ai"] = null
	selected2 = entry
	if selection_indicator2 != null:
		selection_indicator2.attach_to(entry["node"])


func switch_player2() -> void:
	if selected2.is_empty():
		return
	var next := _closest_to_ball(seat2_side(), selected2["slot"])
	if not next.is_empty():
		_select2(next)
		if switch_policy2 != null:
			switch_policy2.note_switch(_clock)


func _auto_switch2(owner: Dictionary) -> void:
	if switch_policy2 == null or selected2.is_empty():
		return
	var acts := selected2.get("actions") as FootballActions
	var charging := acts != null and acts.is_charging()
	match switch_policy2.on_owner(owner, str(selected2["player_id"]), charging, _clock):
		"receiver":
			_select2(owner)
		"closest":
			var next := _closest_to_ball(seat2_side(), -1)
			if not next.is_empty() and next != selected2:
				_select2(next)


## The second phone is gone: its player goes back to the AI at once.
func _release_seat2() -> void:
	if not selected2.is_empty():
		var ai := AIIntent.new()
		selected2["ai"] = ai
		selected2["node"].intent = ai
		selected2["actions"].intent = ai
		selected2["actions"].aim_assist = null
		selected2 = {}
	if selection_indicator2 != null:
		selection_indicator2.queue_free()
		selection_indicator2 = null
	switch_policy2 = null
	if camera != null and camera.has_method("set_mode") and setup.human_side != "none" \
			and str(GameSettings.get_value("match", "camera")) == "follow":
		camera.set_mode(GameCamera.Mode.FOLLOW)


## Freezes the whole match (physics, AI, clock) and opens the pause menu.
func pause_match() -> void:
	if pause_menu != null or results_view != null:
		return
	get_tree().paused = true
	pause_menu = MatchMenus.open_pause(self)


func resume_match() -> void:
	if pause_menu == null:
		return
	MatchMenus.close_pause(pause_menu)
	pause_menu = null
	get_tree().paused = false


## Abandons this run and starts the same match again from kick-off. No result is recorded.
func restart_match() -> void:
	abandoned = true
	var fresh := MatchSetup.from_dict(initial_setup_dict)
	get_tree().paused = false
	restart_requested.emit(fresh)
	var gm := get_node_or_null("/root/GameManager")
	if return_to_menu_on_finish and gm != null:
		gm.start_configured_match(fresh)


## Leaves the match without a result (a competition fixture stays pending).
func quit_match() -> void:
	abandoned = true
	get_tree().paused = false
	quit_requested.emit()
	var gm := get_node_or_null("/root/GameManager")
	if return_to_menu_on_finish and gm != null:
		gm.return_to_menu()


# --- KING CONTROLLER companion adapter ----------------------------------------------------------------
# The read-only surface `KingControllerMatchData.CONTRACT` asks the match for. Everything here
# reports what the live match really holds — no synthetic values. The validated writes
# (`controller_apply_tactic`, `controller_substitute`) land with the tactics phase (Phase 4).


## Which side a controller seat drives. Seat 0 = the human side of MatchSetup, seat 1 = its
## opponent (versus play — the same mapping `seat2_side()` uses). "" for an unknown seat.
func controller_side_for_slot(slot: int) -> String:
	if slot == 0 and setup != null and setup.human_side in ["home", "away"]:
		return setup.human_side
	if slot == 1:
		return seat2_side()
	return ""


## Team id + display name per side, read straight from `sides` and the database.
func controller_side_info() -> Dictionary:
	var out: Dictionary = {}
	for side in ["home", "away"]:
		if not sides.has(side):
			continue
		var data: Dictionary = sides[side]
		var info: Dictionary = {"side": side, "id": str(data.get("team_id", "")), "name": ""}
		var team: TeamData = db.get_team(str(data.get("team_id", ""))) \
				if db != null and db.has_method("get_team") else null
		if team != null:
			info["name"] = team.display_name
		out[side] = info
	return out


## Read-only view of a side's live tactics (the values a phone Tactics page would show).
func controller_tactical_state(side: String) -> Dictionary:
	if not sides.has(side):
		return {}
	var preset: TacticsPreset = sides[side].get("tactics")
	if preset == null:
		return {}
	return {"formation": str(sides[side].get("formation", "")), "mentality": preset.mentality,
			"pressing": preset.pressing, "defensive_line": preset.defensive_line,
			"build_up": preset.build_up, "passing_style": preset.passing_style,
			"width": preset.width, "preset_name": preset.preset_name}


## Applies a tactical value from a controller. Returns "" on success, else a reason code.
## Keys: formation, mentality, build_up, passing_style, preset_name (string values);
## pressing, defensive_line, width (0..100 integers). No team name is ever accepted.
func controller_apply_tactic(side: String, key: String, value: Variant) -> String:
	if not sides.has(side):
		return "unknown_side"
	if state == null or state.phase == MatchState.Phase.FINISHED:
		return "finished"
	var preset: TacticsPreset = sides[side].get("tactics")
	if preset == null:
		return "no_tactics"
	match key:
		"formation":
			if typeof(value) != TYPE_STRING or String(value).length() == 0 or String(value).length() > 24:
				return "bad_value"
			sides[side]["formation"] = String(value)
			return ""
		"mentality":
			if typeof(value) != TYPE_STRING or not (String(value) in ["defensive", "balanced", "attacking"]):
				return "bad_value"
			preset.mentality = {"defensive": 0, "balanced": 1, "attacking": 2}[String(value)]
			return ""
		"build_up":
			if typeof(value) != TYPE_STRING or not (String(value) in ["short", "mixed", "long"]):
				return "bad_value"
			preset.build_up = {"short": 0, "mixed": 1, "long": 2}[String(value)]
			return ""
		"passing_style":
			if typeof(value) != TYPE_STRING or not (String(value) in ["safe", "balanced", "risky"]):
				return "bad_value"
			preset.passing_style = {"safe": 0, "balanced": 1, "risky": 2}[String(value)]
			return ""
		"preset_name":
			if typeof(value) != TYPE_STRING or String(value).length() > 24:
				return "bad_value"
			preset.preset_name = String(value)
			return ""
		"pressing", "defensive_line", "width":
			if not (value is int or value is float):
				return "bad_value"
			var iv := clampi(int(value), 0, 100)
			if key == "pressing":
				preset.pressing = iv
			elif key == "defensive_line":
				preset.defensive_line = iv
			else:
				preset.width = iv
			return ""
		_:
			return "unknown_key"


## Substitution from a controller. slot = on-pitch slot, player_id = bench player id.
func controller_substitute(side: String, slot: int, player_id: String) -> String:
	if not sides.has(side):
		return "unknown_side"
	if state == null or state.phase == MatchState.Phase.FINISHED:
		return "finished"
	if state != null and int(state.subs_used[side]) >= ManagerAI.MAX_SUBS:
		return "no_subs_left"
	var squad = sides[side].get("squad")
	if squad == null:
		return "no_squad"
	var out_pid: String = ""
	var entries_side: Array = entries.get(side, [])
	for e in entries_side:
		if int(e.get("slot", -1)) == slot:
			out_pid = str(e.get("player_id", ""))
			break
	if out_pid == "":
		return "no_player_in_slot"
	if out_pid == player_id:
		return "same_player"
	var reason: String = squad.substitute(db, slot, player_id)
	if reason != "":
		return reason
	var pdata: PlayerData = db.get_player(player_id) if db != null and db.has_method("get_player") else null
	_swap_player(side, slot, player_id)
	if pdata != null:
		for e in entries_side:
			if int(e.get("slot", -1)) == slot:
				e["pdata"] = pdata
				e["mods"] = AttributeModifiers.new(pdata)
				break
	state.stamina[player_id] = 100.0
	state.record_substitution(side, out_pid, player_id)
	return ""


## Player display name from the database, or "" when unknown (never a made-up name).
func controller_player_name(player_id: String) -> String:
	if player_id == "" or db == null or not db.has_method("get_player"):
		return ""
	var pdata: PlayerData = db.get_player(player_id)
	return pdata.display_name if pdata != null else ""
