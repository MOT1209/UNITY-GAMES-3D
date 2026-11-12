# Player Card System (Phase V5, V7)

Identity: Premium Black & Gold (`#111111 #D4AF37 #A8862D #A51E2B #E7E3D8 #343A40`, constants in `CardCategory`).

## One implementation, five data-driven categories

| Class | Overall (derived on every read) | Look |
|---|---|---|
| Bronze | < 65 | bronze metal frame, simple (no ornament) |
| Silver | 65–74 | silver frame, divider line |
| Gold | 75–84 | gold frame, corner studs |
| Elite | 85–89 | black/gold, side rails, stronger sheen |
| Legendary | ≥ 90 | black/gold + **controlled Royal-Red** accents (base band, gradient end), crown chevrons, strongest sheen |

Categories are a visual classification only. No packs, randomness, currency or monetisation exist.
Thresholds and per-class theme live in `scripts/players/card_category.gd` (`THRESHOLDS`, `THEMES`).
Because the class is derived from `PlayerData.get_overall()`, a card can't show an outdated class.

## Components (reusable, no per-category scenes)

| Component | File |
|---|---|
| Card Background + Frame + Rarity decoration + Effects | `scripts/ui/cards/card_frame.gd` (`CardFrame`, one `_draw` driven by the theme; optional slow sheen `animate` for the detail view only) |
| Card Base: portrait, rating, position, name, club/nationality, attribute grid | `scripts/ui/cards/player_card.gd` (`PlayerCard`) |
| View-model | `scripts/players/player_card_data.gd` (`PlayerCardData`) |
| Detail view | `scripts/ui/cards/card_detail_view.gd` |
| Scene | `ui/cards/player_card.tscn` (instantiable `PlayerCard`) |

## Data binding (never a copy)

`PlayerCardData.from_player(db, id)` reads name, age, nationality, club (`TeamData.display_name`), position,
OVR, the **six real attributes** `PAC SHO PAS DRI DEF PHY` (`pace…physical`), goalkeeping (goalkeepers get an extra `GK` line),
appearance, shirt number, kit. Nothing is stored; `PlayerCard.refresh()` rebuilds from the live `PlayerData`.
Tested: attribute growth, position change, rename, transfer (club) all update the same card.

## Layout rules

- Fixed aspect 1 : 1.4, everything placed from fractions of the control size, fonts scale with width → any resolution (tested at 60 px and 420 px wide).
- Long names shrink (down to 9 px) before ellipsis; tested with a 58-char Latin and a 49-char Arabic name in en/de/ar.
- Arabic / German / English: captions from `translations/player_visual.csv` (`CARD_STAT_*`, `CARD_CAT_*`); numbers through `Loc.num`. The card's layout is pinned to LTR (`layout_direction = LTR`) because it is a fixed brand layout placed with absolute fractions — under an RTL root Godot mirrored the children and broke it (found by screenshot). Arabic *text* still shapes RTL inside each label.
- Restrained effects: single soft sheen, no glow; metallic look from a light→dark frame gradient.

## Not done

- No bespoke Legendary background artwork / animated particles; no team-badge or competition icon on the card (the model has `logo_path`, not wired); no flag icon for nationality (text only).
