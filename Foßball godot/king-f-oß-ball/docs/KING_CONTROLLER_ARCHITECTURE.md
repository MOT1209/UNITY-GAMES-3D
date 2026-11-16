# KING CONTROLLER architecture (P5, stabilised in P9)

Status: **protocol v2, up to two phone controllers (player 1, and a friend as player 2 on the opposing side - P10).** The PC hosts the match and the controller server; the
phone is a browser page (no app, no store) that sends input over the local Wi-Fi. Bluetooth and iOS-specific
work are NOT part of this path. Real phone validation is **NOT TESTED** (see
[qa/KING_CONTROLLER_QA.md](qa/KING_CONTROLLER_QA.md)).

## What the player does
1. Main menu -> KING CONTROLLER. The PC shows a QR code, the URL, the one-time pairing code (with a countdown),
   the PC address in use (selectable when several network adapters exist) and the slot list.
2. Scan the QR with the phone (same Wi-Fi). The page opens, pairs, and shows **Connected**.
3. Start a match (before or after pairing): the phone drives the human player. Keyboard / gamepad / touch keep
   working whenever the phone is not connected.

## Components
| File | Role |
|---|---|
| `scripts/systems/controller/controller_protocol.gd` | `KingControllerProtocol`: constants, byte-level `parse` (size check first), `validate_message`, `process_input` (sequence + rate), builders. Pure logic. |
| `scripts/systems/controller/controller_session.gd` | `KingControllerSession`: one paired phone; the seven lifecycle states. |
| `scripts/systems/controller/controller_registry.gd` | `KingControllerRegistry`: pairing token, sessions, slots, resume, revoke, heartbeat / input-gap rules, edge generation, pause debounce. Injectable clock and random source -> deterministic tests. |
| `scripts/systems/controller/controller_network.gd` | `KingControllerNetwork`: ranks `IP.get_local_interfaces()` to pick the LAN address for the QR. |
| `scripts/systems/controller/king_controller_server.gd` | `KingControllerServer`: thin transport (HTTP TCPServer for the page on `port`, WebSocket on `port + 1`); closes sockets; emits `input_received`, `client_connected`, `client_disconnected`, `pause_requested`. |
| `scripts/systems/controller/king_controller_hub.gd` | `KingControllerHub`: feeds `IntentProvider`s (one per supported slot) with edge discipline identical to `TouchControls`; releases everything on loss. |
| `scripts/systems/controller/qr_encoder.gd` | pure-GDScript QR encoder. |
| `scripts/ui/pairing_screen.gd` | `PairingScreen`: a *view* of the shared server (see "Shared server"). |
| `assets/controller/controller_page.html` | the phone page (Pointer Events, i18n en/de/ar, RTL). |

### Shared server
`GameManager.ensure_controller_server()` creates the single server (default ports **7250 / 7251**). The pairing
screen, the match and the tests all use it. Closing the pairing screen does **not** stop the server or drop the
phone; reopening shows the live state. `GameManager.stop_controller_server()` shuts it down cleanly (sockets
closed, every session ended, every held input released). If the port pair is busy the next pair (+2, up to 5
attempts) is used and the screen shows the real ports; if none is free the screen says so.

## Slots (honest count)
`KingControllerProtocol.SUPPORTED_SLOTS = 2` (P10). Slot 1 drives the human player (`MatchManager.human_intent`).
Slot 2 is a **friend on the opposing side**: a second seat (`human_intent2`, `selected2`, its own indicator in the
slot-2 colour, auto-switch policy and aim assist). The seat is dynamic: while no second phone is connected the
opponent is plain AI exactly as before; when a phone pairs into slot 2 (before or during the match) it takes the
opponent's outfield player closest to the ball at once (never the goalkeeper) and the camera switches to the
broadcast view (one camera cannot follow two players); when that phone is lost, revoked or leaves, every button is
released and the player goes back to the AI immediately. A match without a human side has no second seat. Each
phone needs its own QR code (the pairing token is one-time); a third phone gets `pair_fail: no_slot`.
The pairing screen lists slots 3-4 as "not supported in this version". Input for a slot without a connected
provider is dropped and counted (`KingControllerHub.dropped_unrouted`). Two controllers can never drive one player.
Limits: the second human is always the opponent of the first (versus play, no co-op on one team); keyboard /
gamepad drive only player 1; the HUD's "controlled player" box shows player 1; career statistics and the result
report still treat the first human side as the user's side. The phone page shows "Player 1" / "Player 2".

## Protocol v2
JSON text frames, **at most 1024 bytes**; the size is checked before any parsing. Every message has `"v": 2`.

Phone -> PC
- `pair` `{v,type,token,name?}` - first connection (token from the QR)
- `resume` `{v,type,session}` - reconnect with the session credential
- `input` `{v,type,seq,move:{x,y},held:[actions],t?}` - the **full** controller state (level, not edges), ~30 Hz while active, 2 Hz idle
- `ping` `{v,type,seq}` - heartbeat, every 1 s
- `bye` `{v,type}` - the user disconnects

