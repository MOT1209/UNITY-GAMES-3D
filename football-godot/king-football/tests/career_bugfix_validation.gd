## Bug-fix validation (career start / loans / free agents / wage budget / development / youth).
##   godot --headless --path . res://tests/career_bugfix_validation.tscn
## Saves go to a private folder, never to the player's saves.
extends Node

const PACK := "real_2025"
const ROOT := "user://test_bugfix_saves"

var _passed := 0
var _failed := 0
var app: Node
var hub: HubRoot


func _check(ok: bool, name: String, detail := "") -> void:
	if ok:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s%s" % [name, (" — " + detail) if detail != "" else ""])


func _ready() -> void:
	await get_tree().process_frame
	print("=== KING FOOTBALL — Career bug-fix validation ===")
	app = get_node("/root/AppHub")
	var cfg := ConfigFile.new()
	var had_cfg := cfg.load(TeamDatabase.SETTINGS_PATH) == OK
	var saved_pack: String = str(cfg.get_value("data", "pack", "")) if had_cfg else ""
	var saved_root: String = app.save_root
	app.save_root = ROOT
	DirAccess.make_dir_recursive_absolute(ROOT)
	for f in DirAccess.get_files_at(ROOT):
		DirAccess.remove_absolute(ROOT + "/" + f)
	hub = (load("res://ui/hub/hub.tscn") as PackedScene).instantiate() as HubRoot
	add_child(hub)
	await get_tree().process_frame
	var only := OS.get_cmdline_user_args()          # optional: -- continue | market (run one part)
	if only.is_empty() or "continue" in only:
		await _test_new_career_continue()
	if only.is_empty() or "market" in only:
		await _test_market_and_development()
	app.save_root = saved_root
	app.switch_world(saved_pack)
	hub.queue_free()
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


## Wizard -> start -> (save) -> main-menu Continue (load the latest save) -> career Continue, per world and several clubs.
func _test_new_career_continue() -> void:
	var worlds: Array = [""]
	if TeamDatabase.available_packs().any(func(p: Dictionary) -> bool: return p["id"] == PACK):
		worlds.append(PACK)
	for world in worlds:
		app.switch_world(world)
		app.career = null
		hub.navigate("career_wizard")
		await get_tree().process_frame
		var w := hub.current
		w.select_world(world)
		var picks: Array = []
		if world == "":
			picks = w.division_clubs().slice(0, 2).map(func(t: TeamData) -> String: return t.id)
		else:
			for key in app.db.leagues.keys().slice(0, 3):
				w.league_key = key
				w.division_index = 0
				var clubs: Array = w.division_clubs()
				if not clubs.is_empty():
					picks.append((clubs[clubs.size() - 1] as TeamData).id)
		for club_id in picks:
			hub.navigate("career_wizard")
			await get_tree().process_frame
			w = hub.current
			if world != "":
				w.world_id = world
				for key in app.db.leagues.keys():
					if (app.db.leagues[key] as LeagueDef).divisions.any(func(d: Dictionary) -> bool: return club_id in d.get("team_ids", [])):
						w.league_key = key
			w.club_id = club_id
			w.coach_name = "Test Coach"
			var err: String = w.start_career()
			var tag := "[%s/%s]" % [world if world != "" else "fictional", club_id]
			_check(err == "" and app.career != null and app.career.club_id == club_id, "%s new career starts" % tag, err)
			if app.career == null:
				continue
			var audit := CareerValidator.validate(app.career, false)
			_check((audit["errors"] as Array).is_empty(), "%s a fresh career passes its integrity audit" % tag, str((audit["errors"] as Array).slice(0, 3)))
			_check(FileAccess.file_exists(app.latest_save_path()), "%s the new career is on disk right away (Continue has something to load)" % tag)
			var info: Dictionary = app.save_info(app.latest_save_path())
			_check(str(info.get("club", "")) == app.db.get_team(club_id).display_name, "%s the newest save is the new career" % tag, str(info))
			var lerr: String = app.load_game()
			_check(lerr == "" and app.career != null and app.career.club_id == club_id, "%s main-menu Continue loads it" % tag, lerr)
			if app.career == null:
				continue
			var res: Dictionary = await CareerFlow.continue_days(app.career, app.advance_day_async)
			_check(app.career != null and res.has("stop"), "%s career Continue advances" % tag, str(res))
			var serr: String = app.save_game()
			_check(serr == "", "%s saving after Continue" % tag, serr)
			var lerr2: String = app.load_game()
			_check(lerr2 == "" and app.career != null and app.career.club_id == club_id, "%s ... and loading it again" % tag, lerr2)


