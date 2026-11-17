class_name FinanceLedger
extends RefCounted

## Club finances (Phase T9). EVERY change of money is a ledger entry, so the
## balance is always reproducible: opening + sum(entries) == balance.
## Expenses that would push the balance below zero are refused unless the
## category is one of the unavoidable ones (salaries).

const CATEGORIES: Array[String] = [
	"transfer_in", "transfer_out", "loan_in", "loan_out", "salary", "match_revenue",
	"competition_reward", "sponsorship", "academy", "scouting", "facility", "other",
	"installment", "sell_on", "signing_bonus", "facilities", "maintenance",
	"ticket_income", "merchandise", "broadcast", "loan_bank", "loan_repayment", "fine",
	"agent_fee",  # F5: player-agent commission on signings and renewals
]
## Categories that may overdraw the club (the club is in debt but must pay): wages and transfer installments
## (agreed in a contract, so they are binding like wages).
const UNAVOIDABLE: Array[String] = ["salary", "installment", "maintenance", "loan_repayment", "fine"]

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


## Keeps the ledger bounded: every entry except the newest `keep` is folded into one summary entry per category
## (translation key FIN_SUMMARY). Balance, category totals and the audit (`is_consistent`) are unchanged; only the
## per-transaction detail of old entries is dropped. Returns the number of entries that were folded away.
func compact(keep: int) -> int:
	var n := entries.size() - maxi(keep, 0)
	if n <= CATEGORIES.size():                    # not worth it: the summaries would be as long as what they replace
		return 0
	var sums := {}                                # category -> [amount, week, count], in order of first appearance
	for i in n:
		var e: Dictionary = entries[i]
		var cat := str(e["category"])
		var row: Array = sums.get(cat, [0, 0, 0])
		row[0] += int(e["amount"])
		row[1] = maxi(int(row[1]), int(e["week"]))
		row[2] += int((e.get("args", [1]) as Array)[0]) if e.get("key", "") == "FIN_SUMMARY" else 1
		sums[cat] = row
	var folded: Array = []
	var running := opening_balance
	for cat in sums:
		var row: Array = sums[cat]
		if int(row[0]) == 0:
			continue                              # nets to nothing: `total()` and the balance chain are unaffected
		running += int(row[0])
		folded.append({"id": next_entry_id, "week": int(row[1]), "category": cat, "amount": int(row[0]),
				"description": "Summary of %d earlier entries" % int(row[2]), "balance_after": running,
				"key": "FIN_SUMMARY", "args": [int(row[2])]})
		next_entry_id += 1
	entries = folded + entries.slice(n)
	return n - folded.size()


## Books a player-agent commission as an expense (F5). Additive: a non-positive amount is a no-op.
## Uses the ordinary ledger rules, so the commission is audited and shown like every other cost.
func book_agent_fee(amount: int, description: String, week: int) -> String:
	if amount <= 0:
		return ""
	return record("agent_fee", -amount, description, week)


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


## Financial report over the weeks `from_week..to_week` (inclusive): income and expenses per category, the net result and
## the number of entries. Computed only from the audited entries, so it always matches the balance movement.
func report(from_week: int = 0, to_week: int = 1_000_000) -> Dictionary:
	var income := {}
	var expense := {}
	var count := 0
	for e in entries:
		var w := int(e["week"])
		if w < from_week or w > to_week:
			continue
		count += 1
		var amount := int(e["amount"])
		var bucket: Dictionary = income if amount > 0 else expense
		bucket[e["category"]] = int(bucket.get(e["category"], 0)) + amount
	var total_in := 0
	var total_out := 0
	for k in income:
		total_in += int(income[k])
	for k in expense:
		total_out += int(expense[k])
	return {"income": income, "expense": expense, "total_income": total_in, "total_expense": total_out,
			"net": total_in + total_out, "entries": count}


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
		if e.has("args"):
			e["args"] = PlayerData._restore_ints(e["args"])
	l.next_entry_id = int(d.get("next_id", l.entries.size() + 1))
	return l
