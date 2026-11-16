# Feature status

Same status words as CURRENT_PROJECT_AUDIT.md. Tests = headless suites in `tests/`.

## Round 3 (2026-11-15): residual bugs, flags + card data, card redesign, player visuals
Before/after shots: `docs/qa/round3/` (camera, flags, `before/` and `after/` screens in ar + en at 1280x720 and 2400x1080),
card matrix `docs/qa/cards/` (5 categories x outfield / goalkeeper x ar / en), portrait grids `docs/qa/players/`.

**Tests**: `tests/run_all.sh --full` (all suites incl. the long career / performance ones): 4,755 passed, 2 failed — both in
`player_visual_integration_validation`, tests that pinned the old appearance shape (forced `hair_style`/`skin` instead of the v3
`cut`/`tone`) and the old clip count (9; `PortraitIdle` makes 10). Both fixed to test the intent (stored appearance drives the
match look; reaction clips fit the goal pause); the suite re-run alone: 72 / 72.

**Data change (owner request, 2026-11-15)**: Israel removed from the game — country record, flag files, flag mapping and
translation, and the 4 Israeli players of the real pack (Villarreal, Levante, Hamburger SV, Lecce; each squad 30 -> 29,
Hamburg keeps two goalkeepers). Counts now: 115 countries (111 real + 4 fictional), 8,009 players (2,863 real). Tests updated.

**A — residual bugs** (IMPLEMENTED, tested)
* Cedar City crest: already restored by `4eb19b7` (file + `.import` match). NEW: `crest_assets_validation` reads every
  club JSON (default world and every data pack, incl. the `team` object) and fails on a `logo` that names a missing file.
* `controller_qr_validation`: already registered in `SUITES` by `4eb19b7`; the run_all guard passes.
* Broadcast camera: the look point now follows the ball across the pitch completely (`broadcast_track_x_factor` 0.35 -> 1.0,
  `broadcast_track_speed` 2.5 -> 3.5 in `arena_camera_config.tres`). New suite `camera_framing_validation` plays 40 s of an
  AI-vs-AI match and projects the ball every frame: 99.9 % of frames between 35 % and 65 % of the screen height (was 71.8 %;
  the ball drifted to the bottom whenever it was on the near side). Shots: `docs/qa/round3/camera/`.
* `export_presets.cfg`: `gradle_build/min_sdk` = 24, `target_sdk` = 36 (Google Play: API 36 for new apps / updates since
  31 Aug 2026). Godot refuses any SDK override without a Gradle build, so `use_gradle_build` is now on and
  `tools/export_android.sh` installs the build template (`android/`, git-ignored). `release_readiness_validation` checks the
  values, the Gradle flag and the script. NOT DONE: a real Gradle export (no Android SDK in this environment) — run the
  script once before the next release.

**B — country, flag, club on the card** (IMPLEMENTED, tested: new suite `flags_validation` 24 checks)
* 115 flags in `assets/flags/<id>.png` (128x84) and `<id>_64.png` (64x42); `flag_asset` filled for every country.
  Real countries: flag-icons 7.6.0 (MIT, licence shipped next to the files), rasterised by `tools/build_flags.tscn`.
  Fictional countries: `FlagGenerator` (deterministic designs, files rebuildable). Sources in `DATA_SOURCE_AND_LICENSES.md`.
* `FlagService.texture(country_id, small)` with a cache and a neutral grey fallback flag showing the 3-letter code.
* 100 % of players have a known `nationality_id` (276 fictional-world, 8,009 real-pack players; no exceptions).
* 106 country names translated (ar / de / en; were English-only); `Loc.country_key()` handles commas / apostrophes.
* `PlayerCardData` adds country id / translated name / flag, club crest / name, league name, last name, birth year, height,
  weight, preferred foot, secondary positions, potential, traits, contract, wage, market value, fitness, morale, loan,
  captain flag, badges, last match ratings.

