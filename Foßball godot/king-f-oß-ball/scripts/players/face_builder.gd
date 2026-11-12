class_name FaceBuilder
extends RefCounted

## Procedural face variation (Phase V2, face system).
##
## The shipped character has ONE head with its eyes/brows/mouth baked into the body
## mesh's `*_Dark` surface (verified: that surface holds only facial boxes). Without a
## DCC tool we cannot edit that mesh, so this builder
##   1. hides the baked features (surface override with a fully transparent material),
##   2. builds eyes, eyebrows, nose and mouth from primitive meshes attached to the
##      `Head` bone (`BoneAttachment3D`), so they follow every animation, and
##   3. changes the head shape by scaling the `Head` bone (skin and hair are skinned to
##      it, so they scale together; no clip animates bone scale).
## All variant tables are data (below); `PlayerAppearance` stores only the indices.
## Meshes and materials are cached and shared between players.

const ATTACH_NAME := "KF_Face"
const HEAD_BONE := "Head"
## Offsets relative to the Head bone origin (1.56 m above ground in the model).
const FACE_Z := -0.0985
## Readability at card/portrait size: all eye/brow/mouth dimensions are multiplied by this.
const FEATURE_SCALE := 1.25

## Head shapes: bone scale (x width, y height, z depth).
const SHAPES: Array[Vector3] = [
	Vector3(1.00, 1.00, 1.00),      # oval (the original head)
	Vector3(1.09, 0.97, 1.04),      # round
	Vector3(0.93, 1.07, 0.98),      # long
	Vector3(1.07, 1.01, 1.05),      # broad
	Vector3(0.94, 0.98, 0.96),      # narrow
]
## Eyes: half-size w/h (m), gap = distance of each eye from the centre line, sclera = white of the eye.
const EYES: Array[Dictionary] = [
	{"w": 0.0075, "h": 0.0085, "gap": 0.036, "sclera": false},   # dot (closest to the original)
	{"w": 0.0105, "h": 0.0115, "gap": 0.038, "sclera": true},    # round
	{"w": 0.0130, "h": 0.0075, "gap": 0.037, "sclera": true},    # almond
	{"w": 0.0090, "h": 0.0090, "gap": 0.043, "sclera": true},    # wide set
	{"w": 0.0070, "h": 0.0100, "gap": 0.032, "sclera": false},   # close set
]
const EYE_COLORS: Array[Color] = [Color(0.05, 0.04, 0.04), Color(0.28, 0.16, 0.08), Color(0.22, 0.38, 0.62),
	Color(0.24, 0.50, 0.30), Color(0.45, 0.48, 0.52)]
## Brows: length, thickness, tilt (rad; + = inner end lower = stern), dy = height above the eye centre.
const BROWS: Array[Dictionary] = [
	{"len": 0.026, "th": 0.0042, "tilt": 0.10, "dy": 0.021},     # thin, slightly stern
	{"len": 0.030, "th": 0.0085, "tilt": 0.00, "dy": 0.022},     # thick straight
	{"len": 0.028, "th": 0.0060, "tilt": 0.32, "dy": 0.019},     # angry
	{"len": 0.026, "th": 0.0050, "tilt": -0.18, "dy": 0.025},    # raised / soft
	{"len": 0.020, "th": 0.0090, "tilt": 0.05, "dy": 0.021},     # short thick
]
## Noses: prism size (w, h, d).
const NOSES: Array[Vector3] = [Vector3(0.012, 0.030, 0.012), Vector3(0.022, 0.028, 0.014),
	Vector3(0.012, 0.040, 0.016), Vector3(0.016, 0.034, 0.020)]
## Mouths: width, thickness, curve (rad of the end segments; + = smile, - = frown), open = dark red mouth.
const MOUTHS: Array[Dictionary] = [
	{"w": 0.038, "th": 0.0050, "curve": 0.00, "open": false},    # flat
	{"w": 0.054, "th": 0.0055, "curve": 0.00, "open": false},    # wide
	{"w": 0.026, "th": 0.0050, "curve": 0.00, "open": false},    # small
	{"w": 0.046, "th": 0.0050, "curve": 0.40, "open": false},    # smile
	{"w": 0.042, "th": 0.0050, "curve": -0.35, "open": false},   # serious / frown
]

