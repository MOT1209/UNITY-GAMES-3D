class_name MatchEventEngine
extends RefCounted

## Phase S1: event-based match simulation. Two modes, one set of rules:
##   * `distribute(...)`: the score is already decided (by `MatchSimulator`, whose goal distribution is calibrated); the engine
##     turns it into a full match record — goal minutes, scorers and assisting players (weighted by position, shooting and
##     passing), shots, corners, fouls, cards, possession, injuries and a rating per player. Deterministic per seed.
##     Sum of the scorers' goals = the team's goals, always.
##   * `LiveMatch`: minute by minute with tactics that act at once (used by the live simulation screen).
## An event: {minute, type: goal/shot/save/corner/foul/yellow/red/injury/sub, side, player_id, assist_id}.

const WEIGHT := SeasonStats.POSITION_GOAL_WEIGHT


## Lineup of a club for a match: the best available eleven ({"xi": Array[PlayerData], "outfield": Array[PlayerData]}).
static func lineup(db: Node, team_id: String, rotate: bool = false) -> Array[PlayerData]:
	return SeasonStats._build_eleven(db, team_id, rotate)


static func _pick(rng: RandomNumberGenerator, players: Array, key: String, exclude: String = "") -> PlayerData:
	var total := 0.0
	var ws: Array[float] = []
	for p: PlayerData in players:
		var w := 0.0
		if p.id != exclude and p.position != PlayerData.Position.GK:
			w = float(WEIGHT.get(SeasonStats._position_keys[p.position], 1.0)) * float(p.get(key))
		ws.append(w)
		total += w
	if total <= 0.0:
		return null
	var roll := rng.randf() * total
	for i in players.size():
		roll -= ws[i]
		if roll <= 0.0 and ws[i] > 0.0:
			return players[i]
	return players[players.size() - 1]


## Full record of a match with a fixed score. Returns {events, stats, ratings, lineups}.
static func distribute(db: Node, home_id: String, away_id: String, hg: int, ag: int, seed_text: String, rotate_home := true, rotate_away := true) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("evt|" + seed_text)
	var xi := {"home": lineup(db, home_id, rotate_home), "away": lineup(db, away_id, rotate_away)}
	var goals := {"home": hg, "away": ag}
	var events: Array = []
	var stats := {"home": _empty_stats(), "away": _empty_stats()}
	var bonus := {}
	var ratings := {}
	for side in ["home", "away"]:
		var other := "away" if side == "home" else "home"
		var outfield: Array = (xi[side] as Array).filter(func(p: PlayerData) -> bool: return p.position != PlayerData.Position.GK)
		for g in int(goals[side]):
			var scorer := _pick(rng, outfield, "shooting")
			if scorer == null:
				continue
			var ev := {"minute": 1 + rng.randi() % 90, "type": "goal", "side": side, "player_id": scorer.id, "assist_id": ""}
			if rng.randf() < 0.7:
				var a := _pick(rng, outfield, "passing", scorer.id)
				if a != null:
					ev["assist_id"] = a.id
					bonus[a.id] = float(bonus.get(a.id, 0.0)) + 0.4
			bonus[scorer.id] = float(bonus.get(scorer.id, 0.0)) + 0.9
			events.append(ev)
		# shots: every goal is a shot on target; the rest by a quality-driven count
		var shots := int(goals[side]) + 4 + rng.randi() % 9
		var on_target := mini(shots, int(goals[side]) + 1 + rng.randi() % 4)
		stats[side]["shots"] = shots
		stats[side]["on_target"] = on_target
		stats[side]["corners"] = 2 + rng.randi() % 7
		stats[side]["xg"] = snappedf(float(shots) * 0.1 + float(goals[side]) * 0.35, 0.01)
		for i in shots - int(goals[side]):
			var s := _pick(rng, outfield, "shooting")
			if s != null:
				events.append({"minute": 1 + rng.randi() % 90, "type": "shot" if i >= on_target - int(goals[side]) else "save", "side": side, "player_id": s.id, "assist_id": ""})
		for i in int(stats[side]["corners"]):
			events.append({"minute": 1 + rng.randi() % 90, "type": "corner", "side": side, "player_id": "", "assist_id": ""})
		# discipline: fouls, cards, a rare injury
		var fouls := 6 + rng.randi() % 9
		stats[side]["fouls"] = fouls
		for i in fouls:
			if rng.randf() < 0.22:
				var f := _pick(rng, xi[side], "defending")
				if f != null:
					var red := rng.randf() < 0.04
					events.append({"minute": 1 + rng.randi() % 90, "type": "red" if red else "yellow", "side": side, "player_id": f.id, "assist_id": ""})
					stats[side]["reds" if red else "yellows"] += 1
		if rng.randf() < 0.05:
			var inj := _pick(rng, xi[side], "physical")
			if inj != null:
				events.append({"minute": 1 + rng.randi() % 90, "type": "injury", "side": side, "player_id": inj.id, "assist_id": ""})
		var conceded: int = int(goals[other])
		for p: PlayerData in xi[side]:
			var r := 6.0 + (0.3 if int(goals[side]) > conceded else (-0.3 if int(goals[side]) < conceded else 0.0)) + float(bonus.get(p.id, 0.0))
			if p.position == PlayerData.Position.GK:
				r += 0.6 if conceded == 0 else -0.2 * conceded
			ratings[p.id] = snappedf(clampf(r + rng.randf_range(-0.3, 0.3), 3.0, 10.0), 0.1)
	var h_str := _strength(xi["home"]) + 4.0
	var share := clampf(50.0 + (h_str - _strength(xi["away"])) * 0.8, 30.0, 70.0)
	stats["home"]["possession"] = roundi(share)
	stats["away"]["possession"] = 100 - roundi(share)
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["minute"]) < int(b["minute"]))
	return {"events": events, "stats": stats, "ratings": ratings,
			"lineups": {"home": (xi["home"] as Array).map(func(p: PlayerData) -> String: return p.id), "away": (xi["away"] as Array).map(func(p: PlayerData) -> String: return p.id)}}


