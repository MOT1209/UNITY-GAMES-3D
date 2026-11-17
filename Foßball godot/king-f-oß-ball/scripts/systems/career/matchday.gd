class_name Matchday
extends RefCounted

## Career phase C4 (logic part): pre-match opponent report (C4.1), team talks (C4.1 / C4.3), touchline shouts (C4.3) and the press
## conference (C4.4). Pure rules over the real career state, no scene access, so each effect is testable.
## NOT wired to screens or to the running 3D match yet: `Shouts.apply` returns the TacticsPreset the TeamAI would use.

# --- touchline shouts ---------------------------------------------------------------------------------

const SHOUTS := {
	"press_high": {"pressing": 25, "defensive_line": 15},
	"hold_lead": {"pressing": -10, "defensive_line": -25, "mentality": -1},
	"attack_wings": {"width": 30, "mentality": 1},
	"calm_down": {"pressing": -10, "passing_style": -1},
	"want_reaction": {"mentality": 1, "pressing": 10},
}
const SHOUT_DURATION_MIN := 3        # match minutes a shout lasts
const SHOUT_COOLDOWN_MIN := 6        # match minutes before the next one

var shout_id := ""
var shout_minute := -1000
var shouts_used := 0


## Starts a shout at match minute `minute`. False while one is cooling down or the id is unknown.
func shout(id: String, minute: int) -> bool:
	if not SHOUTS.has(id) or minute - shout_minute < SHOUT_COOLDOWN_MIN:
		return false
	shout_id = id
	shout_minute = minute
	shouts_used += 1
	return true


func active(minute: int) -> bool:
	return shout_id != "" and minute - shout_minute < SHOUT_DURATION_MIN


## The tactics the team plays with at `minute`: the base ones, bent by the active shout (a copy; `base` is never changed).
func effective_tactics(base: TacticsPreset, minute: int) -> TacticsPreset:
	var t := TacticsPreset.from_dict(base.to_dict())
	if not active(minute):
		return t
	var fx: Dictionary = SHOUTS[shout_id]
	t.pressing = clampi(t.pressing + int(fx.get("pressing", 0)), 0, 100)
	t.defensive_line = clampi(t.defensive_line + int(fx.get("defensive_line", 0)), 0, 100)
	t.width = clampi(t.width + int(fx.get("width", 0)), 0, 100)
	t.mentality = clampi(int(t.mentality) + int(fx.get("mentality", 0)), 0, TacticsPreset.Mentality.size() - 1) as TacticsPreset.Mentality
	t.passing_style = clampi(int(t.passing_style) + int(fx.get("passing_style", 0)), 0, TacticsPreset.PassingStyle.size() - 1) as TacticsPreset.PassingStyle
	return t


# --- team talk ------------------------------------------------------------------------------------------

const TALKS: Array[String] = ["calm", "motivate", "pressure", "focus"]


## A team talk before a match (`importance` 0..1: 1 = a final). Returns {reactions: [{player_id, delta, mood}], total}.
## The effect depends on each player's personality and the current atmosphere; a pressure talk to a tense squad before a big
## match backfires. Morale really moves and the reasons are logged ("MORALE_TALK_*").
static func team_talk(career: CareerState, kind: String, importance: float) -> Dictionary:
	var out := {"reactions": [], "total": 0}
	if not TALKS.has(kind):
		return out
	var squad: Array = career.db.get_squad(career.club_id).filter(func(p: PlayerData) -> bool: return p.status != PlayerData.Status.YOUTH)
	var avg := MoraleSystem.average(career.db, career.club_id)
	var tense := avg < 60.0
	for p: PlayerData in squad:
		var pers := PlayerPersonality.for_player(p)
		var d := 0
		match kind:
			"calm":
				d = 2 + (1 if int(pers["temperament"]) < 8 else 0) - (1 if importance > 0.8 and int(pers["pressure"]) >= 14 else 0)
			"motivate":
				d = 2 + int(round(importance * 2.0)) + (1 if int(pers["ambition"]) >= 12 else 0) - (2 if tense else 0)
			"pressure":
				var coping := int(pers["pressure"]) - 10
				d = int(round(coping * 0.35)) + int(round(importance * 2.0)) - (4 if tense else 0)
			"focus":
				d = 1 + (1 if int(pers["professionalism"]) >= 12 else 0)
		var real := career.morale.apply(p, d, "MORALE_TALK_" + kind.to_upper(), career.season, career.week)
		(out["reactions"] as Array).append({"player_id": p.id, "delta": real, "mood": "good" if real > 0 else ("bad" if real < 0 else "neutral")})
		out["total"] += real
	return out


# --- opponent report --------------------------------------------------------------------------------

