## Atmosphere and presentation: weather / time of day, crowd reactions, replays.
##   godot --headless --path . res://tests/phase13_presentation_validation.tscn
extends Node

const TEAM_H := "club_royal_harbor"
const TEAM_A := "club_northgate_utd"

var _passed := 0
var _failed := 0
var db: Node


func _check(ok: bool, name: String, detail := "") -> void:
	if ok:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s%s" % [name, (" — " + detail) if detail != "" else ""])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _ready() -> void:
	await get_tree().process_frame
	print("=== KING FOOTBALL — Atmosphere and presentation validation ===")
	db = get_node("/root/TeamDB")
	db.reload()
	_test_environment()
	_test_crowd()
	_test_replay_buffer()
	await _test_replay_player()
	await _test_sounds()
	await _test_match_integration()
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _arena() -> Node3D:
	var a := (load("res://scenes/stadium/stadium_arena.tscn") as PackedScene).instantiate() as Node3D
	add_child(a)
	return a


func _test_environment() -> void:
	var day := _arena()
	var d := MatchEnvironment.apply(day, {"weather": "clear", "time_of_day": "day"})
	var env_day: Environment = (day.get_node("WorldEnvironment") as WorldEnvironment).environment
	_check(not d["fog"] and not d["rain"] and d["floodlights"] == 0 and not env_day.fog_enabled and (day.get_node("Sun") as DirectionalLight3D).light_energy > 0.8, "clear day leaves the arena as it is")
	var night := _arena()
	var n := MatchEnvironment.apply(night, {"weather": "rain", "time_of_day": "night"})
	var env_night: Environment = (night.get_node("WorldEnvironment") as WorldEnvironment).environment
	_check(n["rain"] and night.get_node_or_null("Rain") is CPUParticles3D, "rain adds a rain emitter above the pitch")
	_check(env_night.fog_enabled and (night.get_node("Sun") as DirectionalLight3D).light_energy < 0.1 and env_night.ambient_light_energy < 0.2, "night + rain: fog, dark sun and dark ambient light")
	_check(n["floodlights"] == 4 and night.get_node_or_null("Floodlight_3") is OmniLight3D, "night switches on four floodlights")
	_check(not env_day.fog_enabled and env_day != env_night, "a night match does not change the environment of a day match (resource is not shared)")
	var fog := _arena()
	var f := MatchEnvironment.apply(fog, {"weather": "fog", "time_of_day": "dusk"})
	var env_fog: Environment = (fog.get_node("WorldEnvironment") as WorldEnvironment).environment
	_check(f["fog"] and not f["rain"] and env_fog.fog_density > 0.01 and f["floodlights"] == 4, "fog raises the fog density; dusk lights the floodlights")
	var bad := MatchEnvironment.apply(_arena(), {"weather": "volcano", "time_of_day": "never"})
	_check(bad["weather"] == "clear" and bad["time_of_day"] == "day", "unknown conditions fall back to a clear day")
	var again := _arena()
	_check(not ((again.get_node("WorldEnvironment") as WorldEnvironment).environment as Environment).fog_enabled, "a fresh arena after a foggy match is clear")


func _test_crowd() -> void:
	var c := CrowdSystem.new(0.9, 1.0)
	var base := c.loudness()
	c.on_event({"type": "goal", "side": "home"})
	_check(c.mood == "cheer" and c.loudness() > base + 0.3, "a home goal makes the crowd cheer and louder")
	c.update(10.0)
	_check(c.mood == "calm" and is_equal_approx(c.loudness(), base), "the excitement fades back to the base atmosphere")
	c.on_event({"type": "goal", "side": "away"})
	_check(c.mood == "groan", "a goal against the home side makes the crowd groan")
	c.on_event({"type": "goal", "side": "home", "own_goal": true})
	_check(c.mood == "groan", "an own goal by the home side is a groan")
	var boo := CrowdSystem.new()
	boo.on_event({"type": "foul", "side": "away"})
	_check(boo.mood == "boo", "a foul by the visitors is booed")
	boo.on_event({"type": "shot", "side": "home"})
	_check(boo.mood == "tense", "a shot builds tension")
	var derby := CrowdSystem.new(0.9, 2.0)
	var quiet := CrowdSystem.new(0.3, 1.0)
	_check(derby.loudness() > CrowdSystem.new(0.9, 1.0).loudness() and quiet.loudness() < CrowdSystem.new(0.9, 1.0).loudness(), "derbies are louder, half-empty stadiums quieter")
	var feed := CrowdSystem.new()
	var evs := [{"type": "shot", "side": "home"}, {"type": "goal", "side": "home"}]
	_check(feed.consume(evs) == 2 and feed.consume(evs) == 0 and feed.mood == "cheer", "every event is consumed exactly once")
	var loud := CrowdSystem.noise(4000, 0.9, 5)
	var soft := CrowdSystem.noise(4000, 0.1, 5)
	var rms_loud := _rms(loud)
	var rms_soft := _rms(soft)
	_check(rms_loud > rms_soft * 5.0 and rms_loud <= 1.0 and CrowdSystem.noise(4000, 0.9, 5) == loud, "procedural crowd noise follows the loudness and is deterministic")


