class_name KingControllerHub
extends Node

## Bridges a KingControllerServer to one or more IntentProviders (one per slot).
## Edge discipline mirrors TouchControls: inputs are queued from network
## callbacks and applied exactly once per physics tick after begin_tick().

@export var grace_ms: int = 5000

var server: KingControllerServer
var providers: Dictionary = {}  # slot -> IntentProvider

var _pending_press: Dictionary = {}   # slot -> Array[StringName]
var _pending_release: Dictionary = {}
var _last_move: Dictionary = {}       # slot -> Vector2
var _connected: Dictionary = {}      # slot -> bool
var _disconnect_at: Dictionary = {}  # slot -> ms


func setup(p_server: KingControllerServer, p_providers: Dictionary) -> void:
	server = p_server
	providers = p_providers
	for slot in providers.keys():
		_pending_press[slot] = []
		_pending_release[slot] = []
		_last_move[slot] = Vector2.ZERO
		_connected[slot] = false
	if server != null:
		server.input_received.connect(_on_input)
		server.client_connected.connect(_on_connected)
		server.client_disconnected.connect(_on_disconnected)


func _on_connected(slot: int) -> void:
	_connected[slot] = true
	_disconnect_at.erase(slot)
	if providers.has(slot):
		var ip: IntentProvider = providers[slot]
		ip.set_driven(true)
		_pending_press[slot] = []
		_pending_release[slot] = []
		_last_move[slot] = Vector2.ZERO


func _on_disconnected(slot: int) -> void:
	_connected[slot] = false
	_disconnect_at[slot] = Time.get_ticks_msec() + grace_ms


func _on_input(slot: int, move: Vector2, press: Array, release: Array) -> void:
	if not providers.has(slot):
		return
	_last_move[slot] = move
	if not _pending_press.has(slot):
		_pending_press[slot] = []
	if not _pending_release.has(slot):
		_pending_release[slot] = []
	for a in press:
		var an := StringName(String(a))
		if not _pending_press[slot].has(an):
			_pending_press[slot].append(an)
	for a in release:
		var an := StringName(String(a))
		if not _pending_release[slot].has(an):
			_pending_release[slot].append(an)


func _physics_process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	for slot in providers.keys():
		var ip: IntentProvider = providers[slot]
		if not ip.driven and not _connected.get(slot, false):
			# grace handling
			if _disconnect_at.has(slot) and now < int(_disconnect_at[slot]):
				continue
			_disconnect_at.erase(slot)
			continue
		if not ip.driven:
			continue
		# grace expiry -> release
		if _disconnect_at.has(slot) and now >= int(_disconnect_at[slot]):
			ip.set_driven(false)
			_disconnect_at.erase(slot)
			_pending_press[slot] = []
			_pending_release[slot] = []
			_last_move[slot] = Vector2.ZERO
			continue
		ip.begin_tick()
		var press: Array = _pending_press.get(slot, [])
		var release: Array = _pending_release.get(slot, [])
		_pending_press[slot] = []
		_pending_release[slot] = []
		for a in press:
			ip.press(a)
		for a in release:
			ip.release(a)
		ip.set_move(_last_move.get(slot, Vector2.ZERO))