PC -> phone: `paired {slot,session,tick_rate,heartbeat_ms,timeout_ms}`, `pair_fail {reason}`, `pong {seq}`,
`revoked`, `error {reason}`.

Actions: `sprint tackle switch_player pass shoot lob_pass through_pass cross` (player actions) and `pause`
(system action). Unknown fields, wrong types, out-of-range values, unknown actions, more than 9 held entries,
non-finite numbers and wrong versions are rejected (`validate_message`). `move` uses the screen convention
(up = -1), like `TouchJoystick` / `Input.get_vector`.

### Timestamps and freshness (P9.1)
v1 compared the browser's `Date.now()` with the PC's monotonic clock - two unrelated clock domains - so **every
real browser packet was rejected** (measured: `ok=false reason=stale_freshness`; the phone could never move a
player). v2 trusts no client clock: the server stamps each packet with its own arrival time (one
`Time.get_ticks_msec()` per frame). `t` is optional, must be a finite number if present, and is ignored.
Rules:
- `seq` strictly increases per connection (`duplicate_seq`, `out_of_order_seq`, `seq_jump` > 100000 rejected;
  rejected packets never advance it; a new connection starts again at 0);
- at most 60 input packets per second and 10 pings per second per connection (arrival time); extra are dropped and counted;
- heartbeat: no valid packet for 3 s -> connection lost, held inputs released, socket closed;
- input gap: something held / stick off-centre and no input for 500 ms -> everything released (connection stays);
- at most 128 packets per connection per frame, 20 invalid packets per connection, then it is closed.

### Pause (P9.2)
`pause` is a real protocol action, never mapped onto another action. The registry turns its rising edge into a
single `pause_requested`, debounced to one per 500 ms; the hub forwards it to `MatchManager.toggle_pause_from_controller()`
(pause menu open -> resume, else pause; refused when the match is finished). The server and hub run in
`PROCESS_MODE_ALWAYS`, so the phone can resume a paused match. Press edges arriving while the tree is paused are
dropped, so a tap during the pause menu cannot fire a kick on resume. The page sends pause as a 150 ms press
with a 500 ms client debounce.

## Pairing and session security (P9.5)
- **Pairing token**: 8 characters from a 32-symbol alphabet (40 bits) from `Crypto.generate_random_bytes`,
  valid 120 s, **one-time** (replaced after a successful pairing), replaced after 5 wrong guesses or on expiry,
  compared in constant time, never written to the log (logs hold short session ids and reason codes only).
- **Session credential**: 128 random bits sent once in `paired`, kept by the page in `sessionStorage` (this tab),
  stored on the PC only as a SHA-256 hash. Used for `resume`. Valid 120 s after the connection is lost and at most
  4 h after pairing. The token is removed from the phone's address bar after pairing.
- **No slot takeover**: a live session can only be replaced by a `resume` with its own credential (the older socket
  is closed). A slot whose controller lost its connection stays reserved for the resume window; a new pairing
  cannot take it (use "Disconnect" on the PC to free it at once).
- **Revocation**: the PC "Disconnect" button (`KingControllerServer.revoke(slot)`) ends the session, releases
  inputs, tells the phone (`revoked`), and remembers the credential hash for 10 min so it can never resume.
- The server accepts only the page, `/favicon.ico` and the WebSocket. No shell, file system or admin command exists
  in the protocol. Page responses carry `Cache-Control: no-store`, `Referrer-Policy: no-referrer` and a strict CSP.

### Security limitations (not hidden)
- **No TLS.** HTTP and WebSocket are plain; anyone on the same Wi-Fi who sees the traffic (or the QR code) can
  read the token / credential and send inputs. Use a trusted network only. LAN only: never forward the ports.
- A 40-bit token with 5 guesses per code and a 120 s lifetime is a convenience barrier, not strong authentication.
- Input flooding is limited per connection, not per source address.

## Lifecycle (P9.6)
States (`KingControllerSession.State`): Disconnected, Connecting, Pairing, Connected, Reconnecting,
Connection lost, Revoked. A socket is Connecting/Pairing until it authenticates (5 s limit); a session is
Connected while live, Connection lost while its slot is reserved (resume window), Revoked after the PC ended it;
a freed slot is Disconnected. The phone page shows Connecting / Pairing / Connected / Reconnecting / Connection lost
/ Removed by the PC / Disconnected (en/de/ar); the PC shows one row per slot with the real state and device name.
On every kind of loss (close, error, heartbeat timeout, revoke, `bye`, server stop, match teardown) every held
button is released, the stick is zeroed, and the `IntentProvider` leaves driven mode so keyboard / gamepad work at
once (the old 5 s grace that kept the last stick position running is gone). The page also releases on `blur`,
`pagehide`, `visibilitychange`, `orientationchange`, `pointercancel` and lost pointer capture.

