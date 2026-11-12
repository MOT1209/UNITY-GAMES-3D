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
const CHARGE_TIME := {&"shoot": 0.40, &"pass": 0.15}

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
var last_toucher_id: String = ""

var _hud_label: Label
var _pause_left: float = 0.5
var _needs_reset: bool = true
var _half_handled: bool = false
var _manager_timer: float = 0.0
var _finished_emitted: bool = false
var _clock: float = 0.0
var _rng := RandomNumberGenerator.new()


## Builds the match. Returns "" or an error text (nothing is spawned on error).
func begin(p_setup: MatchSetup, p_db: Node) -> String:
	var problems := p_setup.validate(p_db)
	if not problems.is_empty():
		return problems[0]
	setup = p_setup
	db = p_db
	_rng.seed = setup.rng_seed
	state = MatchState.create(setup.home_id, setup.away_id, setup.duration_minutes, setup.match_id)
	for side in ["home", "away"]:
		sides[side] = setup.build_side(db, side)
	_build_arena()
	_spawn_ball()
	for side in ["home", "away"]:
		_spawn_team(side)
	var ids: Array = []
	for side in ["home", "away"]:
		for e in entries[side]:
			ids.append(e["player_id"])
	state.init_stamina(ids)
	_build_hud()
	if setup.human_side != "none":
		_select(_closest_to_ball(setup.human_side, -1))
	return ""


# --- construction -------------------------------------------------------------------------

func _build_arena() -> void:
	arena_root = (load(ARENA_SCENE) as PackedScene).instantiate()
	add_child(arena_root)
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
	var data: Dictionary = sides[side]
	var squad: Squad = data["squad"]
	var packed: PackedScene = load(PLAYER_SCENE)
	var keeper_packed: PackedScene = load(KEEPER_SCENE)
	var team: TeamData = db.get_team(data["team_id"])
	# Real kit data: the selected kit slot for the outfield, the goalkeeper slot for the keeper.
	var kit := TeamKit.from_dict(team.kits.get(data["kit"], {}), team.primary_color)
	var gk_kit := TeamKit.from_dict(team.kits.get("goalkeeper", {}), Color(0.1, 0.75, 0.3))
	for slot in 11:
		var pid: String = squad.starting[slot]
		var pdata: PlayerData = db.get_player(pid)
		var mods := AttributeModifiers.new(pdata)
		var node: CharacterBody3D
		var actions: FootballActions = null
		var ai: AIIntent = null
		if slot == 0:
			# The single goalkeeper implementation: positioning, reading shots,
			# diving, catching and throwing (TeamGoalkeeper); no PlayerAI branch.
			var gk := keeper_packed.instantiate() as TeamGoalkeeper
			gk.attribute_modifiers = mods
			node = gk
		else:
			var outfield := packed.instantiate() as PlayerController
			ai = AIIntent.new()
			outfield.intent = ai
			actions = outfield.get_node("BallActions") as FootballActions
			actions.intent = ai
			outfield.attribute_modifiers = mods
			actions.attribute_modifiers = mods
			node = outfield
		node.name = "%s_%02d_%s" % [side, slot, pid]
		add_child(node)
		_dress(node, pdata, gk_kit if slot == 0 else kit, slot)
		entries[side].append({"node": node, "actions": actions, "ai": ai, "player_id": pid,
				"pdata": pdata, "slot": slot, "side": side, "mods": mods, "cmd": {},
				"kit": gk_kit if slot == 0 else kit,
				"think": _rng.randf() * 0.2, "release_at": -1.0, "charging": &""})
	_place_team(side, true)


## Applies kit colours, shirt number and individual look to a spawned player.
func _dress(node: Node, pdata: PlayerData, kit: TeamKit, slot: int) -> void:
	var visual: PlayerCharacterVisual
	if node is TeamGoalkeeper:
		visual = (node as TeamGoalkeeper).visual
	else:
		visual = node.get_node_or_null("VisualRoot") as PlayerCharacterVisual
	if visual == null:
		return
	visual.kit = kit
	visual.number = pdata.shirt_number if pdata.shirt_number > 0 else slot + 1
	visual.look = PlayerAppearance.look_for(pdata)     # stored identity, same as card / portrait
	visual.apply_kit()
	visual.apply_number()
	visual.apply_look()


## Geometry frame of `side`. The teams change ends for the second half, so every
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
	add_child(layer)
	_hud_label = Label.new()
	_hud_label.layout_direction = Control.LAYOUT_DIRECTION_LTR     # scoreboard keeps home-left / away-right
	_hud_label.anchor_right = 1.0
	_hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_label.offset_top = 12.0
	_hud_label.add_theme_font_size_override("font_size", 26)
	layer.add_child(_hud_label)
	_update_hud()


func _update_hud() -> void:
	if _hud_label == null:
		return
	var h: TeamData = db.get_team(setup.home_id)
	var a: TeamData = db.get_team(setup.away_id)
	# Names and numbers are isolated so Arabic/Latin mixing can never reorder the scoreboard.
	var text := "%s  %d - %d  %s     %s" % [Loc.iso(h.short_name), state.score["home"], state.score["away"],
			Loc.iso(a.short_name), state.clock_text()]
	if state.phase == MatchState.Phase.HALF_TIME:
		text += "   " + Loc.t("HUD_HALF_TIME")
	elif state.phase == MatchState.Phase.FINISHED:
		text += "   " + Loc.t("HUD_FULL_TIME")
	_hud_label.text = text


# --- human control ------------------------------------------------------------------------------

