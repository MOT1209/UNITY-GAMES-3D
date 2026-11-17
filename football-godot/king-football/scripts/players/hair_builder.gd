class_name HairBuilder
extends RefCounted

## Sculpted haircuts and beard styles (round 3, task D4), in the same spirit as `FaceBuilder`: pieces built
## from primitives in code, merged into ONE vertex-coloured mesh per distinct (cut, beard, colour) and attached
## to the `Head` bone, so they follow every animation and the head shape (bone scale).
##
## * Each haircut (`PlayerLook.CUTS`) sits on one of the model's own hair meshes (always drawn, also far away);
##   the sculpted extras on top (waves, curls, braids, ponytail, bun, mohawk, dreadlocks, side part, flat top)
##   are near-camera detail with the face LOD (`PlayerCharacterVisual.FACE_LOD_END`).
## * Beards: style 1 is the model's full-beard mesh; stubble, goatee, moustache, chin strap and
##   moustache + goatee are built here. Stubble is a second, semi-transparent surface.
## * Shading: no flat colour — every vertex is darkened towards the underside and the edges of a piece
##   (from its normal), so hair and beards read as volumes under the portrait lights.
## Offsets are relative to the Head bone origin (1.56 m above the ground; face front at z = -0.0985,
## the model faces -Z, the crown is about 0.235 above the bone).

const ATTACH_NAME := "KF_Hair"
const HEAD_BONE := "Head"

static var _cache: Dictionary = {}
static var _sphere: SphereMesh
static var _cyl: CylinderMesh
static var _box: BoxMesh
static var _opaque: StandardMaterial3D
static var _alpha: StandardMaterial3D


## Haircuts with sculpted pieces (the others are the model's meshes alone).
static func sculpted_cuts() -> Array:
	return ["Wavy", "Curly", "Braids", "Ponytail", "ManBun", "Mohawk", "Dreads", "SidePart", "FlatTop"]


## Builds (or removes) the hair / beard pieces of `model` for `look`. Idempotent.
static func apply(model: Node, look: PlayerLook) -> void:
	var skeleton := _skeleton(model)
	if skeleton == null:
		return
	var old := skeleton.get_node_or_null(ATTACH_NAME)
	if old != null:
		skeleton.remove_child(old)
		old.queue_free()
	if look == null or skeleton.find_bone(HEAD_BONE) < 0:
		return
	var beard := look.beard_style if look.beard_style >= 0 else (1 if look.beard else 0)
	var has_cut := look.cut in sculpted_cuts()
	var has_beard := beard >= 2
	if not has_cut and not has_beard:
		return
	var key := "%s|%d|%s" % [look.cut if has_cut else "-", beard, look.hair.to_html(false)]
	if not _cache.has(key):
		_cache[key] = _build(look.cut if has_cut else "", beard, look.hair)
	var attach := BoneAttachment3D.new()
	attach.name = ATTACH_NAME
	attach.bone_name = HEAD_BONE
	skeleton.add_child(attach)
	var mi := MeshInstance3D.new()
	mi.name = "Hair"
	mi.mesh = _cache[key]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = PlayerCharacterVisual.HAIR_LOD_END       # LOD: near cameras only
	mi.visibility_range_end_margin = 3.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	attach.add_child(mi)


static func _skeleton(model: Node) -> Skeleton3D:
	if model == null:
		return null
	var list := model.find_children("*", "Skeleton3D", true, false)
	return list[0] as Skeleton3D if not list.is_empty() else null


