# KING CONTROLLER architecture (P5)

Status: **v1 implemented.** PC hosts the match and the controller server; the
phone is a browser page (no app-store dependency) that sends input over local
Wi-Fi. Bluetooth is NOT part of this path (see P6 spike).

## Roles
- **Host (PC):** runs `MatchManager` + `KingControllerServer` (HTTP on `port`,
  WebSocket on `port + 1`). Generates a one-time pairing token and renders it
  as a QR code on the pairing screen (`PairingScreen`).
- **Client (phone):** opens the URL encoded in the QR (`http://<lan-ip>:<port>/?t=<token>`),
  loads the served page (`assets/controller/controller_page.html`), and connects
  a WebSocket to `ws://<lan-ip>:<port+1>/`. Sends pairing then input messages.

## Components
- `scripts/systems/controller/king_controller_server.gd` — `KingControllerServer` (Node):
  HTTP TCPServer serving the page; WebSocketMultiplayerPeer on `port+1`; token
  generation; LAN IP detection; pairing slot assignment (max 2); validation;
  emits `input_received(slot, move, press, release)`, `client_connected`,
  `client_disconnected`.
- `scripts/systems/controller/controller_protocol.gd` — `KingControllerProtocol` (RefCounted):
  versioned message schema + validation (version, token, seq monotonicity,
  freshness, rate limit, action whitelist, move clamping).
- `scripts/systems/controller/king_controller_hub.gd` — `KingControllerHub` (Node):
  bridges the server to `IntentProvider`s, edge discipline identical to
  `TouchControls` (queue in callbacks, apply once per physics tick after
  `begin_tick()`), grace-period handling on disconnect.
- `scripts/systems/controller/qr_encoder.gd` — `KingQrEncoder`: pure-GDScript
  byte-mode QR (EC level L, versions 1-5).
- `scripts/ui/pairing_screen.gd` — `PairingScreen`: overlay UI with QR, URL,
  token, connection count.
- `assets/controller/controller_page.html`: phone page (virtual stick + 8
  buttons), reconnects automatically.

## Protocol
Messages are JSON over WebSocket text frames, carrying `"v": 1`.

Phone -> PC:
- `pair`: `{v, type:"pair", token, name}`
- `input`: `{v, type:"input", seq, move:{x,y}, press:[actions], release:[actions], t}` (ms)
- `ping`: `{v, type:"ping", seq}`

PC -> phone:
- `paired`: `{v, type:"paired", slot, tick_rate}`
- `pair_fail`: `{v, type:"pair_fail", reason}`
- `pong`: `{v, type:"pong", seq}`

Validation (server side):
- Protocol version must match `PROTOCOL_VERSION` (1).
- Pairing token must equal the issued token (one-time: first use binds the slot;
  later uses with the same token re-bind to the same slot for reconnect).
- Free slot required on first pair (max 2 slots).
- Input: `seq` must be strictly increasing per client (stale dropped).
- Freshness: `t` within `FRESHNESS_MS` (1500 ms) of server now.
- Rate limit: `RATE_LIMIT_MSGS_PER_SEC` (60) per client per second.
- Move components clamped to [-1,1] and length <= 1.
- Actions filtered to the allowed set (sprint, tackle, switch_player, pass,
  shoot, lob_pass, through_pass, cross).

## Intent sink
Slot 0 feeds the match's shared human `IntentProvider` (driven mode), exactly
like `TouchControls`. Slot 1 is reserved for a second controller (protocol-level
support; gameplay wiring is slot 0 only in v1). On disconnect the provider is
released after a grace window (`grace_ms`, default 5 s).

## Wiring
- Main menu adds a "KING CONTROLLER" button opening `PairingScreen`.
- `GameManager.king_controller_server` holds the server across scene changes so
  a match started after pairing reuses it.
- `MatchManager` (when a server is present) creates a `KingControllerHub` with
  `{0: human_intent}`.

## Security / scope
- LAN binding only (`0.0.0.0` on the chosen port); no internet exposure.
- One-time token in the QR URL; not reusable beyond its slot binding.
- No TLS in v1 (LAN-only, browser page avoids cert-store issues).
- iOS: page works in any mobile browser; no native app required.

## Tests
- `tests/controller_protocol_validation.tscn` — protocol + QR encoder (25 checks).
- `tests/controller_loopback_validation.tscn` — real in-process WebSocket
  loopback: pairing, input flow, bad token, stale seq, disconnect/reconnect
  (21 checks). HTTP serving is exercised by the same server in production; raw
  TCP loopback is not verifiable in-process with Godot 4.7's StreamPeerTCP, so
  the page-serving path is covered by the standard HTTP responder code and
  manual browser checks.

## Open items
- Android real-device test of the page + WS (P8).
- Optional: TLS for non-LAN use (out of scope v1).