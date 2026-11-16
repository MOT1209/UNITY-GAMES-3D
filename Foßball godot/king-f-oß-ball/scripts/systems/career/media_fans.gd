class_name MediaFans
extends RefCounted

## Career phase C6: fan satisfaction with visible reasons, short in-game social posts, transfer rumours (some true), the trophy room,
## the hall of fame and the end-of-season summary. Saved with the career (`fan_log`, `rumours`). Texts are translation templates with
## variables, so every post exists in ar / de / en.

const FAN_LOG_MAX := 8
const POSTS := {
	"win": ["POST_WIN_1", "POST_WIN_2", "POST_WIN_3"],
	"loss": ["POST_LOSS_1", "POST_LOSS_2", "POST_LOSS_3"],
	"draw": ["POST_DRAW_1", "POST_DRAW_2"],
}

var fan_log: Array = []                       # [{season, week, key, delta}] newest last
var rumours: Array = []                       # [{player_id, club, week, true, due_week, done}]


## Moves the fans' mood and records why. Returns the delta really applied.
func fan_event(career: CareerState, delta: int, key: String) -> int:
	var before := career.fan_mood
	career.fan_mood = clampi(career.fan_mood + delta, 0, 100)
	var real := career.fan_mood - before
	if real != 0:
		fan_log.append({"season": career.season, "week": career.week, "key": key, "delta": real})
		while fan_log.size() > FAN_LOG_MAX:
			fan_log.pop_front()
	return real


func fan_reasons() -> Array:
	var out := fan_log.duplicate(true)
	out.reverse()
	return out


## Attendance share (0.5..1.2) from the fans' mood: a sad crowd stays home.
static func attendance_from_mood(fan_mood: int) -> float:
	return clampf(0.5 + 0.7 * float(fan_mood) / 100.0, 0.5, 1.2)


# --- social posts ------------------------------------------------------------------------------------------

## A post after a match of the managed club: {key, args} from a stable choice of template. `outcome` = win / draw / loss.
static func match_post(career: CareerState, outcome: String, opponent: String, score: String) -> Dictionary:
	var pool: Array = POSTS.get(outcome, [])
	if pool.is_empty():
		return {}
	var i := hash([career.season, career.week, opponent, outcome]) % pool.size()
	var t: TeamData = career.db.get_team(opponent)
	return {"key": pool[i], "args": [t.display_name if t != null else opponent, score]}


func post_match(career: CareerState, outcome: String, opponent: String, score: String) -> void:
	var p := match_post(career, outcome, opponent, score)
	if p.is_empty():
		return
	career.inbox.add("post:%d:%d:%s" % [career.season, career.week, opponent], career.season, career.week, "media", str(p["key"]), p["args"], {"sender": "fans"})


# --- rumours -------------------------------------------------------------------------------------------------

## Weekly: maybe starts a rumour about one of the user's best players. About 40% are true: the offer then really arrives within 2 weeks.
## Deterministic from season / week. Returns the rumour or {}.
func weekly_rumour(career: CareerState) -> Dictionary:
	var h := hash([career.season, career.week, "rumour"]) & 0x7fffffff
	if h % 100 >= 12:
		return {}
	var squad: Array = career.db.get_squad(career.club_id).filter(func(p: PlayerData) -> bool: return p.status != PlayerData.Status.YOUTH and p.loan_parent == "")
	squad.sort_custom(func(a: PlayerData, b: PlayerData) -> bool: return a.get_overall() > b.get_overall())
	if squad.is_empty():
		return {}
	var p: PlayerData = squad[(h / 100) % mini(5, squad.size())]
	var clubs: Array = career.db.list_teams(TeamData.Category.CLUB).filter(func(t: TeamData) -> bool: return t.id != career.club_id)
	if clubs.is_empty():
		return {}
	var club: TeamData = clubs[(h / 1000) % clubs.size()]
	var is_true := (h / 7) % 100 < 40
	var r := {"player_id": p.id, "club": club.id, "week": career.week, "true": is_true, "due_week": career.week + 1 + (h / 13) % 2, "done": false, "season": career.season}
	rumours.append(r)
	while rumours.size() > 20:
		rumours.pop_front()
	career.inbox.add("rumour:%d:%d" % [career.season, career.week], career.season, career.week, "media", "INBOX_RUMOUR", [club.display_name, p.display_name], {"sender": "press"})
	return r


