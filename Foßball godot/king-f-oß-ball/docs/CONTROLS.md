# KING FOOTBALL — Controls

Actions are defined in `project.godot` (`[input]`). The player controller
(Phase 2) reads the movement + sprint actions; the gameplay node
(Phase 4, `FootballActions`) now consumes the pass/shoot/lob/dribble
actions; camera toggle and pause remain scene-level.

| Action | Keyboard | Gamepad | Consumer |
|---|---|---|---|
| move_forward | `W` · `Up` | Left stick up (axis 1 −) | **Player controller** |
| move_backward | `S` · `Down` | Left stick down (axis 1 +) | **Player controller** |
| move_left | `A` · `Left` | Left stick left (axis 0 −) | **Player controller** |
| move_right | `D` · `Right` | Left stick right (axis 0 +) | **Player controller** |
| sprint | `Shift` | Right stick click (button 7 - pad) | **Sprint system** + dribble speed boost* |
| pass | `Space` | Button 0 (bottom/A) | **Phase 4 gameplay** — hold to charge, release to kick |
| shoot | `E` | Button 1 (right/B) | **Phase 4 gameplay** — hold = power + elevation |
| lob_pass | `Q` | Button 3 (top/Y) | **Phase 4 gameplay** — aerial pass |
| dribble | `C` | Button 2 (left/X) | **Phase 4 gameplay** — hold to control the ball |
| through_pass | `R` | Button 8 (right stick press / R3) | **P3 gameplay** — through ball into a team-mate's run (aim assist) |
| cross | `T` | Button 15 (touchpad/Share) · Button 13 (d-pad left) | **P3 gameplay** — cross into the box (aim assist) |
| tackle | `F` | Button 10 (left stick press) | No (mapping only, later phase) |
| switch_player | `Tab` | Button 9 (right stick press) | Debug only: test scene reset** |
| camera_toggle | `V` | Button 4 (Back/Select) | **Yes** — toggles BROADCAST ↔ FOLLOW |
| pause | `Esc` | Button 6 (Start) | **Yes** — stadium/test scene → menu (back) |

Menu navigation: mouse click, or keyboard focus (↑/↓ + Enter) to Select Start /
Quit. `Esc` in the main menu is ignored (menu is the root state in Phase 1).

## In the player controller test scene

`WASD`/arrows or left stick move the player; `Shift` sprints; `V` toggles
camera; `Tab` teleports the player back to the centre spot (debug only);
`Esc` returns to the main menu. HUD shows the live movement state and speed.

## In the stadium prototype

- `V` — toggle camera mode; HUD label reads "Camera: Broadcast / Dynamic (V to toggle)"
- `Esc` — back to main menu

*deadzone 0.2 for movement axes, 0.5 for button actions. Sprint is a hold
action with no stamina cost; it also boosts dribble control while carrying
the ball. **real player switching is a later phase.

## Gameplay kick semantics (Phase 4)

- **Quick tap** (hold < 0.12 s) = the action's default power (pass 9 m/s,
  shoot 16 m/s, lob 7 m/s).
- **Hold** ramps power up to max over 0.9 s (pass 16, shoot 26 + elevated,
  lob 12). The shoot elevation scales with the charge.
- Charges are mutually exclusive and cancel if the ball leaves the
  interaction window mid-hold. Cooldowns: pass 0.35 s, shoot 0.5 s,
  lob 0.6 s, through 0.4 s, cross 0.65 s.
- Direction follows movement input (camera-relative) blended toward the
  ball; standing still uses the player's facing.

## Through pass & cross (P3)

Both are charged kicks through the same pass/lob systems (no second ball
implementation):

- **Through pass** (`R` / R3): pass-family kick. The aim assist
  (`HumanAimAssist` → `PlayerAI.lead_point`, the AI's own logic) picks the
  most goal-advanced team-mate inside a 55° aim cone and aims into his run;
  with no candidate it falls back to a plain directional pass.
- **Cross** (`T` / touchpad or d-pad left): lob-family kick into the
  opponent box. The assist reuses `PlayerAI.cross_target`: the free
  team-mate in the box closest to the goal, aimed slightly ahead; without
  one it falls back to the plain lob direction.
- Both scale with the passing attribute and carry the same aim error as
  passes (P2 attribute modifiers).

## Touch play (P4, Android first)

On touch devices the match shows a virtual stick (bottom-left) and 8 action
buttons (bottom-right) plus a pause button (top-right), all offset into the
display safe area. They feed the **same** intent layer as the keyboard/gamepad
(`IntentProvider` driven mode), so gameplay behaviour is identical:

| Stick / button | Drives |
|---|---|
| Stick (drag) | move (+x right, −y forward — same convention as WASD) |
| SPRINT (hold) | sprint |
| TACKLE, SWITCH | tackle / switch_player (tap) |
| PASS, SHOOT, LOB, THR, CROSS (hold) | charged kicks — same charge/cooldown as the keyboard actions |
| II (top-right) | pause menu |

The layer only appears when `DisplayServer.is_touchscreen_available()`
(desktop play is never affected). Configuration and the Android export preset
are documented in [CROSS_PLATFORM_STRATEGY.md](CROSS_PLATFORM_STRATEGY.md).

## KING CONTROLLER (phone over local Wi-Fi)

A phone on the same Wi-Fi network can act as a second controller. The PC shows a QR code (main menu -> KING CONTROLLER); scanning it opens a browser page with the same virtual stick and 8 action buttons as the touch layer. Input is validated (version, token, sequence, freshness, rate limit, action whitelist) and fed into the shared human `IntentProvider` in driven mode, exactly like the touch layer. See [KING_CONTROLLER_ARCHITECTURE.md](KING_CONTROLLER_ARCHITECTURE.md).
