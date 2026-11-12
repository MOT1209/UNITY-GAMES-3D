class_name CrowdAudio
extends Node

## Plays the procedural crowd noise (`CrowdSystem.noise`) through an AudioStreamGenerator, its level following the crowd's loudness.
## There are no recorded chants or commentary (no audio assets exist); this is a synthesized bed only.

const MIX_RATE := 22050.0

var crowd: CrowdSystem
var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _seed := 1


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.25
	_player.stream = gen
	_player.volume_db = -8.0
	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback


func _process(_delta: float) -> void:
	if _playback == null or crowd == null:
		return
	var n := _playback.get_frames_available()
	if n <= 0:
		return
	var samples := CrowdSystem.noise(n, crowd.loudness(), _seed)
	_seed += 1
	var buf := PackedVector2Array()
	buf.resize(n)
	for i in n:
		buf[i] = Vector2(samples[i], samples[i])
	_playback.push_buffer(buf)
