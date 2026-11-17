class_name BoardObjectives
extends RefCounted

## Season objectives set by the board and their evaluation (Phase 4). Pure functions.
## Objective: finish at or above `target_rank` in the club's division. The target comes from the club's rating rank
## inside the division (best club = 1): `target = max(1, round(rating_rank * 0.8))`, never worse than the safe zone.
## Result: MET (rank <= target) +8 confidence; PARTIAL (<= target + 2) -3; FAILED -25. Champion: +5 reputation and a
## trophy; relegation zone: an extra -15 confidence. Reputation moves +3 / 0 / -3 for met / partial / failed.


## Objective for `club_id` in a division described by LeagueDef's division dict (`team_ids`, `relegate`, `name`).
static func for_club(db: Node, club_id: String, division: Dictionary) -> Dictionary:
	var ids: Array = (division.get("team_ids", []) as Array).duplicate()
	if not (club_id in ids):
		return {}
	ids.sort_custom(func(a: String, b: String) -> bool:
		var ra: int = db.get_team_rating(a)
		var rb: int = db.get_team_rating(b)
		return ra > rb if ra != rb else a < b)
	var rating_rank := ids.find(club_id) + 1
	var size := ids.size()
	var safe := size - int(division.get("relegate", 0))
	var target := clampi(roundi(float(rating_rank) * 0.8), 1, maxi(safe, 1))
	return {"target_rank": target, "rating_rank": rating_rank, "division_size": size, "relegate": int(division.get("relegate", 0))}


## Evaluates a finished season. `rank` = final league position (1 = champion). Returns
## {result: "met"|"partial"|"failed", confidence: int, reputation: int, champion: bool, relegated: bool}.
static func evaluate(objective: Dictionary, rank: int) -> Dictionary:
	if objective.is_empty() or rank < 1:
		return {}
	var target := int(objective["target_rank"])
	var size := int(objective["division_size"])
	var relegated: bool = int(objective.get("relegate", 0)) > 0 and rank > size - int(objective["relegate"])
	var result := "failed"
	var dc := -25
	var dr := -3
	if rank <= target:
		result = "met"
		dc = 8
		dr = 3
	elif rank <= target + 2:
		result = "partial"
		dc = -3
		dr = 0
	var champion := rank == 1
	if champion:
		dr += 5
	if relegated:
		dc -= 15
	return {"result": result, "confidence": dc, "reputation": dr, "champion": champion, "relegated": relegated}


## Clubs that would hire a manager with `reputation`: rating at most 40 + 0.45 * reputation, best first, at most `limit`.
## A manager is never left without offers: when fewer than MIN_OFFERS clubs qualify, the weakest clubs of the world fill up.
const MIN_OFFERS := 3


static func job_offers(db: Node, reputation: int, exclude_club: String, limit: int = 5) -> Array:
	var cap := 40.0 + 0.45 * float(reputation)
	var all: Array = []
	for t: TeamData in db.list_teams(TeamData.Category.CLUB):
		if t.id != exclude_club:
			all.append({"club_id": t.id, "rating": db.get_team_rating(t.id)})
	var better := func(a: Dictionary, b: Dictionary) -> bool:
		return a["rating"] > b["rating"] if a["rating"] != b["rating"] else a["club_id"] < b["club_id"]
	all.sort_custom(better)
	var out: Array = all.filter(func(o: Dictionary) -> bool: return float(o["rating"]) <= cap)
	if out.size() < MIN_OFFERS:
		out = all.slice(maxi(all.size() - MIN_OFFERS, 0))         # the weakest clubs always hire
	return out.slice(0, limit)
