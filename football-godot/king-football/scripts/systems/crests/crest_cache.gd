class_name CrestCache
extends RefCounted

## LRU cache of crest textures, keyed by (design, variant, size, version). A crest is only
## drawn when a screen first asks for it; repeated requests (tables, cards) reuse the texture.
## Memory-aware: it holds at most MAX_BYTES of pixel data (RGBA) and MAX_ENTRIES textures, so a list
## of every club (298 icons = ~2 MB) fits and is not re-drawn on every pass (measured: with 256 entries
## a sequential pass over 298 clubs evicted each icon just before it was needed again, 0 hits).

const MAX_ENTRIES := 1024
const MAX_BYTES := 24 * 1024 * 1024

var _textures: Dictionary = {}      # key -> Texture2D (insertion order = least recently used first)
var bytes := 0
var hits := 0
var misses := 0
var evictions := 0


func size() -> int:
	return _textures.size()


func has(key: String) -> bool:
	return _textures.has(key)


func fetch(key: String) -> Texture2D:
	if not _textures.has(key):
		misses += 1
		return null
	hits += 1
	var t: Texture2D = _textures[key]
	_textures.erase(key)                 # re-insert = most recently used
	_textures[key] = t
	return t


static func _bytes_of(t: Texture2D) -> int:
	return t.get_width() * t.get_height() * 4 if t != null else 0


func store(key: String, texture: Texture2D) -> void:
	if _textures.has(key):
		bytes -= _bytes_of(_textures[key])
		_textures.erase(key)
	_textures[key] = texture
	bytes += _bytes_of(texture)
	while (_textures.size() > MAX_ENTRIES or bytes > MAX_BYTES) and _textures.size() > 1:
		var oldest: String = _textures.keys()[0]
		bytes -= _bytes_of(_textures[oldest])
		_textures.erase(oldest)
		evictions += 1


func clear() -> void:
	_textures.clear()
	bytes = 0
