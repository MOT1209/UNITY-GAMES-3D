extends Node3D

## Match manager, part 1 of 3 (split Nov 2026; the class is `MatchManager` in match_manager. The file is split by call order, not by topic: a part only uses functions of its own part or an
## earlier one (part 1 holds every constant, variable and signal).
## Contains: _notification, _start_walkout, _build_arena, _spawn_ball, _spawn_team, frame_side, _build_hud,
## _update_hud, _closest_to_ball, _select, _aim_context, _positions, _update_ai, _start_goal_replay,
## _on_replay_finished, _goal_reactions, _on_goal_entered, toggle_pause_from_controller,
## _on_controller_active_changed, seat2_side, _sync_seat2, _select2, _release_seat2, pause_match, resume_match.


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
## Stadium / ball actually used (StadiumCatalog / BallCatalog ids).
var stadium_id: String = StadiumCatalog.DEFAULT_ID
var ball_id: String = BallCatalog.DEFAULT_ID
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
## Phase 2 advanced mechanics (deception, physical duels, shield contests, tackle context) and aerial contests.
var advanced: AdvancedPlay
var aerial: AerialArbiter
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


# --- construction# --- construction -------------------------------------------------------------------------

# --- human control ------------------------------------------------------------------------------

# --- simulation ------------------------------------------------------------------------------------

## The player who has the ball: the closest one within POSSESSION_RADIUS (planar). Phase M1: a ball travelling faster
## than FAST_BALL m/s relative to a player only belongs to him once it is within his touch (FAST_BALL_RADIUS) — before,
## a pressing opponent 1.2 m from the passer "owned" every pass the moment it left the foot (counted as a failed pass,
## cleared the offside check and triggered the auto-switch).
const FAST_BALL := 6.0
const FAST_BALL_RADIUS := 0.8
## The ground pass / lob in flight and its intended receiver ({receiver_id, passer_id, t}; {} = none). Set by
## `MatchAIDriver` when an AI kick is released (and by the human pass), read by the receiver's AI (Phase M1).
var incoming_pass: Dictionary = {}


# --- save / restore ----------------------------------------------------------------------------------

# --- replay -------------------------------------------------------------------------------------

# --- goals / end -------------------------------------------------------------------------------------

# --- pause ---------------------------------------------------------------------------------------

## KING CONTROLLER bridge of this match (null without a controller server).
var controller_hub: KingControllerHub


# --- KING CONTROLLER companion adapter ----------------------------------------------------------------
# The read-only surface `KingControllerMatchData.CONTRACT` asks the match for. Everything here
# reports what the live match really holds — no synthetic values. The validated writes
# (`controller_apply_tactic`, `controller_substitute`) land with the tactics phase (Phase 4).



func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:          # Android back: pause / resume, never leaves the game
		toggle_pause_from_controller.call_deferred()      # deferred: the tree is busy propagating the notification
	if what == NOTIFICATION_PREDELETE and rules != null:
		rules.release()          # rules <-> restarts reference each other
	if what == NOTIFICATION_PREDELETE and advanced != null:
		advanced.release()       # its signal lambdas hold the manager


func _start_walkout() -> void:
	MatchWalkout.start(self)


func _build_arena() -> void:
	arena_root = (load(ARENA_SCENE) as PackedScene).instantiate()
	var home_team: TeamData = db.get_team(setup.home_id) if db != null and setup != null else null
	stadium_id = StadiumCatalog.apply_to(arena_root.get_node_or_null("Arena"),
			StadiumCatalog.resolve(setup.stadium_id if setup != null else "", home_team))
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
	ball_id = BallCatalog.apply_to(ball, setup.ball_id if setup != null else "")
	var kick_fx := KickEffects.new()
	kick_fx.name = "KickEffects"
	add_child(kick_fx)
	kick_fx.setup(ball)


func _spawn_team(side: String) -> void:
	MatchTeamBuilder.spawn_team(self, side)


## Geometry frame of `side`.## Geometry frame of `side`. The teams change ends for the second half, so every
## attack-direction / goal / formation calculation uses the opposite frame then;
## ownership (score, squads, kits) always stays with the real side.
func frame_side(side: String) -> String:
	if state == null or state.half == 1:
		return side
	return "away" if side == "home" else "home"


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
