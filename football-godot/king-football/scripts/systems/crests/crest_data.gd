class_name CrestData
extends Resource

## Metadata of ONE club crest (database phase 4). The crest identity is `crest_id`; every
## variant (full, icon, mono, kit, card) is rendered from this record, so they can never drift.
##
## Asset types
##   OFFICIAL_LICENSED     licensed official artwork (none is shipped; needs a licence record)
##   ORIGINAL_ALTERNATIVE  independently designed stand-in for a REAL club (generic geometric symbols,
##                         own composition; not affiliated with the club and not derived from its logo)
##   FICTIONAL             crest of a fictional club
##   USER_CUSTOM           image or template chosen by the player
## `asset_path` "" = drawn procedurally from the fields below; otherwise an image file or a
## "template:<id>" reference (see LogoService).

enum AssetType { OFFICIAL_LICENSED, ORIGINAL_ALTERNATIVE, FICTIONAL, USER_CUSTOM }

const SHAPES: Array[String] = ["shield", "round", "hex", "banner", "oval", "kite"]
const DIVISIONS: Array[String] = ["plain", "vertical", "diagonal", "band", "quarters"]
const SYMBOLS: Array[String] = ["star", "tower", "mountain", "crown", "ball", "tree", "sun", "arrow",
		"bridge", "leaf", "gem", "castle"]
const LICENSES: Array[String] = ["LICENSED", "ORIGINAL_NOT_AFFILIATED", "FICTIONAL", "USER_SUPPLIED"]
const REQUIRED_LICENSE := {
	AssetType.OFFICIAL_LICENSED: "LICENSED", AssetType.ORIGINAL_ALTERNATIVE: "ORIGINAL_NOT_AFFILIATED",
	AssetType.FICTIONAL: "FICTIONAL", AssetType.USER_CUSTOM: "USER_SUPPLIED",
}

@export var crest_id: String = ""
@export var club_id: String = ""
@export var asset_path: String = ""
@export var asset_type: AssetType = AssetType.FICTIONAL
@export var version: int = 1
@export var shape_style: String = "shield"
@export var division: String = "plain"
@export var symbol: String = "star"
@export var primary_color: Color = Color.WHITE
@export var secondary_color: Color = Color.BLACK
@export var accent_color: Color = Color.WHITE
@export var transparent_background: bool = true
@export var license_status: String = "FICTIONAL"
@export var source: String = "procedural"
@export var created_at: String = ""


func is_procedural() -> bool:
	return asset_path == ""


func is_template() -> bool:
	return LogoService.is_template(asset_path)


func is_file() -> bool:
	return asset_path != "" and not is_template()


## The design only (shape, division, symbol, colours): two clubs with the same signature
## would show the same picture.
func signature() -> String:
	return "%s|%s|%s|%s|%s|%s" % [shape_style, division, symbol, primary_color.to_html(false),
			secondary_color.to_html(false), accent_color.to_html(false)]


func validate() -> Array[String]:
	var errors: Array[String] = []
	if crest_id.strip_edges() == "":
		errors.append("crest has empty id")
	if club_id.strip_edges() == "":
		errors.append("crest '%s' has no club" % crest_id)
	if not (shape_style in SHAPES):
		errors.append("crest '%s' has unknown shape '%s'" % [crest_id, shape_style])
	if not (division in DIVISIONS):
		errors.append("crest '%s' has unknown division '%s'" % [crest_id, division])
	if not (symbol in SYMBOLS):
		errors.append("crest '%s' has unknown symbol '%s'" % [crest_id, symbol])
	if version < 1:
		errors.append("crest '%s' version %d < 1" % [crest_id, version])
	if not (license_status in LICENSES):
		errors.append("crest '%s' has unknown license status '%s'" % [crest_id, license_status])
	elif REQUIRED_LICENSE[asset_type] != license_status:
		errors.append("crest '%s': %s needs license status %s, not %s" % [crest_id,
				AssetType.keys()[asset_type], REQUIRED_LICENSE[asset_type], license_status])
	if source.strip_edges() == "":
		errors.append("crest '%s' has no source/provenance" % crest_id)
	if created_at.strip_edges() == "":
		errors.append("crest '%s' has no creation date" % crest_id)
	if is_template() == false and asset_path != "" and not LogoService.file_ok(asset_path):
		errors.append("crest '%s': asset file missing (%s)" % [crest_id, asset_path])
	return errors


func to_dict() -> Dictionary:
	return {"crest_id": crest_id, "club_id": club_id, "asset_path": asset_path,
			"asset_type": AssetType.keys()[asset_type], "version": version, "shape_style": shape_style,
			"division": division, "symbol": symbol, "primary_color": primary_color.to_html(false),
			"secondary_color": secondary_color.to_html(false), "accent_color": accent_color.to_html(false),
			"transparent_background": transparent_background, "license_status": license_status,
			"source": source, "created_at": created_at}


static func from_dict(d: Dictionary) -> CrestData:
	var c := CrestData.new()
	c.crest_id = str(d.get("crest_id", ""))
	c.club_id = str(d.get("club_id", ""))
	c.asset_path = str(d.get("asset_path", ""))
	var at := str(d.get("asset_type", "FICTIONAL"))
	c.asset_type = AssetType[at] if AssetType.has(at) else AssetType.FICTIONAL
	c.version = int(d.get("version", 1))
	c.shape_style = str(d.get("shape_style", "shield"))
	c.division = str(d.get("division", "plain"))
	c.symbol = str(d.get("symbol", "star"))
	c.primary_color = Color.from_string(str(d.get("primary_color", "ffffff")), Color.WHITE)
	c.secondary_color = Color.from_string(str(d.get("secondary_color", "000000")), Color.BLACK)
	c.accent_color = Color.from_string(str(d.get("accent_color", "ffffff")), Color.WHITE)
	c.transparent_background = bool(d.get("transparent_background", true))
	c.license_status = str(d.get("license_status", "FICTIONAL"))
	c.source = str(d.get("source", "procedural"))
	c.created_at = str(d.get("created_at", ""))
	return c
