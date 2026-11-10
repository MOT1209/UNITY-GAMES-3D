# KING FOOTBALL — Controls (Phase 2)

Actions are defined in `project.godot` (`[input]`). Phase 2 adds the first
gameplay consumer: the player controller reads the movement + sprint actions;
camera toggle and pause remain scene-level. The ball actions stay guaranteed
mappings for Phase 3.

| Action | Keyboard | Gamepad | Consumed in Phase 2 |
|---|---|---|---|
| move_forward | `W` · `Up` | Left stick up (axis 1 −) | **Yes** — player controller |
| move_backward | `S` · `Down` | Left stick down (axis 1 +) | **Yes** — player controller |
| move_left | `A` · `Left` | Left stick left (axis 0 −) | **Yes** — player controller |
| move_right | `D` · `Right` | Left stick right (axis 0 +) | **Yes** — player controller |
| sprint | `Shift` | Right stick click (button 7 - pad) | **Yes** — sprint system* |
| pass | `Space` | Button 0 (bottom/A) | No (mapping only, Phase 3) |
| shoot | `E` | Button 1 (right/B) | No (mapping only, Phase 3) |
| lob_pass | `Q` | Button 3 (top/Y) | No (mapping only, Phase 3) |
| dribble | `C` | Button 2 (left/X) | No (mapping only, Phase 4) |
| tackle | `F` | Button 10 (left stick press) | No (mapping only, later) |
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
action with no stamina cost in Phase 2. **real player switching is later phase.