func _rms(a: PackedFloat32Array) -> float:
	var s := 0.0
	for v in a:
		s += v * v
	return sqrt(s / float(maxi(a.size(), 1)))


func _sampler(bodies: int, t: Array) -> Callable:
	return func() -> PackedFloat32Array:
		var d := PackedFloat32Array()
		d.resize(bodies * 4)
		for i in bodies:
			d[i * 4] = t[0] + float(i)
			d[i * 4 + 1] = 0.0
			d[i * 4 + 2] = -t[0]
			d[i * 4 + 3] = 0.0
		return d


func _test_replay_buffer() -> void:
	var rb := ReplayBuffer.new(3, 2.0)
	var t := [0.0]
	var s := _sampler(3, t)
	var stored := 0
	for i in 200:
		t[0] = float(i) * 0.05
		if rb.tick(0.05, s):
			stored += 1
	_check(stored == 200 and rb.frame_count() == 40, "20 Hz recording keeps only the newest 2 s (memory is bounded)", str(rb.frame_count()))
	_check(not rb.tick(0.01, s), "ticks faster than the recording rate store nothing")
	var clip := rb.clip(1.0)
	_check((clip["frames"] as Array).size() == 20 and is_equal_approx(float(clip["frames"][0]["t"]), 0.0) and clip["duration"] > 0.9, "a clip is the newest second, rebased to start at 0")
	var mid := ReplayBuffer.sample(clip, 0.5 * float(clip["duration"]))
	var first: PackedFloat32Array = clip["frames"][0]["data"]
	var last: PackedFloat32Array = clip["frames"][(clip["frames"] as Array).size() - 1]["data"]
	_check(absf(mid[0] - (first[0] + last[0]) * 0.5) < 0.2, "sampling between frames interpolates")
	_check(ReplayBuffer.sample(clip, -5.0) == first and ReplayBuffer.sample(clip, 99.0) == last, "sampling outside the clip clamps to its ends")
	_check(rb.clip(0.0)["frames"].size() == 1 and ReplayBuffer.new(3).clip(2.0)["frames"].is_empty(), "degenerate clips are safe")


func _test_replay_player() -> void:
	var rb := ReplayBuffer.new(3, 4.0)
	var t := [0.0]
	var s := _sampler(3, t)
	for i in 100:
		t[0] = float(i) * 0.05
		rb.tick(0.05, s)
	var clip := rb.clip(2.0)
	var rp := ReplayPlayer.new()
	add_child(rp)
	var colors: Array[Color] = [Color.WHITE, Color.RED, Color.BLUE]
	var finished := [false]
	rp.finished.connect(func() -> void: finished[0] = true)
	_check(rp.start(clip, colors, 0.5) and rp.playing and rp.get_child_count() == 3, "a replay starts with one ghost per body")
	var d: float = clip["duration"]
	rp.advance(1.0)
	_check(is_equal_approx(rp.time, 0.5) and rp.playing, "slow motion: one real second plays half a second of the clip")
	var p1 := (rp.get_child(1) as Node3D).position
	var expected := ReplayBuffer.sample(clip, rp.time)
	_check(is_equal_approx(p1.x, expected[4]) and is_equal_approx(p1.z, expected[6]), "the ghosts stand where the recording says")
	rp.paused = true
	var before := rp.time
	rp._process(1.0)
	_check(rp.time == before, "a paused replay does not move")
	rp.seek(0.0)
	rp.set_speed(10.0)
	_check(rp.speed == 2.0, "speed is limited to 0.25..2")
	rp.paused = false
	rp.advance(d)
	_check(finished[0] and not rp.playing, "the replay finishes at the end of the clip")
	await get_tree().process_frame
	_check(rp.get_child_count() == 0, "the ghosts are removed when it finishes")
	finished[0] = false
	rp.start(clip, colors, 1.0)
	rp.skip()
	_check(finished[0] and not rp.playing, "skip ends the replay at once")
	_check(not rp.start(clip, [Color.RED], 0.5) and not rp.playing, "a replay with the wrong number of colours is refused")
	rp.queue_free()


