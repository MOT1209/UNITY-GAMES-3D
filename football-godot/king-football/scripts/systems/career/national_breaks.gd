class_name NationalBreaks
extends RefCounted

## Career phase C5.1 (simplified): international breaks. Three per season (weeks 10, 22 and 34). Each country's squad is its 23 best
## players of that nationality in the loaded database. Called-up players of the managed club are away for the break week and come
## back tired (fitness -12) and, now and then, injured (6%, seeded by season / week / player). No tournament and no national-team job.

## Phase K2: the four international windows of a European season (season 1 dates): mid September, mid October,
## mid November and late March (`CareerDate`). No club matches are played in these weeks.
const BREAK_WEEKS: Array[int] = [7, 11, 16, 34]
const SQUAD_SIZE := 23
const RETURN_FATIGUE := 12
const INJURY_CHANCE := 0.06

var called_up: Array = []                    # player ids away during the current break


static func is_break(week: int) -> bool:
	return BREAK_WEEKS.has(week)


## The national squad of a nationality (player ids, best first).
static func squad_for(db: Node, nationality: String) -> Array:
	var all: Array = []
	for p: PlayerData in db.players.values():
		if p.nationality == nationality and p.status != PlayerData.Status.RETIRED and p.status != PlayerData.Status.YOUTH:
			all.append(p)
	all.sort_custom(func(a: PlayerData, b: PlayerData) -> bool:
		var oa := a.get_overall()
		var ob := b.get_overall()
		return oa > ob if oa != ob else a.id < b.id)
	return all.slice(0, SQUAD_SIZE).map(func(p: PlayerData) -> String: return p.id)


## Week hook. On a break week the managed club's called-up players leave; the week after they return tired.
func weekly(career: CareerState) -> Dictionary:
	var out := {"left": [], "returned": [], "injured": []}
	if not called_up.is_empty():
		for pid in called_up:
			var p: PlayerData = career.db.get_player(str(pid))
			if p == null:
				continue
			p.fitness = clampi(p.fitness - RETURN_FATIGUE, 0, 100)
			out["returned"].append(pid)
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([career.season, career.week, pid, "intl"])
			if p.status == PlayerData.Status.ACTIVE and rng.randf() < INJURY_CHANCE:
				Availability.injure(career, p, 1 + int(rng.randi() % 3))
				out["injured"].append(pid)
		called_up = []
	if is_break(career.week):
		var by_nation := {}
		for p: PlayerData in career.db.get_squad(career.club_id):
			if p.status != PlayerData.Status.ACTIVE or p.nationality == "":
				continue
			if not by_nation.has(p.nationality):
				by_nation[p.nationality] = NationalBreaks.squad_for(career.db, p.nationality)
			if (by_nation[p.nationality] as Array).has(p.id):
				called_up.append(p.id)
				out["left"].append(p.id)
		if not called_up.is_empty():
			career.inbox.add("intl:%d:%d" % [career.season, career.week], career.season, career.week, "players", "INBOX_INTL_BREAK", [called_up.size()], {})
	return out


func to_dict() -> Dictionary:
	return {"called_up": called_up.duplicate()}


static func from_dict(d: Dictionary) -> NationalBreaks:
	var n := NationalBreaks.new()
	n.called_up = (d.get("called_up", []) as Array).map(func(x: Variant) -> String: return str(x))
	return n
