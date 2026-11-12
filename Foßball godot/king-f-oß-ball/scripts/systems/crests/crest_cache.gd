class_name CrestCache
extends RefCounted

## LRU cache of crest textures, keyed by (design, variant, size, version). A crest is only
## drawn when a screen first asks for it; repeated requests (tables, cards) reuse the texture.

const MAX_ENTRIES := 256

var _textures: Dictionary = {}      # key -> Texture2D (insertion order = least recently used first)
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


func store(key: String, texture: Texture2D) -> void:
	_textures.erase(key)
	_textures[key] = texture
	while _textures.size() > MAX_ENTRIES:
		_textures.erase(_textures.keys()[0])
		evictions += 1


func clear() -> void:
	_textures.clear()
