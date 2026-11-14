# Feature status

Same status words as CURRENT_PROJECT_AUDIT.md. Tests = headless suites in `tests/`.

## P4 — mobile foundations (Android first)
IMPLEMENTED (tested on desktop, **not device-built**: no Android SDK/device on this host).
Touch layer (`TouchControls` + `TouchJoystick`, owned by the MatchManager with the HUD) drives
the shared human `IntentProvider` in driven mode — same seam as KING CONTROLLER and the test
suites: stick bottom-left, 8 action buttons + pause bottom-right/top-right, safe-area offset,
localized labels (`TOUCH_*` in `translations/match.csv` ar/de/en). Active only on touch devices;
desktop keyboard/gamepad untouched. Config: `[input_devices]` emulate flags (explicit defaults),
`window/handheld/orientation="sensor_landscape"`. Android export preset in `export_presets.cfg`
(APK, arm64-v8a + armeabi-v7a, immersive, GL Compatibility) — **an APK has never been built
here; the device build is a P8 gate**. iOS documentation-only (no Apple machine). Tests:
`mobile_input_validation` **26** incl. an end-to-end touch-tap kick in a real match.
Regression: input_system 29, gameplay_feel 37, match_rules 33, phase4 159.
Docs: [CROSS_PLATFORM_STRATEGY.md](CROSS_PLATFORM_STRATEGY.md), [CONTROLS.md](CONTROLS.md).

## P3 — gameplay feel pass (through pass + cross, DLS-inspired)
IMPLEMENTED (tested, `gameplay_feel_validation` 30): the human now has the two kick actions the
AI already had, through the SAME ball systems (no second implementation). `through_pass`
(R key / gamepad R3) is a pass-family charged kick with aim assist reusing `PlayerAI.lead_point`
(most goal-advanced team-mate in a 55° aim cone, aimed into his run); `cross`
(T key / touchpad or d-pad left) is a lob-family charged kick with assist reusing
`PlayerAI.cross_target` (free team-mate in the box). Both scale with the passing attribute,
carry pass aim error, degrade gracefully to plain directional kicks without an assist or
candidate, and have their own cooldowns (0.4 s / 0.65 s in `BallActionConfig`).
`HumanAimAssist` (`scripts/systems/match/human_aim_assist.gd`) is dependency-injected: the
MatchManager creates one instance wired to live match state via a bound Callable and attaches
it to every human selection. First-touch quality (DLS-style): `AttributeModifiers.control_multiplier()`
(dribbling ±10 %) scales the reception damping/pull via `BallControlSystem.physics_tick`'s new
`quality` parameter, and `HumanAimAssist.pressure_quality()` degrades the touch when an
opponent is inside 4 m (linear to floor 0.8). Neutral without data or context — AI and
untouched Phase 4 behaviour are unchanged. Regression-checked: phase4 159, match_rules 33,
input_system 29, gameplay_feel_validation **37**.
Docs: [CONTROLS.md](CONTROLS.md) (new bindings + semantics), `HUD_MATCH_HINTS` in
`translations/match.csv` (ar/de/en).

## P2 — input system hardening (gameplay + cross-platform program)
IMPLEMENTED (tested, `input_system_validation` 29): the intent layer is now the single gameplay
input seam — `switch_player` and the human tackle read the shared `MatchManager.human_intent`
instead of `Input.*` directly; raw mode is byte-for-byte the old global-Input behaviour
(regression-checked by phase2 57, phase4 159, match_rules 33). Driven mode (the feeding contract
for touch UI and KING CONTROLLER remote input, same API as `AIIntent`) is implemented and tested.
Persisted input settings (movement/button deadzones, rumble) in `user://settings.cfg` section
`input`, applied at boot; goal rumble on connected joypads (`InputSettings.pulse`, setting-gated);
match-scoped device monitor with localized ar/de/en controller connect/disconnect overlay.
Docs: [INPUT_SYSTEM.md](INPUT_SYSTEM.md). Not done: touch input, remote controller transport,
per-device remap UI (later phases, see `docs/audits/GAMEPLAY_AND_CROSS_PLATFORM_AUDIT.md`).

