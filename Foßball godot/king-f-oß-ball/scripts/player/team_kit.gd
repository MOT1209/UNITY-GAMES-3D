class_name TeamKit
extends Resource

## Colour set for a character. Recolours every material whose name ends with
## Jersey / Trim / Shorts / Socks / Boots / Skin / Hair (e.g. "P_Jersey",
## "G_Shorts") — the player and goalkeeper models use the same naming, so one
## kit resource dresses both.
##
## The look system (`PlayerLook`) is applied *after* the kit, so an individual
## player's skin / hair / boots win over the kit defaults.

@export var jersey := Color(0.93, 0.74, 0.2)
@export var trim := Color(0.08, 0.12, 0.3)
@export var shorts := Color(0.12, 0.16, 0.32)
@export var socks := Color(0.93, 0.74, 0.2)
@export var boots := Color(0.07, 0.07, 0.09)
@export var skin := Color(0.86, 0.64, 0.49)
@export var hair := Color(0.09, 0.06, 0.04)


## Builds a kit from a `TeamData.kits` entry ({main, secondary, shorts, socks,
## ...} hex strings). main -> jersey, secondary -> trim. Missing/invalid values
## fall back to sensible derived colours. `pattern` (stripes, hoops, ...) is not
## rendered: the models only expose flat colour slots.
static func from_dict(kit: Dictionary, fallback: Color = Color.WHITE) -> TeamKit:
	var k := TeamKit.new()
	k.jersey = Color.from_string(str(kit.get("main", "")), fallback)
	k.trim = Color.from_string(str(kit.get("secondary", "")), k.jersey.darkened(0.4))
	k.shorts = Color.from_string(str(kit.get("shorts", "")), k.trim)
	k.socks = Color.from_string(str(kit.get("socks", "")), k.jersey)
	return k


## Recolours every matching material of `root` (and its children).
func apply_to(root: Node) -> void:
	if root == null:
		return
	var map := {"Jersey": jersey, "Trim": trim, "Shorts": shorts, "Socks": socks,
		"Boots": boots, "Skin": skin, "Hair": hair}
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(s)
			if mat == null:
				continue
			for suffix in map:
				if mat.resource_name.ends_with(suffix):
					var own := (mat.duplicate() as StandardMaterial3D)
					own.albedo_color = map[suffix]
					m.set_surface_override_material(s, own)
