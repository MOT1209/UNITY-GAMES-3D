class_name DetailedAttributes
extends RefCounted

## Trainable, stored detailed attributes (development ecosystem, step 2) layered on top of the seven broad attributes.
##
## COMPATIBILITY RULES (the match engine keeps reading only the seven broad attributes, `PlayerData.ATTRIBUTES`):
##  * Every detailed attribute has exactly ONE parent broad attribute (`CATALOG`), so a point is never counted twice.
##  * Storage is lazy: `PlayerData.detail` is empty until a detailed attribute is first trained (`ensure`). An untouched player
##    reports `derived()` values (broad value + a stable per-player offset), so existing players, data packs and saves are unchanged
##    and migrating costs nothing. Once materialised, the stored values are authoritative.
##  * Training a detailed attribute (`apply_points`) raises it by one and gives its parent 1 / Z of a point (Z = how many detailed
##    attributes share that parent), i.e. the broad attribute follows the AVERAGE of its detailed attributes. The potential cap is
##    checked on the broad rise, so a detailed point that would push the overall past potential is refused.
##  * When a broad attribute changes by any other route (legacy broad training, yearly ageing, lifecycle), `PlayerData` calls
##    `on_broad_changed` and every detailed attribute under it moves by the same amount, keeping both layers consistent.
## The 1..99 scale and `OFFSET` mirror `AttributeDetail` (the older read-only derived view used for database export).

const OFFSET := 6
const EPSILON := 0.000001
const GROUPS: Array[String] = ["technical", "physical", "mental", "goalkeeping"]

## name -> [group, parent broad attribute]. `positioning` is position-dependent, see `parent_of`.
const CATALOG := {
	# technical: shooting
	"finishing": ["technical", "shooting"], "shot_power": ["technical", "shooting"], "long_shots": ["technical", "shooting"],
	"volleys": ["technical", "shooting"], "penalties": ["technical", "shooting"], "heading": ["technical", "shooting"],
	# technical: passing
	"short_passing": ["technical", "passing"], "long_passing": ["technical", "passing"], "vision": ["technical", "passing"],
	"crossing": ["technical", "passing"], "curve": ["technical", "passing"],
	# technical: dribbling (Agility and Balance live here once; they are not repeated under physical)
	"ball_control": ["technical", "dribbling"], "dribbling_skill": ["technical", "dribbling"],
	"agility": ["technical", "dribbling"], "balance": ["technical", "dribbling"],
	# technical: defending
	"tackling": ["technical", "defending"], "interceptions": ["technical", "defending"], "marking": ["technical", "defending"],
	"defensive_positioning": ["technical", "defending"], "defensive_awareness": ["technical", "defending"],
	# physical
	"acceleration": ["physical", "pace"], "sprint_speed": ["physical", "pace"],
	"stamina": ["physical", "physical"], "strength": ["physical", "physical"], "jumping": ["physical", "physical"],
	# mental / tactical
	"composure": ["mental", "shooting"], "concentration": ["mental", "defending"], "anticipation": ["mental", "defending"],
	"decisions": ["mental", "passing"], "reactions": ["mental", "pace"], "positioning": ["mental", ""],
	"work_rate": ["mental", "physical"], "aggression": ["mental", "physical"], "teamwork": ["mental", "passing"],
	# goalkeeping (only meaningful for goalkeepers)
	"reflexes": ["goalkeeping", "goalkeeping"], "diving": ["goalkeeping", "goalkeeping"], "handling": ["goalkeeping", "goalkeeping"],
	"gk_positioning": ["goalkeeping", "goalkeeping"], "kicking": ["goalkeeping", "goalkeeping"], "one_on_one": ["goalkeeping", "goalkeeping"],
}


static func names() -> Array:
	return CATALOG.keys()


static func has(attr: String) -> bool:
	return CATALOG.has(attr)


static func names_in_group(group: String) -> Array[String]:
	var out: Array[String] = []
	for n in CATALOG:
		if CATALOG[n][0] == group:
			out.append(n)
	return out


static func group_of(attr: String) -> String:
	return str((CATALOG.get(attr, ["", ""]) as Array)[0])


## Goalkeeping details only exist for goalkeepers; every other detail applies to everybody.
static func applicable(p: PlayerData, attr: String) -> bool:
	if not CATALOG.has(attr):
		return false
	return p.position == PlayerData.Position.GK or group_of(attr) != "goalkeeping"


## The broad attribute a detailed attribute feeds. Positioning follows the part of the pitch the position plays in.
static func parent_of(p: PlayerData, attr: String) -> String:
	if attr == "positioning":
		match p.position:
			PlayerData.Position.GK:
				return "goalkeeping"
			PlayerData.Position.CB, PlayerData.Position.LB, PlayerData.Position.RB, PlayerData.Position.CDM:
				return "defending"
			PlayerData.Position.CM, PlayerData.Position.CAM, PlayerData.Position.LM, PlayerData.Position.RM:
				return "passing"
			_:
				return "shooting"
	return str((CATALOG.get(attr, ["", ""]) as Array)[1])


## Z: how many detailed attributes of `p` share the broad attribute `broad` (the broad value follows their average).
static func count_under(p: PlayerData, broad: String) -> int:
	var n := 0
	for a in CATALOG:
		if parent_of(p, a) == broad:
			n += 1
	return n


