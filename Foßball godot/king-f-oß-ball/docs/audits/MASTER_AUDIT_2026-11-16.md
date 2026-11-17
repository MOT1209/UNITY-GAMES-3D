# KING FOOTBALL — Master audit (Phase 0, revised 2026-11-17)

Repo state audited: branch `ccr-a4b966c9-7papge`, HEAD `34c1bb8` (merge of PR #39), clean tree. Engine: Godot 4.7.2
(official Linux binary downloaded and run headless). This revision supersedes the 2026-11-16 audit written at `1ec4565`;
several of its numbers had drifted (e.g. `match_manager.gd` is now 1064 lines, not 900).

Evidence labels: **[RAN]** executed in this session · **[READ]** source read/grep'd in this session · **[DOC]** taken from
existing docs only, not re-verified. Nothing here changed game code.

## 0. Test baseline [RAN]
`tests/run_all.sh --quick godot` → **5518 checks passed, 0 failed, 0 suites failed** (99 test scripts, 92 `*_validation`
scenes, duplicate-`class_name` guard and "every suite is registered" guard both green). `--full` (same session, Linux, software renderer): **5841 passed, 3 failed, 1 suite failed** —
`career_p1_long_validation`: save size at season 10 (780 KB, "stays bounded" check), real-pack `advance_week()` 645.5 ms vs 350 ms budget,
46-week season 29.7 s vs 18 s budget. Not diagnosed; the two timing failures were measured on a shared software-rendered container.
What this does **not** prove: rendering on a real GPU, Android runtime, real phones/Wi-Fi, audio, or football *quality*
(the suites assert logic and state, not how matches feel).

## 1. Architecture [READ]
Autoloads `Loc`, `GameManager`, `TeamDB`, `AppHub`. 230 GDScript files / ~40.9k lines under `scripts/`.
Domains in `scripts/systems/*` (academy, career, competitions, controller, crests, finance, flags, generation, input,
match, promotion, scouting, squads, teams, tools, training, transfers). On-pitch layer: `scripts/ball`, `gameplay`,
`player`, `players`. Match core: `MatchManager` (1064 lines, 69 funcs) delegating to `MatchRules`, `MatchRestarts`,
`MatchReferee`, `MatchStats`, `MatchReport`, `MatchSnapshot`, `MatchAIDriver`, `TeamAI`, `PlayerAI`, `ManagerAI`,
`Replay*`, `MatchSave`. Save: `save_manager.gd`, `SAVE_VERSION = 3` with step-wise migration and refusal of newer saves.
Controller: `scripts/systems/controller/*` + `assets/controller/controller_page.html`, protocol v3 (4096-byte frames).
CI: `.github/workflows/king-football-tests.yml` (at repo root) downloads Godot 4.7.2 and runs `run_all.sh`.

## 2. Verified implemented [READ]/[RAN]
Match loop, fouls/cards, free kicks, penalties + shoot-out, throw-ins, corners, goal kicks, offside (`match_rules.gd`,
`match_restarts.gd`; suites `match_rules_validation`, `match_restarts_validation`, `match_flow_validation` green);
team tactics + 6 individual instructions (`team_ai.gd`, `data/tactics_preset.gd`, `tactics_screen.gd`); event log with
positions, shot map and timeline in `MatchState`/`MatchReport`; event-driven commentary (`match_commentary.gd`, 64 lines);
replay buffer/director/player; Transfers v2 (`transfer_market.gd`, 1967 lines); league pyramid, promotion/relegation,
continental competitions (suite `phase14_continental_validation`); finance ledger; academy/scouting; manager profile,
board objectives, news, awards, national breaks (`national_breaks.gd`); ar/de/en localization with RTL;
KING CONTROLLER pairing, sessions, two phones, pause, live-data frames (protocol v3). Android presets exist with
min SDK 24 / target 36, arm64 + armv7 (`export_presets.cfg`), packaged by `tools/export_android.sh`.

## 3. Findings
Severity: C critical · H high · M medium · L low.

| # | Sev | Finding | File / symbol | Explanation | Repair | Verification |
|---|---|---|---|---|---|---|
| F1 | H | **Handball rule missing** | `scripts/systems/match/match_rules.gd`, `match_referee.gd` | grep for `hand` in the match rules/referee finds only the throw-in comment (line 213). No handball detection exists. | Read of `match_rules.gd` shows fouls arise **only** from tackle rolls (`resolve`, `foul_roll`); players have no arm/hand collider, so the engine cannot observe a hand-ball contact. A handball built today would be a dice roll presented as a rule, which the master prompt forbids. Prerequisite: ball-contact body-part data (e.g. arm hit shapes on the player body) — then reuse the foul/free-kick/penalty path. | New cases in `match_rules_validation`; sim run showing handball events in the log. |
| F2 | H | **Advantage rule missing** | `match_rules.gd` / `match_referee.gd` | `advantage` appears only in `match_simulator.gd` (home advantage) and in free-agent naming; the engine never plays on after a foul. | Delay the whistle for a bounded window when the fouled team keeps the ball in a promising position; call the foul if it is lost. | Rules test + event-log assertion. |
| F3 | M | **Difficulty changes only think-interval and sprint** | `match_manager.gd:25` `THINK_INTERVAL`, `player_ai.gd:46`, `manager_ai.gd` | It does not touch passing/shot decision quality or positioning. Prompt Phase 3 wants measurable decision-quality profiles. The absence of physical cheating is good; the depth is thin. | Add decision-noise/option-evaluation parameters per profile; keep physics identical. | `tools/sim_matches.tscn` across difficulties, compare shots/pass accuracy/turnovers. |
| F4 | M | **No xG, heatmap or passing network** | `match_stats.gd`, `match_report.gd` | `shot_map` and `timeline` exist; no `xg`, no heatmap, no pass graph (grep: 0 hits). Event log already carries positions, so these can be *measured* rather than invented. | Compute xG from recorded shot position/body part with a documented formula, label as an estimate; heatmap/pass network from events. | Unit tests on synthetic event logs with known outputs. |
| F5 | M | **Agents / agent fees missing** | `scripts/systems/transfers/` | Only free-agent references; no agent entity or commission. Release clauses, loans and instalments exist. | Add agent fee as a ledger-booked cost on signing/renewal. | `transfers_v2_validation` cases + ledger audit. |
| F6 | M | **`MatchManager` is the debt hotspot** | `match_manager.gd` | 1064 lines, 69 funcs; already delegates much. Further splitting is possible but risky without behavioural tests of feel. | Extract only cohesive blocks (e.g. substitution/pause/controller glue) behind the existing suites. | Full suite green before and after, `sim_fingerprint` unchanged. |
| F7 | M | **Controller: no custom layouts, profiles, haptics settings, tactics/substitution from phone, tutorial** | `controller_page.html`, `controller_match_data.gd` | Mini-map/live data exist (v3); the rest of Phase 9 is absent. Transport is plain local-network, **no TLS**. | Client-side layout/profile storage first (no protocol change). Document the no-TLS threat model (`KING_CONTROLLER_SECURITY.md`). | `controller_page_browser_test.js`, then real-device QA. |
| F8 | H | **No real-device verification of Android, controller, or performance** | — | APKs are built and signed [DOC], but never run on a phone or emulator. All timing numbers are software-rendered (llvmpipe) and are not evidence of device FPS. | Needs hardware; cannot be done in this container. | Device test log, `adb shell dumpsys gfxinfo`. |
| F9 | L | **Two-human Pause/Resume flake reported on Windows** | `controller_registry.gd` `apply_input`, `match_manager.toggle_pause_from_controller` | Not reproduced on Linux (prior audit: 14/14 pass; `two_human_validation` green again here). No fix is justified without a failing trace. | Add logging at the failing check on the Windows host. | Repeated runs on Windows. |
| F10 | L | **Documentation drift** | README, `FEATURE_STATUS.md`, `MASTER_ROADMAP.md`, `plan.md` | Different docs give different line counts and say different things about what is built; `plan.md` is largely Arabic and dated 2026-11-11. | Reconcile after each phase. | Manual diff against this audit. |
| F11 | M | **Save size / structure** | `save_manager.gd` | Career JSON is ~8 MB [DOC]; migration exists (v0→3). Risk is size and load time, not a known corruption. | Measure with `tools/profile_save.tscn` before changing anything. | Save/migration suites + profile. |
| F12 | L | **Sparse error logging** | whole `scripts/` | Only 11 `push_error`/`push_warning` calls in 230 files; failures often surface as returned error dictionaries. | Add logging at I/O boundaries (save, load, network) only. | Log inspection in tests. |

Not found broken: no failing suite, no duplicate `class_name`, no unregistered suite. The prompt's Phase 1 premise
("fix runtime errors and broken references") therefore has **no failing evidence to act on** at this commit.

## 4. Save compatibility [READ]
`SAVE_VERSION` is 3; older versions are migrated step by step; newer versions are refused with an error. Any new
persisted field must be additive with a default and be covered by `db_migration_validation`/`world_save_consistency_validation`.

## 5. Networking / security [READ]/[DOC]
Pairing uses one-time tokens from `Crypto.generate_random_bytes`, a TTL, arrival-time rate limiting, heartbeat timeout,
sequence-jump and held-button limits (`controller_protocol.gd`, `controller_registry.gd`). Transport is unencrypted
local-network WebSocket/HTTP — acceptable for a LAN controller only if documented as such (F7). No Bluetooth support exists
and none is claimed.

## 6. Performance
Software-renderer numbers only. No optimisation is justified without a device/GPU profile (F8).

## 7. Prioritised plan
1. Finish `--full` run; record in `STABILIZATION_REPORT.md`.
2. F1 handball and F2 advantage, each with tests and event-log evidence (smallest rule gaps, high realism value).
3. F4 xG/heatmap/pass network from recorded events, labelled measured vs estimated.
4. F3 difficulty profiles with a before/after `sim_matches` table.
5. F5 agents via the existing ledger; F7 controller layouts/profiles.
6. F6 only where tests protect behaviour. F8 blocked on hardware.
Phases 4–7 and 10 of the master prompt are large feature programmes; each needs its own scoped session and cannot be
honestly called "done" from this audit.
