class_name TransferOffer
extends RefCounted

## One offer between two clubs for one player (transfers v2). The same record is used for the user's offers, the
## AI's offers to the user and loan requests, so every rule is applied by the same code (`TransferMarket`).
## Every round of a negotiation is kept in `rounds` ({by, terms, week}); `terms()` are the terms currently on the table.

const PENDING := "pending"            # waiting for the other club's answer
const COUNTERED := "countered"        # the other club proposed new terms (waiting for the offering club)
const ACCEPTED := "accepted"          # clubs agree; the player's contract is still open (permanent / free deals)
const DEFERRED := "deferred"          # agreed outside the window: carried out when the next window opens
const REJECTED := "rejected"
const WITHDRAWN := "withdrawn"
const EXPIRED := "expired"
const COMPLETED := "completed"
const STATUSES: Array[String] = [PENDING, COUNTERED, ACCEPTED, DEFERRED, REJECTED, WITHDRAWN, EXPIRED, COMPLETED]
const OPEN_STATUSES: Array[String] = [PENDING, COUNTERED, ACCEPTED, DEFERRED]

const PERMANENT := "permanent"
const LOAN := "loan"
const LOAN_WITH_OPTION := "loan_option"
const LOAN_WITH_OBLIGATION := "loan_obligation"
const FREE := "free"                  # free agent: no club to negotiate with
const PRE_CONTRACT := "pre_contract"  # free move next season (contract ends within 26 weeks)
const TYPES: Array[String] = [PERMANENT, LOAN, LOAN_WITH_OPTION, LOAN_WITH_OBLIGATION, FREE, PRE_CONTRACT]

const MAX_INSTALLMENTS := 4
const MAX_SELL_ON := 30

var id: int = 0
var created_week: int = 0             # absolute career week (season and week)
var expires_week: int = 0             # absolute week after which an unanswered offer expires
var status: String = PENDING
var from_club: String = ""            # the club that wants the player (buyer / borrower)
var to_club: String = ""              # the club that owns the player ("" for a free agent)
var player_id: String = ""
var type: String = PERMANENT
## Terms on the table (the latest round).
var fee: int = 0
var installments: int = 1             # 1-4 payments, one per half season
var sell_on_percent: int = 0          # share of the next sale paid to the selling club
var loan_weeks: int = 0
var loan_fee: int = 0
var wage_split_percent: int = 100     # share of the wage the borrower pays (the lender pays the rest)
var option_fee: int = 0               # purchase price at the end of the loan (option / obligation)
var obligation_apps: int = 0          # obligation to buy after this many appearances (0 = always)
var recall_after_weeks: int = 0       # 0 = no early recall
var min_play_percent: int = 0         # promised share of matches
var rounds: Array = []                # [{by, terms, week}]
var reason: String = ""               # translation key of the last refusal ("" = none)
var unread: bool = true               # new for the user (red dot)
var via_release_clause: bool = false
var contract: Dictionary = {}         # personal terms agreed with the player (ContractOffer.to_dict); {} = not yet
var contract_rounds: int = 0          # contract proposals made to the player


func is_loan() -> bool:
	return type == LOAN or type == LOAN_WITH_OPTION or type == LOAN_WITH_OBLIGATION


func is_open() -> bool:
	return status in OPEN_STATUSES


## Terms currently on the table, as stored in `rounds`.
func terms() -> Dictionary:
	return {"fee": fee, "installments": installments, "sell_on_percent": sell_on_percent, "loan_weeks": loan_weeks,
			"loan_fee": loan_fee, "wage_split_percent": wage_split_percent, "option_fee": option_fee,
			"obligation_apps": obligation_apps, "recall_after_weeks": recall_after_weeks, "min_play_percent": min_play_percent}


func set_terms(t: Dictionary) -> void:
	fee = maxi(0, int(t.get("fee", fee)))
	installments = clampi(int(t.get("installments", installments)), 1, MAX_INSTALLMENTS)
	sell_on_percent = clampi(int(t.get("sell_on_percent", sell_on_percent)), 0, MAX_SELL_ON)
	loan_weeks = int(t.get("loan_weeks", loan_weeks))
	loan_fee = maxi(0, int(t.get("loan_fee", loan_fee)))
	wage_split_percent = clampi(int(t.get("wage_split_percent", wage_split_percent)), 0, 100)
	option_fee = maxi(0, int(t.get("option_fee", option_fee)))
	obligation_apps = maxi(0, int(t.get("obligation_apps", obligation_apps)))
	recall_after_weeks = maxi(0, int(t.get("recall_after_weeks", recall_after_weeks)))
	min_play_percent = clampi(int(t.get("min_play_percent", min_play_percent)), 0, 100)


func add_round(by: String, week: int) -> void:
	rounds.append({"by": by, "terms": terms(), "week": week})


## Number of counter-offers made by the club that owns the player.
func counters() -> int:
	var n := 0
	for r in rounds:
		if str(r["by"]) == to_club:
			n += 1
	return n


## The amount the deal costs the receiving club now (permanent: first installment; loans: the loan fee).
func upfront() -> int:
	if is_loan():
		return loan_fee
	if installments <= 1:
		return fee
	return fee - (fee / installments) * (installments - 1)


func to_dict() -> Dictionary:
	return {"id": id, "created_week": created_week, "expires_week": expires_week, "status": status,
			"from_club": from_club, "to_club": to_club, "player_id": player_id, "type": type,
			"terms": terms(), "rounds": rounds.duplicate(true), "reason": reason, "unread": unread,
			"via_release_clause": via_release_clause, "contract": contract.duplicate(), "contract_rounds": contract_rounds}


static func from_dict(d: Dictionary) -> TransferOffer:
	var o := TransferOffer.new()
	o.id = int(d.get("id", 0))
	o.created_week = int(d.get("created_week", 0))
	o.expires_week = int(d.get("expires_week", 0))
	o.status = str(d.get("status", PENDING))
	if not (o.status in STATUSES):
		o.status = EXPIRED
	o.from_club = str(d.get("from_club", ""))
	o.to_club = str(d.get("to_club", ""))
	o.player_id = str(d.get("player_id", ""))
	o.type = str(d.get("type", PERMANENT))
	if not (o.type in TYPES):
		o.type = PERMANENT
	o.set_terms(d.get("terms", {}))
	o.rounds = PlayerData._restore_ints((d.get("rounds", []) as Array).duplicate(true))
	o.reason = str(d.get("reason", ""))
	o.unread = bool(d.get("unread", false))
	o.via_release_clause = bool(d.get("via_release_clause", false))
	o.contract = PlayerData._restore_ints((d.get("contract", {}) as Dictionary).duplicate())
	o.contract_rounds = int(d.get("contract_rounds", 0))
	return o
