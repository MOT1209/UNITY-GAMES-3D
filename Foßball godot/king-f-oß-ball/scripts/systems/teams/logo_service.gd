class_name LogoService
extends RefCounted

## Team logos (Phase T7): original procedural templates plus validated custom
## image import. A missing or broken logo never breaks the UI: `resolve()`
## always returns a usable Image (falls back to a template in club colors).
## No protected logos are shipped.

const TEMPLATES: Array[String] = ["shield", "circle", "diamond", "stripes"]
const TEMPLATE_PREFIX := "template:"
const LOGO_DIR := "user://logos"
const MAX_BYTES := 2 * 1024 * 1024
const MIN_SIZE := 32
const MAX_SIZE := 4096
const OUTPUT_SIZE := 256
const EXTENSIONS: Array[String] = ["png", "jpg", "jpeg", "webp"]


static func template_ref(template_id: String) -> String:
	return TEMPLATE_PREFIX + template_id


static func is_template(ref: String) -> bool:
	return ref.begins_with(TEMPLATE_PREFIX) and ref.trim_prefix(TEMPLATE_PREFIX) in TEMPLATES


## Procedural original logo in the club colors.
static func render_template(template_id: String, primary: Color, secondary: Color, size: int = 128) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := (size - 1) / 2.0
	for y in size:
		for x in size:
			var nx := (x - c) / c        # -1..1
			var ny := (y - c) / c
			var col := Color(0, 0, 0, 0)
			match template_id:
				"circle":
					var r := sqrt(nx * nx + ny * ny)
					if r <= 0.95:
						col = secondary if r > 0.78 else primary
				"diamond":
					var d := absf(nx) + absf(ny)
					if d <= 0.95:
						col = secondary if d > 0.75 else primary
				"stripes":
					if absf(nx) <= 0.9 and absf(ny) <= 0.9:
						col = primary if int((nx + 1.0) * 3.0) % 2 == 0 else secondary
				_:   # shield
					var half_width := 0.9 * (1.0 - maxf(ny, 0.0) * 0.85)
					if ny >= -0.9 and ny <= 0.95 and absf(nx) <= half_width:
						col = secondary if (absf(nx) > half_width - 0.14 or ny < -0.78) else primary
			img.set_pixel(x, y, col)
	return img


## Validates an image file for import. Returns "" when it is acceptable.
static func validate_import(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "file not found"
	if not (path.get_extension().to_lower() in EXTENSIONS):
		return "unsupported file type (use png, jpg or webp)"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "cannot read file"
	var length := f.get_length()
	f.close()
	if length > MAX_BYTES:
		return "file too large (max %d KB)" % (MAX_BYTES / 1024)
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return "file is not a valid image"
	if img.get_width() < MIN_SIZE or img.get_height() < MIN_SIZE:
		return "image too small (min %d px)" % MIN_SIZE
	if img.get_width() > MAX_SIZE or img.get_height() > MAX_SIZE:
		return "image too large (max %d px)" % MAX_SIZE
	return ""


## Imports a custom logo for a team: validated, resized, stored as PNG.
## Returns {"ok": bool, "error": String, "path": String}.
static func import_logo(team: TeamData, source_path: String) -> Dictionary:
	var err := validate_import(source_path)
	if err != "":
		return {"ok": false, "error": err, "path": ""}
	var img := Image.load_from_file(source_path)
	img.convert(Image.FORMAT_RGBA8)
	img.resize(OUTPUT_SIZE, OUTPUT_SIZE, Image.INTERPOLATE_LANCZOS)
	if not DirAccess.dir_exists_absolute(LOGO_DIR):
		DirAccess.make_dir_recursive_absolute(LOGO_DIR)
	var dest := "%s/%s.png" % [LOGO_DIR, team.id]
	if img.save_png(dest) != OK:
		return {"ok": false, "error": "could not store logo", "path": ""}
	team.logo_path = dest
	return {"ok": true, "error": "", "path": dest}


## Always returns a usable image: the stored logo, or a template placeholder.
static func resolve(team: TeamData, size: int = 128) -> Image:
	var ref := team.logo_path
	if is_template(ref):
		return render_template(ref.trim_prefix(TEMPLATE_PREFIX), team.primary_color, team.secondary_color, size)
	if ref != "" and FileAccess.file_exists(ref):
		var img := Image.load_from_file(ref)
		if img != null and not img.is_empty():
			if img.get_width() != size:
				img.resize(size, size, Image.INTERPOLATE_BILINEAR)
			return img
	return render_template("shield", team.primary_color, team.secondary_color, size)
