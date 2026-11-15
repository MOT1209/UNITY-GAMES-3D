class_name KingControllerHub
extends Node

## Bridges a KingControllerServer to the IntentProviders of the match (one per supported slot). Edge
## discipline mirrors TouchControls: inputs are queued from network callbacks and applied exactly once per
## physics tick after begin_tick().
##
## P9 rules:
##  * only slots that HAVE a provider are routed (the match has one human player: slot 0); input for any
##    other slot is dropped and counted, never applied to a player it does not own;
##  * the moment a controller is lost (disconnect, heartbeat timeout, revoke) every button the phone held
##    is released and the stick is zeroed, and the provider leaves driven mode so keyboard / gamepad work
##    again immediately (the old 5 s "grace" kept the last stick position running);
##  * `pause` never touches a player: it is forwarded as `pause_requested` (match-control system);
##  * while the game tree is paused, press edges are dropped (a tap during the pause menu must not fire a
##    kick when the match resumes); movement and releases are still tracked;
##  * `controller_active_changed(slot, active)` lets the match switch the on-screen touch layer off while a
##    phone controller is connected (both would write the same intent every tick).

signal pause_requested(slot: int)
signal controller_active_changed(slot: int, active: bool)

var server: KingControllerServer
var providers: Dictionary = {}        # slot -> IntentProvider
var dropped_unrouted := 0             # input events for slots without a provider

var _pending_press: Dictionary = {}   # slot -> Array[StringName]
var _pending_release: Dictionary = {}
var _last_move: Dictionary = {}       # slot -> Vector2
var _connected: Dictionary = {}       # slot -> bool
var _fed_held: Dictionary = {}        # slot -> {action: true}: what THIS hub pressed (released on loss)


func setup(p_server: KingControllerServer, p_providers: Dictionary) -> void:
	server = p_server
	providers = p_providers
	for slot in providers.keys():
		_pending_press[slot] = []
		_pending_release[slot] = []
		_last_move[slot] = Vector2.ZERO
		_connected[slot] = false
		_fed_held[slot] = {}
	if server != null:
		server.input_received.connect(_on_input)
		server.client_connected.connect(_on_connected)
		server.client_disconnected.connect(_on_disconnected)
		server.pause_requested.connect(_on_pause)
		# A phone paired BEFORE the match started (the normal flow: pair on the menu, then Play) has already
		# produced its `client_connected`; without this the hub would wait for an event that never comes.
		if server.registry != null:
			for slot in providers.keys():
				if int(slot) < server.registry.sessions.size():
					var s: KingControllerSession = server.registry.sessions[int(slot)]
					if s != null and s.state == KingControllerSession.State.CONNECTED:
						_on_connected(int(slot))


func _exit_tree() -> void:
	# A hub that leaves the tree (match ended) must never leave a provider stuck in driven mode.
	for slot in providers.keys():
		if _connected.get(slot, false):
			_lose(slot)
	if server != null and is_instance_valid(server):
		if server.input_received.is_connected(_on_input):
			server.input_received.disconnect(_on_input)
		if server.client_connected.is_connected(_on_connected):
			server.client_connected.disconnect(_on_connected)
		if server.client_disconnected.is_connected(_on_disconnected):
			server.client_disconnected.disconnect(_on_disconnected)
		if server.pause_requested.is_connected(_on_pause):
			server.pause_requested.disconnect(_on_pause)


func is_connected_slot(slot: int) -> bool:
	return bool(_connected.get(slot, false))


func _on_connected(slot: int) -> void:
	if not providers.has(slot):
		return
	_connected[slot] = true
	_pending_press[slot] = []
	_pending_release[slot] = []
	_last_move[slot] = Vector2.ZERO
	_fed_held[slot] = {}
	controller_active_changed.emit(slot, true)          # listeners (touch layer) step aside first
	(providers[slot] as IntentProvider).set_driven(true)


func _on_disconnected(slot: int) -> void:
	if providers.has(slot) and _connected.get(slot, false):
		_lose(slot)


## Releases everything the phone held and hands the provider back (keyboard / gamepad resume).
func _lose(slot: int) -> void:
	_connected[slot] = false
	var ip: IntentProvider = providers[slot]
	ip.begin_tick()
	for a in (_fed_held.get(slot, {}) as Dictionary).keys():
		ip.release(a)
	ip.set_move(Vector2.ZERO)
	ip.set_driven(false)                              # also clears every held action and the stick
	_pending_press[slot] = []
	_pending_release[slot] = []
	_last_move[slot] = Vector2.ZERO
	_fed_held[slot] = {}
	controller_active_changed.emit(slot, false)


func _on_pause(slot: int) -> void:
	if providers.has(slot) and _connected.get(slot, false):
		pause_requested.emit(slot)


func _on_input(slot: int, move: Vector2, press: Array, release: Array) -> void:
	if not providers.has(slot) or not _connected.get(slot, false):
		dropped_unrouted += 1
		return
	_last_move[slot] = move
	var paused := is_inside_tree() and get_tree().paused
	for a in press:
		var an := StringName(String(a))
		if paused:
			continue                                   # no kick / pass fired by a tap during the pause menu
		if not (_pending_press[slot] as Array).has(an):
			(_pending_press[slot] as Array).append(an)
	for a in release:
		var an := StringName(String(a))
		if not (_pending_release[slot] as Array).has(an):
			(_pending_release[slot] as Array).append(an)


func _physics_process(_delta: float) -> void:
	for slot in providers.keys():
		if not _connected.get(slot, false):
			continue
		var ip: IntentProvider = providers[slot]
		ip.begin_tick()
		var press: Array = _pending_press[slot]
		var release: Array = _pending_release[slot]
		_pending_press[slot] = []
		_pending_release[slot] = []
		for a in press:
			ip.press(a)
			(_fed_held[slot] as Dictionary)[a] = true
		for a in release:
			ip.release(a)
			(_fed_held[slot] as Dictionary).erase(a)
		ip.set_move(_last_move[slot])
