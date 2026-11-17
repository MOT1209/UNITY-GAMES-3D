## Builds assets/flags/<country_id>.png (128 x 84) and <country_id>_64.png (64 x 42) for every country in
## data/countries.json and writes the `flag_asset` field.
##   godot --headless --path . res://tools/build_flags.tscn -- <flag-icons package dir>
## Real countries: the flag-icons 4x3 SVG (MIT, https://github.com/lipis/flag-icons; `npm pack flag-icons`)
## named in tools/flags/flag_map.json, rasterised by Godot (ThorVG) at 4x and scaled down; the 4:3 artwork
## is cropped to 3:2 around its centre. Fictional countries: FlagGenerator (pure code).
extends Node

const OUT := "res://assets/flags/"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var src := args[0] if args.size() > 0 else ""
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/flags/flag_map.json"))
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/countries.json"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var made := 0
	var failed: Array = []
	for c: Dictionary in data["countries"]:
		var id := str(c["country_id"])
		var big: Image
		if str(c["database_status"]) == "FICTIONAL":
			big = FlagGenerator.generate(id, FlagGenerator.WIDTH * 2, FlagGenerator.HEIGHT * 2)
		else:
			big = _from_svg(src.path_join("flags/4x3/%s.svg" % str(map.get(id, ""))))
		if big == null:
			failed.append(id)
			continue
		var large := big.duplicate() as Image
		large.resize(FlagGenerator.WIDTH, FlagGenerator.HEIGHT, Image.INTERPOLATE_LANCZOS)
		var small := big.duplicate() as Image
		small.resize(64, 42, Image.INTERPOLATE_LANCZOS)
		large.save_png(ProjectSettings.globalize_path(OUT + id + ".png"))
		small.save_png(ProjectSettings.globalize_path(OUT + id + "_64.png"))
		made += 1
	print("flags built: %d, failed: %s" % [made, str(failed)])
	get_tree().quit(0 if failed.is_empty() else 1)


## 256 x 168 image of an SVG: rendered 4:3 at 256 x 192, the middle 168 rows kept (3:2).
func _from_svg(path: String) -> Image:
	if not FileAccess.file_exists(path):
		push_error("missing SVG " + path)
		return null
	var buf := FileAccess.get_file_as_bytes(path)
	var img := Image.new()
	if img.load_svg_from_buffer(buf, 256.0 / 640.0 * 2.0) != OK:      # flag-icons 4x3 viewBox is 640 x 480
		return null
	img.convert(Image.FORMAT_RGBA8)
	img.resize(256, 192, Image.INTERPOLATE_LANCZOS)
	return img.get_region(Rect2i(0, 12, 256, 168))