static func _offset(player_id: String, attr: String) -> int:
	return (hash(player_id + ":d:" + attr) & 0x7fffffff) % (OFFSET * 2 + 1) - OFFSET


## Value of an untouched player: parent broad value plus a stable per-player offset.
static func derived(p: PlayerData, attr: String) -> int:
	var parent := parent_of(p, attr)
	if parent == "":
		return 0
	return clampi(p.get_attribute(parent) + _offset(p.id, attr), PlayerData.MIN_RATING, PlayerData.MAX_RATING)


static func is_materialised(p: PlayerData) -> bool:
	return not p.detail.is_empty()


## Stored value when the player has been materialised, else the derived one. 0 for an unknown name.
static func value(p: PlayerData, attr: String) -> int:
	if not CATALOG.has(attr):
		return 0
	if p.detail.has(attr):
		return int(p.detail[attr])
	return derived(p, attr)


## Every detailed attribute that applies to `p`, {name: value}.
static func all_for(p: PlayerData) -> Dictionary:
	var out := {}
	for a in CATALOG:
		if applicable(p, a):
			out[a] = value(p, a)
	return out


## Average of the detailed attributes under a broad attribute (what the broad value is meant to track).
static func average_under(p: PlayerData, broad: String) -> float:
	var total := 0.0
	var n := 0
	for a in CATALOG:
		if parent_of(p, a) == broad:
			total += float(value(p, a))
			n += 1
	return total / float(n) if n > 0 else 0.0


## Writes every detail of `p` from its current derived values (once). Never changes a broad attribute.
static func ensure(p: PlayerData) -> void:
	if not p.detail.is_empty():
		return
	for a in CATALOG:
		p.detail[a] = derived(p, a)


## A stored but incomplete dictionary (corrupt or hand-edited save) is completed with derived values; an empty one stays empty.
static func complete(p: PlayerData) -> void:
	if p.detail.is_empty():
		return
	for a in CATALOG:
		if not p.detail.has(a):
			p.detail[a] = derived(p, a)


## Called by `PlayerData` when a broad attribute changed outside detail training: details under it follow by the same amount.
static func on_broad_changed(p: PlayerData, broad: String, delta: int) -> void:
	for a in p.detail:
		if parent_of(p, str(a)) == broad:
			p.detail[a] = clampi(int(p.detail[a]) + delta, PlayerData.MIN_RATING, PlayerData.MAX_RATING)


static func _set_broad_silently(p: PlayerData, broad: String, v: int) -> void:
	p._detail_busy = true
	p.set(broad, v)
	p._detail_busy = false


## Adds fractional progress to a detailed attribute and converts whole points: detail + 1, parent + 1/Z. Returns whole points gained.
## Refused (progress parked at 0.99) when the parent's rise would push the overall rating past potential.
static func apply_points(p: PlayerData, attr: String, points: float, week: int, event: String = "train") -> int:
	if not applicable(p, attr):
		return 0
	ensure(p)
	var parent := parent_of(p, attr)
	var z := float(maxi(count_under(p, parent), 1))
	var progress := float(p.growth_progress.get(attr, 0.0)) + points
	var gained := 0
	while progress >= 1.0 and int(p.detail[attr]) < PlayerData.MAX_RATING:
		var bp := float(p.growth_progress.get(parent, 0.0)) + 1.0 / z
		if bp >= 1.0 - EPSILON and p.get_attribute(parent) < PlayerData.MAX_RATING:     # EPSILON: seven times 1/7 is 0.99999994
			var before_b := p.get_attribute(parent)
			_set_broad_silently(p, parent, before_b + 1)
			if p.get_overall() > p.potential:
				_set_broad_silently(p, parent, before_b)
				p.growth_progress[parent] = 0.99
				progress = 0.99
				break
			bp = maxf(bp - 1.0, 0.0)
		elif p.get_attribute(parent) >= PlayerData.MAX_RATING:
			bp = 0.0
		p.growth_progress[parent] = bp
		var before := int(p.detail[attr])
		p.detail[attr] = before + 1
		p.development_history.append({"event": event, "week": week, "attribute": attr, "from": before, "to": before + 1, "overall": p.get_overall()})
		progress -= 1.0
		gained += 1
	p.growth_progress[attr] = progress
	return gained


## Cleans a loaded dictionary: unknown names are dropped, values are made integers and clamped to 1..99.
static func sanitize(raw: Variant) -> Dictionary:
	var out := {}
	if not (raw is Dictionary):
		return out
	for k in (raw as Dictionary):
		var name := str(k)
		var v: Variant = (raw as Dictionary)[k]
		if CATALOG.has(name) and (v is int or v is float):
			out[name] = clampi(roundi(float(v)), PlayerData.MIN_RATING, PlayerData.MAX_RATING)
	return out


## Human-readable problems with the stored detailed attributes (empty = fine).
static func validate(p: PlayerData) -> Array[String]:
	var errors: Array[String] = []
	for k in p.detail:
		if not CATALOG.has(str(k)):
			errors.append("player '%s' has unknown detailed attribute '%s'" % [p.id, k])
			continue
		var v := int(p.detail[k])
		if v < PlayerData.MIN_RATING or v > PlayerData.MAX_RATING:
			errors.append("player '%s' detailed %s=%d out of range 1-99" % [p.id, k, v])
	if not p.detail.is_empty():
		for a in CATALOG:
			if not p.detail.has(a):
				errors.append("player '%s' is missing detailed attribute '%s'" % [p.id, a])
	return errors
