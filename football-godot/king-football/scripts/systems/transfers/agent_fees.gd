class_name AgentFees
extends RefCounted

## F5 — player-agent commission. Agents are not modelled as separate entities: the commission is a deterministic
## function of money that already exists in the deal (the transfer fee, or the agreed wage on a renewal). Nothing new
## is persisted, so no save field, no migration and no SAVE_VERSION bump are needed. The buying club pays the
## commission when a player signs; the club pays it again when his contract is renewed.

## Share of the transfer fee paid to the agent on a signing.
const SIGNING_PERCENT := 5
## Share of one year's wage paid to the agent on a renewal.
const RENEWAL_PERCENT := 3
## Turns a weekly wage into a yearly wage for the renewal commission.
const WEEKS_PER_YEAR := 52
## Bounds, so neither a tiny nor a record-breaking deal produces an absurd commission.
const SIGNING_MIN := 5_000
const SIGNING_MAX := 2_000_000
const RENEWAL_MIN := 1_000
const RENEWAL_MAX := 1_000_000


## Commission on a signing: a bounded percentage of the fee. No fee (a free transfer) means no commission.
static func signing(fee: int) -> int:
	if fee <= 0:
		return 0
	return clampi(fee * SIGNING_PERCENT / 100, SIGNING_MIN, SIGNING_MAX)


## Commission on a renewal: a bounded percentage of one year of the agreed wage.
static func renewal(salary: int) -> int:
	if salary <= 0:
		return 0
	return clampi(salary * WEEKS_PER_YEAR * RENEWAL_PERCENT / 100, RENEWAL_MIN, RENEWAL_MAX)
