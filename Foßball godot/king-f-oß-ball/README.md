# KING FOOTBALL

Stylized 3D football game prototype — **Godot 4.7.2**, built phase by phase
from the Arabic plan documents (`المرحلة الأول 1.txt`).

## Current status

**Phase 1 — Foundation: COMPLETE** (validated, 49/49 automated checks).

What Phase 1 delivers:

- Complete project structure (`scenes/`, `scripts/`, `ui/`, `resources/`, `tests/`, `docs/`)
- Procedurally built stylized stadium: full-size pitch (105 × 68 m) with all
  markings (boundary, halfway line, centre circle + spot, penalty areas,
  goal areas, penalty spots, corner arcs), two goals with posts/crossbar/nets,
  grandstands on 4 sides, floodlights, sky, shadows
- Reusable two-mode camera system: **BROADCAST** (elevated, fixed sideline
  perspective) and **DYNAMIC/FOLLOW** (damped chase camera) — toggled with `V`
- Full InputMap for 13 gameplay actions (keyboard + gamepad bindings each)
- Main menu with working Start Match / Quit flow
- Global `GameManager` autoload owning game state (`BOOT / MAIN_MENU / IN_MATCH`)
- Automated headless validation suite + scripted visual screenshot harness

## Requirements

- Godot **4.7.2 stable** (developed and validated on `Godot_v4.7.2-stable_win64.exe`)
- No external addons or assets — everything is code-generated

## Run

```text
# From the project folder:
godot --path .
# or open project.godot in the Godot editor and press F5.
```

## Validate (headless, no window)

```text
godot --headless --path . res://tests/phase1_validation.tscn
# Expected: "=== Validation summary: 49 passed, 0 failed ===", exit code 0.

# Visual captures (windowed, saves PNGs into assets/placeholders/validation/):
godot --path . res://tests/screenshot_runner.tscn -- menu
godot --path . res://tests/screenshot_runner.tscn -- stadium
godot --path . res://tests/screenshot_runner.tscn -- stadium_follow
```

## Controls (Phase 1)

`WASD`/arrows move · `Shift` sprint · `Space` pass · `E` shoot · `Q` lob pass ·
`C` dribble · `F` tackle · `Tab` switch player · `V` toggle camera · `Esc` back/pause.
Full table incl. gamepad bindings: [docs/CONTROLS.md](docs/CONTROLS.md).

## Documentation

- [docs/PHASE_1_REPORT.md](docs/PHASE_1_REPORT.md) — what was built, tested, and known limitations
- [docs/PHASE_1_AUDIT.md](docs/PHASE_1_AUDIT.md) — initial repository audit
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — code/scene structure and design decisions
- [docs/CONTROLS.md](docs/CONTROLS.md) — input map reference
- [docs/PHASE_2_HANDOFF.md](docs/PHASE_2_HANDOFF.md) — where to pick up for Phase 2

Phases 2+ (players, ball physics gameplay, AI, audio, polish) are **not started** per plan.
