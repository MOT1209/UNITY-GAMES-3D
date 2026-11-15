class_name PlayerLook
extends Resource

## Individual appearance of one player: skin tone, hair colour and style,
## beard, boots, height and build.
##
## The models ship every hair style as its own mesh (`P_Hair_Short`,
## `P_Hair_Buzz`, `P_Hair_Afro`, `P_Hair_Long`) plus an optional beard
## (`P_Beard`); "Bald" simply hides all of them. `PlayerLook.random()` gives a
## deterministic look for a given seed, so a team always dresses the same.

const SKINS := [Color(0.98, 0.84, 0.72), Color(0.90, 0.70, 0.54), Color(0.80, 0.58, 0.40), Color(0.64, 0.43, 0.29),
	Color(0.46, 0.30, 0.20), Color(0.30, 0.19, 0.13)]
const HAIRS := [Color(0.05, 0.04, 0.04), Color(0.16, 0.10, 0.06), Color(0.32, 0.20, 0.10), Color(0.78, 0.62, 0.30),
	Color(0.55, 0.22, 0.10), Color(0.62, 0.62, 0.62)]
const BOOTS := [Color(0.07, 0.07, 0.09), Color(0.95, 0.95, 0.95), Color(0.95, 0.45, 0.08), Color(0.12, 0.35, 0.85),
	Color(0.6, 0.9, 0.1), Color(0.9, 0.1, 0.4)]
## Hair styles that exist as separate meshes in the model.
const HAIR_STYLES := ["Short", "Buzz", "Afro", "Long", "Bald"]
## Skin tones (round 3): every legacy tone (even index = SKINS[i / 2], unchanged) followed by a variant
## with a different undertone, light to dark — 12 tones.
const SKIN_TONES := [Color(0.98, 0.84, 0.72), Color(0.95, 0.80, 0.70), Color(0.90, 0.70, 0.54), Color(0.86, 0.68, 0.58),
	Color(0.80, 0.58, 0.40), Color(0.74, 0.55, 0.42), Color(0.64, 0.43, 0.29), Color(0.58, 0.40, 0.30),
	Color(0.46, 0.30, 0.20), Color(0.40, 0.27, 0.20), Color(0.30, 0.19, 0.13), Color(0.24, 0.15, 0.11)]
## Haircuts (round 3): each one = a base hair MESH of the model (`HAIR_STYLES`, always drawn) plus optional
## sculpted pieces built by `HairBuilder` (near cameras only, see PlayerCharacterVisual.FACE_LOD_END).
const CUTS := {"Short": "Short", "Buzz": "Buzz", "Afro": "Afro", "Long": "Long", "Bald": "Bald",
	"Wavy": "Short", "Curly": "Buzz", "Braids": "Buzz", "Ponytail": "Short", "ManBun": "Short",
	"Mohawk": "Buzz", "Dreads": "Short", "SidePart": "Short", "FlatTop": "Buzz"}
## Beard styles: 0 none, 1 full (the model's beard mesh), 2 stubble, 3 goatee, 4 moustache, 5 chin strap,
## 6 moustache + goatee.
const BEARD_STYLES := ["None", "Full", "Stubble", "Goatee", "Moustache", "ChinStrap", "Anchor"]

@export var skin := Color(0.86, 0.64, 0.49)
@export var hair := Color(0.09, 0.06, 0.04)
@export var boots := Color(0.07, 0.07, 0.09)
@export_enum("Short", "Buzz", "Afro", "Long", "Bald") var hair_style := "Short"
@export var beard := false
## Face parts (indices into the `FaceBuilder` tables). -1 = keep the model's original
## baked face, so every look that does not carry face data renders exactly as before.
@export var face_shape := -1
@export var eyes := 0
@export var brows := 0
@export var nose := 0
@export var mouth := 0
@export var eye_color := 0
## Round 3 (appearance v3). `cut` "" = use `hair_style` alone (older looks); `jaw` 0 = original chin.
@export var cut := ""
@export_range(0, 6) var beard_style := -1      # -1 = derive from `beard` (older looks)
@export var jaw := 0
@export var long_sleeves := false
@export_range(0.9, 1.12) var height := 1.0
@export_range(0.9, 1.15) var build := 1.0


## Deterministic look for a seed. `goalkeeper` gives keepers a slightly
## taller frame on average.
static func random(seed_value: int, goalkeeper := false) -> PlayerLook:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var l := PlayerLook.new()
	l.skin = SKINS[r.randi() % SKINS.size()]
	l.hair = HAIRS[r.randi() % HAIRS.size()]
	l.boots = BOOTS[r.randi() % BOOTS.size()]
	var roll := r.randf()
	l.hair_style = "Short" if roll < 0.35 else "Buzz" if roll < 0.55 \
		else "Afro" if roll < 0.70 else "Long" if roll < 0.82 else "Bald"
	if l.hair_style == "Afro":
		l.hair = HAIRS[r.randi() % 3]
	# A shaved head usually goes with a beard; a full head rarely does.
	l.beard = r.randf() < (0.4 if l.hair_style == "Bald" or l.hair_style == "Buzz" else 0.22)
	l.height = r.randf_range(0.95, 1.07) + (0.03 if goalkeeper else 0.0)
	l.build = r.randf_range(0.94, 1.10)
	return l
