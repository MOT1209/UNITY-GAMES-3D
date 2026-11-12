# Arabic / RTL support

Status: **implemented; verified by automated structure checks and by screenshots from a real window**
(HarfBuzz text server). It is *not* verified by a native Arabic speaker or on devices other than the
Windows development machine.

## How direction is applied

* `Loc.set_language("ar")` calls `get_tree().root.set_layout_direction(Window.LAYOUT_DIRECTION_RTL)`
  (LTR for de/en). In Godot 4.7 `layout_direction` is a method on `Window`, not a property.
* Every Control with `layout_direction = INHERITED` (the default) follows it: containers reverse child order
  (the hub navigation moves from the left to the **right** of the content), labels/buttons align to the right,
  option arrows and sliders mirror.
* The old workaround (forcing `layout_direction = 2` on the main menu root) was **removed**; it would have
  kept Arabic LTR. The menu scene now inherits.
* `Loc` also calls `TranslationServer.set_locale`, so Godot itself uses the right locale for shaping.

## What is deliberately *not* mirrored

| Element | Why | How |
|---|---|---|
| Football pitch diagram (tactics) | A pitch is not a reading-direction object; markers must not move | `PitchDiagram` (`scripts/ui/kit/pitch_diagram.gd`) draws with `_draw()` and is forced LTR |
| Match scoreboard (HUD) | Home on the left, away on the right in every language | `layout_direction = LTR` on the HUD label; team names isolated with `Loc.iso` |
| Language picker | The same visual order (العربية · Deutsch · English) in every mode | forced LTR |
| Gameplay controls / 3D view | Not UI text | untouched |

## Shaping, fonts, bidi

* Text server: ICU / HarfBuzz / Graphite — Arabic joining and ligatures work (see
  `docs/qa/visual_report.txt`: `shaping (Arabic joining): true`, `bidi: true`).
* Font stack (installed as the root theme's default font by `Loc`): Godot's Latin base font → bundled
  **Noto Sans Arabic** → system fonts (Segoe UI, Tahoma, Noto Naskh Arabic, Arial). German ä ö ü ß and Latin are
  covered by the base font; coverage for U+0627/0644/0649 and the German glyphs is checked at runtime in the
  visual QA run.
* Mixed text: Latin team/player names inside an Arabic sentence are wrapped with Unicode bidi isolates
  (`Loc.iso`, U+2068…U+2069) so they cannot reorder neighbouring words or numbers. Numbers keep Western digits;
  thousands separator is `٬`, decimal `٫`.
* Arabic list separator is `،`; plural forms use the six CLDR categories (zero/one/two/few/many/other).

## Bugs found and fixed while adding RTL

* The tactics pitch **lost all 11 player markers in RTL** (0 white pixels vs 1100 in LTR; child-ColorRect
  positions are mirrored). Fixed by drawing the diagram directly (`PitchDiagram`); covered by a test.
* The kit editor showed English colour-slot names (`f.capitalize()`), stat bars and set-piece labels used
  English capitalisation of internal ids → now translated through `ENUM_*` keys.

## Verification evidence

`tests/localization_validation.gd`: root direction per language, menu `is_layout_rtl()`, navigation x-position
left (LTR) vs right (RTL), picker stays LTR, pitch not mirrored with 11 markers.
`docs/qa/*.png` + `docs/qa/visual_report.txt`: screenshots of the main menu, settings panel and 15 hub screens
in ar/de/en. See `docs/MULTILINGUAL_QA_REPORT.md`.

## Remaining RTL limitations

* Tables (`GridContainer`) mirror their column order in RTL (name column on the right) — intended, but column
  widths are not tuned per language.
* `ConfirmationDialog` native windows follow the OS/engine chrome; button texts are localized.
* Not verified: Arabic input in `LineEdit` (IME), very small window sizes, high-DPI scaling.