# --- loans / free agents / wage budget / development / youth (one career in the fictional world, every step through the hub) ---

func _test_market_and_development() -> void:
	app.switch_world("")
	app.career = null
	_check(app.start_career("club_desert_kings") == "", "career for the market and development checks")
	var c: CareerState = app.career
	var m: TransferMarket = c.market
	m.replies_next_week = false
	for i in 3:                                          # pre-season week 0: the summer window opens in week 1
		if TransferMarket.window_open(c.week):
			break
		app.advance_week()
	_check(TransferMarket.window_open(c.week), "the transfer window is open", str(c.week))
	_test_wage_budget(c, m)
	_test_free_agents(c, m)
	_test_loans(c, m)
	await _test_development(c)


## 6: a club with 30 M in the bank is not refused a reasonable wage; transfer and wage money stay separate; the reason has figures.
func _test_wage_budget(c: CareerState, m: TransferMarket) -> void:
	var l: FinanceLedger = c.ledger()
	l.balance = 30_000_000
	l.transfer_budget = 12_000_000
	var room := m.wage_room(c.club_id)
	_check(room >= (30_000_000 - 12_000_000) / TransferMarket.WAGE_RESERVE_WEEKS, "[wage] 30 M balance: the spare cash raises the weekly wage room", "room %d" % room)
	_check(m.wage_room(c.club_id) == m.wage_budget_of(c.club_id) - m.wage_bill(c.club_id), "[wage] room = budget - the wages really paid (wage_bill)")
	var tb := l.transfer_budget
	var before := m.wage_budget_of(c.club_id)
	l.spend_transfer("transfer_in", 1_000_000, "test fee", c.week)
	_check(l.transfer_budget == tb - 1_000_000 and m.wage_budget_of(c.club_id) == before, "[wage] a transfer fee lowers the transfer budget, not the wage budget")
	var err := m.wage_check(c.club_id, room + 1)
	var shown := ErrorText.localize(err)
	_check(err.begins_with("wage budget exceeded (") and shown != err and shown.find(Loc.num(room)) >= 0 and shown.find(Loc.num(room + 1)) >= 0,
			"[wage] a refusal names the room and the need", shown)
	_check(m.wage_check(c.club_id, room) == "", "[wage] a wage that fits is allowed")


## 5: several free agents with reasonable (demanded) wages sign; the old club's wage is no floor any more; lowballs get a reason.
func _test_free_agents(c: CareerState, m: TransferMarket) -> void:
	var signed := 0
	var tried := 0
	var others: Array = c.db.list_teams(TeamData.Category.CLUB).filter(func(t: TeamData) -> bool: return t.id != c.club_id)
	for t: TeamData in others.slice(0, 4):
		var squad: Array = c.db.get_squad(t.id)
		squad.sort_custom(func(a: PlayerData, b: PlayerData) -> bool: return a.get_overall() > b.get_overall())
		var p: PlayerData = squad[3]
		t.squad_ids.erase(p.id)                 # released: a free agent who earned a big wage at his old club
		p.team_id = ""
		p.salary *= 3
		tried += 1
		var fair := m.fair_wage(p)
		_check(m.minimum_wage(p) <= fair, "[free] %s: the minimum follows his level, not his old wage" % p.display_name, "min %d fair %d old %d" % [m.minimum_wage(p), fair, p.salary])
		var low := ContractOffer.make(maxi(100, fair / 4), 2, "rotation")
		var a_low := m.player_answer(p, c.club_id, low)
		_check(a_low["status"] != TransferOffer.ACCEPTED and str(a_low["reason"]) != "", "[free] %s: a lowball is not accepted and has a reason" % p.display_name, str(a_low["reason"]))
		var r: Dictionary = m.make_offer(c.club_id, p.id, TransferOffer.FREE, {})
		if r["offer"] == null:
			_check(false, "[free] offer for %s" % p.display_name, str(r["error"]))
			continue
		var terms := m.free_agent_terms(p, c.club_id)
		var err := m.propose_contract((r["offer"] as TransferOffer).id, terms)
		if err == "" and p.team_id == c.club_id:
			signed += 1
		else:
			_check(false, "[free] %s signs at his stated terms" % p.display_name, "%s / %s" % [err, (r["offer"] as TransferOffer).reason])
	_check(signed == tried, "[free] %d of %d free agents signed at reasonable wages" % [signed, tried])


