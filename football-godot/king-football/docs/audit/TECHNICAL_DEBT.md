# KING FOOTBALL — Technical Debt Register

Date: 2026-11-17 · HEAD `9fdb5bb` · Supersedes rows of `docs/TECHNICAL_DEBT.md` after re-verification.

| ID | Sev | Debt | Where | Evidence | Payoff plan |
|----|-----|------|-------|----------|-------------|
| TD1 | M | `MatchManager` god-object | `scripts/systems/match/match_manager.gd` (924 lines) [READ] | Down from 1064 after PR #40 moved advantage into `MatchRules`; still 69+ funcs and pause/controller/substitution glue | Extract only cohesive blocks behind existing suites; require full quick suite green + `sim_fingerprint` unchanged before/after |
| TD2 | M | Difficulty has no decision-quality dimension | `match_manager.gd:25` (`THINK_INTERVAL`), `player_ai.gd:46`, `manager_ai.gd:15-35` [READ] | Think interval + sprint gate + manager timing only | Add per-profile decision-noise/option-evaluation parameters (F3); keep physics identical; verify with `tools/sim_matches.tscn` stat table across difficulties |
| TD3 | M | No agent representation in transfers economy | `scripts/systems/transfers/` (0 hits for agent/commission) [READ] | F5 | Ledger-booked agent fee on signing/renewal, covered by `transfers_v2_validation` + ledger audit |
| TD4 | M | Controller lacks layouts/profiles/haptics; plain no-TLS LAN transport | `controller_page.html`, `controller_protocol.gd` [DOC] | F7 | Client-side layout/profile storage first (no protocol change); keep `KING_CONTROLLER_SECURITY.md` threat model current |
| TD5 | M | Save size growth not plateauing | `save_manager.gd` SAVE_VERSION 3 [READ] | 780 KB at season 10 [DOC]; `tools/profile_save.tscn` exists | Profile on Windows; if change needed, additive fields + migration + suite evidence |
| TD6 | L | Sparse error logging (11 push_error/warning across 230 files) [DOC] | `scripts/` | F12 | Add logging at I/O boundaries only (save/load/network); assert log content in tests |
| TD7 | L | No body-part contact model for fouls/handball | `match_rules.gd` (fouls only from tackle rolls) [READ] | Blocks F1 handball | Prerequisite design: arm hit shapes + ball-contact tagging; then reuse foul/free-kick path. Do NOT ship a dice-roll handball |
| TD8 | L | Doc drift across README/FEATURE_STATUS/MASTER_ROADMAP/plan.md | root + docs [DOC] | F10/B3 | Reconcile per phase; `docs/audit/` is this cycle's truth |
| TD9 | H | Android: Gradle build never executed, no device run | `export_presets.cfg`, `tools/export_android.sh` [DOC] | F8 | Run the export script on a host with the Android SDK; device QA checklist in `docs/ANDROID_RELEASE.md` |
| TD10 | L | `plan.md` stale (2026-11-11, Arabic) | root [DOC] | — | Replace with a pointer to the roadmap or refresh |

## Explicitly not debt

- Renderer split (`gl_compatibility` everywhere + D3D12 driver on Windows) — deliberate for Android parity.
- `ESTIMATED` xG labelling — a correctness feature, keep it.
- Refusal of newer save versions — keep.
