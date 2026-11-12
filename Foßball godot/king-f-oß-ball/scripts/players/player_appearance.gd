class_name PlayerAppearance
extends RefCounted

## Appearance DATA of one player (Phase V2/V9). Lives in `PlayerData.appearance`
## (a plain Dictionary, saved with the player, keyed by the stable player id)
## and is turned into the runtime `PlayerLook` resource by `to_look()`.
##
## Identity rules
##   - Generated once, deterministically, from the player id (`seed_for`), then
##     STORED. The stored indices win over any later change of the generator, so
##     a player never changes face because the code or palette moved on.
##   - The generation sequence is identical to `PlayerLook.random(hash(id))`, so
##     every player that already existed keeps the exact look they had before
##     this system was introduced.
##   - Promotion, transfers and kit changes never touch it (they do not
##     replace the PlayerData instance or its id).
##
## Fields: v, seed, skin, hair_style, hair, beard, boots, height_pm, build_pm and (v2)
## face, eyes, brows, nose, mouth, eye_color (indices into the `FaceBuilder` tables).
## v1 records (no face fields) are upgraded by `upgrade()` with a SEPARATE RNG stream, so
## nothing a v1 record already had can change.
## Palette entries are INDICES into PlayerLook.SKINS / HAIRS / BOOTS. Height and
## build are INTEGER per-mille (1000 = 1.0): Godot's JSON parser does not round-trip
## every double exactly, integers always do, so a save can never drift.
##
## NOT here (needs new art, see docs/PLAYER_APPEARANCE_SYSTEM.md): separate
## face meshes for eyes / nose / mouth. The shipped model has one head.

const VERSION := 2
const FACE_KEYS: Array[String] = ["face", "eyes", "brows", "nose", "mouth", "eye_color"]
const HEIGHT_RANGE := Vector2i(900, 1120)   # per-mille; mirrors PlayerLook @export_range
const BUILD_RANGE := Vector2i(900, 1150)


## Stable seed for a player id (String.hash is stable across runs/platforms).
static func seed_for(player_id: String) -> int:
	return hash(player_id) & 0x7fffffff


## Deterministic appearance for `seed_value` (see class doc for the sequence).
static func generate(seed_value: int, goalkeeper := false) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var a := {"v": VERSION, "seed": seed_value}
	a["skin"] = r.randi() % PlayerLook.SKINS.size()
	a["hair"] = r.randi() % PlayerLook.HAIRS.size()
	a["boots"] = r.randi() % PlayerLook.BOOTS.size()
	var roll := r.randf()
	var style: String = "Short" if roll < 0.35 else "Buzz" if roll < 0.55 \
		else "Afro" if roll < 0.70 else "Long" if roll < 0.82 else "Bald"
	if style == "Afro":
		a["hair"] = r.randi() % 3
	a["hair_style"] = style
	a["beard"] = r.randf() < (0.4 if style == "Bald" or style == "Buzz" else 0.22)
	a["height_pm"] = roundi((r.randf_range(0.95, 1.07) + (0.03 if goalkeeper else 0.0)) * 1000.0)
	a["build_pm"] = roundi(r.randf_range(0.94, 1.10) * 1000.0)
	a.merge(_face_fields(seed_value))
	return a


## Face part indices for a seed: an independent RNG stream (never disturbs the body fields).
static func _face_fields(seed_value: int) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed_value, "face"])
	var c := FaceBuilder.counts()
	var out := {}
	for k in FACE_KEYS:
		out[k] = r.randi() % int(c[k])
	return out


## v1 -> v2: keeps every existing field, adds the face fields deterministically.
static func upgrade(a: Dictionary, fallback_seed := 0) -> Dictionary:
	var out := a.duplicate(true)
	var seed_value := _int(a.get("seed"), fallback_seed)
	for k in FACE_KEYS:
		if not out.has(k):
			out.merge({k: _face_fields(seed_value)[k]})
	out["v"] = VERSION
	return out