**C — card redesign** (IMPLEMENTED, tested: `player_card_validation` 233 checks, `ui_layout_validation` +20)
* Full card (aspect 1 : 1.4): rating, position, flag (~28x19) and crest (~26x26) in the first top corner — mirrored to the right
  in Arabic; uncropped head-and-shoulders portrait on a gradient panel in the category colour; last name (shrinks to fit,
  ellipsis only at the minimum size) + shirt number; 2x3 grid of big value + fixed 3-letter abbreviation (new
  `CARD_ABBR_*` keys, exactly 3 letters in ar / de / en; goalkeepers get GKP / DEF / PHY / PAS / PAC / DRI); footer
  "club · league" (ellipsis); badges for injured, suspended, on loan, captain, under 21 and potential >= rating + 5.
* Pitch card (minimal): rating, position, small flag, portrait, last name. The squad pitch is no longer locked to 0.8: it fills
  the width beside it (ratio 1.25), cards grew from ~55 px to ~90 px wide at 1280x720, names >= 12 px (tested).
* Detail panel (click a card in the collection, or the card in the player profile): full name, flag + country, crest + club
  + league, age and birth year, height and weight, foot, positions, number, rating / potential, contract years + weekly
  wage, market value, status, fitness and morale bars, traits as chips, last 5 match ratings from the career log.
* Categories: five distinct palettes (bronze, silver, gold, teal "elite", red/gold legendary); every text colour >= 4.5:1
  against every background of its class (lowest: 5.0). Animated gloss shader only on gold / elite / legendary and off
  when the graphics level is "off" (`GameSettings.is_low_performance()`).
* Tests: every content node inside the card, every label's line height inside its box, fixed texts never trimmed, the
  longest name in the data ("Ayoube Amaimouni-Echghouyab") at 150 / 220 / 300 px in ar / de / en.
  Design: original layout and drawing; no EA FC / FUT shapes, fonts or logos.

**D — player visuals** (IMPLEMENTED in code with procedural pieces, tested: `player_visual_validation` 171 checks; see
`PLAYER_VISUAL_QA_REPORT.md` "Update 3")
* `PortraitIdle` static clip (arms relaxed, both rigs) — keepers no longer raise an arm on their card; camera anchored on the
  Head bone; three-point lighting (warm key, cool fill, rim) + low ambient, linear tone mapping, no auto exposure.
* Face: ears, nose bridge + tip + nostrils, eyelid creases, lower lip, 4 jaw shapes x 5 head shapes, 12 skin tones, 5 eye colours.
* 14 haircuts (5 model meshes + 9 sculpted: wavy, curly, braids, ponytail, man bun, mohawk, dreadlocks, side part, flat top),
  beard styles none / full / stubble / goatee / moustache / chin strap / moustache + goatee; vertex-shaded, rim-lit hair.
* Body / kit: proportions from real height / weight when known, fabric-fold normal map on shirt and shorts (portraits / preview only), long sleeves for
  ~20 % of outfield players, name on the back above the number, per-player boot colour (unchanged), keeper gloves (model).
* Identity: appearance v3 (own RNG streams; golden signatures tested); v2 records upgrade to v3 with an identical look.
* LOD: face <= 30 m, sculpted hair / beards <= 22 m, back name <= 18 m, sleeves <= 35 m; the model's base hair mesh stays far away.
NOT DONE: a new Blender base model with shape keys (no Blender here); faces and hair remain stylised low-poly primitives.
Performance: measured on this machine (software GL, llvmpipe — not a phone GPU; numbers are relative). Match, AI vs AI, broadcast view,
300 frames: average frame 172.3 ms over 4 runs vs 172.0 ms baseline over 3 runs (+0.2 %, inside the run-to-run spread of
159-184 ms). A first version cost +15-20 %; the fabric-fold normal map is therefore portraits / 3D preview only
(`PlayerCharacterVisual.fabric_folds`), and sculpted hair (22 m) and the back name (18 m) got tighter near-camera LOD.
`db_performance_validation` 16/16; `load_world` best of 5: 503 ms vs 501 ms (+0.4 %; medians vary +-12 % between runs);
`PlayerAppearance.ensure` over all 8,013 players +20 ms (69.6 -> 89.1 ms); save file 9.9 -> 10.6 MB (+7 %, the five new
appearance fields — the one metric above 5 %).

