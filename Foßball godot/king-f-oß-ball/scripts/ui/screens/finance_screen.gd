extends HubScreen

## Club Finance: balance, budgets, wages and the full audited ledger.


func build() -> void:
	if not header(Loc.t("FINANCE_CLUB_FINANCE"), true, true):
		return
	var career: CareerState = app().career
	var l := career.ledger()
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	var wages := career.market.weekly_wages(career.club_id)
	var facts := {Loc.t("FINANCE_BALANCE"): l.balance, Loc.t("FINANCE_TRANSFER_BUDGET"): l.transfer_budget, Loc.t("FINANCE_WAGE_BUDGET_WEEKLY"): l.wage_budget,
			Loc.t("FINANCE_CURRENT_WAGES_WEEKLY"): wages, Loc.t("FINANCE_WAGE_ROOM"): l.wage_budget - wages,
			Loc.t("FINANCE_ACADEMY_BUDGET"): app().academy().budget if app().academy() != null else 0}
	for k in facts:
		grid.add_child(UIKit.label(k, 15, UIKit.MUTED))
		grid.add_child(UIKit.label(Loc.money(int(facts[k])), 16, UIKit.BAD if int(facts[k]) < 0 else UIKit.TEXT))
	add_child(UIKit.panel(grid))
	add_child(UIKit.label(Loc.t("FINANCE_TOTALS_BY_CATEGORY"), 16, UIKit.GOLD))
	var totals: Array = []
	for cat in FinanceLedger.CATEGORIES:
		var t := l.total(cat)
		if t != 0:
			totals.append([_category_label(cat), Loc.money(t)])
	if totals.is_empty():
		add_child(UIKit.muted(Loc.t("FINANCE_NO_TRANSACTIONS_YET")))
	else:
		add_child(UIKit.table([Loc.t("FINANCE_CATEGORY"), Loc.t("FINANCE_TOTAL")], totals))
	add_child(UIKit.label(Loc.f("FINANCE_LEDGER_LATEST_FIRST_AUDIT", (Loc.t("FINANCE_AUDIT_OK") if l.is_consistent() else Loc.t("FINANCE_AUDIT_MISMATCH"))), 16,
			UIKit.GOOD if l.is_consistent() else UIKit.BAD))
	var rows: Array = []
	var entries := l.entries.duplicate()
	entries.reverse()
	for e in entries.slice(0, 30):
		rows.append([e["week"], _category_label(e["category"]), Loc.money(int(e["amount"])),
				Loc.money(int(e["balance_after"])), Loc.f(e["key"], e.get("args", [])) if e.has("key") else e["description"]])
	if rows.is_empty():
		add_child(UIKit.empty_state(Loc.t("FINANCE_TRANSACTIONS_APPEAR_HERE_AFTER_WAG")))
	else:
		add_child(UIKit.scroll(UIKit.table([Loc.t("FINANCE_WEEK"), Loc.t("FINANCE_CATEGORY"), Loc.t("FINANCE_AMOUNT"), Loc.t("FINANCE_BALANCE"), Loc.t("FINANCE_NOTE")], rows)))


## Localized name of a ledger category ("salary" -> "الرواتب"). Falls back to the raw
## category id when no translation exists, so a new category never breaks the table.
func _category_label(category: String) -> String:
	var key := "FINANCE_CATEGORY_" + category.to_upper()
	return Loc.t(key) if Loc.has_key(key) else category
