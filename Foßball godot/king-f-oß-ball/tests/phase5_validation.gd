## Phase 5 validation suite — runs headless:
##   godot --headless --path . res://tests/phase5_validation.tscn
## Asserts: the formation table (and its exported JSON mirror), team
## spawning / mirroring / formation switching, kits + shirt numbers +
## individual looks, the goalkeeper AI (guard line, shot reading, dive,
## catch, hold, throw-out) and that the keeper works with the project's real
## `BallController` — the ball is never frozen and never teleported.

extends Node

const ARENA_SCENE := "res://scenes/stadium/stadium_arena.tscn"
const BALL_SCENE := "res://scenes/ball/football_ball.tscn"
const DEMO_SCENE := "res://scenes/teams/teams_demo.tscn"
const TEAM_GOLD := "res://resources/teams/team_gold.tres"
const TEAM_RED := "res://resources/teams/team_red.tres"
const FORMATIONS_JSON := "res://resources/formations/formations.json"

var _passed := 0
var _failed := 0
var _env: Node3D
var _ball: BallController
var _max_step := 0.0
var _prev_ball_pos := Vector3.ZERO
var _caught := 0
var _released := 0
var _dives := 0


func _check(condition: bool, test_name: String, detail := "") -> void:
	if condition:
		_passed += 1
		print("[PASS] %s" % test_name)
	else:
		_failed += 1
		print("[FAIL] %s%s" % [test_name, (" — " + detail) if detail != "" else ""])


func _ready() -> void:
	await get_tree().process_frame
	print("=== KING FOOTBALL — Phase 5 validation ===")
	_test_formation_table()
	_test_formation_json_mirror()
	await _test_team_spawning()
	await _test_kits_numbers_and_looks()
	await _test_goalkeeper_ai()
	await _test_integration()

	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _await_ticks(ticks: int) -> void:
	for i in ticks:
		await get_tree().physics_frame


## Drops the previous test environment (its teams and their keepers are live
## physics bodies) and starts a clean one.
func _reset_env() -> void:
	if _env != null and is_instance_valid(_env):
		_env.queue_free()
		await get_tree().physics_frame
		await get_tree().physics_frame
		await get_tree().physics_frame
	_env = Node3D.new()
	add_child(_env)


# --- 1. Formation data ---------------------------------------------------------

func _test_formation_table() -> void:
	var names := Formation.names()
	_check(names.size() == 4, "Four formations are defined", str(names))
	_check(names.has("4-4-2") and names.has("4-3-3") and names.has("3-5-2")
			and names.has("4-2-3-1"), "The four expected formation ids exist", str(names))
	for id in names:
		var slots := Formation.slots(id)
		_check(slots.size() == 11, "%s has 11 slots" % id, str(slots.size()))
		_check(slots[0][0] == "GK", "%s: slot 0 is the goalkeeper" % id, str(slots[0]))
		var keepers := 0
		var roles_ok := true
		for s in slots:
			if s[0] == "GK":
				keepers += 1
			if not Formation.ROLES.has(s[0]):
				roles_ok = false
			_check(s[1] > 0.0 and s[1] <= 0.5, "%s: %s stays in the own half (depth %.2f)"
					% [id, s[0], s[1]])
			var pos_a := Formation.home_position(s, -1.0)
			var pos_b := Formation.home_position(s, 1.0)
			_check(absf(pos_a.x) <= FootballPitch.PITCH_WIDTH * 0.5
					and absf(pos_a.z) <= FootballPitch.PITCH_LENGTH * 0.5,
				"%s: %s is on the pitch" % [id, s[0]], str(pos_a))
			_check(is_equal_approx(pos_a.x, -pos_b.x) and is_equal_approx(pos_a.z, -pos_b.z),
				"%s: %s mirrors for the opposite attack direction" % [id, s[0]],
				"%s vs %s" % [str(pos_a), str(pos_b)])
		_check(keepers == 1, "%s has exactly one goalkeeper" % id, str(keepers))
		_check(roles_ok, "%s only uses known roles" % id)


