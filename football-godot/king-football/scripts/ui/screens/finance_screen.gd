extends HubScreen

## Club Finance: balance, budgets, wages and the full audited ledger.


func _init() -> void:
	super()
	own_scroll = true       # lays out its own ScrollContainer


func build() -> void:
	if not header(Loc.t("FINANCE_CLUB_FINANCE"), true, true):
		return
	var career: CareerState = app().career
	var l := career.ledger()
	var wages := career.market.weekly_wages(career.club_id)
	var academy_budget: int = app().academy().budget if app().academy() != null else 0
	var cards := HFlowContainer.new()
	cards.name = "FinanceCards"
	cards.add_theme_constant_override("h_separation", 10)
	cards.add_theme_constant_override("v_separation", 10)
	cards.add_child(_stat_card(Loc.t("FINANCE_BALANCE"), l.balance, true))
	cards.add_child(_stat_card(Loc.t("FINANCE_TRANSFER_BUDGET"), l.transfer_budget))
	cards.add_child(_stat_card(Loc.t("FINANCE_ACADEMY_BUDGET"), academy_budget))
	var com := career.market.commitments(career.club_id)      # transfers v2: installments still to pay / receive
	if int(com["pay"]) > 0 or int(com["obligations"]) > 0:
		cards.add_child(_stat_card(Loc.t("FINANCE_COMMITMENTS"), -(int(com["pay"]) + int(com["obligations"]))))
	if int(com["receive"]) > 0:
		cards.add_child(_stat_card(Loc.t("FINANCE_RECEIVABLE"), int(com["receive"])))
	add_child(cards)
	# wage budget: how much of the weekly wage room is used
	var wage_box := UIKit.vbox(6)
	wage_box.name = "WageBudget"
	var ratio := float(wages) / maxf(1.0, float(l.wage_budget))
	wage_box.add_child(ChartKit.bar_row(Loc.t("FINANCE_CURRENT_WAGES_WEEKLY"), Loc.money(wages), ratio,
			UIKit.BAD if ratio > 1.0 else (UIKit.WARN if ratio > 0.9 else UIKit.GOOD), 190.0))
	wage_box.add_child(UIKit.label("%s: %s   ·   %s: %s" % [Loc.t("FINANCE_WAGE_BUDGET_WEEKLY"), Loc.money(l.wage_budget),
			Loc.t("FINANCE_WAGE_ROOM"), Loc.money(l.wage_budget - wages)], 14, UIKit.MUTED))
	add_child(UIKit.panel(wage_box))
	var report := l.report()
	var charts := HFlowContainer.new()
	charts.add_theme_constant_override("h_separation", 12)
	charts.add_theme_constant_override("v_separation", 12)
	charts.add_child(_balance_panel(l))
	charts.add_child(_flow_panel(report))
	add_child(charts)
	var totals_net: int = int(report["net"])
	var net := UIKit.label("%s: %s" % [Loc.t("FINANCE_TOTAL"), Loc.money(totals_net)], 16, UIKit.GOOD if totals_net >= 0 else UIKit.BAD)
	net.name = "NetTotal"
	add_child(net)
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


## One figure card: caption above, big number (red when negative).
func _stat_card(caption: String, value: int, highlight := false) -> Control:
	var box := UIKit.vbox(2)
	box.add_child(UIKit.label(caption, 13, UIKit.MUTED))
	box.add_child(UIKit.label(Loc.money(value), 22 if highlight else 19, UIKit.BAD if value < 0 else (UIKit.GOLD if highlight else UIKit.TEXT)))
	var p := UIKit.panel(box)
	p.custom_minimum_size.x = 210
	return p


## Balance after every booking (last 60), oldest left.
func _balance_panel(l: FinanceLedger) -> Control:
	var series: Array = [l.opening_balance]
	for e in l.entries.slice(maxi(0, l.entries.size() - 60)):
		series.append(int(e["balance_after"]))
	var box := UIKit.vbox(6)
	box.name = "BalanceChart"
	box.add_child(UIKit.label(Loc.t("FINANCE_BALANCE_OVER_TIME"), 16, UIKit.GOLD))
	if series.size() < 2:
		box.add_child(UIKit.muted(Loc.t("FINANCE_NO_TRANSACTIONS_YET")))
	else:
		box.add_child(ChartKit.line(series, Vector2(380, 160)))
	var p := UIKit.panel(box)
	p.custom_minimum_size.x = 420
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return p


## Income (green) and expense (red) per category as bars, the biggest first.
func _flow_panel(report: Dictionary) -> Control:
	var box := UIKit.vbox(6)
	box.name = "FlowBars"
	box.add_child(UIKit.label(Loc.t("FINANCE_TOTALS_BY_CATEGORY"), 16, UIKit.GOLD))
	var rows: Array = []
	for cat in report["income"]:
		rows.append([cat, int(report["income"][cat])])
	for cat in report["expense"]:
		rows.append([cat, int(report["expense"][cat])])
	if rows.is_empty():
		box.add_child(UIKit.muted(Loc.t("FINANCE_NO_TRANSACTIONS_YET")))
	rows.sort_custom(func(a: Array, b: Array) -> bool: return absi(a[1]) > absi(b[1]))
	var top := 1
	for r in rows:
		top = maxi(top, absi(r[1]))
	for r in rows.slice(0, 8):
		box.add_child(ChartKit.bar_row(_category_label(r[0]), Loc.money(r[1]), float(absi(r[1])) / top, UIKit.GOOD if r[1] > 0 else UIKit.BAD))
	var p := UIKit.panel(box)
	p.custom_minimum_size.x = 420
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return p
