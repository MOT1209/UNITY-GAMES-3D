extends "res://scripts/systems/transfers/transfer_market_base.gd"

## Transfer market, part 2 of 3: how the selling club and the player judge a deal (squad rank, importance,
## asking price, refusals, the seller's answer; fair wage, deserved role, the player's answer, default contract).

# --- the selling club --------------------------------------------------------------------------------------

## Rank of `p` among his club's players: {pos: better players at his position, all: better players in the squad,
## same: players at his position (him included)}. "Better" = higher overall, ties by id.
func squad_rank(p: PlayerData, team_id := "") -> Dictionary:
	var tid := team_id if team_id != "" else p.team_id
	var pos := 0
	var all := 0
	var same := 1
	var ov := p.get_overall()
	var t: TeamData = db.get_team(tid)
	if t == null:
		return {"pos": 0, "all": 0, "same": 1}
	for pid in t.squad_ids:
		if pid == p.id:
			continue
		var q: PlayerData = db.players.get(pid)
		if q == null:
			continue
		var qo := q.get_overall()
		var better := qo > ov or (qo == ov and q.id < p.id)
		if better:
			all += 1
		if q.position == p.position:
			same += 1
			if better:
				pos += 1
	return {"pos": pos, "all": all, "same": same}


## How much the owning club wants to keep the player: 1.0 (squad player) to 1.8 (one of the club's best three, first
## choice at his position, no cover behind him).
func importance(p: PlayerData) -> float:
	var r := squad_rank(p)
	var m := 1.0
	if int(r["all"]) < 3:
		m += 0.35
	if int(r["pos"]) == 0:
		m += 0.25
	elif int(r["pos"]) == 1:
		m += 0.1
	if int(r["same"]) <= 2:
		m += 0.15
	return clampf(m, 1.0, 1.8)


## The fee the owning club asks in a negotiation: the listing price when the player is on the transfer list, else the
## market value × importance (+10 % for young high-potential players), less in the last contract year and on deadline day.
func seller_price(p: PlayerData) -> int:
	if is_transfer_listed(p.id) and int(listings[p.id].get("price", 0)) > 0:
		return int(listings[p.id]["price"])
	var price := float(market_value(p)) * importance(p)
	if p.age <= 23 and p.potential - p.get_overall() >= 10:
		price *= 1.1
	if p.contract_years <= 1:
		price *= 0.85
	if bool(window_info(cur_week)["deadline"]):
		price *= 0.93
	return maxi(Valuation.round_value(price), 1000)


## Why the owner refuses to talk at all ("" = it negotiates). Translation keys OFFER_REASON_*.
func refusal(p: PlayerData, buyer_id: String, loan_deal: bool, fee: int = 0) -> String:
	if p == null or p.status == PlayerData.Status.YOUTH or p.status == PlayerData.Status.RETIRED or p.team_id == "":
		return "OFFER_REASON_NOT_AVAILABLE"
	if p.team_id == buyer_id:
		return "OFFER_REASON_OWN_PLAYER"
	if p.loan_parent != "":
		return "OFFER_REASON_ON_LOAN"
	var clause := release_clause(p.id)
	if not loan_deal and clause > 0 and fee >= clause:
		return ""                                        # the release clause is paid: the club cannot say no
	if listing_of(p.id) == LISTING_UNTOUCHABLE:
		return "OFFER_REASON_UNTOUCHABLE"
	var arrived := int(arrivals.get(p.id, -1000))
	if arrived > -1000 and abs_week() - arrived < RECENT_ARRIVAL_WEEKS and listing_of(p.id) == LISTING_NONE:
		return "OFFER_REASON_JUST_ARRIVED"
	var owner: TeamData = db.get_team(p.team_id)
	if owner == null or owner.squad_ids.size() <= MIN_SQUAD:
		return "OFFER_REASON_SQUAD_SIZE"
	if loan_deal:
		# a player the club itself listed for loan may go past the usual cap, but never past the hard cap
		var out_now := loans_out(p.team_id)
		if out_now >= MAX_LOANS_OUT_LISTED or (out_now >= MAX_LOANS_OUT and not is_loan_listed(p.id)):
			return "OFFER_REASON_LOAN_LIMIT"
		if loans_in(buyer_id) >= MAX_LOANS_IN:
			return "OFFER_REASON_BORROWER_LIMIT"
		if int(loan_seasons.get("%s|%s" % [buyer_id, p.id], 0)) == cur_season:
			return "OFFER_REASON_LOANED_THIS_SEASON"
		if not is_loan_listed(p.id) and int(squad_rank(p)["pos"]) == 0 and int(squad_rank(p)["all"]) < 11:
			return "OFFER_REASON_KEY_PLAYER"
	return ""


