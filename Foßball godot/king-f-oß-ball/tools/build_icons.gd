## Renders the Android launcher icons from icon.svg into assets/icons/:
##   godot --headless --path . res://tools/build_icons.tscn
## main 192x192, adaptive foreground 432x432 (logo inside the central 66 % safe zone, transparent
## around it) and adaptive background 432x432 (navy, the menu colour).
extends Node

const SRC := "res://icon.svg"
const OUT := "res://assets/icons"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var ok := true
	ok = _save(_scaled(192), "icon_192.png") and ok
	var fg := Image.create(432, 432, false, Image.FORMAT_RGBA8)
	fg.fill(Color(0, 0, 0, 0))
	var logo := _scaled(264)                       # 61 % of 432: inside the adaptive safe zone
	fg.blit_rect(logo, Rect2i(Vector2i.ZERO, logo.get_size()), Vector2i((432 - 264) / 2, (432 - 264) / 2))
	ok = _save(fg, "icon_foreground_432.png") and ok
	var bg := Image.create(432, 432, false, Image.FORMAT_RGBA8)
	bg.fill(UIKit.BG)
	ok = _save(bg, "icon_background_432.png") and ok
	get_tree().quit(0 if ok else 1)


func _scaled(px: int) -> Image:
	var img := Image.new()
	var svg := FileAccess.get_file_as_string(SRC)
	var probe := Image.new()
	probe.load_svg_from_string(svg, 1.0)
	img.load_svg_from_string(svg, float(px) / maxf(probe.get_width(), 1.0))
	if img.get_width() != px:
		img.resize(px, px, Image.INTERPOLATE_LANCZOS)
	img.convert(Image.FORMAT_RGBA8)
	return img


func _save(img: Image, file: String) -> bool:
	var err := img.save_png(ProjectSettings.globalize_path("%s/%s" % [OUT, file]))
	print("%s -> %s" % [file, "ok" if err == OK else str(err)])
	return err == OK