## Weekly: a true rumour whose time has come becomes a real offer. Returns the offers created.
func deliver_rumours(career: CareerState) -> int:
	var n := 0
	for r in rumours:
		if bool(r["true"]) and not bool(r["done"]) and int(r["season"]) == career.season and career.week >= int(r["due_week"]):
			r["done"] = true
			var p: PlayerData = career.db.get_player(str(r["player_id"]))
			if p != null and p.team_id == career.club_id:
				var res := career.market.make_external_offer(p.id, career.db.get_team(str(r["club"])).display_name, career.db.get_team(str(r["club"])).country, int(career.market.market_value(p) * 0.95))
				if res.get("offer") != null:
					n += 1
	return n


# --- trophy room, hall of fame, season summary ---------------------------------------------------------------

## Titles of the managed club, newest first: [{season, competition, kind}] from the real history; plus the manager's trophy count.
static func trophy_room(career: CareerState) -> Dictionary:
	var titles: Array = []
	for h in career.club_history:
		if str(h.get("key", "")).begins_with("rewards_paid_") and str(h.get("champion", "")) == career.club_id:
			titles.append({"season": int(h["season"]), "competition": str(h["competition"])})
	for sc in career.world.super_cups:
		if str(sc["winner"]) == career.club_id:
			titles.append({"season": int(sc["season"]), "competition": "super_cup"})
	titles.reverse()
	return {"titles": titles, "manager_trophies": career.manager.trophies}


## Best scorers and most appearances of the career, and retired players among them (the legends).
static func hall_of_fame(career: CareerState, n: int = 5) -> Dictionary:
	var scorers: Array = []
	var apps: Array = []
	for pid in career.player_stats:
		var s: Dictionary = career.player_stats[pid]
		scorers.append({"player_id": pid, "value": int(s["goals"])})
		apps.append({"player_id": pid, "value": int(s["apps"])})
	var by_value := func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["value"]) > int(b["value"]) if int(a["value"]) != int(b["value"]) else str(a["player_id"]) < str(b["player_id"])
	scorers.sort_custom(by_value)
	apps.sort_custom(by_value)
	var legends: Array = []
	for a in apps:
		var p: PlayerData = career.db.get_player(str(a["player_id"]))
		if p != null and p.status == PlayerData.Status.RETIRED and int(a["value"]) >= 10:
			legends.append(a)
	return {"scorers": scorers.slice(0, n), "appearances": apps.slice(0, n), "legends": legends.slice(0, n)}


## Numbers of the season that just finished (or the running one): taken from the real tables and statistics.
static func season_summary(career: CareerState) -> Dictionary:
	var out := {"season": career.season, "rank": 0, "points": 0, "played": 0, "goals_for": 0, "goals_against": 0, "top_scorer": "", "top_scorer_goals": 0,
			"net_finance": 0, "young_players_used": 0}
	var ud := career.user_division()
	if not ud.is_empty():
		var pyr: LeaguePyramid = career.pyramids[ud["pyramid"]]
		var comp: Competition = career.competitions.get(pyr.comp.get(ud["division"]["id"], ""))
		if comp != null:
			var st := comp.standings()
			for i in st.size():
				if st[i]["team_id"] == career.club_id:
					out["rank"] = i + 1
					out["points"] = int(st[i]["points"])
					out["played"] = int(st[i]["played"])
					out["goals_for"] = int(st[i]["gf"])
					out["goals_against"] = int(st[i]["ga"])
	var best := 0
	for p: PlayerData in career.db.get_squad(career.club_id):
		var s := career.stats_for(p.id, career.season)
		if int(s["goals"]) > best:
			best = int(s["goals"])
			out["top_scorer"] = p.id
			out["top_scorer_goals"] = best
		if p.age <= 21 and int(s["apps"]) >= 6:
			out["young_players_used"] += 1
	out["net_finance"] = int(career.ledger().report()["net"])
	return out


func to_dict() -> Dictionary:
	return {"fan_log": fan_log.duplicate(true), "rumours": rumours.duplicate(true)}


static func from_dict(d: Dictionary) -> MediaFans:
	var m := MediaFans.new()
	m.fan_log = PlayerData._restore_ints((d.get("fan_log", []) as Array).duplicate(true)).slice(-FAN_LOG_MAX)
	m.rumours = PlayerData._restore_ints((d.get("rumours", []) as Array).duplicate(true))
	for r in m.rumours:
		r["true"] = bool(r.get("true", false))
		r["done"] = bool(r.get("done", false))
	return m