## UX fix program round 2 (2026-11-15): scrolling, squad screen, header, numbers
IMPLEMENTED (tested; new suite `ui_scroll_validation` 16 checks, `squad_pitch_validation` 63, extended `localization_validation` / `arabic_ui_validation`; before/after shots ar+en at 1280x720 and 1600x720 (= 2400x1080 phone) in `docs/qa/round2/`):
* **Scrolling (task 0)**: `HubRoot.navigate()` wraps every screen in a vertical `ScrollContainer` (`follow_focus`, touch deadzone 12) unless the screen sets `own_scroll = true` (those that already lay out their own scroll: team select / details, collection, training, promotion, finance, leagues, bracket, database, settings, career wizard, squad). No scroll inside scroll; a new screen opens at the top; `rebuild()` keeps the position. Transfers, academy, career, profile and the other screens that were cut off are now fully reachable. `ui_scroll_validation` checks every screen x ar/en x 1280x720 / 1600x720. NOT verifiable here: real touch drags (the headless engine has no touchscreen, so a synthetic `InputEventScreenDrag` is never delivered to a `ScrollContainer`); the suite asserts the conditions instead (deadzone, vertical-only, `PlayerCard` passes input on) — test swiping over transfer rows on a phone.
* **Squad screen (task A)**: one screen without scrolling. Pitch fills the height (aspect 0.8, goalkeeper and all lines always visible, cards >= 48 px), bench panel beside it (7 substitutes always visible, reserves collapsible), formation dropdown + auto-pick + "Roles" dialog + slot-list toggle in one bar with the title. Tap a starter then a substitute (or the reverse) to swap, or drag one onto the other (desktop); the substitute rows show a green / yellow / red position-fit bar for the selected slot, the pitch rings the selection. Role badges (C, P, FK, CK) on the pitch cards. Duplicate "starting cards" strip removed. Per-slot dropdown list kept hidden as an accessible alternative. All edits through `Squad` (new `swap_starters`, `ensure_roles`).
* **Set-piece takers** are never the goalkeeper by default: `Squad.ensure_roles` picks the best field player by attribute (shooting for penalties, shooting + passing for free kicks, passing for corners) after `auto_pick` / `start_career` / substitutions and when the screen opens (old saves).
* **Portraits**: `PlayerCard` retries a portrait whose first frames came out empty (5 x 0.25 s) instead of staying grey; `PlayerPortraitRenderer.player_portrait_ready(player_id, texture)` added next to the existing key-based `portrait_ready`. With a real renderer (xvfb + software GL) every starter's portrait arrives (checked in `squad_pitch_validation`; skipped headless).
* **Header (B)**: the top bar line is a forced right-to-left paragraph in Arabic ("... الموسم 1، الأسبوع 0" in order).
* **`Loc.decimal` (C)**: computed with integers; "82.0" / "82,0" and, for millions, `trim_zero` gives "82M" / "82 Mio." / "82 مليون" (was "82.M").
* **Season ranges (D)**: `Loc.isolate_years()` wraps "2025-26" in an LTR isolate (world picker in Settings; wizard fallback).
* **Cards (E1)**: stat block is two columns x three rows with a fixed value / caption gap (no more "72 تسديد49").
* **Team details (E2)**: "fictional club" / "real club" only (the extra "club" word is gone).
NOT CHANGED (checked): broadcast camera — in the captured match frames (`docs/qa`-style run, kick-off and 22 s) the centre circle / ball sit at mid-frame; no evidence of an empty lower third, so the config is untouched. `export_presets.cfg` min / target SDK — `docs/ANDROID_RELEASE.md` records that Godot only accepts these with a Gradle build (`use_gradle_build=false` now), and that the prebuilt template already ships minSdk 24 / targetSdk 36 (verified with aapt); filling them without Gradle is rejected, so they stay empty. Check the Play Console requirement before each release.

