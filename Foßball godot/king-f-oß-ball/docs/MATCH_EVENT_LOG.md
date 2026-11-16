# Match event log

`MatchState.events` is the single, append-only log of what happened in a match. Everything that needs match history
(crowd, sounds, referee reactions, report, and the planned replay selection, commentary, shot map, heatmaps and
controller dashboard) reads it. Nothing is estimated: an entry exists only because the engine reported that event.

## Entry fields
| Field | Meaning |
|---|---|
| `id` | 1, 2, 3... unique inside the match; continues after a save/restore |
| `t` | match clock in real seconds (`MatchState.elapsed`) |
| `half` | 1 or 2 |
| `minute` | 0-90 display minute (kept for existing readers) |
| `type` | goal, shot, save, foul, yellow_card, red_card, corner, throw_in, goal_kick, offside, substitution, half_time, full_time, penalty_kick |
| `side`, `player_id` | as before; type-specific fields (`assist_id`, `victim_id`, `out_id`, `shooter_id`...) unchanged |
| `pos` | `[x, z]` ball position in metres when the event was logged |
| `outcome` | shots only: `goal`, `saved`, `missed`; absent while still open |

All entries are written by `MatchState.log_event` (no other code appends to `events`). `MatchManager` feeds the ball
position every frame with `set_ball_position`.

## Honest limits
* `pos` is the BALL position at the event, not the player's. For a shot it is where the ball was when the kick
  started, which is the shot location to within a step.
* `missed` means "no save and no goal within 6 s, or another shot started": the engine does not separate off target
  from blocked, so neither does the log. Because of this, "shots on target" in `MatchStats` is unchanged (it counts
  saves and goals as before).
* Passes, tackles and interceptions are counters in `MatchStats`, not individual log entries (volume). Heatmaps and
  xG are therefore NOT built yet; xG would need shot distance and angle, which `shot_map()` can now supply, plus a
  documented model.
* Old saves without `id` / `t` / `half` / `pos` load with defaults (`pos` = [0, 0] means "unknown").

## Queries
`events_in(types, t_from, t_to)` and `shot_map()`. Tests: `tests/match_event_log_validation.gd` (27 checks).