## 2/4: a player listed for loan is lent; the owner's out-limit does not block a listed player; in and out are counted apart.
func _test_loans(c: CareerState, m: TransferMarket) -> void:
	var others: Array = c.db.list_teams(TeamData.Category.CLUB).filter(func(t: TeamData) -> bool: return t.id != c.club_id)
	var owner: TeamData = others[5]
	var squad: Array = c.db.get_squad(owner.id)
	squad.sort_custom(func(a: PlayerData, b: PlayerData) -> bool: return a.get_overall() < b.get_overall())
	var target: PlayerData = squad[0]
	_check(m.set_listing(owner.id, target.id, TransferMarket.LISTING_LOAN, {"loan_min_split": 50}) == "", "[loan] the owner lists a player for loan")
	# the owner is at its loan-out limit (its squad is too small to really lend six players: temporary entries, removed below)
	var fake: Array = []
	for i in TransferMarket.MAX_LOANS_OUT:
		fake.append("test_fake_loan_%d" % i)
		m.loans[fake[-1]] = {"from": owner.id, "to": others[(i + 1) % others.size()].id, "wage_split": 100, "type": TransferOffer.LOAN}
	_check(m.loans_out(owner.id) >= TransferMarket.MAX_LOANS_OUT, "[loan] the owner is at its out-limit", "%d" % m.loans_out(owner.id))
	_check(m.loans_in(c.club_id) == 0, "[loan] loans of other clubs are not counted as the user's incoming loans")
	_check(m.refusal(target, c.club_id, true) == "", "[loan] a listed player is still available", m.refusal(target, c.club_id, true))
	_check(m.refusal(squad[1], c.club_id, true) == "OFFER_REASON_LOAN_LIMIT" or m.is_loan_listed((squad[1] as PlayerData).id), "[loan] an unlisted player of that club is still refused (limit kept)", m.refusal(squad[1], c.club_id, true))
	for i in range(TransferMarket.MAX_LOANS_OUT, TransferMarket.MAX_LOANS_OUT_LISTED):
		fake.append("test_fake_loan_%d" % i)
		m.loans[fake[-1]] = {"from": owner.id, "to": others[(i + 1) % others.size()].id, "wage_split": 100, "type": TransferOffer.LOAN}
	_check(m.refusal(target, c.club_id, true) == "OFFER_REASON_LOAN_LIMIT", "[loan] even a listed player is refused at the hard loan-out cap", m.refusal(target, c.club_id, true))
	for k in fake:
		m.loans.erase(k)
	var r: Dictionary = m.make_offer(c.club_id, target.id, TransferOffer.LOAN, {"wage_split_percent": 50})
	var o: TransferOffer = r["offer"]
	_check(o != null and o.status == TransferOffer.COMPLETED and target.team_id == c.club_id, "[loan] the loan request for the listed player is accepted and completed",
			"%s / %s / %s" % [r["error"], o.status if o != null else "", o.reason if o != null else ""])
	_check(m.loans_in(c.club_id) == 1 and m.loans_out(c.club_id) == 0, "[loan] the user's loan counts as incoming, not outgoing")
	var mine: Array = c.db.get_squad(c.club_id).filter(func(q: PlayerData) -> bool: return q.loan_parent == "")
	var oerr := m.loan(others[1].id, (mine[mine.size() - 1] as PlayerData).id, 10, 0, c.week, {}, {"wage_split_percent": 0})
	_check(oerr == "", "[loan] the user lends a player out", oerr)
	_check(m.loans_out(c.club_id) == 1 and m.loans_in(c.club_id) == 1, "[loan] lending one out leaves the incoming count unchanged")


func _academy_sum(c: CareerState) -> int:
	var s := 0
	var ac: Academy = app.academy()
	for pid in ac.roster_ids:
		var y: PlayerData = c.db.get_player(pid)
		for a in DevelopmentPlans.tracked_attrs(y):
			s += y.get_attribute(a)
	return s


