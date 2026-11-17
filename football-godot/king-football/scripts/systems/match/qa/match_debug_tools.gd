class_name MatchDebugTools
extends Node3D

## PC diagnostics inside a match (Phase M0). Added by `MatchManager.begin()`.
##   F8 - saves a bug report (`MatchBugReport`) and shows "Bug report saved" in the HUD notice.
##   F9 - toggles the debug view: per player a velocity arrow and the AI intent (HOLD_SHAPE / CLOSE_DOWN / SUPPORT /
##        RECEIVE / CARRY ...), a ring under the ball owner, the target of the pass in flight and its receiving area.
## Both work during pause too (process mode ALWAYS). Nothing here changes the match.

var m: MatchManager
var debug_visible := false
var last_report_path := ""
var _mesh := ImmediateMesh.new()
var _lines: MeshInstance3D
var _labels: Dictionary = {}           # player_id -> Label3D
var _mat: StandardMaterial3D


func _init(p_m: MatchManager = null) -> void:
	m = p_m
	name = "MatchDebugTools"
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mat.no_depth_test = true
	_lines = MeshInstance3D.new()
	_lines.mesh = _mesh
	_lines.material_override = _mat
	_lines.top_level = true
	_lines.visible = false
	add_child(_lines)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or (event as InputEventKey).echo:
		return
	match (event as InputEventKey).keycode:
		KEY_F8:
			save_report()
			get_viewport().set_input_as_handled()
		KEY_F9:
			set_debug_visible(not debug_visible)
			get_viewport().set_input_as_handled()


## F8. Returns the saved path ("" on failure) and shows the result in the HUD notice.
func save_report() -> String:
	if m == null or m.state == null:
		return ""
	last_report_path = MatchBugReport.save(m)
	if m.rules != null:
		m.rules.say("HUD_BUG_REPORT_SAVED" if last_report_path != "" else "HUD_BUG_REPORT_FAILED")
	return last_report_path


func set_debug_visible(value: bool) -> void:
	debug_visible = value
	if _lines != null:
		_lines.visible = value
	for l in _labels.values():
		(l as Label3D).visible = value
	if value and m != null and m.rules != null:
		m.rules.say("HUD_DEBUG_ON")


func _process(_delta: float) -> void:
	if not debug_visible or m == null or m.ball == null:
		return
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var owner := m._owner_entry()
	for side in ["home", "away"]:
		var col := Color(0.3, 0.7, 1.0) if side == "home" else Color(1.0, 0.45, 0.3)
		for e in m.entries[side]:
			var n := e["node"] as CharacterBody3D
			var p := n.global_position + Vector3(0, 0.15, 0)
			var v := Vector3(n.velocity.x, 0.0, n.velocity.z)
			_line(p, p + v * 0.5, col)
			if not owner.is_empty() and owner["player_id"] == e["player_id"]:
				_ring(n.global_position, 1.0, Color(1, 1, 0.2))
			_label_for(e).global_position = n.global_position + Vector3(0, 2.3, 0)
			_label_for(e).text = "%d %s" % [int(e["slot"]), str(e.get("intent", "HUMAN" if e["ai"] == null else ""))]
	var inc := m.incoming_pass
	if not inc.is_empty():
		for side in ["home", "away"]:
			for e in m.entries[side]:
				if e["player_id"] == inc.get("receiver_id", ""):
					var rp := (e["node"] as Node3D).global_position
					_line(m.ball.global_position, rp, Color(0.3, 1.0, 0.4))
					_ring(rp, 1.5, Color(0.3, 1.0, 0.4))
	_mesh.surface_end()


func _label_for(e: Dictionary) -> Label3D:
	var pid: String = e["player_id"]
	if not _labels.has(pid) or not is_instance_valid(_labels[pid]):
		var l := Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.font_size = 30
		l.fixed_size = true                    # readable at any camera distance
		l.pixel_size = 0.0009
		l.outline_size = 8
		l.top_level = true
		l.visible = debug_visible
		add_child(l)
		_labels[pid] = l
	return _labels[pid]


func _line(a: Vector3, b: Vector3, c: Color) -> void:
	_mesh.surface_set_color(c)
	_mesh.surface_add_vertex(a)
	_mesh.surface_set_color(c)
	_mesh.surface_add_vertex(b)


func _ring(center: Vector3, r: float, c: Color) -> void:
	for i in 24:
		var a0 := TAU * i / 24.0
		var a1 := TAU * (i + 1) / 24.0
		_line(center + Vector3(cos(a0) * r, 0.1, sin(a0) * r), center + Vector3(cos(a1) * r, 0.1, sin(a1) * r), c)
