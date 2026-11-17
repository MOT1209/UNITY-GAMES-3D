class_name TeamKit
extends Resource

## Colour set (and shirt pattern) for a character. Recolours every material whose name ends with
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
## Shirt pattern (`KitEditor.PATTERNS`): solid, stripes, hoops, halves, sash, checks. Rendered on the
## jersey (jersey colour + trim colour) by `KitPattern`.
@export var pattern := "solid"
## Club crest drawn on the left chest of the 3D shirt (null = none). Set by whoever builds the kit
## from a team (`TeamKit.with_crest`), never stored in the kit data itself.
@export var crest: Texture2D


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
	var pat := str(kit.get("pattern", "solid"))
	k.pattern = pat if KitPattern.is_patterned(pat) else "solid"
	return k


## Builds the kit of `team` in `slot` with the club crest on the chest (national teams have none).
static func for_team(db: Node, team: TeamData, slot: String, fallback: Color = Color.WHITE) -> TeamKit:
	var k := from_dict(team.kits.get(slot, {}), team.primary_color if fallback == Color.WHITE else fallback)
	k.crest = CrestService.texture(db, team, "kit")
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
					if suffix == "Jersey":
						KitPattern.apply(own, pattern, jersey, trim)
					else:
						own.albedo_color = map[suffix]
					m.set_surface_override_material(s, own)
