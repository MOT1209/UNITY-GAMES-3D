# Phase M — 3D match repair: measurements

All numbers come from the engine itself (`MatchQualityProbe` attached to a real `MatchManager`), headless with
`--fixed-fps 60`, Royal Harbor v Northgate, 5-minute matches. Commands:

```
godot --headless --fixed-fps 60 --path . res://tools/qa_m3d.tscn -- matches=4 minutes=5           # AI v AI
godot --headless --fixed-fps 60 --path . res://tools/qa_m3d.tscn -- matches=3 minutes=5 human     # SimulatedHuman at home
godot --headless --fixed-fps 60 --path . res://tests/match_quality_validation.tscn                 # the acceptance suite (slow)
godot --headless --fixed-fps 60 --path . res://tests/match_mechanics_validation.tscn               # the per-bug regression checks
```

Extra probe options: `dump` (one line per pass: power, speed off the foot, direction error, result, contacts) and
`dump_out` (every player sample outside the pitch with his intent and the last match event).

## Root causes found (each with its regression check in `match_mechanics_validation`)

| # | Symptom | Cause (proved with the probe / experiments in `tools/exp/`) | Fix |
|---|---|---|---|
| 1 | AI passes go to the wrong man | the AI plants (move = 0) while charging; `get_kick_direction()` only read the stick on the release frame, so the kick went along a stale aim or the facing: median **85 deg** off | `IntentProvider.aim`; the AI aims at the receiver (with his run) every frame of the charge |
| 2 | passes "intercepted" at once | ownership = closest player within 1.5 m, even for a ball flying past at 12 m/s: a presser 1.2 m from the passer "won" every pass | a ball faster than 6 m/s (relative) is only owned within 0.8 m |
| 3 | passes die short, opponents collect them | Jolt's default `max_angular_velocity` (47 rad/s) caps a 0.22 m ball's rolling speed at **5.2 m/s**; a struck ball also slid without spin and lost half its speed in 0.75 s | project setting 400 rad/s; `BallController.strike()` gives ground kicks matching topspin; ball damping 0.15/0.5 -> 0.08/0.2 |
| 4 | kicks "add" the dribble velocity | `apply_kick` adds to the current velocity: a pass while dribbling at 6 m/s left the foot 31 deg off | `strike()` replaces the velocity (10 % kept) for passes, lobs, shots |
| 5 | passes across / behind the kicker bounce back | the kicker's own capsule stood in the ball's way (3-5 m/s, 120-165 deg off) | 0.2 s collision exception kicker <-> ball after his own kick |
| 6 | 4 of 5 passes reach an opponent | the pass choice ignored opponents in the lane | `PlayerAI.pass_lane_open` (from the ball, widening with distance) |
| 7 | the receiver does not move to the ball | nothing told him | `MatchManager.incoming_pass` + `MatchAIDriver.receive_move` (interception point, slows down) |
| 8 | wind-up lost to pressing | AI held the button 0.15-0.4 s to reach a distance power | `IntentProvider.kick_power` (power for the distance, release after 0.03 s) |
| 9 | 0 offsides, up to 223 player-samples off the pitch, endless throw-ins | after `rules.update` had started a restart, `_update_ai` still ran in the same frame and re-applied every player's last move, which then stayed on for the whole pause: players walked off the pitch and the taker pushed the ball out again | the AI does not run on a frame play stopped; all commands are cleared |
| 10 | team-mate of the carrier runs into him | the closest player of the side IN possession was a "chaser" | only a side without the ball presses |
| 11 | 17 % of outfield samples standing > 3 s | arrived players froze | slow shuffle on the spot (`PlayerAI.shape_shuffle`) |
| 12 | ball lost in a 90 deg dribble turn | full speed through the turn + the reception system switched the dribble off | slower sharp turns with the ball; no reception while dribbling |
| 13 | body snaps round | exponential facing (~1300 deg/s) | 540 deg/s cap (x0.67 with the ball) |
| 14 | shots too weak / too accurate / every shot a goal | tap 16 m/s, no spread, keeper could only hold < 22 m/s, AI shot at everything inside 24 m (31 m open) | tap 23 / full 32 m/s, spread 9 deg + rating + charge + pressure, keeper holds < 30 m/s, xG threshold for AI shots |

## Before / after (fill-in by the final run, see FEATURE_STATUS.md)

Baseline (commit 34c1bb8, same tool, 4 AI matches + 3 simulated-human matches):

| metric | AI v AI before | target |
|---|---|---|
| pass accuracy (MatchStats) | 12-26 % (avg 18 %) | >= 70 % |
| passes per match | 41-57 | >= 120 |
| shots on target | 6-18 % | 35-50 % |
| goals per match | 0.5 (0-1) | 2.0-3.0 |
| offsides | 0-1 | > 0 |
| player-samples off the pitch | 45-109 | ~ 0 |
| outfield standing > 3 s | 11-17 % | <= 3 % |
| team-mates within 10 m of the ball | 0.25-0.42 | <= 2.5 |
| human side: pass arrival | 3-12 % | >= 75 % |