## 7-10: development plans and academy training show real gains; the screen estimate and reports match; everything survives save / load.
func _test_development(c: CareerState) -> void:
	var squad: Array = c.db.get_squad(c.club_id).filter(func(q: PlayerData) -> bool: return q.loan_parent == "" and q.potential - q.get_overall() >= 4)
	squad.sort_custom(func(a: PlayerData, b: PlayerData) -> bool: return a.age < b.age)
	if squad.is_empty():
		_check(false, "[dev] a young player with headroom")
		return
	var p: PlayerData = squad[0]
	var attr := "short_passing" if DetailedAttributes.applicable(p, "short_passing") else "reflexes"
	c.development.plans.assign(p, "attribute", c.absolute_week(), {"attribute": attr})
	var start := p.get_attribute(attr)
	var start_pts := float(p.growth_progress.get(attr, 0.0))
	var y0 := _academy_sum(c)
	app.advance_week()
	app.advance_week()
	var pts2 := float(p.get_attribute(attr) - start) + float(p.growth_progress.get(attr, 0.0)) - start_pts
	_check(pts2 > 0.2, "[dev] two weeks on a plan give real progress (%.2f points on %s, age %d)" % [pts2, attr, p.age])
	app.advance_week()
	app.advance_week()
	var pts4 := float(p.get_attribute(attr) - start) + float(p.growth_progress.get(attr, 0.0)) - start_pts
	var est: Dictionary = c.development.plans.progress(p, DevelopmentEngine.facility_quality(c))
	_check(p.get_attribute(attr) > start, "[dev] a month on the plan raises the attribute (%d -> %d)" % [start, p.get_attribute(attr)])
	var wpp := float(est.get("weeks_per_point", -1.0))
	_check(wpp > 0.0 and absf(4.0 / wpp - pts4) <= maxf(0.5 * pts4, 0.3), "[dev] the screen's estimate matches the real rate", "estimate %.1f wk/pt, real %.2f pts in 4 wk" % [wpp, pts4])
	var lead: Dictionary = (est["targets"] as Array)[0]
	_check(int(lead["gain"]) == p.get_attribute(attr) - start, "[dev] the plan view (player card) shows the real gain")
	var y4 := _academy_sum(c)
	_check(y4 > y0, "[youth] the academy prospects gained attribute points in four weeks (%d)" % (y4 - y0))
	# a cycle that ends without any gain is not reported as a completed goal
	var stuck: PlayerData = null
	for q: PlayerData in c.db.get_squad(c.club_id):
		if q.get_overall() >= q.potential and q.loan_parent == "":
			stuck = q
			break
	if stuck != null:
		c.development.plans.assign(stuck, "attribute", c.absolute_week(), {"attribute": "stamina" if DetailedAttributes.applicable(stuck, "stamina") else "reflexes"})
		c.development.plans.plan_for(stuck.id)["cycle_weeks"] = DevelopmentPlans.GOAL_MAX_WEEKS
		var ev := DevelopmentEngine._notify(c, c.development, stuck, c.development.plans.plan_for(stuck.id), {}, c.absolute_week())
		var keys: Array = ev.map(func(e: Dictionary) -> String: return str(e["key"]))
		_check(not ("INBOX_DEV_PLAN_DONE" in keys) and "INBOX_DEV_PLAN_STALLED" in keys, "[dev] no progress -> no 'goal completed' report", str(keys))
	# save / load keeps the attributes, the fractional progress and the plan; development goes on afterwards
	var attr_now := p.get_attribute(attr)
	var prog_now := float(p.growth_progress.get(attr, 0.0))
	var pid := p.id
	var ysave := _academy_sum(c)
	_check(app.save_game() == "", "[dev] save")
	_check(app.load_game() == "", "[dev] load")
	c = app.career
	p = c.db.get_player(pid)
	_check(p.get_attribute(attr) == attr_now and absf(float(p.growth_progress.get(attr, 0.0)) - prog_now) < 0.0001, "[dev] attribute and progress survive save / load")
	_check(str(c.development.plans.plan_for(pid).get("type", "")) == "attribute", "[dev] the plan survives save / load")
	_check(_academy_sum(c) == ysave, "[youth] academy attributes survive save / load")
	var before := float(p.get_attribute(attr)) + float(p.growth_progress.get(attr, 0.0))
	app.advance_week()
	app.advance_week()
	_check(float(p.get_attribute(attr)) + float(p.growth_progress.get(attr, 0.0)) > before, "[dev] development continues after loading")
