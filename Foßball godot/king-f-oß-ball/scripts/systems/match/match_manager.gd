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
var abandoned := false                   # the player quit/restarted: no result may be recorded

var _hud_layer: CanvasLayer
var hud: MatchHud
var _touch: TouchControls
var _pause_left: float = 0.5
var _needs_reset: bool = true
var _half_handled: bool = false
var _manager_timer: float = 0.0
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
	return ""


## Both teams line up side by side at the halfway line by the touchline (the tunnel side), then walk to
## their kick-off positions under the TV camera; kick-off follows. Skippable (pause / accept).
func _start_walkout() -> void:
	walkout_left = WALKOUT_SECONDS
	_pause_left = WALKOUT_SECONDS
	for side in ["home", "away"]:
		var lane_z := -1.6 if side == "home" else 1.6
		for e in entries[side]:
			var node := e["node"] as CharacterBody3D
			node.global_position = Vector3(-PitchSpace.HALF_WIDTH - 1.0 + float(e["slot"]) * 1.4, 0.05, lane_z)
			node.velocity = Vector3.ZERO
			node.rotation.y = -PI * 0.5            # facing into the pitch (+X)
			if node is PlayerController:
				var temp := AIIntent.new()
				_walkout_intents[node] = temp
				node.intent = temp
				if e["actions"] != null:
					(e["actions"] as FootballActions).intent = temp
	if camera != null and camera.has_method("set_mode"):
		camera.set_mode(GameCamera.Mode.BROADCAST)


func walkout_active() -> bool:
	return walkout_left > 0.0


## Every tick of the walk-out: each player walks (no sprint) towards his kick-off spot.
func _step_walkout(delta: float) -> void:
	walkout_left -= delta
	for side in entries:
		for e in entries[side]:
			var node := e["node"] as Node3D
			var intent: AIIntent = _walkout_intents.get(node)
			if intent == null:
				continue
			intent.begin_tick()
			var to := _kickoff_position(side, int(e["slot"])) - node.global_position
			to.y = 0.0
			intent.set_move_world(to.normalized() * 0.5 if to.length() > 0.6 else Vector3.ZERO)
	if walkout_left <= 0.0:
		end_walkout()


## Ends the walk-out (time up or skipped): intents back to AI / human, camera back to the saved choice.
func end_walkout() -> void:
	walkout_left = 0.0
	_pause_left = minf(_pause_left, 0.3)
	for side in entries:
		for e in entries[side]:
			var node := e["node"] as Node3D
			if not _walkout_intents.has(node):
				continue
			var ai: AIIntent = e["ai"]
			if ai != null:
				node.intent = ai
				if e["actions"] != null:
					(e["actions"] as FootballActions).intent = ai
	_walkout_intents.clear()
	if not selected.is_empty():
		_select(selected)                           # the human takes his player back
	if camera != null and camera.has_method("set_mode") and setup.human_side != "none" \
			and str(GameSettings.get_value("match", "camera")) == "follow":
		camera.set_mode(GameCamera.Mode.FOLLOW)


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
	if gm != null and gm.king_controller_server != null:
		var srv: KingControllerServer = gm.king_controller_server
		var hub := KingControllerHub.new()
		hub.name = "KingControllerHub"
		add_child(hub)
		hub.setup(srv, {0: human_intent})
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
	_clock += delta
	match state.phase:
		MatchState.Phase.KICKOFF:
			if walkout_left > 0.0:
				_step_walkout(delta)
			_step_kickoff(delta)
		MatchState.Phase.PLAYING:
			state.tick(delta)
			_update_possession()
			rules.update(delta)
			replay_buffer.tick(delta, _sample_bodies)
			if _possession_side != "":
				state.record_possession(_possession_side, delta)
			_update_ai(delta)
			_update_stamina(delta)
			_update_managers(delta)
		MatchState.Phase.HALF_TIME:
			_step_half_time(delta)
		MatchState.Phase.FINISHED:
			_finish()
	crowd.consume(state.events, "home")
	crowd.update(delta)
	_update_presentation(delta)
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


func _owner_entry() -> Dictionary:
	var best: Dictionary = {}
	var best_d := POSSESSION_RADIUS
	for side in entries:
		for e in entries[side]:
			var d := Vector2((e["node"] as Node3D).global_position.x - ball.global_position.x,
					(e["node"] as Node3D).global_position.z - ball.global_position.z).length()
			if d < best_d:
				best_d = d
				best = e
	return best


func _update_possession() -> void:
	var owner := _owner_entry()
	if not owner.is_empty():
		if owner["player_id"] != last_toucher_id:
			state.record_owner(owner["side"], owner["player_id"], int(owner["slot"]) == 0)
			rules.restarts.on_owner(owner)
			_auto_switch(owner)
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
