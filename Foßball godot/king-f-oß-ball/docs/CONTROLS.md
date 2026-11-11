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
  lob 0.6 s.
- Direction follows movement input (camera-relative) blended toward the
  ball; standing still uses the player's facing.
