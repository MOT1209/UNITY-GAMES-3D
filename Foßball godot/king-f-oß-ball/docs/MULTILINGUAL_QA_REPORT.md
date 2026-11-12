# Multilingual QA report

Date: 2026-11-12 · Engine: Godot 4.7.2 (Windows, GL Compatibility, text server ICU/HarfBuzz/Graphite) ·
Languages: Arabic `ar` (RTL), German `de`, English `en`.

Legend: **TESTED-OK** · **TESTED-WITH-FAILURES (fixed)** · **NOT TESTED** · **NOT IMPLEMENTED**.

## 1. Automated checks — `tests/localization_validation.tscn` (headless): 90 passed, 0 failed

| Area | What is verified | Result |
|---|---|---|
| Tables | `ar`/`de`/`en` loaded from `translations/*.csv`; no load errors; every key present and non-empty in all three; placeholders (`%d %s {n}`) identical across languages; keys are UPPER_SNAKE identifiers | TESTED-OK |
| Required keys | menu, navigation, HUD, dialog keys exist in all languages; `MENU_PLAY` = العب / Spielen / Play; Youth Academy = أكاديمية الشباب / Jugendakademie | TESTED-OK |
| Switching | `set_language` for each language; locale and `TranslationServer` follow; root direction is RTL only for `ar`; `language_changed` fires once per switch; unsupported code rejected; scene labels whose text is a key translate natively | TESTED-OK |
| Persistence | choice saved to `user://settings.cfg`; a fresh manager ("restart") finds it; later change overwrites it; other settings survive; first run detects "no language saved" | TESTED-OK |
| Text quality | German `ä ö ü ß` present and round-trip exactly; every Arabic string contains Arabic letters; no long German string equals English; no mojibake/replacement characters | TESTED-OK |
| Formatting | en `1,234,567`/`€1,500,000`, de `1.234.567`/`1.500.000 €`/`3,5`/`12.11.2026`, ar `1٬234٬567`; large whole numbers in dynamic text grouped; names with umlauts inserted; bidi isolates only in Arabic | TESTED-OK |
| Plurals | CLDR categories; English/German singular-plural; **six distinct Arabic forms** (0, 1, 2, 5, 12, 100) | TESTED-OK |
| Enum/data coverage | every enum or data value shown by the UI (mentality, status, foot, competition type, difficulty, sides, training categories, attributes, traits, kit slots/colours/patterns, set pieces, logos) translated in all languages | TESTED-OK |
| No hardcoded UI strings | regex scan of all `scripts/ui/**` scripts for literals passed to `UIKit.label/title/muted/button/empty_state`, `say`, `header`; main-menu scene contains keys only | TESTED-OK |
| Main menu | first launch shows the language dialog; choosing applies + saves + closes it; menu texts change immediately in Settings; RTL in Arabic, LTR again in English | TESTED-OK |
| Every screen × every language | all 19 hub screens rendered in ar, de and en: no raw key, no untranslated English table text, no raw internal id (`home`, `solid`, …); switching language on an open screen re-renders it in place | TESTED-OK |
| RTL structure | navigation left of content in en/de, **right** of content in ar; language picker keeps its order; tactics pitch is a `PitchDiagram` with 11 markers and not mirrored | TESTED-OK |

Mutation checks (break the feature, confirm a test fails, restore): Arabic marked LTR → 5 failures; a screen
showing a raw id → 2 failures (the check was added after a visual review found exactly this defect).

## 2. Visual verification — `tests/localization_visual.tscn` (real window, 1280×720)

Output: `docs/qa/*.png` (52 screenshots) and `docs/qa/visual_report.txt`.

* Text server: `ICU / HarfBuzz / Graphite (Built-in)`, **Arabic shaping: true, bidi: true**.
* Glyph coverage (theme font stack): Arabic U+0627/0644, German ä ö ü ß, Latin A — all `true`; bundled Noto Sans Arabic
  loaded.
* Captured per language (ar, de, en): main menu, settings panel, and 15 hub screens (team selection, squad,
  tactics, academy, scouting, training, promotion, competitions, career, transfers, finance, customization,
  kit editor, match setup, settings) + the first-run language dialog.

Screenshots I inspected one by one: `menu_ar`, `settings_panel_ar`, `first_run_dialog`, `hub_academy_ar`,
`hub_squad_ar`, `hub_tactics_ar`/`_en`, `hub_career_ar`, `hub_kit_editor_ar`, `hub_match_setup_de`,
`hub_transfers_de`. Observed: Arabic letters are correctly **joined and shaped**; the whole hub **mirrors**
(navigation bar on the right, titles/labels right-aligned, dropdown arrows on the left, tables start from the
right); Latin team and player names stay readable inside Arabic lines; German umlauts/ß render correctly;
English unchanged. The other captured screens were generated and saved but **not individually reviewed**.

### Defects found by the visual review (all fixed, then re-captured)

| # | Defect | Fix |
|---|---|---|
| 1 | Tactics pitch lost all 11 player markers in Arabic (0 vs 1,100 white pixels in LTR) | `PitchDiagram` drawn with `_draw()`, forced LTR; test added |
| 2 | Kit editor dropdowns showed raw ids (`home`, `solid`) in ar/de | `ENUM_KITSLOT_*`, `ENUM_PATTERN_*`, `ENUM_LOGO_*`; test now flags raw ids |
| 3 | Numbers 1,000–9,999 ungrouped next to grouped millions (`8335/Woche`) | grouping threshold 1,000 |
| 4 | Settings overlay semi-transparent (menu text ghosting through) | opaque background |
| 5 | Kit-editor colour names, stat bars, set-piece labels used English capitalisation of internal ids | translated through `ENUM_*` |

## 3. Screens × languages

All 18 management screens + Settings + main menu: **ar TESTED-OK · de TESTED-OK · en TESTED-OK** (automated
rendering for all; visual review for the subset listed above).

## 4. Not covered / limitations

* **NOT IMPLEMENTED (nothing to localize yet):** tutorials, loading screens, in-match pause menu, match-results
  screen, statistics screen.
* **NOT LOCALIZED:** the simulation systems' internal error/validation sentences (≈150, e.g. promotion/transfer
  rejections) are shown verbatim in English inside a localized message bar; the Phase-1 prototype stadium overlay
  and developer test scenes.
* **NOT TESTED:** Arabic text entry (IME) in `LineEdit`, other operating systems, high-DPI, window sizes below
  1280×720, review of the Arabic/German wording by native speakers (translations were written by the
  developer assistant and should be proofread).
* The in-match HUD (score line with `HALF TIME` / `FULL TIME`) is localized and isolates names, but was verified
  by unit-level checks (keys exist, LTR scoreboard), not by a windowed match screenshot.