## LAN discovery (P9.7)
`KingControllerNetwork.choose()` ranks adapter addresses: never loopback / 0.0.0.0 / link-local (169.254.x) /
multicast / IPv6; adapters named virtual or VPN (vEthernet, VirtualBox, VMware, WSL, docker, tun/tap, Tailscale,
ZeroTier, WireGuard, ...) and 100.64.0.0/10 are ranked down; Wi-Fi / Ethernet with a private address win
(192.168 > 10 > 172.16-31). The chosen address is shown and can be changed from a list on the pairing screen.
No usable address -> a specific message (no network / no DHCP / no private address), never a loopback URL.
Both ports are really opened (HTTP + WS) or the screen reports the error. Windows may ask to allow the game on
private networks the first time - allow it, otherwise the phone cannot connect (a note is shown on the screen).
The code cannot detect the firewall state; that stays a manual check.

## Phone page
Controls: virtual stick, Pass, Through pass, Shoot, Cross, Lob pass, Sprint, Switch player, Tackle, Pause.
The task list asked for a "Press" button; the game has no distinct "press" action (only `tackle`), so no fake
button was added - see the QA report. Languages en / de / ar chosen from `?lang=`, the saved choice, then the
browser language; Arabic sets `dir="rtl"` (labels use «تمريرة بينية» for the through pass). Black / Gold / Red.
Zoom, scrolling, text selection and context menus are disabled; portrait shows a "rotate" overlay.

## Tests
| Suite | Checks | Covers |
|---|---|---|
| `controller_protocol_validation` | 72 | parse / size / JSON / types / versions / fields / ranges, timestamps, sequence, rate, pause, QR |
| `controller_session_validation` | 85 | token, pairing, brute force, slots, resume, revoke, edges, pause debounce, timeouts, snapshot, LAN selection |
| `controller_loopback_validation` | 67 | real sockets: HTTP page, pairing, browser-style input, pause, junk traffic, second phone, resume, revoke, disconnect cleanup, heartbeat timeout, stop/start, port conflicts |
| `controller_gameplay_validation` | 70 | real match: pair-before-match, stick direction vs keyboard, buttons, pause/resume, release on loss, keyboard restored, pairing screen |
| `controller_page_validation` | 48 | static checks of the page |
| `two_human_validation` | 41 | real match with two phones: seats, independent sticks / buttons / switch, pause from slot 2, join and leave mid-match, release to AI, teardown |
| `tests/e2e/controller_browser_e2e.js` | 32 | emulated mobile Chromium (Playwright) against the real server - **not a real phone** |

## Control preferences and vibration (phone page only, 2026-11-16)
All of this lives in the phone's `localStorage`; **nothing about it is sent to the PC and the protocol is unchanged**.
* Settings: hand (left / right), button size, opacity, stick dead zone, stick sensitivity, hide any of SPRINT / SWITCH /
  TACKLE / CROSS / LOB / THROUGH (PASS and SHOOT can never be hidden), vibration (off / light / strong), 3 profile slots
  (save / load), presets (Default, Left-handed, Big buttons) and Reset. Corrupt or out-of-range stored values are clamped
  on load. Custom button *positions* (free drag) are NOT built: hand, size and visibility are.
* Vibration: `navigator.vibrate` on every button press (9 ms light / 22 ms strong). Where the browser does not provide it
  (notably iOS Safari) the page says so and works normally. **Goal / match-event vibration is NOT built**: the PC sends the
  phone no match events yet (protocol v2 has none); it needs the PC -> phone state channel planned for the live dashboard.
* Test: `node tests/controller_page_browser_test.js` (Chromium via Playwright, 21 checks, vibration API stubbed). This
  is a desktop browser with emulated touch: it is NOT a test on a physical phone.

## Match feed: PC -> phone (dashboard, mini-map, goal vibration)
New PC -> phone message types `state` and `event` (`KingControllerProtocol.FEED_TYPES`, built only by
`KingControllerFeed`; sent by `MatchManager._feed_controllers` through `KingControllerServer.send_to_slot`). Protocol
version stays **2**: pages that do not know these types ignore them, and the PC still rejects them if a phone sends
them (tested). The channel is one-way display data; the phone cannot ask for anything through it.
* `state` (5 Hz, ~600 bytes): viewer side, clock, half, phase, score, possession, shots, shots on target, cards and 11 + 11
  positions plus the ball, normalised to -1..1 with the **viewer's own goal at the bottom**. Slot 1 sees the match as the
  human side, slot 2 as the opposing side. Nothing is built while no phone is connected.
* `event` (once each): goal (with own-goal flag), yellow / red card, substitution, save, penalty kick, with the minute, the
  player's display name and whether it is the viewer's side.
* Page: the chip with the chart icon opens a click-through panel (it can stay open during play) with score, clock,
  possession bar, shots, cards, the last six events and the mini-map (canvas, 5 Hz). Goal for you / against you and red cards
  vibrate with different patterns (honouring the vibration setting). Text is set with `textContent` only.
* Tests: `controller_feed_validation` (27: frame content, per-viewer orientation, real socket, a real match streaming to a
  paired phone) and the Chromium test (34). Still NOT tested on a physical phone, over real Wi-Fi, or for 10 minutes.
* NOT built: tactics changes from the phone, controller analytics (connection history, latency), controller tutorial.
