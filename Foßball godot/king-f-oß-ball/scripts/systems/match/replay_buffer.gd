class_name ReplayBuffer
extends RefCounted

## Bounded recording of the last seconds of a match (Phase 11). Every `RATE` Hz one frame is stored: the ball position and, for
## each tracked body, position and facing. Memory is bounded: at most `capacity` frames are kept (a ring), 23 bodies x 4 floats
## each, so 10 s at 20 Hz is about 18 KB. Nothing but transforms is stored - a replay replays movement, not gameplay state.
## A clip is a copy of the newest `seconds` of frames.

const RATE := 20.0                       # frames per second
const FLOATS_PER_BODY := 4               # x, y, z, yaw

var capacity: int = 200                  # 10 s
var body_count: int = 0
var _frames: Array = []                  # each: {t: float, data: PackedFloat32Array}
var _accum: float = 0.0
var _clock: float = 0.0


func _init(p_body_count: int = 23, seconds: float = 10.0) -> void:
	body_count = p_body_count
	capacity = int(seconds * RATE)


## Call every physics tick with `delta` and a callable returning a PackedFloat32Array of `body_count * 4` floats
## (ball first, then players). Returns true when a frame was stored.
func tick(delta: float, sampler: Callable) -> bool:
	_clock += delta
	_accum += delta
	if _accum < 1.0 / RATE:
		return false
	_accum -= 1.0 / RATE
	var data: PackedFloat32Array = sampler.call()
	if data.size() != body_count * FLOATS_PER_BODY:
		return false
	_frames.append({"t": _clock, "data": data})
	while _frames.size() > capacity:
		_frames.pop_front()
	return true


func frame_count() -> int:
	return _frames.size()


func clear() -> void:
	_frames.clear()
	_accum = 0.0


## The newest `seconds` as a clip: {frames: Array of {t, data}, duration}. Frame times are rebased to start at 0.
func clip(seconds: float) -> Dictionary:
	var n := mini(_frames.size(), maxi(int(seconds * RATE), 1))
	if n <= 0:
		return {"frames": [], "duration": 0.0, "body_count": body_count}
	var src: Array = _frames.slice(_frames.size() - n)
	var t0: float = src[0]["t"]
	var frames: Array = []
	for f in src:
		frames.append({"t": float(f["t"]) - t0, "data": f["data"]})
	return {"frames": frames, "duration": float(frames[frames.size() - 1]["t"]), "body_count": body_count}


## Interpolated sample of a clip at `time` (clamped to the clip): PackedFloat32Array like the recorded frames.
static func sample(clip_data: Dictionary, time: float) -> PackedFloat32Array:
	var frames: Array = clip_data["frames"]
	if frames.is_empty():
		return PackedFloat32Array()
	if time <= float(frames[0]["t"]):
		return frames[0]["data"]
	var last: Dictionary = frames[frames.size() - 1]
	if time >= float(last["t"]):
		return last["data"]
	var lo := 0
	var hi := frames.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if float(frames[mid]["t"]) <= time:
			lo = mid
		else:
			hi = mid
	var a: Dictionary = frames[lo]
	var b: Dictionary = frames[hi]
	var k := (time - float(a["t"])) / maxf(float(b["t"]) - float(a["t"]), 0.0001)
	var out := PackedFloat32Array()
	out.resize((a["data"] as PackedFloat32Array).size())
	for i in out.size():
		var va: float = (a["data"] as PackedFloat32Array)[i]
		var vb: float = (b["data"] as PackedFloat32Array)[i]
		if i % FLOATS_PER_BODY == 3:
			out[i] = lerp_angle(va, vb, k)
		else:
			out[i] = lerpf(va, vb, k)
	return out