## UX fix program (2026-11-14) — phase 6: content
IMPLEMENTED (tested, suite `match_content_validation` 37 checks; real-window shots in `docs/qa/fixes/phase6`):
* Free-kick wall: direct free kicks within 32 m of goal line up 3 (4 inside 25 m) defenders 9.15 m from the
  ball on the line to goal, facing the ball (`MatchRules._build_wall`).
* Referee on the pitch (`MatchReferee`, `referee.glb`): follows play diagonally behind the ball, Idle / Walk /
  Run, whistle and card gestures; no collision body; one hair mesh drawn.
* Animated spectators (`StandCrowd` + `stand_crowd.gdshader`): raycast-placed silhouette cards in home / away /
  neutral colours, one draw call, jumping with the crowd model's excitement (goals); 1500 on phones, 4000 else.
* Throw-in: generated `ThrowIn` clip (both hands over the head, feet down) played by the taker, who faces the pitch.
* Multi-angle goal replay (`ReplayDirector`): the replay cuts from the TV angle to behind the goal to a close-up
  (thirds of the clip), then gives the view back to the match camera.
* Team walk-out (`MatchSetup.walkout`, set for matches started from the hub): both teams line up by the touchline
  at halfway and walk to their kick-off positions through their own intents (move_and_slide), under the TV
  camera; skippable with pass / accept; then kick-off.
* Penalty shoot-out on the pitch (`PenaltyDuel`) for level knockout matches with a human player: 5 kicks each,
  alternating, early decision, sudden death; the human takes his team's kicks with the normal shoot button (HUD
  prompt), AI kickers aim at corners with an error from their shooting attribute and a charged strike; the
  `TeamGoalkeeper` got a penalty mode (stays at his line depth, commits to a guessed side when the ball is
  struck); the waiting keeper stands in the other goal; the tally becomes the result's penalty score.
  AI-vs-AI and simulated matches keep the statistical `PenaltyShootout`.
Limits: the shoot-out success rate was not tuned against real-world rates (it depends on the physics of
each shot); there is no keeper control for the human; the walk-out has no tunnel geometry or music.

## UX fix program (2026-11-14) — phase 5: technical / release readiness
IMPLEMENTED (tested, new suite `release_readiness_validation` 27):
* Android preset: version 0.3.0, min SDK 24, target SDK 35 (gradle build fields), adaptive launcher icons
  rendered from a new game icon (`icon.svg` was the engine logo) by `tools/build_icons.tscn`; signing material
  only via `GODOT_ANDROID_KEYSTORE_RELEASE_*` environment variables, keystores git-ignored, procedure in
  `docs/ANDROID_RELEASE.md`. **No APK/AAB was built here** (no Android SDK / device).
* Performance: imported meshes (players, keepers, referee, stadium) carry generated LODs and the graphics level
  sets `mesh_lod_threshold` (phones switch earlier); detail LOD for crest / armband (35 m) and face / beard
  (30 m); phone shadow level; 1500 spectators on phones; developer overlay (F3). Locomotion clips cross-fade
  (0.18 s) and play at speed-matched rates — an AnimationTree was NOT introduced (the existing blending covers the
  requirement; a rewrite of the clip system was judged too risky). `tests/perf_benchmark.tscn` measures FPS /
  draw calls per level (`docs/qa/perf_report.txt`): ~430-460 draw calls, ~8 FPS on this machine's llvmpipe
  SOFTWARE renderer — this is not a phone measurement; the 60 / 30 FPS target is still unverified on a device.
  Biggest remaining cost: the player body mesh has 9 material surfaces (needs a texture atlas in the asset).
* Android: debug and release APKs built and signed here (`tools/export_android.sh`, see ANDROID_RELEASE.md);
  never run on a phone or emulator.