static func _strength(xi: Array) -> float:
	var s := 0.0
	for p: PlayerData in xi:
		s += float(p.get_overall())
	return s / maxf(xi.size(), 1.0)


static func _empty_stats() -> Dictionary:
	return {"shots": 0, "on_target": 0, "corners": 0, "fouls": 0, "yellows": 0, "reds": 0, "possession": 50, "xg": 0.0}


## One-line text of an event for the live feed (keys DATE-style translated through Loc).
static func describe(db: Node, ev: Dictionary) -> String:
	var p: PlayerData = db.get_player(str(ev.get("player_id", ""))) if str(ev.get("player_id", "")) != "" else null
	var name := p.display_name if p != null else ""
	match str(ev["type"]):
		"goal":
			var a: PlayerData = db.get_player(str(ev.get("assist_id", ""))) if str(ev.get("assist_id", "")) != "" else null
			return Loc.f("LIVE_EV_GOAL_ASSIST", [name, a.display_name]) if a != null else Loc.f("LIVE_EV_GOAL", name)
		"shot": return Loc.f("LIVE_EV_SHOT", name)
		"save": return Loc.f("LIVE_EV_SAVE", name)
		"corner": return Loc.t("LIVE_EV_CORNER")
		"yellow": return Loc.f("LIVE_EV_YELLOW", name)
		"red": return Loc.f("LIVE_EV_RED", name)
		"injury": return Loc.f("LIVE_EV_INJURY", name)
	return ""


## --- live, minute by minute -------------------------------------------------------------------------------------------

