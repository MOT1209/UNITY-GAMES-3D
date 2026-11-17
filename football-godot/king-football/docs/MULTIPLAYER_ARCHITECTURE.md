# Multiplayer architecture (design only)

Status: **NOT IMPLEMENTED by design.** The roadmap says not to add networking before the single-player game is stable. This
document records what the current code already allows, what is missing, and the plan for a first prototype. No networking code exists.

## What the code already gives
| Need | Today | Evidence |
|---|---|---|
| Stable entity ids | Player ids are stable strings; a match has `uid`, `match_id`, side + slot per entry | `MatchState.uid`, `MatchManager.entries` |
| Simulation separate from UI | Match rules live in `MatchState`, `MatchStats`, `MatchRules`, `MatchRestarts`; the HUD and results view only read them | `scripts/systems/match` |
| Network-friendly events | Every event is a small dictionary `{minute, type, side, player_id}`; stats and report are JSON-safe | `MatchState.events`, `MatchReport` |
| Full state capture | `MatchSnapshot.capture/restore` already serialises players, ball, state and flow | `match_snapshot.gd` |
| Input as data | AI and humans both drive players through `IntentProvider` / `AIIntent` | `scripts/systems/match/ai_intent.gd` |
| Determinism | Match RNG is seeded (`rng_seed`); injuries, simulation and AI transfers are seeded; physics is NOT deterministic across machines | `MatchSetup.rng_seed` |

## What is missing
1. A fixed simulation tick decoupled from rendering (physics already runs at a fixed step, but the match loop also reads `delta`).
2. Deterministic or snapshot-based ball and player physics. Godot physics is not bit-exact across machines, so a server-authoritative model with client snapshots is required; lockstep is not viable.
3. An input command format: `{tick, side, slot, move, buttons}` (buttons = pass, shoot, lob, tackle, sprint ...).
4. Authority rules, lobby, reconnection, anti-cheat, test tooling.

## Proposed design
- **Server-authoritative.** One headless Godot instance runs `MatchManager` without the HUD. Clients send only input commands; the server validates them (rate, ranges, only the slot the client controls) and broadcasts snapshots (20 Hz: ball, 22 players, phase, score, clock) plus discrete events (goal, foul, card, restart, offside).
- **Clients** interpolate snapshots, predict only their own player's movement, and reconcile with the server.
- **Lobby/session:** matchmaking returns a session id, the two squads (player ids and appearance dictionaries, already JSON) and the seed. Squads are validated on the server against `Squad.validate`.
- **Reconnection:** the server keeps the last `MatchSnapshot.capture()`; a returning client receives it and the event log, then resumes snapshots. AI takes over a missing human after N seconds through the existing `AIIntent`.
- **Anti-cheat:** clients never send state, only inputs; the server ignores impossible inputs and owns the clock and the score.
- **Career/online separation:** online friendlies do not touch a career save; results are returned as a `MatchReport` only.

## First prototype (when approved)
1. Extract a `MatchSimulationHost` that runs `MatchManager` headless with a fixed tick (no HUD, no audio).
2. Define the input command and snapshot formats as plain dictionaries with a version field, with round-trip tests.
3. Local loopback prototype (two clients, one server in one process) using Godot's `MultiplayerAPI` high-level RPC; measure snapshot size and bandwidth.
4. Only then add lobbies and reconnection.

## Test architecture
- Unit tests for command and snapshot encode/decode and for server-side input validation (these run headless today's way).
- A loopback integration test: scripted client inputs produce the same final score on the server twice.
- Latency/loss simulation by delaying and dropping packets in the loopback transport.
