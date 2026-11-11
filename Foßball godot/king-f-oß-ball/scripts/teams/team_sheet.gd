class_name TeamSheet
extends Resource

## One team's lineup sheet: name, kit, goalkeeper kit, kick-off formation and
## shirt numbers.
##
## Named "TeamSheet" on purpose: the career layer owns `TeamData`
## (`scripts/data/team_data.gd`), which is the *club record* (budget, squad
## ids, competitions). The two are different things and must not share a
## global class name — one name, one class.

@export var team_name := "KING FC"
@export var short_name := "KNG"
@export var kit: TeamKit
@export var goalkeeper_kit: TeamKit
@export var formation := "4-4-2"

## Shirt numbers, one per formation slot **in slot order** — not per role.
## The same list is reused for every formation, so the number follows the
## *position*, not the person: with the default list #7 is the right winger in
## 4-4-2, the left winger in 4-3-3 and the right wing-back in 3-5-2.
@export var numbers: PackedInt32Array = [1, 3, 4, 5, 2, 11, 8, 6, 7, 9, 10]
