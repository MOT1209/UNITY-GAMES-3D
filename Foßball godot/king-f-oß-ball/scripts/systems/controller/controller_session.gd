class_name KingControllerSession
extends RefCounted

## One paired phone (P9). Plain data owned by `KingControllerRegistry`; the transport (server) only holds a
## reference to find the socket. The session credential itself is never stored: only its SHA-256, so a
## memory dump or a log line cannot leak a usable secret.

## Lifecycle of a controller connection. A socket without a session is CONNECTING (accepted, not yet
## authenticated) and PAIRING (a pair / resume message is being checked) — tracked by the server; the
## registry owns the states of real sessions: CONNECTED, CONNECTION_LOST (no live socket, slot reserved for
## the resume window; the PC shows it as "reconnecting"), RECONNECTING (a resume replaced a still-open
## socket), REVOKED (the user ended it) and DISCONNECTED (the slot is free again / the session is gone).
enum State { DISCONNECTED, CONNECTING, PAIRING, CONNECTED, RECONNECTING, CONNECTION_LOST, REVOKED }

const STATE_NAMES: Array[String] = ["disconnected", "connecting", "pairing", "connected", "reconnecting",
		"connection_lost", "revoked"]

var id := ""                        # short public id (8 hex characters): safe to show and log
var slot := -1
var name := ""
var state: State = State.CONNECTED
var credential_hash := ""
var created_ms := 0
var last_seen_ms := 0               # last valid packet of any kind
var last_input_ms := 0              # last accepted input packet
var lost_ms := 0                    # when the connection was lost
var connection_id := -1             # transport connection currently bound (-1 = none)
var input_state: Dictionary = {}    # sequence / rate state of the CURRENT connection
var held: Dictionary = {}           # StringName -> true: actions currently held (player actions only)
var move := Vector2.ZERO
var pause_down := false
var last_pause_ms := -1000000
var connections := 1                # how many sockets this session has used (reconnects + 1)
## Which companion screen the phone currently shows (the `view` message). The PC only pushes the
## streams that screen needs, so a phone resting on the controller screen costs no data traffic.
## Defaults to the primary screen; a fresh session never starts on a companion screen.
var current_view := "controller"


## Removes a period during which the server could not serve this session (its _process was frozen by a
## synchronous match build, a load screen, …) from the connection clocks: the stamps shift forward by
## `frozen_ms`, so the heartbeat / input-gap / resume rules measure only time the server was actually
## running. Without this, a slow `MatchManager.begin()` (seconds, single-threaded) looks like a dead
## phone and kills freshly paired controllers right when the match starts. `created_ms` is NOT shifted:
## the session's total age keeps running in real time.
func skip_frozen(frozen_ms: int) -> void:
	if frozen_ms <= 0:
		return
	last_seen_ms += frozen_ms
	last_input_ms += frozen_ms
	lost_ms += frozen_ms


func state_name() -> String:
	return STATE_NAMES[int(state)]


func is_live() -> bool:
	return state == State.CONNECTED or state == State.RECONNECTING


func clear_inputs() -> void:
	held.clear()
	move = Vector2.ZERO
	pause_down = false