static var _face_cache: Dictionary = {}
static var _mat_cache: Dictionary = {}


static func counts() -> Dictionary:
	return {"face": SHAPES.size(), "eyes": EYES.size(), "brows": BROWS.size(), "nose": NOSES.size(),
			"mouth": MOUTHS.size(), "eye_color": EYE_COLORS.size()}


## Dresses the face of `model` (a character scene root) according to `look`.
## Safe on models without a skeleton or without the `Dark` surface (does nothing).
static func apply(model: Node, look: PlayerLook) -> void:
	if model == null or look == null or look.face_shape < 0:
		return
	var skeleton := _skeleton(model)
	if skeleton == null:
		return
	var head := skeleton.find_bone(HEAD_BONE)
	if head < 0:
		return
	skeleton.set_bone_pose_scale(head, SHAPES[clampi(look.face_shape, 0, SHAPES.size() - 1)])
	_hide_baked_face(model)
	var old := skeleton.get_node_or_null(ATTACH_NAME)
	if old != null:
		skeleton.remove_child(old)
		old.queue_free()
	var attach := BoneAttachment3D.new()
	attach.name = ATTACH_NAME
	attach.bone_name = HEAD_BONE
	skeleton.add_child(attach)
	_build(attach, look)


## Reverts to the model's original face (used by tests / looks without face data).
static func clear(model: Node) -> void:
	var skeleton := _skeleton(model)
	if skeleton == null:
		return
	var old := skeleton.get_node_or_null(ATTACH_NAME)
	if old != null:
		skeleton.remove_child(old)
		old.queue_free()
	var head := skeleton.find_bone(HEAD_BONE)
	if head >= 0:
		skeleton.set_bone_pose_scale(head, Vector3.ONE)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			if _is_dark(m, s):
				m.set_surface_override_material(s, null)


static func _skeleton(model: Node) -> Skeleton3D:
	var list := model.find_children("*", "Skeleton3D", true, false)
	return list[0] as Skeleton3D if not list.is_empty() else null


static func _is_dark(m: MeshInstance3D, surface: int) -> bool:
	var mat := m.mesh.surface_get_material(surface)
	return mat != null and mat.resource_name.ends_with("Dark")


static func _hide_baked_face(model: Node) -> void:
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			if _is_dark(m, s):
				m.set_surface_override_material(s, _material(Color(0, 0, 0, 0), true))


