class_name Economy
extends RefCounted

## Career phase C7: ticket and shirt prices, sponsor offers, broadcast rights, the bank loan and the financial sustainability rule.
## All money moves through the FinanceLedger. The same sustainability rule is applied to every club (`check_sustainability`).

const TICKET_LEVELS := {"low": 0.8, "normal": 1.0, "high": 1.5}          # income multiplier per home match
const TICKET_FAN_EFFECT := {"low": 1, "normal": 0, "high": -1}              # fan mood change per home match
const TICKET_ATTENDANCE := {"low": 1.1, "normal": 1.0, "high": 0.8}         # attendance multiplier (before fan mood)
const MERCH_BASE := 6_000
const LOAN_MAX_WEEKS_OF_INCOME := 40
const LOAN_RATE := 0.08                                                    # flat, over the loan's life
const LOAN_WEEKS := 46
const SUSTAINABILITY_SPEND_LIMIT := 1.30                                   # spend / income above this is a strike
const SUSTAINABILITY_STRIKES := 3

var ticket_level := "normal"
var shirt_price := 50                         # 20..120
var sponsor: Dictionary = {}                  # chosen offer {kind, fixed_weekly, rank_bonus, goal_bonus}
var loan: Dictionary = {}                     # {principal, weekly, weeks_left}
var strikes: Dictionary = {}                  # club id -> consecutive seasons over the limit
var transfer_ban: Dictionary = {}             # club id -> windows still banned


func set_ticket_level(level: String) -> bool:
	if not TICKET_LEVELS.has(level):
		return false
	ticket_level = level
	return true


func set_shirt_price(price: int) -> void:
	shirt_price = clampi(price, 20, 120)


## Multiplier on a home match's income and the attendance factor that comes with the price and the fans' mood (0..100).
func matchday_multiplier(fan_mood: int) -> float:
	var attendance := float(TICKET_ATTENDANCE[ticket_level]) * (0.8 + 0.4 * float(fan_mood) / 100.0)
	return float(TICKET_LEVELS[ticket_level]) * clampf(attendance, 0.5, 1.4)


## Weekly merchandise income: cheaper shirts sell more, richer / more popular clubs sell more.
func merchandise_income(reputation: int, fan_mood: int) -> int:
	var demand := (120.0 - float(shirt_price)) / 70.0                   # 1.43 at 20, 0.0 at 120
	return int(MERCH_BASE * (0.5 + float(reputation) / 100.0) * demand * float(shirt_price) / 50.0 * (0.7 + 0.6 * float(fan_mood) / 100.0))


# --- sponsor offers ------------------------------------------------------------------------------------

## Three offers with different terms (fixed money / paid by final position / goal bonuses). Deterministic per season.
static func sponsor_offers(season: int, club_seed: int, reputation: int) -> Array:
	var base := 20_000 + reputation * 900
	var jitter := float(hash([season, club_seed, "sponsor"]) % 21) / 100.0 + 0.9
	return [
		{"kind": "fixed", "fixed_weekly": int(base * jitter), "rank_bonus": 0, "goal_bonus": 0},
		{"kind": "variable", "fixed_weekly": int(base * 0.55 * jitter), "rank_bonus": int(base * 14 * jitter), "goal_bonus": 0},
		{"kind": "goals", "fixed_weekly": int(base * 0.7 * jitter), "rank_bonus": 0, "goal_bonus": int(base * 0.06 * jitter)},
	]


func choose_sponsor(offer: Dictionary) -> bool:
	if not ["fixed", "variable", "goals"].has(str(offer.get("kind", ""))):
		return false
	sponsor = offer.duplicate()
	return true


## The AI picks the best expected value for its club (same offers, same rule): mid-table assumption.
static func ai_choose(offers: Array, expected_rank: int, size: int) -> Dictionary:
	var best := {}
	var best_v := -1.0
	for o in offers:
		var rank_factor := clampf(1.0 - float(expected_rank - 1) / maxf(size - 1, 1), 0.0, 1.0)
		var v := float(o["fixed_weekly"]) * 46.0 + float(o["rank_bonus"]) * rank_factor + float(o["goal_bonus"]) * 50.0
		if v > best_v:
			best_v = v
			best = o
	return best


## Season-end payment of the variable parts: `rank` final position, `size` clubs, `goals` scored in the league.
func sponsor_season_payment(rank: int, size: int, goals: int) -> int:
	if sponsor.is_empty():
		return 0
	var rank_factor := clampf(1.0 - float(rank - 1) / maxf(size - 1, 1), 0.0, 1.0)
	return int(float(sponsor.get("rank_bonus", 0)) * rank_factor) + int(sponsor.get("goal_bonus", 0)) * goals


## Broadcast money at the season end by tier and final position (tier 1 pays most, the champion most within a tier).
static func broadcast_income(tier: int, rank: int, size: int) -> int:
	var pool := [3_000_000, 1_200_000, 500_000, 250_000]
	var base: int = pool[clampi(tier - 1, 0, pool.size() - 1)]
	return int(base * (0.5 + 0.5 * clampf(1.0 - float(rank - 1) / maxf(size - 1, 1), 0.0, 1.0)))


