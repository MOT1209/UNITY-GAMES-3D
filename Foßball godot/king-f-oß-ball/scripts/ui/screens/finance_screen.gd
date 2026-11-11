extends HubScreen

## Club Finance: balance, budgets, wages and the full audited ledger.


func build() -> void:
	if not header("Club Finance", true, true):
		return
	var career: CareerState = app().career
	var l := career.ledger()
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	var wages := career.market.weekly_wages(career.club_id)
	var facts := {"Balance": l.balance, "Transfer budget": l.transfer_budget, "Wage budget (weekly)": l.wage_budget,
			"Current wages (weekly)": wages, "Wage room": l.wage_budget - wages,
			"Academy budget": app().academy().budget if app().academy() != null else 0}
	for k in facts:
		grid.add_child(UIKit.label(k, 15, UIKit.MUTED))
		grid.add_child(UIKit.label(str(facts[k]), 16, UIKit.BAD if int(facts[k]) < 0 else UIKit.TEXT))
	add_child(UIKit.panel(grid))
	add_child(UIKit.label("Totals by category", 16, UIKit.GOLD))
	var totals: Array = []
	for cat in FinanceLedger.CATEGORIES:
		var t := l.total(cat)
		if t != 0:
			totals.append([cat, t])
	if totals.is_empty():
		add_child(UIKit.muted("No transactions yet."))
	else:
		add_child(UIKit.table(["Category", "Total"], totals))
	add_child(UIKit.label("Ledger (latest first) — audit: %s" % ("OK" if l.is_consistent() else "MISMATCH"), 16,
			UIKit.GOOD if l.is_consistent() else UIKit.BAD))
	var rows: Array = []
	var entries := l.entries.duplicate()
	entries.reverse()
	for e in entries.slice(0, 30):
		rows.append([e["week"], e["category"], e["amount"], e["balance_after"], e["description"]])
	if rows.is_empty():
		add_child(UIKit.empty_state("Transactions appear here after wages, transfers and matches."))
	else:
		add_child(UIKit.scroll(UIKit.table(["Week", "Category", "Amount", "Balance", "Note"], rows)))