func _closest_to_ball(side: String, exclude_slot: int) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for e in entries[side]:
		if e["slot"] == 0 or e["slot"] == exclude_slot:
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
	var human := IntentProvider.new()
	entry["node"].intent = human
	entry["actions"].intent = human
	entry["ai"] = null
	selected = entry
	if camera != null and camera.has_method("set_follow_target"):
		camera.set_follow_target(entry["node"])


## Hands control to the human-side player closest to the ball.
func switch_player() -> void:
	if setup.human_side == "none" or selected.is_empty():
		return
	var next := _closest_to_ball(setup.human_side, selected["slot"])
	if not next.is_empty():
		_select(next)


# --- simulation ------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if state == null or ball == null:
		return
	if Input.is_action_just_pressed("switch_player"):
		switch_player()
	_clock += delta
	match state.phase:
		MatchState.Phase.KICKOFF:
			_step_kickoff(delta)
		MatchState.Phase.PLAYING:
			state.tick(delta)
			_update_possession()
			_update_ai(delta)
			_update_stamina(delta)
			_update_managers(delta)
		MatchState.Phase.HALF_TIME:
			_step_half_time(delta)
		MatchState.Phase.FINISHED:
			_finish()
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
		last_toucher_id = owner["player_id"]


func _positions(side: String) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for e in entries[side]:
		out.append((e["node"] as Node3D).global_position)
	return out


func _update_ai(delta: float) -> void:
	var owner := _owner_entry()
	var owner_side: String = owner.get("side", "")
	for side in ["home", "away"]:
		var other := "away" if side == "home" else "home"
		var data: Dictionary = sides[side]
		var tactics: TacticsPreset = data["tactics"]
		var mine := _positions(side)
		var theirs := _positions(other)
		var has_ball_team: bool = owner_side == side
		var frame := frame_side(side)
		var targets := TeamAI.formation_targets(frame, data["formation"], tactics, ball.global_position, has_ball_team)
		var chasers: Array[int] = TeamAI.pressers(mine, ball.global_position, frame, tactics)
		for e in entries[side]:
			var ai: AIIntent = e["ai"]
			if ai == null:
				continue                         # human controlled
			ai.begin_tick()
			e["think"] -= delta
			if e["think"] <= 0.0:
				e["think"] = THINK_INTERVAL[clampi(setup.difficulty, 0, 2)]
				var slot: int = e["slot"]
				var pos: Vector3 = (e["node"] as Node3D).global_position
				var is_owner: bool = not owner.is_empty() and owner["player_id"] == e["player_id"]
				var team_mates: Array[Vector3] = []
				for i in mine.size():
					if i != slot:
						team_mates.append(mine[i])
				e["cmd"] = PlayerAI.decide({
					"pos": pos, "ball": ball.global_position, "has_ball": is_owner,
					"is_chaser": (slot in chasers) and not is_owner,
					"target": targets[slot], "goal": PitchSpace.opponent_goal(frame),
					"own_goal": PitchSpace.own_goal(frame), "teammates": team_mates,
					"opponents": theirs, "is_keeper": slot == 0,
					"difficulty": setup.difficulty, "attributes": e["mods"]})
			_apply_cmd(e, ai)


func _apply_cmd(e: Dictionary, ai: AIIntent) -> void:
	var cmd: Dictionary = e["cmd"]
	if cmd.is_empty():
		return
	ai.set_move_world(cmd["move"])
	if cmd["sprint"]:
		ai.press(&"sprint")
	else:
		ai.release(&"sprint")
	var action: StringName = cmd["action"]
	if e["charging"] != &"":
		if _clock >= e["release_at"]:
			ai.release(e["charging"])
			e["charging"] = &""
			e["cmd"] = {}
	elif action != &"":
		ai.release(&"dribble")
		ai.press(action)
		e["charging"] = action
		e["release_at"] = _clock + float(CHARGE_TIME.get(action, 0.2))
	else:
		var carrying: bool = cmd["move"] != Vector3.ZERO and _owner_entry().get("player_id", "") == e["player_id"]
		if carrying:
			ai.press(&"dribble")
		else:
			ai.release(&"dribble")


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
		var orders := ManagerAI.decide(state, side, data["squad"], data["tactics"], db)
		if orders.is_empty():
			continue
		var subs := ManagerAI.apply(orders, side, state, data["squad"], data["tactics"], db)
		for o in subs:
			_swap_player(side, o["slot"], o["in_id"])


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


func _on_goal_entered(goal_id: StringName, body: Node3D) -> void:
	if state == null or body != ball:
		return
	var frame_scorer := PitchSpace.scoring_side(goal_id)     # who attacks this goal in the current half
	var side := frame_scorer if state.half == 1 else ("away" if frame_scorer == "home" else "home")
	if state.goal(side, last_toucher_id):
		goal_scored.emit(side, last_toucher_id)
		_needs_reset = true
		_pause_left = GOAL_PAUSE
		_goal_reactions(side)
		for s in entries:
			for e in entries[s]:
				if e["ai"] != null:
					(e["ai"] as AIIntent).release_all()


func _finish() -> void:
	if _finished_emitted:
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
	match_finished.emit(result)
	var gm := get_node_or_null("/root/GameManager")
	if gm != null:
		gm.set("last_match_result", result)
		if gm.has_signal("match_finished"):
			gm.emit_signal("match_finished", result)
		if return_to_menu_on_finish:
			get_tree().create_timer(5.0).timeout.connect(gm.return_to_menu)