static func _build(cut: String, beard: int, hair: Color) -> ArrayMesh:
	var acc := {"v": [], "n": [], "c": [], "i": []}
	var thin := {"v": [], "n": [], "c": [], "i": []}       # stubble (semi-transparent)
	var dark := hair.darkened(0.12)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(cut)                                  # fixed per cut: identical for every player
	match cut:
		"Wavy":
			for i in 6:
				var z := lerpf(-0.075, 0.075, i / 5.0)
				_sph(acc, Vector3(0.060, 0.024, 0.030), Vector3(0.022 if i % 2 == 0 else -0.022, 0.222 - absf(z) * 0.25, z), hair)
		"Curly":
			for i in 34:
				var a := rng.randf() * TAU
				var el := rng.randf_range(0.35, 1.45)
				var dir := Vector3(cos(a) * cos(el), sin(el), sin(a) * cos(el) * 1.08)
				if dir.z < -0.55 and dir.y < 0.55:
					continue                                     # keep the forehead free
				_sph(acc, Vector3.ONE * rng.randf_range(0.019, 0.026), Vector3(0, 0.122, 0.006) + dir * 0.106, hair)
		"Braids":
			for row in 5:
				var x := lerpf(-0.064, 0.064, row / 4.0)
				for k in 7:
					var ang := lerpf(-1.05, 1.25, k / 6.0)             # front of the hairline -> back of the head
					var p := Vector3(x, 0.125 + cos(ang) * 0.108, sin(ang) * 0.112)
					_sph(acc, Vector3(0.010, 0.012, 0.016), p, hair if k % 2 == 0 else dark)
		"Ponytail":
			_sph(acc, Vector3(0.026, 0.026, 0.026), Vector3(0, 0.150, 0.110), dark)
			_tube(acc, Vector3(0, 0.150, 0.118), Vector3(0, 0.020, 0.152), 0.026, 0.012, hair)
		"ManBun":
			_sph(acc, Vector3(0.046, 0.040, 0.044), Vector3(0, 0.228, 0.062), hair)
			_sph(acc, Vector3(0.030, 0.012, 0.030), Vector3(0, 0.200, 0.060), dark)
		"Mohawk":
			for k in 9:
				var ang := lerpf(-0.95, 1.20, k / 8.0)
				var p := Vector3(0, 0.122 + cos(ang) * 0.128, sin(ang) * 0.125)
				_sph(acc, Vector3(0.016, 0.026, 0.022), p, hair)
		"Dreads":
			for k in 13:
				var ang := lerpf(-PI * 0.62, PI * 0.62, k / 12.0)       # around the back from ear to ear
				var top := Vector3(sin(ang) * 0.094, 0.175, cos(ang) * 0.096)
				var bottom := Vector3(sin(ang) * 0.112, 0.02 + absf(sin(ang)) * 0.04, cos(ang) * 0.128)
				_tube(acc, top, bottom, 0.012, 0.010, hair if k % 2 == 0 else dark)
		"SidePart":
			_sph(acc, Vector3(0.070, 0.026, 0.090), Vector3(0.020, 0.226, -0.010), hair)
			_sph(acc, Vector3(0.050, 0.030, 0.040), Vector3(0.046, 0.200, -0.070), hair)
			_bx(acc, Vector3(0.004, 0.004, 0.10), Vector3(-0.032, 0.236, -0.02), dark)
		"FlatTop":
			_bx(acc, Vector3(0.150, 0.050, 0.170), Vector3(0, 0.226, 0.008), hair)
	var bc := hair.darkened(0.05)
	match beard:
		2:   # stubble: a thin shell over cheeks, chin and upper lip
			for side in [-1.0, 1.0]:
				_sph(thin, Vector3(0.012, 0.026, 0.016), Vector3(side * 0.058, 0.058, -0.082), bc)
			_sph(thin, Vector3(0.034, 0.020, 0.020), Vector3(0, 0.034, -0.080), bc)
			_bx(thin, Vector3(0.046, 0.008, 0.004), Vector3(0, 0.081, -0.098), bc)
		3:   # goatee
			_sph(acc, Vector3(0.026, 0.030, 0.022), Vector3(0, 0.034, -0.088), bc)
		4:   # moustache
			_bx(acc, Vector3(0.052, 0.011, 0.012), Vector3(0, 0.082, -0.099), bc)
		5:   # chin strap: a thin band along the jaw line
			for side in [-1.0, 1.0]:
				for k in 4:
					var t := k / 3.0
					_sph(acc, Vector3(0.012, 0.014, 0.012), Vector3(side * lerpf(0.086, 0.030, t), lerpf(0.090, 0.024, t), lerpf(-0.030, -0.082, t)), bc)
			_sph(acc, Vector3(0.026, 0.012, 0.014), Vector3(0, 0.020, -0.086), bc)
		6:   # moustache + goatee
			_bx(acc, Vector3(0.050, 0.011, 0.012), Vector3(0, 0.082, -0.099), bc)
			_sph(acc, Vector3(0.022, 0.026, 0.020), Vector3(0, 0.034, -0.088), bc)
	var out := ArrayMesh.new()
	if not (acc["v"] as Array).is_empty():
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _arrays(acc))
		out.surface_set_material(out.get_surface_count() - 1, _material(false))
	if not (thin["v"] as Array).is_empty():
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _arrays(thin))
		out.surface_set_material(out.get_surface_count() - 1, _material(true))
	return out


