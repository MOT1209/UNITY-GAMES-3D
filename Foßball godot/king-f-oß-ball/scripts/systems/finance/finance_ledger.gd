class_name FinanceLedger
extends RefCounted

## Club finances (Phase T9). EVERY change of money is a ledger entry, so the
## balance is always reproducible: opening + sum(entries) == balance.
## Expenses that would push the balance below zero are refused unless the
## category is one of the unavoidable ones (salaries).

const CATEGORIES: Array[String] = [
	"transfer_in", "transfer_out", "loan_in", "loan_out", "salary", "match_revenue",
	"competition_reward", "academy", "scouting", "facility", "other",
]
## Categories that may overdraw the club (the club is in debt but must pay).
const UNAVOIDABLE: Array[String] = ["salary"]

var team_id: String = ""
var opening_balance: int = 0
var balance: int = 0
var transfer_budget: int = 0
var wage_budget: int = 0           # max total weekly wages
var entries: Array = []            # {id, week, category, amount, description, balance_after}
var next_entry_id: int = 1


func _init(p_team_id := "", p_balance := 0, p_transfer_budget := 0, p_wage_budget := 0) -> void:
	team_id = p_team_id
	opening_balance = p_balance
	balance = p_balance
	transfer_budget = p_transfer_budget
	wage_budget = p_wage_budget


## Whether `amount` (negative = spend) could be recorded under `category`.
func can_afford(amount: int, category: String) -> bool:
	if amount >= 0 or category in UNAVOIDABLE:
		return true
	return balance + amount >= 0


## Records a transaction. Returns "" or an error; nothing changes on error.
## `key`/`args` (optional) let the UI show the description in the player's language;
## `description` stays the plain-text fallback (and is what old saves contain).
func record(category: String, amount: int, description: String, week: int, key := "", args: Array = []) -> String:
	if not (category in CATEGORIES):
		return "unknown finance category '%s'" % category
	if amount == 0:
		return "amount must not be zero"
	if not can_afford(amount, category):
		return "insufficient funds (%d available, %d needed)" % [balance, -amount]
	balance += amount
	var entry := {"id": next_entry_id, "week": week, "category": category, "amount": amount,
			"description": description, "balance_after": balance}
	if key != "":
		entry["key"] = key
		entry["args"] = args.duplicate()
	entries.append(entry)
	next_entry_id += 1
	return ""


## Spends from the transfer budget as well as the balance (transfers, loans).
func spend_transfer(category: String, fee: int, description: String, week: int) -> String:
	if fee <= 0:
		return "transfer fee must be positive"
	if fee > transfer_budget:
		return "transfer budget too small (%d available, %d needed)" % [transfer_budget, fee]
	var err := record(category, -fee, description, week)
	if err == "":
		transfer_budget -= fee
	return err


func total(category: String) -> int:
	var sum := 0
	for e in entries:
		if e["category"] == category:
			sum += int(e["amount"])
	return sum


## Audit: balance must equal the opening balance plus all entries.
func is_consistent() -> bool:
	var sum := opening_balance
	var last := opening_balance
	for e in entries:
		sum += int(e["amount"])
		last = int(e["balance_after"])
		if last != sum:
			return false
	return sum == balance


func to_dict() -> Dictionary:
	return {"team_id": team_id, "opening": opening_balance, "balance": balance,
			"transfer_budget": transfer_budget, "wage_budget": wage_budget,
			"entries": entries.duplicate(true), "next_id": next_entry_id}


static func from_dict(d: Dictionary) -> FinanceLedger:
	var l := FinanceLedger.new(str(d.get("team_id", "")), int(d.get("opening", 0)),
			int(d.get("transfer_budget", 0)), int(d.get("wage_budget", 0)))
	l.balance = int(d.get("balance", l.opening_balance))
	l.entries = (d.get("entries", []) as Array).duplicate(true)
	for e in l.entries:
		for k in ["id", "week", "amount", "balance_after"]:
			e[k] = int(e[k])
	l.next_entry_id = int(d.get("next_id", l.entries.size() + 1))
	return l