## The exported JSON mirror must not drift away from the GDScript table.
func _test_formation_json_mirror() -> void:
	var text := FileAccess.get_file_as_string(FORMATIONS_JSON)
	_check(text != "", "formations.json is readable", FORMATIONS_JSON)
	var parsed: Variant = JSON.parse_string(text)
	_check(parsed is Dictionary, "formations.json is valid JSON")
	if not (parsed is Dictionary):
		return
	var mirror: Dictionary = parsed
	_check(mirror.size() == Formation.FORMATIONS.size(),
		"formations.json holds every formation", "%d vs %d"
		% [mirror.size(), Formation.FORMATIONS.size()])
	for id in Formation.FORMATIONS.keys():
		var gd: Array = Formation.FORMATIONS[id]
		var js: Array = mirror.get(id, [])
		var same := js.size() == gd.size()
		if same:
			for i in gd.size():
				if js[i][0] != gd[i][0] or absf(float(js[i][1]) - float(gd[i][1])) > 0.0001 \
						or absf(float(js[i][2]) - float(gd[i][2])) > 0.0001:
					same = false
					break
		_check(same, "formations.json matches formation.gd for %s" % id)


# --- 2. Team spawning ---------------------------------------------------------

func _test_team_spawning() -> void:
	await _reset_env()
	var team_a := _spawn_team(TEAM_GOLD, -1.0, 0)
	var team_b := _spawn_team(TEAM_RED, 1.0, 1)
	await get_tree().physics_frame
	await get_tree().physics_frame

	_check(team_a.players.size() == 11, "Team A spawns 11 players",
		str(team_a.players.size()))
	_check(team_b.players.size() == 11, "Team B spawns 11 players",
		str(team_b.players.size()))

	var numbers := {}
	for p in team_a.players:
		numbers[p.number] = true
	_check(numbers.size() == 11, "Team A has 11 unique shirt numbers", str(numbers.size()))

	# Every player stands in his own half: the half that holds his own goal.
	var in_half := true
	for p in team_a.players:
		if p.home.z * (-team_a.attack_dir_z) < -0.5:
			in_half = false
	for p in team_b.players:
		if p.home.z * (-team_b.attack_dir_z) < -0.5:
			in_half = false
	_check(in_half, "Both teams line up in their own half")

	# Facing: team A attacks -Z, team B attacks +Z.
	var forward_a := -team_a.players[3].global_transform.basis.z
	var forward_b := -team_b.players[3].global_transform.basis.z
	_check(forward_a.z < -0.9, "Team A faces -Z", str(forward_a))
	_check(forward_b.z > 0.9, "Team B faces +Z", str(forward_b))

	# The right back (slot 4) is on the team's own right: +X for A, -X for B.
	_check(team_a.players[4].home.x > 10.0, "Team A's right back is on +X",
		str(team_a.players[4].home.x))
	_check(team_b.players[4].home.x < -10.0, "Team B's right back is on -X",
		str(team_b.players[4].home.x))

	# The goalkeepers stand at their own goals (on the 6-yard line).
	_check(team_a.goalkeeper().home.z > 45.0, "Team A's keeper is at the +Z goal",
		str(team_a.goalkeeper().home.z))
	_check(team_b.goalkeeper().home.z < -45.0, "Team B's keeper is at the -Z goal",
		str(team_b.goalkeeper().home.z))
	_check(team_a.goalkeeper() is TeamGoalkeeper, "The goalkeeper slot uses TeamGoalkeeper")
	_check(not (team_a.players[1] is TeamGoalkeeper), "Outfield slots are plain TeamPlayer")
	_check(team_a.goalkeeper().gk_visual is GoalkeeperVisual,
		"The keeper uses the GoalkeeperVisual")

	# Formation switching re-spawns the team with the new roles.
	team_a.set_formation("3-5-2")
	await get_tree().physics_frame
	_check(team_a.players.size() == 11, "The team still has 11 players after the switch",
		str(team_a.players.size()))
	_check(team_a.players[1].role == "CB", "3-5-2 starts with three centre backs",
		str(team_a.players[1].role))
	_check(team_a.goalkeeper().role == "GK", "The keeper stays the keeper after the switch")
	_check(team_a.players[5].role == "CM", "3-5-2 has a midfielder in slot 5",
		str(team_a.players[5].role))