func loans_out(team_id: String) -> int:
	var n := 0
	for pid in loans:
		if str(loans[pid]["from"]) == team_id:
			n += 1
	return n


func loans_in(team_id: String) -> int:
	var n := 0
	for pid in loans:
		if str(loans[pid]["to"]) == team_id:
			n += 1
	return n


## Lowest share of the wage the owner wants a borrower to pay: the listing's minimum, else 50 % for fringe and young
## players and 75 % for the rest; a promise of playing time lowers it by 10 points.
func min_wage_split(p: PlayerData, promised_play: int = 0) -> int:
	var split := 75
	if is_loan_listed(p.id):
		split = int(listings[p.id].get("loan_min_split", 50))
	elif p.age <= 21 or int(squad_rank(p)["pos"]) >= 2:
		split = 50
	if promised_play >= 50:
		split -= 10
	return clampi(split, 0, 100)


## Loan fee the owner expects: nothing for fringe/young players, else about 5 % of the value per cur_season.
func expected_loan_fee(p: PlayerData, weeks: int) -> int:
	if p.age <= 21 or int(squad_rank(p)["pos"]) >= 2 or is_loan_listed(p.id):
		return 0
	return Valuation.round_value(market_value(p) * 0.05 * weeks / float(WEEKS_PER_SEASON))


## Value of an offer for the seller: installments are worth a little less than cash, a sell-on share a little more.
static func effective_fee(o: TransferOffer) -> float:
	return o.fee * (1.0 - 0.03 * (o.installments - 1)) + o.fee * o.sell_on_percent / 100.0 * 0.25


## The owning club's answer to the terms on the table. Pure: nothing changes.
## {status: accepted | countered | rejected, reason: key, terms: counter terms}
func seller_answer(o: TransferOffer) -> Dictionary:
	var p: PlayerData = db.get_player(o.player_id)
	var why := refusal(p, o.from_club, o.is_loan(), o.fee)
	if why != "":
		return {"status": TransferOffer.REJECTED, "reason": why}
	if not o.is_loan():
		var clause := release_clause(p.id)
		if clause > 0 and o.fee >= clause:
			return {"status": TransferOffer.ACCEPTED, "reason": "", "release_clause": true}
		var price := float(seller_price(p))
		var ratio := effective_fee(o) / maxf(price, 1.0)
		if ratio >= 1.0:
			return {"status": TransferOffer.ACCEPTED, "reason": ""}
		if ratio < REJECT_BELOW:
			return {"status": TransferOffer.REJECTED, "reason": "OFFER_REASON_TOO_LOW"}
		if o.counters() >= MAX_NEGOTIATION_ROUNDS:
			return {"status": TransferOffer.REJECTED, "reason": "OFFER_REASON_BROKE_DOWN"}
		var t := o.terms()
		if ratio >= COUNTER_THRESHOLD:
			t["fee"] = maxi(o.fee + 1, Valuation.round_value((o.fee + price) / 2.0 + price * 0.02))
			if o.sell_on_percent == 0 and p.age <= 23:
				t["sell_on_percent"] = 10
		else:
			t["fee"] = int(price)
		t["fee"] = mini(int(t["fee"]), int(price))
		if effective_fee_terms(t) < price * 0.999 and int(t["fee"]) == int(price):
			t["installments"] = 1           # at the full price the club wants cash
		return {"status": TransferOffer.COUNTERED, "reason": "", "terms": t}
	# loans
	if o.loan_weeks < MIN_LOAN_WEEKS or o.loan_weeks > MAX_LOAN_WEEKS:
		return {"status": TransferOffer.REJECTED, "reason": "OFFER_REASON_LOAN_LENGTH"}
	var want_split := min_wage_split(p, o.min_play_percent)
	var want_fee := expected_loan_fee(p, o.loan_weeks)
	var want_option := 0
	if o.type == TransferOffer.LOAN_WITH_OPTION:
		want_option = int(listings[p.id].get("loan_option_fee", 0)) if is_loan_listed(p.id) and bool(listings[p.id].get("loan_option", false)) \
				and int(listings[p.id].get("loan_option_fee", 0)) > 0 else int(seller_price(p))
	elif o.type == TransferOffer.LOAN_WITH_OBLIGATION:
		want_option = int(seller_price(p) * 0.85)
	var ok := o.wage_split_percent >= want_split and o.loan_fee >= int(want_fee * 0.7) and o.option_fee >= int(want_option * 0.97)
	if ok:
		return {"status": TransferOffer.ACCEPTED, "reason": ""}
	if o.counters() >= MAX_NEGOTIATION_ROUNDS:
		return {"status": TransferOffer.REJECTED, "reason": "OFFER_REASON_BROKE_DOWN"}
	if o.option_fee > 0 and o.option_fee < int(want_option * REJECT_BELOW):
		return {"status": TransferOffer.REJECTED, "reason": "OFFER_REASON_TOO_LOW"}
	var t := o.terms()
	t["wage_split_percent"] = maxi(o.wage_split_percent, want_split)
	t["loan_fee"] = maxi(o.loan_fee, want_fee)
	t["option_fee"] = maxi(o.option_fee, want_option)
	return {"status": TransferOffer.COUNTERED, "reason": "", "terms": t}