* Tests: `run_all.sh --quick` (skips 5 long career / performance suites) and `--full`, per-suite timings;
  GitHub Actions workflow `.github/workflows/king-football-tests.yml` (quick on every push/PR touching the
  project, full nightly and on demand). The workflow has not run yet (it starts with the first push).
* Refactor: `match_manager.gd` (913 -> 758 lines, including the new shoot-out and walk-out hooks) lost
  the HUD (`MatchHud`), switching rules (`AutoSwitchPolicy`), selection marker (`SelectionIndicator`),
  pause/results overlays (`MatchMenus`), AI command translation (`MatchAIDriver`), team building
  (`MatchTeamBuilder`), presentation (`MatchPresentation`) and the walk-out (`MatchWalkout`); behaviour unchanged (all match suites green).
* KING CONTROLLER: documented as local-network only (no TLS); token expiry (now 120 s, P9) and wrong-token limit (5,
  then a new token / QR).
* Leaks: the MatchRules <-> MatchRestarts reference cycle is broken when a match is deleted, static texture
  caches are released at exit, test-created orphans are freed: match_flow 25 -> 0, match_ux 69 -> 0, phaseT10
  315 -> 0 leaked objects at exit; the main-menu settings panel no longer leaves a freed-lambda connection.

## UX fix program (2026-11-14) — phase 4: career flow, navigation, settings, theme
IMPLEMENTED (tested, new suite `career_ux_validation` 50):
* 4.1 A career in the fictional world now gets the world's league (all 8 clubs, home and away = 56 fixtures,
  "King League") and a domestic cup ("King Cup") through the existing `LeaguePyramid` (calendar, simulation of
  other matches, user fixtures, tables, season end, save/load): `CareerState.add_default_league()`, called by
  `AppHub.start_career`. Names are translation keys. The Leagues screen shows it (it listed data-pack leagues only).
  One division only in the fictional world, so no promotion/relegation there.