func _spawn_team(data_path: String, attack_dir: float, index: int) -> MatchTeam:
	var team := MatchTeam.new()
	team.data = (load(data_path) as TeamSheet).duplicate()
	team.attack_dir_z = attack_dir
	team.team_index = index
	team.name = "Team%d" % index
	_env.add_child(team)
	return team


# --- 3. Kits, numbers, looks --------------------------------------------------

func _test_kits_numbers_and_looks() -> void:
	await _reset_env()
	var team := _spawn_team(TEAM_GOLD, -1.0, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var players := team.players
	var keeper := players[0]
	var striker := players[9]

	# Kit: the goalkeeper's jersey differs from the outfield jersey.
	var keeper_jersey := _jersey_color(keeper.visual)
	var striker_jersey := _jersey_color(striker.visual)
	_check(keeper_jersey != striker_jersey,
		"Goalkeeper kit differs from the outfield kit",
		"%s vs %s" % [str(keeper_jersey), str(striker_jersey)])
	_check(striker_jersey.is_equal_approx(Color(0.93, 0.74, 0.2)),
		"The gold kit colours the jersey", str(striker_jersey))

	# Shirt number: the striker is #9 → atlas cell column 9, row 0.
	var number_mat := _number_material(striker.visual)
	_check(number_mat != null, "The number material exists on the model")
	if number_mat != null:
		_check(is_equal_approx(number_mat.uv1_offset.x, 0.9)
				and is_equal_approx(number_mat.uv1_offset.y, 0.0),
			"Striker #9 points at its cell of the number atlas",
			str(number_mat.uv1_offset))
		_check(is_equal_approx(number_mat.uv1_scale.x, 0.1),
			"The number atlas cell is 1/10 of the atlas",
			str(number_mat.uv1_scale))

	# Individual looks: only the chosen hair mesh is visible.
	var looks := {}
	var styles := {}
	var heights := {}
	for p in players:
		looks[p.visual.look.skin] = true
		styles[p.visual.look.hair_style] = true
		heights[snappedf(p.visual.look.height, 0.01)] = true
	_check(looks.size() >= 4, "The squad has varied skin tones (%d)" % looks.size())
	_check(styles.size() >= 3, "The squad has varied hair styles (%d)" % styles.size())
	_check(heights.size() >= 8, "The squad has varied heights (%d)" % heights.size())

	var styles_ok := true
	for p in players:
		var want := "Hair_" + p.visual.look.hair_style
		for style in ["Short", "Buzz", "Afro", "Long"]:
			var node := p.visual.find_child("*_Hair_" + style, true, false) as Node3D
			if node == null:
				styles_ok = false
				continue
			if node.visible != (("Hair_" + style) == want):
				styles_ok = false
		var beard := p.visual.find_child("*_Beard", true, false) as Node3D
		if beard == null or beard.visible != p.visual.look.beard:
			styles_ok = false
	_check(styles_ok, "Hair style and beard meshes follow the individual look")

	var rig := players[0].visual.find_child("*_Rig", true, false) as Node3D
	_check(rig != null, "The model exposes its rig node")
	if rig != null:
		var want_scale := players[0].visual.look.height
		_check(absf(rig.scale.y - want_scale) < 0.001,
			"The rig is scaled to the player's height",
			"%.3f vs %.3f" % [rig.scale.y, want_scale])


func _jersey_color(root: Node) -> Color:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			if not m.mesh.surface_get_material(s).resource_name.ends_with("Jersey"):
				continue
			var override := m.get_surface_override_material(s) as StandardMaterial3D
			if override != null:
				return override.albedo_color
	return Color.BLACK


func _number_material(root: Node) -> StandardMaterial3D:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			if m.mesh.surface_get_material(s).resource_name.ends_with("Number"):
				return m.get_surface_override_material(s) as StandardMaterial3D
	return null


# --- 4. Goalkeeper AI ----------------------------------------------------------

func _test_goalkeeper_ai() -> void:
	await _reset_env()
	var arena := (load(ARENA_SCENE) as PackedScene).instantiate()
	_env.add_child(arena)
	await get_tree().physics_frame
	for pc in arena.find_children("*", "PlayerController", true, false):
		pc.queue_free()
	await get_tree().physics_frame

	var team := _spawn_team(TEAM_GOLD, -1.0, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var gk := team.goalkeeper() as TeamGoalkeeper
	gk.dived.connect(func(_side: int) -> void: _dives += 1)
	gk.ball_caught.connect(func() -> void: _caught += 1)
	gk.ball_released.connect(func() -> void: _released += 1)

	# The keeper must find the project's ball through its own group.
	_ball = (load(BALL_SCENE) as PackedScene).instantiate() as BallController
	_ball.position = Vector3(25.0, 0.12, 20.0)
	_env.add_child(_ball)
	await get_tree().physics_frame
	_check(gk.ball == _ball, "The keeper finds the project's BallController", str(gk.ball))

	# The model carries every goalkeeper clip.
	var ap := gk.gk_visual.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_check(ap != null, "The goalkeeper model has an AnimationPlayer")
	if ap != null:
		for clip in ["Ready", "Walk", "Run", "Kick", "DiveLeft", "DiveRight",
				"CatchHigh", "CatchLow", "Throw"]:
			_check(ap.has_animation(clip), "goalkeeper anim %s" % clip)

	# 1. Guarding: the keeper holds his line while the ball is far away.
	var gk_ap := gk.gk_visual.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var clip_pos_before := gk_ap.current_animation_position
	await _await_ticks(120)
	# The animation driver is called every tick; a per-tick play() must not
	# restart the clip, or the keeper would never actually walk.
	_check(gk_ap.current_animation_position > clip_pos_before,
		"The keeper's animation advances while he walks",
		"%.3f -> %.3f (%s)" % [clip_pos_before, gk_ap.current_animation_position,
			str(gk_ap.current_animation)])
	_check(absf(gk.position.x) <= gk.goal_half_width,
		"The keeper stays inside the goal width", str(gk.position.x))
	_check(gk.position.z > 48.0 and gk.position.z < 52.5,
		"The keeper guards in front of his goal line", str(gk.position.z))
	_check(gk.state == TeamGoalkeeper.State.GUARD, "The keeper is in the GUARD state")

	# 2. A central shot is caught — and the ball is never frozen or teleported.
	_ball.reset_ball(Vector3(0.3, 0.12, 22.0))
	_ball.apply_kick(Vector3(0.0, 0.0, 1.0), 20.0)
	# The tracker starts after the scenario reset (a teleport by the test
	# harness is not a gameplay teleport).
	_max_step = 0.0
	_prev_ball_pos = _ball.global_position
	var waited := 0
	while _caught == 0 and waited < 400:
		await get_tree().physics_frame
		waited += 1
		_track_step()
	_check(_caught == 1, "A central shot is caught", "after %d frames" % waited)
	_check(not _ball.freeze, "The caught ball is never frozen")
	var to_gk := _ball.global_position - gk.global_position
	_check(Vector2(to_gk.x, to_gk.z).length() < 1.5,
		"The caught ball ends next to the keeper", str(to_gk))
	# The hands absorb the ball over a few frames — measure once it settled.
	for i in 12:
		await get_tree().physics_frame
		_track_step()
	_check(_ball.linear_velocity.length() < 3.0,
		"The caught ball is under control", str(_ball.linear_velocity.length()))

	# 3. The keeper throws the ball back into play.
	var released := 0
	while _released == 0 and released < 300:
		await get_tree().physics_frame
		released += 1
		_track_step()
	_check(_released == 1, "The keeper throws the ball out", "after %d frames" % released)
	_check(_ball.linear_velocity.z < -3.0,
		"The thrown ball leaves towards the pitch", str(_ball.linear_velocity))
	_check(not _ball.freeze, "The released ball is dynamic again")
	# The whole catch → hold → throw window is covered: no script may move the
	# ball, the keeper may only push it with forces.
	_check(_max_step < 0.5, "The ball is never teleported (max step %.2f)" % _max_step)

	# 4. A ball moving away from the goal is not caught — even when it is right
	# next to the keeper (the keeper may not pick up a clearance).
	await _await_ticks(120)
	_caught = 0
	var gk_pos := gk.global_position
	_ball.reset_ball(gk_pos + Vector3(0.0, 0.12, -0.35))
	# The harness sets the velocity directly: the ball has to be rolling away
	# already when the keeper sees it (an impulse only reaches the physics
	# state on the next step, so a kicked ball would still be at rest for one
	# frame).
	_ball.linear_velocity = Vector3(0.0, 0.0, -15.0)
	await _await_ticks(8)
	_check(_caught == 0, "A ball moving away from the goal is not caught")

	# 5. A shot into the corner makes the keeper dive.
	await _await_ticks(150)
	_dives = 0
	_ball.reset_ball(Vector3(0.0, 0.5, 26.0))
	var target := Vector3(3.0, 0.0, 52.5)
	_ball.apply_kick((target - _ball.global_position).normalized(), 22.0)
	var max_dx := 0.0
	for i in 120:
		await get_tree().physics_frame
		max_dx = maxf(max_dx, absf(gk.position.x))
	_check(_dives >= 1, "The keeper dives for a corner shot", "dives=%d" % _dives)
	_check(max_dx > 1.2, "The keeper moved sideways during the dive", "%.2f" % max_dx)
	await _await_ticks(180)
	_check(gk.state == TeamGoalkeeper.State.GUARD,
		"The keeper returns to GUARD after the dive", str(gk.state))


func _track_step() -> void:
	var pos := _ball.global_position
	_max_step = maxf(_max_step, pos.distance_to(_prev_ball_pos))
	_prev_ball_pos = pos


# --- 5. Integration -------------------------------------------------------------

func _test_integration() -> void:
	# The human player is untouched by the team work.
	await _reset_env()
	var player := (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	await get_tree().physics_frame
	_check(player.get_node_or_null("BallActions") != null,
		"The human player still carries the BallActions node")
	_check(player.get_node_or_null("BallActions/BallDetector") != null,
		"The human player still carries the BallDetector node")
	var visual := player.get_node_or_null("VisualRoot") as Node
	_check(visual != null and visual.has_method("play_kick"),
		"The human player's visual still exposes the kick hook")
	player.queue_free()

	# The demo scene puts two teams on the pitch.
	_env = null
	var demo := (load(DEMO_SCENE) as PackedScene).instantiate()
	add_child(demo)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(demo.team_a != null and demo.team_a.players.size() == 11,
		"The demo lines up team A", str(demo.team_a.players.size()) if demo.team_a else "none")
	_check(demo.team_b != null and demo.team_b.players.size() == 11,
		"The demo lines up team B", str(demo.team_b.players.size()) if demo.team_b else "none")
	_check(demo.ball != null, "The demo has the match ball")
	if demo.team_a != null:
		demo.team_a.set_formation("4-2-3-1")
		await get_tree().physics_frame
		_check(demo.team_a.players.size() == 11 and demo.team_a.players[6].role == "DM",
			"The demo switches the formation", str(demo.team_a.players[6].role))
	demo.queue_free()