static func effective_fee_terms(t: Dictionary) -> float:
	var o := TransferOffer.new()
	o.set_terms(t)
	return effective_fee(o)


## Rough chance that the owner accepts the terms as they are: "high", "medium" or "low" (shown while negotiating).
func acceptance_chance(o: TransferOffer) -> String:
	var a := seller_answer(o)
	if a["status"] == TransferOffer.ACCEPTED:
		return "high"
	if a["status"] == TransferOffer.COUNTERED:
		return "medium"
	return "low"


# --- the player -----------------------------------------------------------------------------------------------

## Weekly wage a player of this level and age can expect.
func fair_wage(p: PlayerData) -> int:
	var ov := p.get_overall()
	var w := float(ov * ov) / 4.0
	if p.age <= 20:
		w *= 0.6
	elif p.age >= 33:
		w *= 0.8
	return maxi(100, int(w))


## Lowest wage the player signs for. A player under contract: 90 % of his current wage. A free agent has no wage to
## defend: half a fair wage for his level (before Nov 2026 the floor was 90 % of the wage of the club he LEFT, which
## undercut FREE_AGENT_WAGE_FACTOR / FREE_AGENT_ACCEPT: he "accepted" an offer the floor then refused when signing).
func minimum_wage(p: PlayerData) -> int:
	if p.team_id == "" and p.status != PlayerData.Status.YOUTH:
		return maxi(100, int(fair_wage(p) * 0.5))
	return maxi(100, int(p.salary * 0.9))


## Role a player would have at `team_id` once he has joined (index into ContractOffer.ROLES). His rank at his position is
## counted among the club's players WITH him, and compared with the club's level (the mean of its best 11):
## best at his position and above the club's level -> star; one of the club's starters at the position (or second in line
## but above the club's level) -> starter; next in line (not far below the level) -> rotation; otherwise backup (a prospect for a teenager).
func deserved_role(p: PlayerData, team_id: String) -> int:
	var r := squad_rank(p, team_id)
	var level := _club_level(team_id, p)
	var ov := p.get_overall()
	var slots := 2 if p.position in [PlayerData.Position.CB, PlayerData.Position.CM] else 1
	var pos := int(r["pos"])
	if pos == 0 and ov >= level + 2:
		return 0
	if pos < slots + (1 if ov >= level + 2 else 0):
		return 1                                  # a player above the club's level also starts when only second in line
	if pos < slots + 1 and ov >= level - 8:
		return 2
	if p.age <= 19 and ov < level - 8:
		return 4
	return 3


## Mean overall of the club's best 11 players, the player himself left out.
func _club_level(team_id: String, p: PlayerData) -> int:
	var t: TeamData = db.get_team(team_id)
	if t == null:
		return 60
	var all: Array = []
	for pid in t.squad_ids:
		var q: PlayerData = db.players.get(pid)
		if q != null and q != p:
			all.append(q.get_overall())
	if all.is_empty():
		return 60
	all.sort()
	all.reverse()
	var n := mini(11, all.size())
	var sum := 0
	for i in n:
		sum += int(all[i])
	return sum / n