func _test_match_integration() -> void:
	var setup := MatchSetup.new()
	setup.home_id = TEAM_H
	setup.away_id = TEAM_A
	setup.duration_minutes = 2
	setup.human_side = "none"
	setup.rng_seed = 3
	setup.conditions = {"weather": "rain", "time_of_day": "night"}
	var m := MatchManager.new()
	m.return_to_menu_on_finish = false
	add_child(m)
	_check(m.begin(setup, db) == "", "a match with rain and night starts")
	_check(m.arena_root.get_node_or_null("Rain") != null and m.arena_root.get_node_or_null("Floodlight_0") != null, "the match applies the chosen weather and time of day to its arena")
	m._needs_reset = false
	m._pause_left = 0.0
	m.state.kick_off()
	await _frames(70)
	_check(m.replay_buffer.frame_count() > 10, "the match records its last seconds while playing")
	var loud_before := m.crowd.loudness()
	var goals_before := m.state.events.filter(func(e: Dictionary) -> bool: return e["type"] == "goal").size()
	var frame := m.frame_side("home")
	var goal_pos := PitchSpace.opponent_goal(frame)
	m.last_toucher_id = m.entries["home"][5]["player_id"]
	m.ball.reset_ball(Vector3(goal_pos.x, 0.5, goal_pos.z + (-1.2 if goal_pos.z < 0.0 else 1.2)))
	await _frames(25)
	var goals_after := m.state.events.filter(func(e: Dictionary) -> bool: return e["type"] == "goal").size()
	_check(goals_after == goals_before + 1, "a goal is scored")
	_check(m.crowd.mood == "cheer" and m.crowd.loudness() > loud_before, "the crowd reacts to the real goal event")
	_check(m.replay_player != null and m.replay_player.playing and m.last_replay_seconds > 1.0, "the goal replay starts", str(m.last_replay_seconds))
	_check(m._pause_left >= m.last_replay_seconds - 0.5, "the restart waits for the replay", "%.2f vs %.2f" % [m._pause_left, m.last_replay_seconds])
	m.skip_replay()
	await _frames(2)
	_check(m.replay_player == null or not m.replay_player.playing, "the replay can be skipped")
	m.process_mode = Node.PROCESS_MODE_DISABLED
	m.queue_free()


func _test_sounds() -> void:
	_check(MatchSounds.available(), "the four generated sound files are part of the project")
	for k in MatchSounds.FILES:
		var st := load(MatchSounds.DIR + MatchSounds.FILES[k]) as AudioStreamMP3
		_check(st != null and st.get_length() > 1.0, "%s loads and is longer than a second" % k, str(st.get_length() if st else -1))
	_check(MatchSounds.effect_for({"type": "goal", "side": "home"}, "cheer") == "cheer" and MatchSounds.effect_for({"type": "goal", "side": "away"}, "groan") == "groan", "goals play the cheer or the groan according to the crowd")
	_check(MatchSounds.effect_for({"type": "foul"}, "boo") == "whistle" and MatchSounds.effect_for({"type": "offside"}, "tense") == "whistle" and MatchSounds.effect_for({"type": "shot"}, "tense") == "", "stoppages blow the whistle, a shot is silent")
	var snd := MatchSounds.new()
	var st2 := MatchState.create("h", "a", 2)
	var cr := CrowdSystem.new()
	snd.crowd = cr
	snd.state = st2
	add_child(snd)
	await get_tree().process_frame
	_check(snd.play_effect("whistle") and not snd.play_effect("ambience") and not snd.play_effect("nothing"), "effects play through the free players; the ambience is not an effect")
	st2.phase = MatchState.Phase.PLAYING
	st2.events.append({"type": "foul", "side": "away", "player_id": "x"})
	await get_tree().process_frame
	_check(snd._seen == 1, "new events are picked up exactly once")
	snd.queue_free()