## Returns the cleaned copy of `a`: unknown / out-of-range values are replaced
## by safe defaults, so a damaged or future save can never crash the renderer.
static func sanitize(a: Dictionary) -> Dictionary:
	var out := {"v": VERSION, "seed": _int(a.get("seed"), 0)}
	out["skin"] = clampi(_int(a.get("skin"), 0), 0, PlayerLook.SKINS.size() - 1)
	out["hair"] = clampi(_int(a.get("hair"), 0), 0, PlayerLook.HAIRS.size() - 1)
	out["boots"] = clampi(_int(a.get("boots"), 0), 0, PlayerLook.BOOTS.size() - 1)
	var style := str(a.get("hair_style", "Short"))
	out["hair_style"] = style if style in PlayerLook.HAIR_STYLES else "Short"
	out["beard"] = _bool(a.get("beard"))
	var c := FaceBuilder.counts()
	for k in FACE_KEYS:
		out[k] = clampi(_int(a.get(k), 0), 0, int(c[k]) - 1)
	out["height_pm"] = clampi(_int(a.get("height_pm"), 1000), HEIGHT_RANGE.x, HEIGHT_RANGE.y)
	out["build_pm"] = clampi(_int(a.get("build_pm"), 1000), BUILD_RANGE.x, BUILD_RANGE.y)
	return out


# Type-safe coercion: a damaged save may hold strings, nulls or arrays anywhere.
static func _int(v: Variant, fallback: int) -> int:
	return int(v) if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT else fallback


static func _bool(v: Variant) -> bool:
	return bool(v) if typeof(v) == TYPE_BOOL or typeof(v) == TYPE_INT else false


## True when `a` is a complete, current appearance record whose values are all
## already in range (i.e. sanitising it would change nothing).
static func is_valid(a: Dictionary) -> bool:
	var clean := sanitize(a)
	for k in clean:
		if not a.has(k) or typeof(a[k]) != typeof(clean[k]) or a[k] != clean[k]:
			return false
	return true


## Makes sure `p.appearance` exists (generating it from the player id when
## missing or incomplete) and returns it. The ONLY writer of a player's
## appearance — every consumer goes through here, so identity is stable.
static func ensure(p: PlayerData) -> Dictionary:
	if p == null:
		return {}
	if not p.appearance.is_empty() and _int(p.appearance.get("v"), 0) < VERSION:
		p.appearance = upgrade(p.appearance, seed_for(p.id))
	if p.appearance.is_empty():
		p.appearance = generate(seed_for(p.id), p.position == PlayerData.Position.GK)
	elif not is_valid(p.appearance):
		var fresh := generate(seed_for(p.id), p.position == PlayerData.Position.GK)
		var merged := fresh.duplicate()
		for k in sanitize(p.appearance):          # keep whatever was valid
			if p.appearance.has(k):
				merged[k] = sanitize(p.appearance)[k]
		p.appearance = merged
	return p.appearance


## Runtime look resource for an appearance dictionary.
static func to_look(a: Dictionary) -> PlayerLook:
	var s := sanitize(a)
	var l := PlayerLook.new()
	l.skin = PlayerLook.SKINS[s["skin"]]
	l.hair = PlayerLook.HAIRS[s["hair"]]
	l.boots = PlayerLook.BOOTS[s["boots"]]
	l.hair_style = s["hair_style"]
	l.beard = s["beard"]
	l.face_shape = s["face"]
	l.eyes = s["eyes"]
	l.brows = s["brows"]
	l.nose = s["nose"]
	l.mouth = s["mouth"]
	l.eye_color = s["eye_color"]
	l.height = float(s["height_pm"]) / 1000.0
	l.build = float(s["build_pm"]) / 1000.0
	return l


## The look for a player (stored appearance, generated on first use).
static func look_for(p: PlayerData) -> PlayerLook:
	return to_look(ensure(p))


## Compact text key of everything that changes how the player looks; used as
## part of portrait cache keys.
static func signature(a: Dictionary) -> String:
	var s := sanitize(a)
	return "%d.%d.%d.%s.%d.%d.%d.f%d%d%d%d%d%d" % [s["skin"], s["hair"], s["boots"], s["hair_style"],
			1 if s["beard"] else 0, s["height_pm"], s["build_pm"], s["face"], s["eyes"], s["brows"],
			s["nose"], s["mouth"], s["eye_color"]]