class LiveMatch:
	extends RefCounted
	## Tactics that change the chances at once: mentality -1 defensive / 0 balanced / +1 attacking, pressing 0..100.
	var db: Node
	var home_id := ""
	var away_id := ""
	var minute := 0
	var score := {"home": 0, "away": 0}
	var events: Array = []
	var stats := {"home": MatchEventEngine._empty_stats(), "away": MatchEventEngine._empty_stats()}
	var mentality := {"home": 0, "away": 0}
	var pressing := {"home": 50, "away": 50}
	var xi := {}
	var subs_used := {"home": 0, "away": 0}
	var rng := RandomNumberGenerator.new()
	var _poss_ticks := {"home": 0, "away": 0}
	var _strength := {"home": 0.0, "away": 0.0}

	func _init(p_db: Node, p_home: String, p_away: String, seed_value: int = 1) -> void:
		db = p_db
		home_id = p_home
		away_id = p_away
		rng.seed = seed_value
		xi = {"home": MatchEventEngine.lineup(db, p_home), "away": MatchEventEngine.lineup(db, p_away)}
		_strength = {"home": MatchEventEngine._strength(xi["home"]) + 4.0 + _morale_edge(xi["home"]), "away": MatchEventEngine._strength(xi["away"]) + _morale_edge(xi["away"])}

	## Squad mood and freshness: +-2 rating points (morale 70 and fitness 90 are neutral).
	static func _morale_edge(list: Array) -> float:
		var m := 0.0
		var f := 0.0
		for p: PlayerData in list:
			m += float(p.morale)
			f += float(p.fitness)
		var n := maxf(list.size(), 1.0)
		return clampf((m / n - 70.0) * 0.06 + (f / n - 90.0) * 0.05, -2.0, 2.0)

	func finished() -> bool:
		return minute >= 90

	## Plays one minute; returns the events it produced.
	func step() -> Array:
		if finished():
			return []
		minute += 1
		var out: Array = []
		for side in ["home", "away"]:
			var other := "away" if side == "home" else "home"
			var edge := float(_strength[side]) - float(_strength[other])
			var atk := 1.0 + 0.18 * float(mentality[side]) + (float(pressing[side]) - 50.0) / 400.0
			var dfn := 1.0 - 0.12 * float(mentality[other]) - (float(pressing[other]) - 50.0) / 600.0
			var lam_shot := clampf(0.13 + edge * 0.004, 0.05, 0.3) * atk * clampf(dfn, 0.7, 1.3)
			_poss_ticks[side] += 1 if rng.randf() < clampf(0.5 + edge * 0.01 + 0.04 * float(mentality[side]), 0.3, 0.7) else 0
			if rng.randf() < lam_shot:
				var outfield: Array = (xi[side] as Array).filter(func(p: PlayerData) -> bool: return p.position != PlayerData.Position.GK)
				var shooter := MatchEventEngine._pick(rng, outfield, "shooting")
				if shooter == null:
					continue
				stats[side]["shots"] += 1
				var quality := clampf(0.10 + float(shooter.shooting) / 700.0 + edge * 0.002, 0.05, 0.3)
				if rng.randf() < 0.42:
					stats[side]["on_target"] += 1
					if rng.randf() < quality * 1.9:
						var ev := {"minute": minute, "type": "goal", "side": side, "player_id": shooter.id, "assist_id": ""}
						if rng.randf() < 0.7:
							var a := MatchEventEngine._pick(rng, outfield, "passing", shooter.id)
							if a != null:
								ev["assist_id"] = a.id
						score[side] += 1
						out.append(ev)
					else:
						out.append({"minute": minute, "type": "save", "side": side, "player_id": shooter.id, "assist_id": ""})
				elif rng.randf() < 0.3:
					stats[side]["corners"] += 1
					out.append({"minute": minute, "type": "corner", "side": side, "player_id": "", "assist_id": ""})
				if rng.randf() < 0.18 * (1.0 + float(pressing[other]) / 150.0):
					var f := MatchEventEngine._pick(rng, xi[other], "defending")
					if f != null:
						stats[other]["fouls"] += 1
						if rng.randf() < 0.3:
							var red := rng.randf() < 0.05
							stats[other]["reds" if red else "yellows"] += 1
							out.append({"minute": minute, "type": "red" if red else "yellow", "side": other, "player_id": f.id, "assist_id": ""})
							if red:
								(xi[other] as Array).erase(f)
								_strength[other] = MatchEventEngine._strength(xi[other]) - 4.0
		var total := float(_poss_ticks["home"] + _poss_ticks["away"])
		stats["home"]["possession"] = roundi(100.0 * float(_poss_ticks["home"]) / maxf(total, 1.0))
		stats["away"]["possession"] = 100 - int(stats["home"]["possession"])
		events.append_array(out)
		return out

	## Substitution (max 5 per side): the bench player takes the slot of `out_id`.
	func substitute(side: String, out_id: String, in_id: String) -> String:
		if int(subs_used[side]) >= 5:
			return "no_subs_left"
		var list: Array = xi[side]
		for i in list.size():
			if (list[i] as PlayerData).id == out_id:
				var pin: PlayerData = db.get_player(in_id)
				if pin == null:
					return "unknown_player"
				list[i] = pin
				subs_used[side] += 1
				events.append({"minute": minute, "type": "sub", "side": side, "player_id": in_id, "assist_id": out_id})
				_strength[side] = MatchEventEngine._strength(list) + (4.0 if side == "home" else 0.0)
				return ""
		return "not_on_pitch"

	func result(match_id: String = "live") -> MatchResult:
		return MatchResult.make(match_id, home_id, away_id, int(score["home"]), int(score["away"]))

	## The same record `distribute` produces ({events, stats, ratings, lineups}), so a live match feeds the statistics like
	## any simulated one: scorers, assists, cards and ratings are exactly what the screen showed.
	func record() -> Dictionary:
		var ratings := {}
		var bonus := {}
		for ev in events:
			if str(ev["type"]) == "goal":
				bonus[ev["player_id"]] = float(bonus.get(ev["player_id"], 0.0)) + 0.9
				if str(ev["assist_id"]) != "":
					bonus[ev["assist_id"]] = float(bonus.get(ev["assist_id"], 0.0)) + 0.4
		for side in ["home", "away"]:
			var other := "away" if side == "home" else "home"
			var rb := 0.3 if int(score[side]) > int(score[other]) else (-0.3 if int(score[side]) < int(score[other]) else 0.0)
			for p: PlayerData in xi[side]:
				var r := 6.0 + rb + float(bonus.get(p.id, 0.0))
				if p.position == PlayerData.Position.GK:
					r += 0.6 if int(score[other]) == 0 else -0.2 * int(score[other])
				ratings[p.id] = snappedf(clampf(r, 3.0, 10.0), 0.1)
		return {"events": events.duplicate(true), "stats": stats.duplicate(true), "ratings": ratings,
				"lineups": {"home": (xi["home"] as Array).map(func(p: PlayerData) -> String: return p.id), "away": (xi["away"] as Array).map(func(p: PlayerData) -> String: return p.id)}}
