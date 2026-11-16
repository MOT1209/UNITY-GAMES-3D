class_name ClubVision
extends RefCounted

## Career phase C2.1 / C2.2: a club's long-term vision, DERIVED from the club's budget rank and age profile (never stored, so
## every save has one), and the extra season objectives that follow from it. Same function for the user's club and the AI clubs.

const VISIONS: Array[String] = ["titles", "profit", "youth", "stability", "promotion"]


## `division` = {team_ids, ...}. titles: top 3 by rating; promotion: a lower tier that is not bottom-ranked;
## youth: young squad; profit: a rich but not top club; stability: everything else.
static func for_club(db: Node, club_id: String, division: Dictionary, tier: int = 1) -> String:
	var ids: Array = (division.get("team_ids", []) as Array).duplicate()
	if not (club_id in ids):
		return "stability"
	ids.sort_custom(func(a: String, b: String) -> bool:
		var ra: int = db.get_team_rating(a)
		var rb: int = db.get_team_rating(b)
		return ra > rb if ra != rb else a < b)
	var rank := ids.find(club_id) + 1
	var size := ids.size()
	var t: TeamData = db.get_team(club_id)
	var squad: Array = db.get_squad(club_id)
	var avg_age := 0.0
	for p: PlayerData in squad:
		avg_age += p.age
	avg_age = avg_age / maxf(squad.size(), 1.0)
	if tier <= 1 and rank <= 3:
		return "titles"
	if tier > 1 and rank <= maxi(size / 3, 1):
		return "promotion"
	if avg_age <= 23.5:
		return "youth"
	var budget_rank := 1
	for id in ids:
		var o: TeamData = db.get_team(str(id))
		if o != null and t != null and o.budget > t.budget:
			budget_rank += 1
	if budget_rank <= maxi(size / 3, 1):
		return "profit"
	return "stability"


## Extra objectives (0-2) for the season, with the numbers to beat: [{kind, target, start}]. Weights (confidence points when met /
## missed) are fixed by kind in `evaluate_extras`.
static func extras_for(vision: String, ledger_balance: int) -> Array:
	match vision:
		"youth":
			return [{"kind": "youth", "target": 3, "start": 0}]
		"profit":
			return [{"kind": "profit", "target": 0, "start": ledger_balance}]
		"titles":
			return [{"kind": "profit", "target": 0, "start": ledger_balance}]
		"promotion", "stability":
			return [{"kind": "youth", "target": 2, "start": 0}]
	return []


## Evaluates the extras at season end. Returns [{kind, met, delta}] and the summed confidence delta is `sum_delta(result)`.
static func evaluate_extras(career: CareerState, extras: Array) -> Array:
	var out: Array = []
	for e in extras:
		var met := false
		match str(e["kind"]):
			"youth":
				var n := 0
				for p: PlayerData in career.db.get_squad(career.club_id):
					if p.age <= 21 and int(career.stats_for(p.id, career.season)["apps"]) >= 6:
						n += 1
				met = n >= int(e["target"])
			"profit":
				met = career.ledger().balance >= int(e["start"]) + int(e["target"])
		out.append({"kind": str(e["kind"]), "met": met, "delta": 2 if met else -2})
	return out


static func sum_delta(results: Array) -> int:
	var d := 0
	for r in results:
		d += int(r["delta"])
	return d