## What the manager learns about `opponent_id` before a match. The amount of detail grows with the assistant's quality and the
## tactical style (`intel`): {form (last 5 W/D/L), xi (11 best), danger (player id), strongest, weakest, style, detail_level}.
static func opponent_report(career: CareerState, opponent_id: String) -> Dictionary:
	var db: Node = career.db
	var level := clampi(1 + int(round(career.delegation.quality * 2.0 * float(career.manager.style_effects()["intel"]))), 1, 4)
	var squad: Array = db.get_squad(opponent_id).filter(func(p: PlayerData) -> bool: return p.status != PlayerData.Status.YOUTH)
	squad.sort_custom(func(a: PlayerData, b: PlayerData) -> bool: return a.get_overall() > b.get_overall())
	var xi: Array = squad.slice(0, 11).map(func(p: PlayerData) -> String: return p.id)
	var report := {"detail_level": level, "opponent": opponent_id, "form": _form(career, opponent_id, 5), "xi": [], "danger": "", "strongest": "", "weakest": "", "style": ""}
	if level >= 2:
		report["xi"] = xi
		var best := ""
		var best_v := -1
		for p: PlayerData in squad.slice(0, 11):
			if p.position != PlayerData.Position.GK and p.get_overall() > best_v:
				best_v = p.get_overall()
				best = p.id
		report["danger"] = best
	if level >= 3:
		var lines := _line_ratings(db, squad.slice(0, 11))
		var keys: Array = lines.keys()
		keys.sort_custom(func(a: String, b: String) -> bool: return lines[a] > lines[b])
		report["strongest"] = keys[0]
		report["weakest"] = keys[keys.size() - 1]
		report["lines"] = lines
	if level >= 4:
		var lines2: Dictionary = report["lines"]
		report["style"] = "attacking" if lines2["attack"] >= lines2["defence"] + 3 else ("defensive" if lines2["defence"] >= lines2["attack"] + 3 else "balanced")
	return report


static func _line_ratings(db: Node, xi: Array) -> Dictionary:
	var sums := {"attack": [0, 0], "midfield": [0, 0], "defence": [0, 0]}
	for p: PlayerData in xi:
		var line := "defence"
		match p.position:
			PlayerData.Position.ST, PlayerData.Position.LW, PlayerData.Position.RW:
				line = "attack"
			PlayerData.Position.CM, PlayerData.Position.CAM, PlayerData.Position.CDM, PlayerData.Position.LM, PlayerData.Position.RM:
				line = "midfield"
		sums[line][0] += p.get_overall()
		sums[line][1] += 1
	var out := {}
	for k in sums:
		out[k] = int(round(float(sums[k][0]) / float(maxi(sums[k][1], 1)))) if sums[k][1] > 0 else 0
	return out


## Last `n` results of any club as "W"/"D"/"L", newest first, read from the real competitions.
static func _form(career: CareerState, team_id: String, n: int) -> Array:
	var rows: Array = []
	for cid in career.competitions:
		var comp: Competition = career.competitions[cid]
		for f in comp.fixtures:
			if not bool(f["played"]) or (f["home"] != team_id and f["away"] != team_id) or not comp.results.has(f["match_id"]):
				continue
			var r := MatchResult.from_dict(comp.results[f["match_id"]])
			var mine := r.home_goals if f["home"] == team_id else r.away_goals
			var theirs := r.away_goals if f["home"] == team_id else r.home_goals
			rows.append({"round": int(f["round"]), "res": "W" if mine > theirs else ("L" if mine < theirs else "D")})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["round"]) > int(b["round"]))
	return rows.slice(0, n).map(func(x: Dictionary) -> String: return str(x["res"]))


# --- press conference -------------------------------------------------------------------------------------

const TONES: Array[String] = ["calm", "confident", "critical", "evasive"]
const QUESTIONS: Array[String] = ["PRESS_Q_RESULT", "PRESS_Q_FORM", "PRESS_Q_TRANSFERS", "PRESS_Q_NEXT_MATCH"]


## Whether this match deserves a press conference: a heavy defeat, a big win, the end of the season or a derby-like match.
static func press_due(my_goals: int, their_goals: int, season_over := false, derby := false) -> bool:
	return season_over or derby or absi(my_goals - their_goals) >= 3


## Answers a question in a tone. Returns {board, fans, morale (squad delta applied), key} and applies them for real:
## calm: safe (+1 board), confident: team +2 but the board expects (-1 if the next result is bad - applied later), critical:
## the board likes honesty but the squad dislikes it (-2 squad, +1 board), evasive: nothing moves except fans -1.
static func press_answer(career: CareerState, tone: String, question: String = "PRESS_Q_RESULT") -> Dictionary:
	var out := {"board": 0, "fans": 0, "morale": 0, "key": "PRESS_REPLY_" + tone.to_upper()}
	if not TONES.has(tone):
		return out
	match tone:
		"calm":
			out["board"] = 1
			out["fans"] = 0
		"confident":
			out["board"] = 0
			out["fans"] = 1
			out["morale"] = 2
		"critical":
			out["board"] = 1
			out["fans"] = -1
			out["morale"] = -2
		"evasive":
			out["fans"] = -1
	if int(out["board"]) != 0:
		career.manager.apply_result(int(out["board"]), 0)
	if int(out["morale"]) != 0:
		for p: PlayerData in career.db.get_squad(career.club_id).filter(func(p: PlayerData) -> bool: return p.status != PlayerData.Status.YOUTH):
			career.morale.apply(p, int(out["morale"]), "MORALE_PRESS", career.season, career.week)
	career.fan_mood = clampi(career.fan_mood + int(out["fans"]), 0, 100)
	if not career.pending_press.is_empty():
		var pm := career.inbox.get_message(int(career.inbox._uids.get("press:%d:%d" % [career.season, int(career.pending_press.get("week", 0))], 0)))
		if not pm.is_empty():
			career.inbox.resolve(int(pm["id"]))
		career.pending_press = {}
	return out
