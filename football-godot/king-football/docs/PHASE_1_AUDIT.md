# PHASE 1 — Repository Audit (KING FOOTBALL)

Date: 2026-11-10 · Auditor: Phase 1 implementation run

## 1. Initial state

The repository already contained a **barely started Godot 4.7 project** (`project.godot`, `config/features = ("4.7", "GL Compatibility")`).

Files present before this phase:

| Path | State |
|---|---|
| `project.godot` | Valid minimal project config: name "KING-FOßBALL", GL Compatibility renderer, D3D12 RD driver entry, Jolt physics engine, canvas_items stretch mode. **No main scene configured, no InputMap actions, no autoloads, no window size.** |
| `main.tscn` | Editor scratch scene: one 50×1×50 box MeshInstance3D + StaticBody3D with a *disabled* CollisionShape3D. Not referenced by any setting. |
| `icon.svg` + `.import` | Default Godot icon. |
| `.gitignore`, `.gitattributes`, `.editorconfig` | Present. |
| `.godot/` | Editor cache (git-ignored). |

No scripts, no scenes with game purpose, no assets, no docs, no tests.

## 2. Problems discovered

1. No run/main scene → project would open an empty editor scene, not a game.
2. No InputMap actions → nothing prepared for Phase 2/3 gameplay controls.
3. `main.tscn` at project root is throwaway editor scratch work (test box), and conflicts with the required structure (`scenes/main/main.tscn`).
4. Project name string (`KING-FOßBALL`) is not the product name "KING FOOTBALL".
5. No documentation, no tests, no architecture.

## 3. Recommended changes (all applied in this phase)

- **Preserve** existing config values that make sense for a Windows desktop prototype: GL Compatibility renderer + Jolt physics + canvas_items stretch. Do not make arbitrary renderer changes.
- Configure `run/main_scene = res://scenes/main/main.tscn`, window size, autoload `GameManager`, and the full InputMap in `project.godot`.
- Keep root `main.tscn` untouched (harmless scratch scene); the real entry point is `scenes/main/main.tscn`. It can be deleted later at the user's discretion.
- Rename project to "KING FOOTBALL".
- Build the required structure (scenes/scripts/ui/resources/docs/tests) — files added in this phase are all listed in `docs/PHASE_1_REPORT.md`.

## 4. Implementation strategy

1. Configure project settings + InputMap first (foundation).
2. Add core scripts: GameManager (autoload), CameraConfig (Resource), GameCamera, FootballPitch (procedural), StadiumStands, TestTarget, menu UI scripts.
3. Build scenes that *use* those scripts: main scene → main menu; stadium scene → procedural pitch + two goal scenes + stands + camera + HUD.
4. Validate headless via Godot CLI (`--headless --editor --quit` for import/parse, and `tests/phase1_validation.tscn` for runtime assertions), then visually via screenshot runs (non-headless), then write reports.

## 5. Godot version

Implementation targets **Godot 4.7.2-stable (win64 editor)**, matching the project's `4.7` feature tags. A copy was downloaded to `C:\tools\godot\` purely for CLI validation — it is not part of the repo.