## One merged, vertex-coloured mesh per distinct face (cached): a single MeshInstance3D and a single
## draw call per player instead of ~10 (Phase 7.6; profiled: the parts cost nothing to BUILD, but
## they multiplied nodes and draw calls by ~10 per player).
static func _build(parent: Node3D, look: PlayerLook) -> void:
	var key := "%d.%d.%d.%d.%d.%d|%s|%s" % [look.face_shape, look.eyes, look.brows, look.nose, look.mouth, look.eye_color,
			look.skin.to_html(false), look.hair.to_html(false)]
	if not _face_cache.has(key):
		_face_cache[key] = _merged_face(look)
	var mi := MeshInstance3D.new()
	mi.name = "Face"
	mi.mesh = _face_cache[key]
	mi.material_override = _material(Color.WHITE, false, true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


static func _merged_face(look: PlayerLook) -> ArrayMesh:
	# plain Arrays (reference types) while building; converted to packed arrays at the end
	var acc := {"v": [], "n": [], "c": [], "i": []}
	var eye: Dictionary = EYES[clampi(look.eyes, 0, EYES.size() - 1)].duplicate()
	var brow: Dictionary = BROWS[clampi(look.brows, 0, BROWS.size() - 1)].duplicate()
	var fs := FEATURE_SCALE
	eye["w"] *= fs
	eye["h"] *= fs
	brow["len"] *= fs
	brow["th"] *= fs
	var nose: Vector3 = NOSES[clampi(look.nose, 0, NOSES.size() - 1)]
	var mouth: Dictionary = MOUTHS[clampi(look.mouth, 0, MOUTHS.size() - 1)].duplicate()
	mouth["w"] *= fs
	mouth["th"] *= fs
	var iris: Color = EYE_COLORS[clampi(look.eye_color, 0, EYE_COLORS.size() - 1)]
	var eye_y := 0.134
	var gap: float = eye["gap"]
	for side in [-1.0, 1.0]:
		if eye["sclera"]:
			_add_box(acc, Vector3(eye["w"] * 2.0, eye["h"] * 1.7, 0.004), Vector3(side * gap, eye_y, FACE_Z), 0.0, Color(0.96, 0.96, 0.94))
			_add_box(acc, Vector3(eye["w"] * 1.1, eye["h"] * 1.5, 0.004), Vector3(side * gap, eye_y, FACE_Z - 0.0025), 0.0, iris)
			_add_box(acc, Vector3(eye["w"] * 0.5, eye["h"] * 0.9, 0.004), Vector3(side * gap, eye_y, FACE_Z - 0.0045), 0.0, Color(0.02, 0.02, 0.02))
		else:
			_add_box(acc, Vector3(eye["w"] * 1.6, eye["h"] * 1.6, 0.005), Vector3(side * gap, eye_y, FACE_Z), 0.0, Color(0.04, 0.04, 0.04))
		_add_box(acc, Vector3(brow["len"], brow["th"], 0.006), Vector3(side * gap, eye_y + float(brow["dy"]), FACE_Z + 0.001),
				-side * float(brow["tilt"]), look.hair.darkened(0.15))
	var pm := PrismMesh.new()
	pm.size = nose
	pm.left_to_right = 0.5
	_add_mesh(acc, pm, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.098, FACE_Z - nose.z * 0.35)), look.skin.darkened(0.14))
	var m_y := 0.066
	var mcol := Color(0.30, 0.10, 0.10)
	var w: float = mouth["w"]
	var curve: float = mouth["curve"]
	if absf(curve) < 0.01:
		_add_box(acc, Vector3(w, mouth["th"], 0.005), Vector3(0.0, m_y, FACE_Z), 0.0, mcol)
	else:
		var seg := w * 0.5
		_add_box(acc, Vector3(seg, mouth["th"], 0.005), Vector3(0.0, m_y, FACE_Z), 0.0, mcol)
		for side in [-1.0, 1.0]:
			_add_box(acc, Vector3(seg * 0.7, mouth["th"], 0.005),
					Vector3(side * (seg * 0.5 + seg * 0.30), m_y + sin(curve) * seg * 0.35, FACE_Z + 0.0005), side * curve, mcol)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(acc["v"])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(acc["n"])
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray(acc["c"])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(acc["i"])
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


static func _add_box(acc: Dictionary, size: Vector3, pos: Vector3, rot_z: float, color: Color) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	_add_mesh(acc, bm, Transform3D(Basis(Vector3.BACK, rot_z), pos), color)


## Appends a primitive's triangles (transformed, one flat colour) to the accumulator.
static func _add_mesh(acc: Dictionary, mesh: PrimitiveMesh, xf: Transform3D, color: Color) -> void:
	var arr := mesh.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var base: int = (acc["v"] as Array).size()
	for k in verts.size():
		(acc["v"] as Array).append(xf * verts[k])
		(acc["n"] as Array).append((xf.basis * norms[k]).normalized())
		(acc["c"] as Array).append(color)
	for k in idx:
		(acc["i"] as Array).append(base + k)


static func _material(color: Color, transparent := false, vertex_color := false) -> StandardMaterial3D:
	var key := "%s%s%s" % [color.to_html(true), transparent, vertex_color]
	if not _mat_cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.vertex_color_use_as_albedo = vertex_color
		m.roughness = 0.9
		if transparent:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mat_cache[key] = m
	return _mat_cache[key]