* 4.1b New-career wizard (`career_wizard` screen, tested in `career_wizard_validation` 33): world (fictional or a
  data pack, switching confirmed when a career runs) -> league (King League, or country + division of the pack)
  -> club (strongest first, with rating, budget and the board's target) -> summary -> start. Reached from the
  main menu ("New career"), the Home section, the career dashboard, team selection and every "start a career
  first" empty state. Pack names are translated; the season keeps its order in Arabic (rendered-order check).
* 4.2 Navigation: "Play next match" on top (plays the next due fixture in 3D, else opens the match setup),
  six collapsible sections with drawn icons (`NavIcon`), the open screen's section expanded and its button
  highlighted, back arrow + Esc + Android back (`NOTIFICATION_WM_GO_BACK_REQUEST`) through the history,
  phones: drawer behind a menu button (`HubRoot.is_compact`), buttons >= 48 px.
* 4.3 Settings screen: sound (master / crowd / effects buses), graphics (shadows, MSAA, 30/60 FPS, resolution
  scale), controls (switching, default camera, aim assist, vibration = controller rumble, touch button size);
  saved in `user://settings.cfg` and applied at once and at boot (`GameSettings.apply_all`).
* 4.4 `resources/theme/main_theme.tres` (built by `tools/build_theme.tscn` from `UIKit` colours): all button
  states, panels, inputs, progress bars, spacing 8/16/24, type scale 14/16/28; `Loc` adds the font stack to it.
  Empty states show an illustration and a next-step button.
Limits: the volume sliders were verified on the audio buses, not by listening; the theme was checked on
screenshots, not by a designer.

## UX fix program (2026-11-14) — phase 3: screens
IMPLEMENTED (tested, new suites `ui_layout_validation` 12 (every screen, ar + en, 1280x720 and 1600x720 = a
2400x1080 phone under `canvas_items`/`expand`: fits horizontally, no clipped text without ellipsis, nav buttons
>= 44 px) and `screens_ux_validation` 32):
* Scouting toolbar wraps (`HFlowContainer`; it needed 1057 px of a 1034 px panel). Nav buttons 48 px tall.
* Squad: green striped pitch; best XI fills natural positions first (`Squad.auto_pick` global pairing — a CB no
  longer plays left back while the LB sits on the bench).
* Portraits: an empty first render is detected and re-rendered (never cached); `portrait_ready` signal lets
  waiting cards refresh. Note: portraits still arrive one per frame, so a card screen fills in over ~0.3 s.
* Cards: Arabic stat captions are words (سرعة، تسديد، تمرير، مراوغة، دفاع، بدنية) with auto-fitted size; the
  goalkeeper badge moved to the top corner (no overlap with the rating); country names translated.
* Profile: 3D preview larger and further away (gloves no longer cut off).
* Team details: missing-kit text in a 96 px column. Team selection: compact rows; during a career "Switch club"
  (confirmed, starts a new career with that club) replaces "Start career"; your club is marked.
* Tactics: pitch and settings in two columns, value next to every slider.
* Promotion: best prospect preselected, details + card in the second column, eligibility localized.
* Training: "this week" shows "—". Transfers: table with headers, ordered by squad need (no more GK-only top),
  translated history entries.
* Database tools: navigation only in debug builds or with `[developer] enabled=true`.
* First-run language screen: blurred stadium (a real in-game frame), game logo, larger buttons.
  Main menu: same background, rotating 3D player (match model/kit), "Continue career" when a save exists; the
  settings panel's language lambda is disconnected on close (removed the "Lambda capture was freed" errors).
* Match ratings include cards, fouls, being fouled and shots.
Moved to phase 4: empty leagues / competitions / standings after a new fictional career (4.1).

## UX fix program (2026-11-14) — phase 2: match
IMPLEMENTED (tested, new suite `match_ux_validation` 60 checks; regression phase1 53, input_system 29,
gameplay_feel 37, match_flow 77, mobile_input 26):
* Selection indicator (`SelectionIndicator`): unshaded ring in the (lightened) team colour under the
  controlled player, head marker, run-direction arrow; child of the selected body, moves instantly on a switch;
  absent when `human_side == "none"`. Second controller slot has its own colour (the second human is still not
  wired into gameplay — see P5).
* Automatic switching (`AutoSwitchPolicy`): auto / semi (pass receiver only) / manual, 0.4 s cooldown, never
  while charging a kick, never to the keeper. Set in the match setup, in the pause menu, saved in
  `GameSettings` (`user://settings.cfg [match]`).
* Camera: follow camera is the default in human play; broadcast camera moved closer/higher and tracks the ball
  along the pitch with smoothing, with a speed-based zoom (`CameraConfig.broadcast_track_*`); the V-key choice is
  saved. Camera label shows for 2 s after a change only, on a dark plate.
* HUD (`MatchHud`): dark rounded semi-transparent scoreboard with both crests, short names, score, clock and
  half; notice line; stamina bar of the controlled player. Arabic: home on the right (also on the results
  screen, whose score puts the home goals next to the home name). Key-hint chips for 8 s, then via the pause
  menu "Controls".
* Lighting: steeper sun (-60°), shadow opacity 0.6, two PSSM splits over 90 m (was one 220 m map); graphics
  setting off / low / high (`MatchEnvironment.apply_shadow_quality`).
Not verified: frame rate on a phone (no device here); the camera values were tuned on screenshots, not by
players.

## UX fix program (2026-11-14) — phase 1: Arabic UI
IMPLEMENTED (tested, new suite `arabic_ui_validation` 38 checks, `localization_validation` 92):
* Numbers: Western digits and separators in Arabic, wrapped in an LTR isolate (`Loc.num/decimal/percent/money/
  match_clock/date`); `Loc.f` isolates numeric placeholder clusters (`%d/%d`, `%+d`, `%.1f%%`) in Arabic; new
  `Loc.ltr/signed/ratio/score/position_code/country`. Used for formations (tactics dropdown, squad text), training
  gains (`+0`), OVR/POT ratios, position codes on every screen, scores in leagues / quick results, age groups.
  The suite checks the **rendered glyph order** through the text server, not only the strings.
* Eastern-Arabic digits: numeral localisation switched off on every text control incl. SpinBox (`Loc._on_node_added`).
* Untranslated text fixed: promotion eligibility (`ErrorText`), scout names, default competition name, club origin
  (real/fictional), KING CONTROLLER (menu + pairing screen, all its texts), the LogoService class name in the
  customise hint, age groups U15/U17/U19, region / country names (`ENUM_COUNTRY_*`), "3D", captain letter,
  empty database fields ("—").
* Match key hints are separate key/action chips (`ControlHints`), Arabic-safe, shown for 8 s at kick-off.
Limits: player and club names stay in their stored (Latin) spelling by design; the database tools screen shows
internal ids (developer tool). Not verified by a native Arabic speaker or on an Android device.

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

## P5 - KING CONTROLLER (cross-platform phone controller) - stabilised in P9
IMPLEMENTED and tested on the PC (controller_protocol 72, controller_session 81, controller_loopback 67, controller_gameplay 70, controller_page 48 checks, plus a 32-check emulated-browser E2E): protocol v2 (server-side arrival time, no client clock, sequence / rate rules, 1024-byte limit checked before parsing, strict validation), dedicated `pause` action routed to the match pause menu, **two** supported controller slots (P10: player 1 and a friend as player 2 on the opposing side, tested in two_human_validation 41 checks; slots 3-4 are shown as unsupported), one-time CSPRNG pairing token (8 chars, 120 s), separate hashed session credential with resume / revoke, heartbeat + input-gap release, seven lifecycle states, LAN address ranking, shared server across the pairing screen and the match, phone page with en/de/ar + RTL. P9 fixed: every real browser packet was rejected by a clock-domain bug; a phone paired before the match was ignored; disconnects left the stick running; `MAX_MSG_BYTES` was unused; Pause sent switch_player. NOT TESTED: any real Android / iOS phone on a real Wi-Fi with the Windows firewall (the earlier claim of a live-device pairing could not be re-verified and is withdrawn; see qa/KING_CONTROLLER_QA.md). No TLS. Open decision: a "Press" button has no gameplay action in the game. See [KING_CONTROLLER_ARCHITECTURE.md](KING_CONTROLLER_ARCHITECTURE.md).

## P6 - Bluetooth investigation spike
NOT IMPLEMENTED (by design, see docs/BLUETOOTH_CAPABILITY_REPORT.md): Godot 4.7 has no built-in Bluetooth API; delivery requires per-platform native plugins (Android JNI, Windows WinRT) plus real-device testing. Wi-Fi (KING CONTROLLER, P5) is the supported phone-controller path. No simulated success.

## Master development pass (2026-11-16)
* **Event log**: `docs/MATCH_EVENT_LOG.md`; suite `match_event_log_validation` (27).
* **Commentary**: `MatchCommentary` + `translations/commentary.csv` (ar / de / en), event-driven, deterministic wording, shown in the
  HUD notice area; suite `match_commentary_validation` (21). Text only: no commentary audio exists.
* **Report**: `MatchReport` gains `timeline` and `shot_map` (real events and positions), declared in `MatchStats.MEASURED`.
* **Player instructions**: stay_back, join_attack, get_forward, hold_position, stay_wide, cut_inside on outfield slots
  (`TacticsPreset.player_instructions`, applied in `TeamAI.formation_targets`, section in the Tactics screen, persisted);
  suite `player_instructions_validation` (19). Marking / interception instructions are NOT offered: the AI driver has no
  man-marking, and a control that did nothing would be a fake feature.
* **Controller**: phone-side control preferences / profiles / vibration (Chromium test, 21 checks). The match dashboard / mini-map
  stream belongs to the v3 companion design on main and is not wired yet.
* NOT DONE: handball and advantage rules, heatmaps, xG, replay selection of fouls / chances, controller dashboard / tactics /
  tutorial / analytics on the phone, real-device QA, Android / GPU profiling.
