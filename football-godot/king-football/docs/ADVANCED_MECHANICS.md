# Advanced football mechanics (Phase 2)

Skill moves, feints, ball shielding, shooting techniques, headers / aerial play and physical duels, for human and AI
players. Built on the existing architecture: `FootballActions` (per player), `IntentProvider` / `AIIntent` (input),
`BallController` (physics ball), `MatchAIDriver` / `PlayerAI` (AI), `MatchRules` (tackles), `TeamGoalkeeper`.
Measurements: `docs/reports/PHASE2_ADVANCED_MECHANICS_REPORT.md`. Controls: `docs/CONTROLS.md`.
Suite: `tests/advanced_mechanics_validation.tscn`.

## Rules every mechanic keeps

- The ball is never attached, positioned or teleported. Touches, headers and pokes are one impulse each
  (`BallController.redirect`, `strike`, `strike_with_spin`, `apply_kick`). The only continuous control is the existing
  capped spring force (dribble, now also shielding). The suite checks this every tick: the ball never moves further
  than its own velocity allows.
- A player's body is only moved by velocity targets with bounded acceleration (`PlayerController.set_motion_override`),
  bounded contact nudges (`nudge`, at most `MAX_NUDGE` = 2 m/s) and a real jump (`jump`, applied only from the ground).
  Player capsules still collide, so players never pass through each other.
- Nothing locks the controls. Every skill move ends after its duration (0.32 to 0.85 s), kicks are allowed again
  from its exit phase, shielding ends as soon as the button is released, and a header request expires.
- Gameplay never waits for an animation. Clips that exist are played; missing ones are reported, not faked.
- Defaults are neutral. Without an opponent, a goal or player data, the systems do nothing special. In ordinary
  play the tackle numbers are exactly the Phase 4 / M5 ones (multiplier x1.0, checked by the suite).
- Randomness is deterministic per match: `AdvancedPlay.rng`, `AerialArbiter.rng` and the per-player skill / header
  RNGs are seeded from the match seed. The existing match RNG stream is not touched.

## Files

| File | Role |
|---|---|
| `scripts/gameplay/skill_move_catalog.gd` | data: 13 moves (feints, touches, body steps, exposure, protection, clip), human input table |
| `scripts/gameplay/skill_move_system.gd` | executes a move: quality, clean / unclean roll, touches, body, feint signals, combos |
| `scripts/gameplay/shielding_system.gd` | shield spring, body orientation, pace cap, cover / protection value, let-run near a line |
| `scripts/gameplay/shot_technique.gd` | technique profiles, shot contexts (volley, half volley, first time), curl and chip maths |
| `scripts/gameplay/header_system.gd` | header window prediction, jump timing, geometric head contact, header shot / pass / clear |
| `scripts/systems/match/aerial_arbiter.gd` | aerial contests between players going for the same ball |
| `scripts/systems/match/advanced_play.gd` | match side: feint reactions, tackle context, shoulder duels, shield contests, stats |
| `scripts/systems/match/advanced_ai.gd` | AI decisions: skill move choice, shot technique, shielding, header kind, aerial spot |
| `scripts/gameplay/football_actions.gd` | wiring: input, kick gating during moves, technique shots, volleys, chips, headers |
| `scripts/player/player_controller.gd` | body hooks: motion override, nudge, balance loss, jump, speed cap, facing override |
| `scripts/ball/ball_controller.gd` + `ball_config.gd` | Magnus curl from vertical-axis spin in flight, `redirect`, `strike_with_spin` |
| `scripts/teams/team_goalkeeper.gd` | reads part of the curl (better keepers more), can bite on a fake shot |
| `scripts/data/attribute_modifiers.gd` | reads the stored detailed attributes; derived weak foot; height / mass |

## Attributes used

All values come from the existing 40 detailed attributes (`DetailedAttributes.value`), read-only:
skill moves use dribbling_skill, ball_control, agility, balance and composure. Feint reading uses anticipation,
defensive_awareness and reactions. Shielding and duels use strength, balance, aggression, defending and body mass.
Shots use finishing, shot_power, curve, volleys and composure. Headers use heading, jumping, strength and height.