static func _arrays(acc: Dictionary) -> Array:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(acc["v"])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(acc["n"])
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray(acc["c"])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(acc["i"])
	return arrays


static func _sph(acc: Dictionary, radii: Vector3, pos: Vector3, color: Color) -> void:
	if _sphere == null:
		_sphere = SphereMesh.new()
		_sphere.radius = 1.0
		_sphere.height = 2.0
		_sphere.radial_segments = 10
		_sphere.rings = 6
	_add(acc, _sphere, Transform3D(Basis.from_scale(radii), pos), color)


static func _bx(acc: Dictionary, size: Vector3, pos: Vector3, color: Color) -> void:
	if _box == null:
		_box = BoxMesh.new()
		_box.size = Vector3.ONE
	_add(acc, _box, Transform3D(Basis.from_scale(size), pos), color)


## Tapered tube from `a` to `b` (ponytail, dreadlocks).
static func _tube(acc: Dictionary, a: Vector3, b: Vector3, r_top: float, r_bottom: float, color: Color) -> void:
	if _cyl == null:
		_cyl = CylinderMesh.new()
		_cyl.top_radius = 1.0
		_cyl.bottom_radius = 1.0
		_cyl.height = 1.0
		_cyl.radial_segments = 8
		_cyl.rings = 1
	var axis := b - a
	var up := axis.normalized()
	var side := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	var fwd := side.cross(up).normalized()
	var r := (r_top + r_bottom) * 0.5
	var basis := Basis(side * r, up * axis.length(), fwd * r)
	_add(acc, _cyl, Transform3D(basis, (a + b) * 0.5), color)


## Appends a primitive (transformed) with per-vertex shading: darker underneath and at grazing edges.
static func _add(acc: Dictionary, mesh: PrimitiveMesh, xf: Transform3D, color: Color) -> void:
	var arr := mesh.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var base: int = (acc["v"] as Array).size()
	var nb := xf.basis.inverse().transposed()
	for k in verts.size():
		var n := (nb * norms[k]).normalized()
		(acc["v"] as Array).append(xf * verts[k])
		(acc["n"] as Array).append(n)
		var shade := 0.68 + 0.32 * clampf(n.y * 0.5 + 0.5, 0.0, 1.0)
		var c := color.darkened(1.0 - shade)
		c.a = color.a
		(acc["c"] as Array).append(c)
	for k in idx:
		(acc["i"] as Array).append(base + k)


static func _material(transparent: bool) -> StandardMaterial3D:
	if transparent and _alpha != null:
		return _alpha
	if not transparent and _opaque != null:
		return _opaque
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.85
	m.rim_enabled = true                 # soft light on the silhouette instead of a flat colour
	m.rim = 0.25
	m.rim_tint = 0.6
	if transparent:
		m.albedo_color = Color(1, 1, 1, 0.30)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_alpha = m
	else:
		_opaque = m
	return m


static func clear_static_cache() -> void:
	_cache.clear()
	_opaque = null
	_alpha = null
