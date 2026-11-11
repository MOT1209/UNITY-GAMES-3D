# Teams, Formations & Goalkeeper (Phase 5 — Part 1)

**Status: COMPLETE** — validated headlessly (218 phase-5 checks) and visually.

## What this adds

Phase 4 gave the *human* player a full interaction layer (pass / shoot / lob /
dribble / reception). This part gives the **world** players: kick-off
formations, kits, individual looks and a goalkeeper who actually plays.

| File | Role |
|---|---|
| `scripts/teams/formation.gd` | `Formation` — the kick-off table (4-4-2, 4-3-3, 3-5-2, 4-2-3-1) and the slot → world-position math |
| `scripts/teams/team_sheet.gd` | `TeamSheet` — name, kit, goalkeeper kit, formation, shirt numbers |
| `scripts/teams/match_team.gd` | `MatchTeam` — spawns the 11 players of a team in their formation |
| `scripts/teams/team_player.gd` | `TeamPlayer` — one squad member: role, number, home slot, kit & look |
| `scripts/teams/team_goalkeeper.gd` | `TeamGoalkeeper` — the goalkeeper AI (guard / dive / catch / throw) |
| `scripts/teams/teams_demo.gd` | `TeamsDemo` — arena + both teams + ball; keys 1–4 switch the gold team's formation |
| `scripts/player/team_kit.gd` | `TeamKit` — recolours every `*Jersey` / `*Trim` / `*Shorts` / `*Socks` / `*Boots` material |
| `scripts/player/player_look.gd` | `PlayerLook` — skin, hair colour & style, beard, boots, height, build (deterministic per player) |
| `scripts/player/player_character_visual.gd` | the one animation driver — now also dresses the model (kit, number, look) |
| `scripts/player/goalkeeper_visual.gd` | `GoalkeeperVisual` — "Ready" stance plus dive / catch / throw clips |
| `assets/models/characters/goalkeeper.glb` | the goalkeeper model (10 clips: Idle, Walk, Run, Kick, Ready, DiveLeft, DiveRight, CatchHigh, CatchLow, Throw) |
| `assets/textures/numbers_atlas.png` | one 10×10 atlas with the shirt numbers 1–99 |
| `resources/kits/*.tres`, `resources/teams/*.tres` | gold + red kits and team sheets |
| `resources/formations/formations.json` | the exported mirror of the formation table (drawings use it) |
| `scenes/teams/*.tscn`, `scenes/player/{player_model,goalkeeper_model}.tscn` | the team scenes |
| `tests/phase5_validation.tscn` | the fifth validation suite (218 checks) |

## The formation table

Every slot is `[role, depth, lateral]`:

- **depth** — 0 = own goal line, 0.5 = halfway. Kick-off positions always stay
  in the team's own half. The goalkeeper stands at depth 0.05 → 5.25 m from
  his goal line, i.e. on the 6-yard line.
- **lateral** — −1 = the team's own left touchline, +1 = its own right.
  `home_position()` mirrors it for the team that attacks the other way.

The pitch dimensions come from `FootballPitch` (`PITCH_LENGTH` 105 m,
`PITCH_WIDTH` 68 m), so the slots can never drift away from the pitch they
are placed on.

`resources/formations/formations.json` is the exported mirror of the table
(the formation drawings are generated from it). The Phase 5 suite compares the
two file by file, so they cannot drift apart silently.

## Shirt numbers are positional

`TeamSheet.numbers` holds **one number per slot, in slot order** — not per
role. The same list therefore serves all four formations, which means the
number follows the *position*: with the default list #7 is the right winger in
4-4-2, the left winger in 4-3-3 and the right wing-back in 3-5-2. Adding a
fifth formation must extend the list accordingly.

## The goalkeeper

`TeamGoalkeeper` runs a four-state machine — `GUARD → DIVE / HOLD → RECOVER`:

- **GUARD** — stands between the ball's side of the goal and his line, comes
  further out the closer the ball gets, and faces the ball smoothly.
- **DIVE** — reads the shot (time to the keeper's plane + gravity, so a lofted
  ball is met lower), then dives **along his line** towards the predicted
  intercept point — a real keeper moves sideways to meet the shot where it
  crosses his plane; he never lunges forward into his own goal.
- **HOLD** — the caught ball is held with a spring + damper towards the
  hands. It is never frozen, never teleported and its velocity is never
  written; the hands absorb it with one mass-scaled impulse and the spring
  keeps it there.
- **RECOVER** — throws the ball back into play with a normal `apply_kick()`
  impulse.

The keeper only catches balls that are heading **towards** his goal — a
clearance rolling past his feet is never picked up.

The keeper works with the project's real `BallController` (it finds it through
the `football_ball` group), so the whole Phase 3/4 ball contract holds: no
teleports, no velocity writes, every kick through `apply_kick()`.

## Validation coverage

`tests/phase5_validation.tscn` (218 checks) asserts:

- the formation table (11 slots, one goalkeeper first, known roles, every slot
  on the pitch and in the own half, the mirror for the opposite attack
  direction) and that the JSON mirror matches it;
- team spawning (11 players, unique numbers, own half, facing, the right back
  on the team's own right, the goalkeeper on his 6-yard line, the keeper is a
  `TeamGoalkeeper` with a `GoalkeeperVisual`, formation switching);
- kits, shirt numbers (the atlas cell of #9) and individual looks (only the
  chosen hair mesh is visible, the beard follows the look, the rig is scaled
  to the player's height, the squad is varied);
- the goalkeeper AI against the real arena: he finds the project's ball, holds
  his line, catches a central shot **without freezing or teleporting the
  ball**, throws it back towards the pitch, does **not** catch a ball moving
  away, dives for a corner shot and returns to `GUARD`;
- the human player is untouched (still carries `BallActions` / `BallDetector`
  and the kick hook) and the demo scene lines up both teams.

Every check was proven to be meaningful with a mutation test: breaking the
ball group, freezing the ball, teleporting the ball, removing the dive,
removing the "moving away" gate, drifting the JSON, breaking the atlas cell,
the rig scale or the hair toggle each makes the matching check fail.

## Not in this part

Outfield movement AI (the players hold their kick-off slot), match rules,
scoreboard / timer, fouls, offside, substitutions and the rest of the plan's
Phase 5 scope.
