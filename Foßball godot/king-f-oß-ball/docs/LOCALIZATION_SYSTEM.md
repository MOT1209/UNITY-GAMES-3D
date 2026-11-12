# Localization system

Status: **implemented and tested** (headless suite `tests/localization_validation.tscn`,
visual QA `tests/localization_visual.tscn`). Languages: Arabic (`ar`, RTL), German (`de`),
English (`en`) — all three are first-class, none is a fallback-only language.

## Files

| Path | Role |
|---|---|
| `scripts/core/localization.gd` | Autoload **`Loc`** (`class_name Localization`): tables, lookup, switching, direction, fonts, persistence, validation |
| `translations/*.csv` | Source tables, columns `key,en,de,ar`. Every `*.csv` in the folder is merged (`screens.csv` = management screens, `shell.csv` = menu / hub shell / enums / plurals). `*.csv.import` uses the `keep` importer so the file is shipped and read as-is at runtime |
| `assets/fonts/NotoSansArabic.ttf` (+ `-OFL.txt`) | Bundled Arabic font (SIL OFL 1.1) |
| `scripts/ui/language_picker.gd` | Three-button language selector + first-run "initial setup" dialog |
| `scripts/ui/screens/settings_screen.gd`, `scripts/ui/main_menu.gd` | The two places where the language can be changed |
| `tests/localization_validation.gd` | 90 automated checks; `tests/localization_visual.gd` renders screenshots |

## Keys

Keys are stable identifiers (`UPPER_SNAKE`), never the translated text: `MENU_PLAY`, `SCREEN_ACADEMY`,
`ACADEMY_PROMOTE`, `COMMON_OK`. Prefixes: `MENU_`, `HUB_`, `SCREEN_`, `NAV_`, `COMMON_` (shared by ≥2
screens), one prefix per screen (`ACADEMY_`, `SQUAD_`, `TRAIN_`, ...), `ENUM_<GROUP>_<VALUE>` for enum/data
values (mentality, status, training categories, traits, kit slots, ...), `HUD_`, `SETTINGS_`.
A plural family is `BASE#zero|one|two|few|many|other`.

## API (`Loc`)

```gdscript
Loc.t("MENU_PLAY")                          # text, fallback: current -> en -> the key (recorded in Loc.missing)
Loc.f("CAREER_SEASON_WEEK_OF", [3, 12, 46]) # printf-style, argument order fixed by the table text
Loc.f("KEY", {"name": n, "goals": 3})       # {named} placeholders — use when word order can differ
Loc.tn("CAREER_CONTRACTS_EXPIRE", n)        # CLDR plural category per language ({n} placeholder)
Loc.enum_name("MENTALITY", "ULTRA_DEFENSIVE")  # ENUM_MENTALITY_ULTRA_DEFENSIVE
Loc.num(1234567) / money() / decimal() / percent() / date()   # locale separators, € placement, date order
Loc.iso(team_name)                          # bidi-isolates Latin names inside Arabic text (no-op in LTR)
Loc.set_language("de")                      # runtime switch; saved to user://settings.cfg [game] language
Loc.language_changed                        # signal; HubRoot / main menu / settings rebuild on it
Loc.validate()                              # parity/quality report used by the test suite
```

* Whole numbers ≥ 10,000 inside `Loc.f` text get locale thousands separators automatically.
* Controls whose `text` is a key (scene labels) are translated by Godot's TranslationServer, because the same
  tables are registered there; they refresh on language change without code.
* Arabic digits stay Western (0-9) — only the separators are localized (`1٬234٬567`).

## Adding a string / screen / language

1. **String:** add a row to a CSV (all three languages), then `Loc.t("YOUR_KEY")` in code. Never put a literal in
   `UIKit.label/button/muted/title/empty_state`, `say()` or `header()` — the test fails on it.
2. **Screen:** extend `HubScreen`, build with `UIKit.*` + `Loc.t`, register id → `["SCREEN_<ID>", path]` in
   `ScreenRegistry`. The hub rebuilds the open screen automatically on language change.
3. **Enum/data value shown to the player:** add `ENUM_<GROUP>_<VALUE>` rows and show it with `Loc.enum_name`.
4. **Language:** add a column to the CSVs, an entry in `Loc.LANGUAGES` / `Loc.ORDER` (native name, `rtl`), plural
   rules in `Localization.plural_category`, number/date separators; the validator then demands full parity.

## Validation (what the tests enforce)

Every key present and non-empty in ar/de/en; placeholders (`%d %s {n}`) identical across languages; no
"TODO/XXX" texts; Arabic strings contain Arabic letters; no long German string equal to English; no mojibake;
all enum/data values used by the UI are translated; no hardcoded literals in `scripts/ui/**`; every hub screen
renders in all three languages with no raw key and no leftover English table text on screen.

## Known limitations (honest list)

* **System-layer diagnostics stay English.** Validation/error strings returned by the simulation systems
  (e.g. `PromotionSystem.why_not`, `Squad.assign_starter`, `TransferMarket`, ~150 strings) are shown to the
  user verbatim by `say(err)`. The UI wrapper text around them is localized. Next step: return error codes
  and map them to keys.
* Player/team/competition names are data (not translated). Default values pre-filled in edit boxes
  ("New Club FC", "Season Competition") are data defaults.
* Position abbreviations (GK, CB, ST...) and age-group ids (U15...) are international codes, not translated.
* Kit patterns (stripes/hoops...) are stored and named but not rendered (flat colour slots only).
* The Phase-1 prototype stadium overlay (`stadium_prototype.gd`) and developer test scenes are not localized.
* No tutorial, loading screen, pause menu or results screen exists yet, so there is nothing to localize there
  (new ones must use `Loc`).
