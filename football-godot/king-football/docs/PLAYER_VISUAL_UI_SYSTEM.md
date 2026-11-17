# Player Visual UI (Phase V8)

All screens are built the project's way (code, `HubScreen`, `UIKit`) and read the shared `AppHub` state;
no screen holds player data of its own.

| Screen | File | What was added |
|---|---|---|
| Squad Management | `scripts/ui/screens/squad_screen.gd` | "Starting XI cards" strip (`CardStrip`, one compact card per starter, click → detail view → profile). **All existing controls (slots, captain, set pieces, bench, auto-pick) are untouched** (asserted by test). |
| Youth Academy | `academy_screen.gd` | Card grid per age group (`ProspectCards`) above the existing table: portrait, OVR, position, six real attributes. Promote/Release/Keep logic unchanged; promotion keeps id, appearance and history (tested). |
| Player Profile | `player_profile_screen.gd` | Large card (`ProfileCard`) with portrait + appearance line (hair, beard, build %, height %). Existing identity/attribute/development/history sections kept. |
| Player Collection (new) | `player_collection_screen.gd`, registered as `collection` | Gallery of first team + academy: search (Enter), position filter, min-OVR filter, card-category filter, sort (rating/name/age/position), count, card → detail view, profile access. `filter_and_sort` is static and unit-tested. Management view only — no packs/rewards. |
| Card Detail View (new) | `scripts/ui/cards/card_detail_view.gd` | Modal overlay: enlarged animated-sheen card, full attribute bars (full translated names), club/age, class, "Open profile", Close/Esc/click-outside. |

Navigation: the `collection` screen appears in the hub navigation bar (title key `SCREEN_COLLECTION`, defined with all other new strings in `translations/player_visual.csv`). `tests/phaseT10_validation.gd` was updated from "19 screens" to "20 screens" accordingly.

Design: dark UI from the existing `UIKit`; cards carry the black/gold identity. English/German LTR and Arabic RTL tested (squad + collection rebuild in all three languages).

Not done: pitch-formation layout with cards (the existing slot pickers remain the lineup editor); a rotating live 3D viewer; promotion-status badge on prospect cards; potential/development bar on the card itself (potential is shown on the profile, not on the card).
