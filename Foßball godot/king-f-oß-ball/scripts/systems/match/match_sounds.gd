class_name MatchSounds
extends Node

## Match sound effects generated with Higgsfield (text-to-audio) and stored in `audio/match/`: a looping crowd ambience whose level
## follows the crowd's loudness, a goal cheer, a disappointed groan and the referee's whistle. All of them are triggered by real
## match events (`MatchState.events`); nothing plays on a timer. Falls back to the procedural `CrowdAudio` when the files are missing.

const DIR := "res://audio/match/"
const FILES := {"ambience": "crowd_ambience.mp3", "cheer": "crowd_cheer.mp3", "groan": "crowd_groan.mp3", "whistle": "whistle.mp3"}
const WHISTLE_EVENTS: Array[String] = ["foul", "yellow_card", "red_card", "offside", "corner", "goal_kick", "throw_in", "half_time"]

var crowd: CrowdSystem
var state: MatchState
var _ambience: AudioStreamPlayer
var _fx: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}
var _seen := 0


static func available() -> bool:
	for k in FILES:
		if not ResourceLoader.exists(DIR + FILES[k]):
			return false
	return true


## Which effect an event triggers ("" = none): goals follow the crowd mood (cheer for the home side, groan against it); the whistle
## marks every stoppage. Pure, so it can be tested without audio.
static func effect_for(ev: Dictionary, mood: String) -> String:
	var t := str(ev.get("type", ""))
	if t == "goal":
		return "groan" if mood == "groan" else "cheer"
	if t in WHISTLE_EVENTS:
		return "whistle"
	return ""


func _ready() -> void:
	for k in FILES:
		_streams[k] = load(DIR + FILES[k])
	var amb: AudioStreamMP3 = _streams["ambience"]
	amb.loop = true
	_ambience = AudioStreamPlayer.new()
	_ambience.stream = amb
	_ambience.volume_db = -14.0
	add_child(_ambience)
	_ambience.play()
	for i in 3:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_fx.append(p)


func _process(_delta: float) -> void:
	if crowd == null or state == null:
		return
	_ambience.volume_db = linear_to_db(clampf(0.12 + crowd.loudness() * 0.9, 0.05, 1.0))
	while _seen < state.events.size():
		var fx := effect_for(state.events[_seen], crowd.mood)
		_seen += 1
		if fx != "":
			play_effect(fx)


func play_effect(effect: String) -> bool:
	if not _streams.has(effect) or effect == "ambience":
		return false
	for p in _fx:
		if not p.playing:
			p.stream = _streams[effect]
			p.volume_db = -4.0 if effect != "whistle" else -8.0
			p.play()
			return true
	return false