## The player's answer to personal terms at `team_id` (renewal = his own club). Pure.
## {status: accepted | countered | rejected, reason: key, demand: ContractOffer}
func player_answer(p: PlayerData, team_id: String, c: ContractOffer, renewal := false) -> Dictionary:
	var demand := ContractOffer.make(c.salary, clampi(c.years, 1, MAX_CONTRACT_YEARS), c.squad_role, c.signing_bonus, c.release_clause, c.loyalty_bonus)
	if c.years < 1 or c.years > MAX_CONTRACT_YEARS:
		return {"status": TransferOffer.REJECTED, "reason": "CONTRACT_REASON_YEARS", "demand": demand}
	var deserved := deserved_role(p, team_id)
	var role_wage: float = float(ContractOffer.ROLE_WAGE[ContractOffer.ROLES[deserved]])
	var expected := float(maxi(minimum_wage(p), int(fair_wage(p) * role_wage)))    # the wage follows the place he will have
	var free_agent := p.team_id == "" and not renewal     # Nov 2026: a player without a club is easy to sign
	var cur_team: TeamData = db.get_team(p.team_id)
	var new_team: TeamData = db.get_team(team_id)
	var cur_rep := cur_team.reputation if cur_team != null else 40
	var new_rep := new_team.reputation if new_team != null else 50
	if renewal:
		expected = maxf(expected, p.salary * 1.05)
		if p.morale < 40:
			expected *= 1.15
	elif free_agent:
		# no club, no wage: he takes a fair wage (no premium on his old salary, no reputation or ambition demands)
		expected *= FREE_AGENT_WAGE_FACTOR
	else:
		expected = maxf(expected, p.salary * 1.1)
		expected *= 1.0 + maxi(0, cur_rep - new_rep) * 0.01
		if new_rep + 30 < cur_rep and p.get_overall() >= 70 and c.salary < expected * 1.5:
			return {"status": TransferOffer.REJECTED, "reason": "CONTRACT_REASON_AMBITION", "demand": demand}
	var promised := ContractOffer.ROLES.find(c.squad_role)
	if promised < 0:
		promised = 2
	var level := mini(promised, 3)                        # "prospect" is a youth role on the backup level
	var diff := level - mini(deserved, 3)
	if diff >= 2 and p.age <= 23 and p.potential >= 70 and not free_agent:
		demand.squad_role = ContractOffer.ROLES[deserved]
		return {"status": TransferOffer.REJECTED, "reason": "CONTRACT_REASON_PLAYING_TIME", "demand": demand}
	expected *= clampf(1.0 + 0.08 * diff, 0.85, 1.3)
	if p.age >= 30:
		expected *= 1.05
	if p.age <= 23 and c.years == 1:
		expected *= 1.05
	var value := maxi(market_value(p), 1)
	if c.release_clause > 0 and c.release_clause < value * 2:
		expected *= 0.97                                  # an affordable way out is worth something to the player
	var weeks := float(c.years * WEEKS_PER_SEASON)
	var effective := c.salary + (c.signing_bonus + c.loyalty_bonus) / weeks
	var want := maxi(int(ceil(expected)), minimum_wage(p))
	demand.salary = maxi(maxi(c.salary, want - int((c.signing_bonus + c.loyalty_bonus) / weeks)), minimum_wage(p))
	# the weekly wage itself must reach his minimum (signing checks it again): bonuses cannot replace it
	if effective >= want * (FREE_AGENT_ACCEPT if free_agent else 1.0) and c.salary >= minimum_wage(p):
		return {"status": TransferOffer.ACCEPTED, "reason": "", "demand": demand}
	if effective >= want * (0.5 if free_agent else 0.8):
		return {"status": TransferOffer.COUNTERED, "reason": "CONTRACT_REASON_WAGE", "demand": demand}
	return {"status": TransferOffer.REJECTED, "reason": "CONTRACT_REASON_WAGE", "demand": demand}


## Terms a free agent signs at once (his demand at `team_id`), for the one-click "Sign now".
func free_agent_terms(p: PlayerData, team_id: String) -> ContractOffer:
	var c := default_contract(p, team_id)
	var a := player_answer(p, team_id, c)
	if a["status"] != TransferOffer.ACCEPTED and a.has("demand"):
		c = a["demand"]
	return c


## Terms the player would sign at `team_id` straight away (what an AI club offers him).
func default_contract(p: PlayerData, team_id: String, renewal := false) -> ContractOffer:
	var years := PlayerLifecycle.renewal_years(p) + (1 if p.age <= 26 else 0)
	var c := ContractOffer.make(maxi(minimum_wage(p), p.salary), clampi(years, 1, MAX_CONTRACT_YEARS),
			ContractOffer.ROLES[deserved_role(p, team_id)])
	var a := player_answer(p, team_id, c, renewal)
	if a["status"] != TransferOffer.ACCEPTED:
		c.salary = (a["demand"] as ContractOffer).salary
		if a["status"] == TransferOffer.REJECTED:
			c.salary = int(c.salary * 1.05) + 1
	return c
