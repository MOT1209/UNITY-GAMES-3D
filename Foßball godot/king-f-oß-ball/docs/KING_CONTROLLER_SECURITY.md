# KING CONTROLLER — Security documentation

Documents **only mechanisms that exist in the code** (verified by the suites listed at the end).
No claim below is aspirational. For the feature roadmap see
[KING_CONTROLLER_ROADMAP.md](KING_CONTROLLER_ROADMAP.md).

## Threat model

The controller server binds to a LAN interface on the player's own PC. Phones on the same Wi-Fi pair
via a QR code and send game inputs. Everything else is out of scope by design: there is **no shell,
no file system access, no arbitrary command, no admin surface and no online service** in the
protocol — `KingControllerProtocol.MESSAGE_TYPES` allowlists exactly five v2 types plus the three
v3 companion types, and every message is validated field-by-field before the registry sees it.

## Pairing

| Property | Implementation |
|---|---|
| Token | 8 characters from a 32-symbol alphabet (40 bits), `Crypto.generate_random_bytes` |
| Lifetime | 120 s (`TOKEN_TTL_MS`), one-time — replaced after a successful pairing |
| Brute force | 5 wrong guesses (`MAX_TOKEN_GUESSES`) replace the token |
| Comparison | constant-time (`token ==` on equal-length strings via the registry's compare helper) |
| Logging | the token is never written to the log; logs hold short session ids and reason codes |
| QR content | the pairing URL only (`http://<lan-ip>:<port>/?t=<token>`); it grants nothing after expiry |

## Session credential

- 128 random bits, sent once inside the `paired` frame; the PC stores **only its SHA-256 hash**.
- The phone keeps it in `sessionStorage` (per browser tab) and uses it for `resume`.
- Valid 120 s after the connection drops (`RESUME_WINDOW_MS`) and at most 4 h after pairing.
- The token is removed from the phone's address bar after pairing (`history.replaceState`).
- Revocation ("Disconnect" on the PC) remembers the credential hash for 10 minutes
  (`REVOKED_MEMORY_MS`) so a revoked session can never resume.

## Input validation (the hot path)

- **Size:** every WebSocket frame is size-checked before any JSON parse (`MAX_MSG_BYTES = 4096` in
  v3; the gameplay `input` frame alone is capped at `MAX_INPUT_BYTES = 1024`).
- **Shape:** strict field allowlists per message type (`validate_message`): unknown fields, wrong
  types, non-finite numbers, wrong protocol versions, unknown actions and oversized held lists are
  rejected with a reason code; nothing is applied partially.
- **Values:** `move` components within tolerance of [-1, 1] (`MOVE_TOLERANCE`); actions must be in
  `ALLOWED_ACTIONS` (8 gameplay actions + `pause`); at most 9 held entries.
- **Sequence:** strictly increasing per connection; `duplicate_seq`, `out_of_order_seq` and jumps
  above 100 000 are rejected; rejected packets never advance the sequence.
- **Rate:** at most 60 input packets/s and 10 pings/s per connection (server arrival time); extra
  packets are dropped and counted; at most 128 packets per connection per frame; after 20 invalid
  packets the connection is closed.
- **No client clock:** timestamps (`t`) are optional, ignored, and never trusted — the PC stamps
  every packet with its own monotonic clock (one read per frame).

## Connection hygiene

- Heartbeat: no valid packet for 3 s → connection lost, **every held input released**, socket
  closed. A held input with no updates for 500 ms releases everything but keeps the connection.
- On every kind of loss (close, error, timeout, revoke, `bye`, server stop, match teardown) the hub
  releases all held buttons, zeroes the stick and hands the provider back to keyboard/gamepad.
- A live session can only be replaced by a `resume` carrying its own credential; a new pairing
  cannot take a reserved slot.
- The server serves only the controller page, `/favicon.ico` and the WebSocket endpoint.
  Page responses carry `Cache-Control: no-store`, `Referrer-Policy: no-referrer` and a strict CSP.

## Honest limitations

1. **No TLS.** HTTP and WebSocket are plaintext. Anyone who can observe the traffic on the same
   Wi-Fi (or see the QR code) can read the token/credential and could send valid inputs. Use a
   trusted network only; never port-forward. The game cannot compensate for this within Godot's
   current server APIs — this is a documented, accepted limitation, not a solved problem.
2. The 40-bit one-time token with 5 guesses per code is a convenience barrier for pairing, not
   strong authentication. It exists so a stranger cannot pair by accident, not to resist a
   determined attacker who already sees LAN traffic.
3. Rate limits are per connection, not per source address; a client that reconnects repeatedly
   gets fresh budgets (bounded by TCP/WS handshake costs).
4. Windows Firewall cannot be detected or configured from inside the game; the pairing screen only
   asks the user to allow the game on private networks. That prompt is part of the normal first-run
   flow and must be answered once.

## Verification

- `tests/controller_protocol_validation.gd` — 79 checks: parse/size/JSON/types/versions/fields/
  ranges, v2-back-compat rules (a v2 client is accepted on the input path and rejected on v3-only
  types), rate and sequence rules.
- `tests/controller_session_validation.gd` — 85 checks: token TTL, brute force, constant-time
  compare path, resume window, revocation memory, slot reservation.
- `tests/controller_loopback_validation.gd` — 67 checks against real sockets, including junk
  traffic, oversized frames, wrong tokens and second-phone isolation.
- Numbers above are from the Phase 0/1 re-run recorded in [KING_CONTROLLER_AUDIT.md](KING_CONTROLLER_AUDIT.md).
