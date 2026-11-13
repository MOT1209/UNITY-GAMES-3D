class_name CrestGenerator
extends RefCounted

## Deterministic original crest designs. The design (shape, division, symbol) is derived from
## the club id only, then moved to the next free combination when another club already uses the
## same design with the same colours (`used` = signatures taken) or when the symbol is blocked
## for that club. No official artwork is read, traced or imitated: shapes and symbols are generic
## pictograms (see CrestSymbols).

const SHAPES := 6
const DIVISIONS := 5
const SYMBOLS := 12
const COMBOS := SHAPES * DIVISIONS * SYMBOLS      # 360
const STEP := 37                                   # coprime to 360: visits every combination


## Canonical processing order: generated fictional clubs (`fic_*`) after all others, then by id, so adding
## generated clubs never changes the crest of an existing club.
static func generation_order(clubs: Array) -> Array:
	var out := clubs.duplicate()
	out.sort_custom(func(a: TeamData, b: TeamData) -> bool:
		var fa := a.id.begins_with("fic_")
		var fb := b.id.begins_with("fic_")
		return a.id < b.id if fa == fb else fb)
	return out


## `used` maps signature -> club id and is updated with the returned design.
static func generate(club_id: String, primary: Color, secondary: Color, accent: Color, is_real: bool,
		used: Dictionary = {}, blocked_symbols: Array = [], created_at: String = "2026-11-12") -> CrestData:
	var base: int = (hash("crest:" + club_id) & 0x7fffffff) % COMBOS
	var c := CrestData.new()
	c.crest_id = "crest_" + club_id
	c.club_id = club_id
	c.primary_color = primary
	c.secondary_color = secondary
	c.accent_color = accent
	c.asset_type = CrestData.AssetType.ORIGINAL_ALTERNATIVE if is_real else CrestData.AssetType.FICTIONAL
	c.license_status = "ORIGINAL_NOT_AFFILIATED" if is_real else "FICTIONAL"
	c.source = "procedural"
	c.created_at = created_at
	for k in COMBOS:
		var idx := (base + k * STEP) % COMBOS
		c.shape_style = CrestData.SHAPES[idx % SHAPES]
		c.division = CrestData.DIVISIONS[(idx / SHAPES) % DIVISIONS]
		c.symbol = CrestData.SYMBOLS[(idx / (SHAPES * DIVISIONS)) % SYMBOLS]
		if c.symbol in blocked_symbols:
			continue
		var sig := c.signature()
		if used.has(sig) and used[sig] != club_id:
			continue
		used[sig] = club_id
		return c
	return c        # unreachable in practice (360 designs per colour set); the last candidate is returned