## Phase 1 — core stabilization
IMPLEMENTED (tested): results screen, pause menu, match event/statistics pipeline, in-progress match save/load, end-to-end journey
(`phase7_end_to_end_validation`), career/competition update after a match. NEEDS_VERIFICATION: SaveSystem migration chain across all old versions.
## Phase 2 — advanced gameplay
IMPLEMENTED: movement, possession, dribbling, short/long/lob passing, shooting, first touch, goalkeeper, stamina, penalty shootouts.
IMPLEMENTED (tested, `match_rules_validation` 33): tackle (human `tackle` button and AI), attribute-based win chance, fouls (from-behind detection), free kicks (ball on the spot, 9.15 m clearance), penalties (spot and box cleared), yellow/red cards, send-off, HUD notices, statistics, report, results screen, save/restore of red cards. IMPLEMENTED (tested, `match_restarts_validation` 27): ball out of play (throw-in, corner, goal kick), offside (second-last-opponent rule, indirect free kick), counters in stats/report/results screen. MISSING: match injuries, adjustable assists. Limits: throw-ins and goal kicks restart with the ball placed at rest (no throwing animation); offside ignores 'interfering with play' without touching the ball; pending offside passes are not stored in match saves. Limits: the 'referee' is the rule code in `MatchRules`; there is no referee model or advantage rule; free kicks have no wall/set-piece animation; penalties are taken in open play, not as a shoot-out duel.
## Phase 3 — tactics and AI
IMPLEMENTED (tested, `phase8_tactics_validation` 20): formations, mentality, pressing, defensive line, NEW team width, build-up style and passing style now change AI pass choice and pressure response (they were stored but unused before), shoot range from mentality/style, AI manager difficulty (easy never adapts, normal from minute 70, hard from 60 and reads the opponent), opponent analysis from measured match statistics. AI attack improved after the game review (see TECHNICAL_DEBT 14; `ai_attack_validation` 21). Crosses, through balls, distance-based pass power and corrected shot aim added (TECHNICAL_DEBT 14; `ai_attack_validation` 37). MISSING: individual player instructions, adaptive tactics that learn across matches, set-piece routines. Limits: the AI reads only the current match's statistics.
## Phase 4 — career / manager
IMPLEMENTED (tested, `phase9_manager_validation` 25): manager profile (reputation, board confidence, contract, trophies, history), board objective from the club's rating rank in its division, season review from the real final position (met / partial / failed, champion, relegation), sacking, contract renewal / expiry, resignation, job offers by reputation (the weakest clubs always hire), taking a job (AppHub switches club and squads), save / load with old-save defaults, Career screen panel (ar/de/en). MISSING: staff management, training management beyond the academy, cup / continental objectives, financial objectives. Limits: only the league position is judged.
## Phase 5 — development / academy
IMPLEMENTED: academy, scouting, training, aging, retirement (`career_longevity_validation` 59). MISSING: mentoring, position changes, regional scouting depth.
## Phase 6 — transfers / finance
IMPLEMENTED (tested, `phase10_finance_validation` 22): ledger-audited finances, weekly sponsorship for every club (grows with reputation), `FinanceLedger.report()` (income / expense by category and week range), seller negotiation with counter-offers and a three-round limit, AI clubs trading in two transfer windows (weeks 1-6, 24-29) through the same `buy()` rules, deterministic, never touching the user's players. Market, contracts, wages, loans, renewals and matchday / prize revenue existed before. MISSING: agents and agent fees, bonuses and release clauses, loan conditions beyond the fee, player-side contract expectations beyond a minimum wage, a UI for the negotiation (it is an API now), a UI for the financial report.
## Phase 7 — world simulation
IMPLEMENTED (tested, `phase11_world_validation` 30): injuries (probability model seeded by match uid and player, reproducible) and suspensions (red card = 1 match, 5 yellows = 1 match) with weekly countdown and save / load, weekly background injuries, lineups repaired automatically (injured reserves no longer invalidate a squad), world event log, news built only from real state (transfers, injuries, bans, champions, promotions, relegations, dismissals) shown on the Career screen in ar/de/en, records computed from stored statistics (top scorer, most appearances, best rating, champions). Earlier: background league simulation, standings, promotion / relegation (`league_pyramid_validation`), AI squad upkeep and transfers (Phase 6). MISSING: club reputation changes over seasons, derby / rivalry news, dedicated news and records screens, suspensions carrying across matches of one week precisely (a ban lasts one calendar week). Limits: the transfer history stores only the week, so old transfers show in the current season.
## Phase 8 — stadium / atmosphere
IMPLEMENTED (tested, `phase13_presentation_validation` 40): the weather and time-of-day chosen in the match setup now take effect (before, the setup screen offered rain / fog and nothing happened): fog, a rain emitter, dusk / night lighting with four floodlights, a per-match copy of the environment; a crowd model whose loudness and mood (cheer / groan / boo / tense) follow real match events, louder for derbies and full stadiums; procedural crowd noise (synthesized, deterministic). IMPLEMENTED later: generated crowd ambience, goal cheer, groan and referee whistle (`MatchSounds`, see audio/README.md, 49 checks in `phase13_presentation_validation`; they load and are triggered by real events, but nobody has listened to them in a running game here). MISSING: club-specific chants, commentary, music, crowd visuals reacting (stands are static), weather effects on ball physics, stadium variety / customization / upgrades, flags and banners, entrance presentation. Limits: no audio assets exist; the noise is a synthesized bed.
## Phase 9 — visuals
IMPLEMENTED: appearances, kit patterns, 3D preview, cards, captain's armband. MISSING: badges, hairstyles, accessories, AnimationTree, LOD.
## Phases 10–12
Phase 10: PARTIALLY_IMPLEMENTED (leagues, domestic cups, tournaments; season awards implemented and tested in `phase12_awards_validation` 29: golden boot, player / goalkeeper / young player of the season, team of the season, computed from per-season statistics; statistics of matches simulated without the engine come from a documented statistical model, those of engine matches from real reports; NOT implemented: Player of the Month, Manager of the Season, Super Cup, national teams, World Cup). Continental club cup IMPLEMENTED and tested (`phase14_continental_validation` 20): 16 clubs from the five countries of the real data pack (best three of every top division, the rest by rating; later seasons use the previous final tables), four groups of four (single round-robin, weeks 8 / 14 / 20), quarter-finals / semi-finals / final in weeks 26 / 32 / 38, simulated through the normal calendar with the user's own matches left to play in 3D, champion in the news, saved with the career, new cup each season. Limits: the cup name is English only; no draw ceremony (groups are dealt by strength); no away-goals or extra rules beyond the shared knockout code; prize money is the generic competition reward; no continental qualification for lower tiers. Phase 11 (replay): PARTIALLY_IMPLEMENTED: a bounded recording buffer (10 s, 20 Hz, ~18 KB) and a slow-motion goal replay played with ghost bodies during the goal pause, skippable, tested in `phase13_presentation_validation`; MISSING: multiple camera angles, replay controls in the UI, highlights reel, commentary, line-up presentation. Phase 12 (multiplayer): NOT IMPLEMENTED by design; the architecture is documented in MULTIPLAYER_ARCHITECTURE.md.
## Last full run
see QA_STRATEGY.md for the latest run; importer unit tests 14 OK.

## P5 - KING CONTROLLER (cross-platform phone controller)
IMPLEMENTED (tested, controller_protocol_validation 25, controller_loopback_validation 21): PC-side pairing screen with one-time token + QR (KingQrEncoder), WebSocket server on port+1 with versioned input protocol (sequence, rate limit, freshness, slot auth), phone browser page with the same 8 action buttons and virtual stick, reuse of IntentProvider as the sink via KingControllerHub with per-tick edge discipline, multi-device slots (max 2), reconnect handling (token re-binds the slot). MISSING: TLS, real Android device test (P8), second-controller gameplay wiring beyond slot 0. Limits: HTTP page serving is standard but not verified in-process (Godot 4.7 StreamPeerTCP does not complete localhost handshakes in the same instance); Bluetooth is out of scope (P6).