**Weak foot** is not in the database. `AttributeModifiers.weak_foot_stars()` derives 2 to 4 stars from the player id
(stable), +1 with ball control of 80 or more, and 5 for `Foot.BOTH`. It is never stored, so saves are unchanged.
It applies to a skill move's decisive touch when it uses the weak foot, and to every shot struck with the weak foot
(the ball's side of the body), including normal shots.

## Skill moves and feints

| Tier | Moves |
|---|---|
| 1 basic | body feint, step-over, double step-over, ball roll, drag back, stop and turn |
| 2 intermediate | roulette, elastico, reverse elastico, heel-to-heel, la croqueta, fake shot, fake pass |
| advanced | combinations: a move started in another one's exit phase (skill 0.62+, max 3 links, x0.88 quality per link) |

Quality (0..1) = skill rating against the move's `min_skill`, x weak foot (decisive touch), x fitness, x speed fit
(each move has a speed range), x pressure (opponent within 1.2 m, composure softens it), x combo penalty. A roll
decides a clean move. An unclean one gets a heavy (60-120 % too long) or mis-directed (20-35 degrees) decisive touch.
A touch on a ball that has already run out of reach is missed.

Defenders (`AdvancedPlay.on_feint`, AI only): every AI defender within 5 m gets
`bite_probability(strength x quality, read, distance, closing speed, difficulty, last man)`, capped at 0.85.
Distance peaks at 1.6 to 2.6 m, a charging defender bites more, the last man less, EASY more, HARD less.
A **bitten** defender steps towards the fake for 0.3 to 0.55 s (shorter with good reactions) and cannot tackle.
A defender who **reads** the feint (chance grows with his reading above 0.45) moves to the real exit side, tackles
1.8x as often and wins 1.25x as often for 0.7 s. A keeper can bite on a fake shot within 26 m and is then planted for
0.4 s divided by his rating. A human defender is never steered.

## Shielding

Hold `shield` with the ball close. The ball is kept on the far side of the body from the nearest opponent (rolled round
the body first when it is on his side), the body turns its back / side to him, and pace is capped at 55 %. The stick
carries the shielded ball. Near a line with the ball running out and no stick input, the ball is not touched (let it
run). Protection = ball on the far side (0.45) + body orientation (0.25) + strength / balance (0.3).
Tackles against a shielder are attempted less (x(1 - 0.5 x protection)) and won less (x(1 - 0.45 x protection)).
A defender within 1.15 m contests the ball every 0.5 s (`shield_loss_probability`: protection, strength and balance
against strength, aggression and defending, clamped 0.04 to 0.6). A lost contest leaves the carrier off balance for
0.45 s and knocks the ball out sideways with a real impulse.

## Shooting techniques

| Technique | Input (human) | Gain | Cost |
|---|---|---|---|
| normal | shoot | as before | as before |
| finesse | `skill_move` held | spread x(1.12 - 0.5 x curve), sidespin curl (the keeper reads only part of it) | 0.8x pace, less lift |
| power | `skill_move` + `shield` held | 1.12x pace | spread x(1.5 - 0.45 x shot power), 0.2 s wind-up (ball can be taken) |
| low driven | `shield` held | no lift (stays under the bar), spread x0.88 | 0.93x pace, blockable |
| chip | `skill_move` held + lob | apex 2.6 to 4.1 m over a keeper off his line | slow, distance error |

Contexts (automatic): **volley** (ball 0.35 to 1.25 m up; technique from volleys, composure and balance; a poor high
contact skies it), **half volley** (rising within 0.18 s of the bounce), **first time** (uncontrolled ball arriving
5+ m/s faster than the shooter). Off balance: spread x1.4. AI (`AdvancedAI.technique_for`): normal stays the most
common. Chip when the keeper is 5+ m off his line, low driven under pressure close in, finesse from an angle with good
curve, power from 21+ m with good shot power. EASY never chips or curls.

## Headers and aerial play

The header window opens when the predicted closest approach of a ball in the air is within 1 m of the player,
between 1.2 m and his reach (0.93 x body height + jump of 0.25 to 0.7 m from jumping), within 0.95 s.
shoot / pass / lob (and through / cross) ask for a header shot / pass / clearance. The jump is timed to meet the
ball. A late press jumps at once (lower timing quality: more error, less power). Contact is geometric: the ball must
come within 0.4 m of the head point of the real (jumping) body, so a ball out of reach is never headed. Contests:
`AerialArbiter` (heading 0.3, jumping 0.3, strength 0.2, height 0.15, timing 0.15, position 0.1, noise 0.3); the
loser does not touch the ball and is briefly off balance. AI: the two players of each side nearest to where the ball
comes down to head height (within 12 m) attack that spot. In the window they head for goal in the opponent box,
clear within 30 m of their own goal, and pass to a team-mate otherwise.

## Physical duels

Opposing outfield players within 0.74 m of each other, at least one moving faster than 1.5 m/s, have a shoulder
challenge (per pair every 0.9 s). Power = strength 0.45 + balance 0.25 + mass 0.15 + momentum into the contact 0.15
(minus 0.15 when already off balance). Win chance = 0.5 + 1.6 x the difference, clamped 0.1 to 0.9, so nobody wins
every duel. The loser is nudged up to 2 m/s along the contact and off balance (72 % pace) for 0.3 to 0.5 s.
A carrier who loses one also loses his skill move.

## Animations

| Mechanic | v2 model clip (reused) | classic model |
|---|---|---|
| side moves (step-over, feints, elastico, croqueta, roulette) | TurnLeft / TurnRight at the start | none |
| double step-over, heel-to-heel | Accelerate | none |
| drag back, stop and turn | Decelerate | none |
| ball roll | BallControl | none |
| fake shot / fake pass | Shoot / Pass wind-up, cut at 0.22 s | Shoot / Pass wind-up, cut |
| header | Header | none |
| shots (all techniques) | Shoot | Shoot |

**Missing assets (not faked):** dedicated clips for step-over, elastico, roulette, drag back, heel-to-heel, la croqueta
and ball roll (the foot never visibly circles or drags the ball), a shielding stance, a jump for the classic model
(the body rises physically, the classic model has no jump pose), a shoulder-charge reaction and a stumble / recovery
clip, and bicycle / scissor kicks. Foot placement (IK) does not exist in the project.

## Not implemented (on purpose)

- Acrobatic shots (bicycle, scissor), rabona, rainbow flick, flicks over the head: no animation could show them.
- KING CONTROLLER phone page: no SKILL / SHIELD buttons yet (protocol whitelist unchanged).
- The in-match control hint bar does not list the two new keys.
- Human defenders get no help reading feints (by design: they read them themselves).
