# KING FOOTBALL — Controls (Phase 1)

Actions are defined in `project.godot` (`[input]`). Phase 1 wires only the camera toggle
and menu navigation into gameplay code; the rest are guaranteed mappings for Phase 2.

| Action | Keyboard | Gamepad | Consumed in Phase 1 |
|---|---|---|---|
| move_forward | `W` · `Up` | Left stick up (axis 1 −) | No (mapping only) |
| move_backward | `S` · `Down` | Left stick down (axis 1 +) | No (mapping only) |
| move_left | `A` · `Left` | Left stick left (axis 0 −) | No (mapping only) |
| move_right | `D` · `Right` | Left stick right (axis 0 +) | No (mapping only) |
| sprint | `Shift` | Right stick click (button 7 - pad) | No (mapping only)* |
| pass | `Space` | Button 0 (bottom/A) | No (mapping only) |
| shoot | `E` | Button 1 (right/B) | No (mapping only) |
| lob_pass | `Q` | Button 3 (top/Y) | No (mapping only) |
| dribble | `C` | Button 2 (left/X) | No (mapping only) |
| tackle | `F` | Button 10 (left stick press) | No (mapping only) |
| switch_player | `Tab` | Button 9 (right stick press) | No (mapping only) |
| camera_toggle | `V` | Button 4 (Back/Select) | **Yes** — toggles BROADCAST ↔ FOLLOW |
| pause | `Esc` | Button 6 (Start) | **Yes** — stadium → menu (back) |

Menu navigation: mouse click, or keyboard focus (↑/↓ + Enter) to Select Start /
Quit. `Esc` in the main menu is ignored (menu is the root state in Phase 1).

## In the stadium prototype

- `V` — toggle camera mode; HUD label reads "Camera: Broadcast / Dynamic (V to toggle)"
- `Esc` — back to main menu

*deadzone 0.2 for movement axes, 0.5 for button actions.
