class_name TeamData
extends Resource

## One team: name, kit, goalkeeper kit, kick-off formation and shirt numbers.

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
