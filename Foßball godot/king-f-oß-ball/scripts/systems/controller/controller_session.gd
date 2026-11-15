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


func state_name() -> String:
	return STATE_NAMES[int(state)]


func is_live() -> bool:
	return state == State.CONNECTED or state == State.RECONNECTING


func clear_inputs() -> void:
	held.clear()
	move = Vector2.ZERO
	pause_down = false