# --- bank loan -----------------------------------------------------------------------------------------

## The most the bank lends: 40 weeks of the club's recent weekly income.
static func loan_limit(weekly_income: int) -> int:
	return weekly_income * LOAN_MAX_WEEKS_OF_INCOME


func take_loan(ledger: FinanceLedger, amount: int, weekly_income: int, week: int) -> String:
	if not loan.is_empty():
		return "LOAN_ERR_ACTIVE"
	if amount <= 0 or amount > loan_limit(weekly_income):
		return "LOAN_ERR_LIMIT"
	ledger.record("loan_bank", amount, "Bank loan", week, "FIN_BANK_LOAN")
	loan = {"principal": amount, "weekly": int(ceil(float(amount) * (1.0 + LOAN_RATE) / LOAN_WEEKS)), "weeks_left": LOAN_WEEKS}
	return ""


## Weekly: the instalment is paid whether the club has money or not (unavoidable category).
func weekly_loan(ledger: FinanceLedger, week: int) -> void:
	if loan.is_empty():
		return
	ledger.record("loan_repayment", -int(loan["weekly"]), "Loan instalment", week, "FIN_LOAN_REPAYMENT")
	loan["weeks_left"] = int(loan["weeks_left"]) - 1
	if int(loan["weeks_left"]) <= 0:
		loan = {}


# --- sustainability (every club) ------------------------------------------------------------------------

## End of a season for one club. `income` / `spend` = that season's totals (spend = wages + transfers + upkeep). Over the limit
## for three seasons in a row: a fine (5% of the balance) and a ban on registering new players for one window.
## Returns "", "strike", "fined".
func check_sustainability(team_id: String, income: int, spend: int, ledger: FinanceLedger, week: int) -> String:
	if income > 0 and float(spend) / float(income) > SUSTAINABILITY_SPEND_LIMIT:
		strikes[team_id] = int(strikes.get(team_id, 0)) + 1
	else:
		strikes[team_id] = 0
	if int(strikes[team_id]) >= SUSTAINABILITY_STRIKES:
		strikes[team_id] = 0
		var fine := int(maxf(float(ledger.balance), 0.0) * 0.05) + 10_000
		ledger.record("fine", -fine, "Financial sustainability fine", week, "FIN_SUSTAINABILITY_FINE")
		transfer_ban[team_id] = 1
		return "fined"
	return "strike" if int(strikes[team_id]) > 0 else ""


var _last_entry: Dictionary = {}              # club id -> last ledger entry id already counted

## End of season for EVERY club: counts the ledger entries since the last settlement and applies the rule. Returns {club: result}.
func settle_season(career: CareerState) -> Dictionary:
	var out := {}
	for team_id in career.ledgers:
		var l: FinanceLedger = career.ledgers[team_id]
		var last := int(_last_entry.get(team_id, 0))
		var income := 0
		var spend := 0
		for e in l.entries:
			if int(e["id"]) <= last:
				continue
			var a := int(e["amount"])
			var cat := str(e["category"])
			if cat == "loan_bank":
				continue
			if a > 0:
				income += a
			else:
				spend -= a
		_last_entry[team_id] = l.next_entry_id - 1
		var r := check_sustainability(str(team_id), income, spend, l, career.week)
		if r != "":
			out[team_id] = r
	return out


func is_banned(team_id: String) -> bool:
	return int(transfer_ban.get(team_id, 0)) > 0


## One transfer window has passed.
func window_passed() -> void:
	for k in transfer_ban.keys():
		transfer_ban[k] = int(transfer_ban[k]) - 1
		if int(transfer_ban[k]) <= 0:
			transfer_ban.erase(k)


func to_dict() -> Dictionary:
	return {"ticket_level": ticket_level, "shirt_price": shirt_price, "sponsor": sponsor.duplicate(), "loan": loan.duplicate(),
			"last_entry": _last_entry.duplicate(), "strikes": strikes.duplicate(), "transfer_ban": transfer_ban.duplicate()}


static func from_dict(d: Dictionary) -> Economy:
	var e := Economy.new()
	var lvl := str(d.get("ticket_level", "normal"))
	e.ticket_level = lvl if TICKET_LEVELS.has(lvl) else "normal"
	e.shirt_price = clampi(int(d.get("shirt_price", 50)), 20, 120)
	e.sponsor = PlayerData._restore_ints((d.get("sponsor", {}) as Dictionary).duplicate())
	e.loan = PlayerData._restore_ints((d.get("loan", {}) as Dictionary).duplicate())
	for k in (d.get("last_entry", {}) as Dictionary):
		e._last_entry[str(k)] = int(d["last_entry"][k])
	for k in (d.get("strikes", {}) as Dictionary):
		e.strikes[str(k)] = int(d["strikes"][k])
	for k in (d.get("transfer_ban", {}) as Dictionary):
		e.transfer_ban[str(k)] = int(d["transfer_ban"][k])
	return e
