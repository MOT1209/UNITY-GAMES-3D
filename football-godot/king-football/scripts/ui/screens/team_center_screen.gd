extends HubScreen

## Phase H2: team centre — the managed club's players with their statistics per competition.
##   * table: number, position, name, apps, goals, assists, clean sheets, cards, average rating; click a column to sort
##     (click again to reverse); tabs Attributes / Statistics / Status (daily fitness, morale, injury days, ban, contract);
##   * side panel of the selected player: name, rating, position and a table of his figures per competition of the season
##     (league, cup, continental ...: apps, goals, assists, clean sheets, yellow / red, average) with the arrows to move
##     through the squad. Figures of matches played by the simulation model are marked "estimated".
## Data: `CareerState.season_stats` (matches played in 3D) + `CareerState.sim_comp_stats` (event-engine matches), per season.

const COLUMNS := [["TC_NO", "num"], ["TC_POS", "pos"], ["TC_NAME", "name"], ["TC_APPS", "apps"], ["TC_GOALS", "goals"], ["TC_ASSISTS", "assists"],
		["TC_CLEAN", "clean_sheets"], ["TC_CARDS", "cards"], ["TC_RATING", "rating"]]
const ATTRS := ["pace", "shooting", "passing", "dribbling", "defending", "physical"]

var tab := "stats"
var sort_key := "goals"
var sort_desc := true
var selected_id := ""


## Rows of one player for `season`: {competition key -> row}, the real and the modelled matches merged, plus "est" apps.
static func comp_rows(career: CareerState, pid: String, season: int) -> Dictionary:
	var out := {}
	var prefix := "%d:" % season
	for src in [[career.season_stats, false], [career.sim_comp_stats, true]]:
		var by_key: Dictionary = (src[0] as Dictionary).get(pid, {})
		for key in by_key:
			if not str(key).begins_with(prefix):
				continue
			var r: Dictionary = by_key[key]
			if not out.has(key):
				out[key] = {"apps": 0, "goals": 0, "assists": 0, "clean_sheets": 0, "yellow": 0, "red": 0, "rating_sum": 0.0, "est_apps": 0}
			for k in ["apps", "goals", "assists", "clean_sheets", "yellow", "red"]:
				out[key][k] += int(r.get(k, 0))
			out[key]["rating_sum"] += float(r.get("rating_sum", 0.0))
			if bool(src[1]):
				out[key]["est_apps"] += int(r.get("apps", 0))
	return out


## Totals of all competitions of a season ({apps, goals, assists, clean_sheets, cards, rating, est_apps}).
static func totals(career: CareerState, pid: String, season: int) -> Dictionary:
	var t := {"apps": 0, "goals": 0, "assists": 0, "clean_sheets": 0, "cards": 0, "rating": 0.0, "est_apps": 0}
	var sum := 0.0
	var rows := comp_rows(career, pid, season)
	for key in rows:
		var r: Dictionary = rows[key]
		t["apps"] += int(r["apps"])
		t["goals"] += int(r["goals"])
		t["assists"] += int(r["assists"])
		t["clean_sheets"] += int(r["clean_sheets"])
		t["cards"] += int(r["yellow"]) + int(r["red"])
		t["est_apps"] += int(r["est_apps"])
		sum += float(r["rating_sum"])
	t["rating"] = snappedf(sum / float(t["apps"]), 0.01) if int(t["apps"]) > 0 else 0.0
	return t


## The squad as sorted rows [{player, num, pos, name, apps, goals, assists, clean_sheets, cards, rating, est_apps}].
static func table_rows(career: CareerState, db: Node, sort_by: String, desc: bool) -> Array:
	var rows: Array = []
	var n := 0
	for p: PlayerData in db.get_squad(career.club_id):
		if p.status == PlayerData.Status.RETIRED:
			continue
		n += 1
		var t := totals(career, p.id, career.season)
		t["player"] = p
		t["num"] = n
		t["pos"] = PlayerData.Position.keys()[p.position]
		t["name"] = p.display_name
		rows.append(t)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var va: Variant = a[sort_by]
		var vb: Variant = b[sort_by]
		if va == vb:
			return str(a["name"]) < str(b["name"])
		return va > vb if desc else va < vb)
	return rows


func build() -> void:
	add_child(UIKit.title(Loc.t("NAV_TEAM_CENTER")))
	var career: CareerState = app().career
	if career == null:
		add_child(UIKit.empty_state(Loc.t("CAREER_NO_CAREER_IN_PROGRESS_PICK_A_CLUB")))
		return
	var rows := table_rows(career, db(), sort_key, sort_desc)
	if selected_id == "" and not rows.is_empty():
		selected_id = (rows[0]["player"] as PlayerData).id
	var tabs := UIKit.hbox(6)
	for t in [["attrs", "TC_TAB_ATTRS"], ["stats", "TC_TAB_STATS"], ["status", "TC_TAB_STATUS"]]:
		var b := Button.new()
		b.text = Loc.t(t[1])
		b.toggle_mode = true
		b.button_pressed = tab == t[0]
		b.name = "TCTab_%s" % t[0]
		b.pressed.connect(func() -> void:
			tab = t[0]
			rebuild())
		tabs.add_child(b)
	add_child(tabs)
	var body := UIKit.hbox(UIKit.SPACE_M)
	body.add_child(_table(rows, career))
	body.add_child(_side(career))
	add_child(body)


func _table(rows: Array, career: CareerState) -> Control:
	var grid := GridContainer.new()
	grid.name = "TCTable"
	grid.columns = _columns().size()
	grid.add_theme_constant_override("h_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for c in _columns():
		var h := Button.new()
		h.flat = true
		h.text = Loc.t(c[0]) + (" ▼" if sort_key == c[1] and sort_desc else (" ▲" if sort_key == c[1] else ""))
		h.name = "TCSort_%s" % c[1]
		h.clip_text = true
		h.pressed.connect(func() -> void:
			if sort_key == c[1]:
				sort_desc = not sort_desc
			else:
				sort_key = c[1]
				sort_desc = c[1] != "name" and c[1] != "pos"
			rebuild())
		grid.add_child(h)
	for r in rows:
		var p: PlayerData = r["player"]
		for c in _columns():
			grid.add_child(_cell(r, p, str(c[1]), career))
	var sc := UIKit.panel(grid)
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return sc


func _columns() -> Array:
	match tab:
		"attrs":
			var cols: Array = [["TC_NO", "num"], ["TC_POS", "pos"], ["TC_NAME", "name"]]
			for a in ATTRS:
				cols.append(["ATTR_" + a.to_upper(), a])
			return cols
		"status":
			return [["TC_NO", "num"], ["TC_POS", "pos"], ["TC_NAME", "name"], ["TC_FITNESS", "fitness"], ["TC_MORALE", "morale"], ["TC_INJURY", "injury"], ["TC_CONTRACT", "contract"]]
	return COLUMNS


func _cell(r: Dictionary, p: PlayerData, key: String, career: CareerState) -> Control:
	var text := ""
	match key:
		"num", "pos", "name", "apps", "goals", "assists", "clean_sheets", "cards":
			text = str(r[key])
		"rating":
			text = ("%.2f" % float(r["rating"])) if int(r["apps"]) > 0 else "–"
			if int(r["est_apps"]) > 0 and int(r["apps"]) > 0:
				text += "*"
		"fitness": text = "%d%%" % p.fitness
		"morale": text = str(p.morale)
		"injury":
			if p.status == PlayerData.Status.SUSPENDED:
				text = Loc.t("TC_SUSPENDED")
			elif p.status == PlayerData.Status.INJURED:
				text = Loc.f("TC_DAYS", maxi(p.unavailable_days, p.unavailable_weeks * 7))
			else:
				text = "–"
		"contract": text = str(p.contract_years)
		_:
			text = str(p.get(key)) if key in ATTRS else ""
	var b := Button.new()
	b.flat = true
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if p.id == selected_id:
		b.add_theme_color_override("font_color", UIKit.GOLD)
	b.pressed.connect(func() -> void:
		selected_id = p.id
		rebuild())
	return b


func _side(career: CareerState) -> Control:
	var box := UIKit.vbox(6)
	box.name = "TCSide"
	box.custom_minimum_size = Vector2(300, 0)
	var p: PlayerData = db().get_player(selected_id)
	if p == null:
		return UIKit.panel(box)
	var nav := UIKit.hbox(6)
	nav.add_child(UIKit.button("<", _step.bind(-1), 44))
	nav.add_child(UIKit.label("%s  %s" % [PlayerData.Position.keys()[p.position], str(p.get_overall())], 17, UIKit.GOLD))
	nav.add_child(UIKit.button(">", _step.bind(1), 44))
	box.add_child(nav)
	box.add_child(UIKit.label(p.display_name, 16))
	box.add_child(UIKit.muted(Loc.t("TC_BY_COMP")))
	var rows := comp_rows(career, p.id, career.season)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 8)
	for h in ["", "TC_APPS", "TC_GOALS", "TC_ASSISTS", "TC_CLEAN", "TC_RATING"]:
		grid.add_child(UIKit.label(Loc.t(h) if h != "" else "", 12, UIKit.MUTED))
	var keys := rows.keys()
	keys.sort()
	var tot := {"apps": 0, "goals": 0, "assists": 0, "clean_sheets": 0, "yellow": 0, "red": 0, "rating_sum": 0.0, "est": 0}
	for key in keys:
		var r: Dictionary = rows[key]
		var cid := str(key).get_slice(":", 1)
		grid.add_child(UIKit.label(app().competition_title(cid) if cid != "friendly" else Loc.t("CAL2_COMP_FRIENDLY"), 13))
		grid.add_child(UIKit.label(str(r["apps"]), 13))
		grid.add_child(UIKit.label(str(r["goals"]), 13))
		grid.add_child(UIKit.label(str(r["assists"]), 13))
		grid.add_child(UIKit.label("%d  🟨%d 🟥%d" % [int(r["clean_sheets"]), int(r["yellow"]), int(r["red"])], 12))
		grid.add_child(UIKit.label(("%.2f" % (float(r["rating_sum"]) / float(r["apps"]))) if int(r["apps"]) > 0 else "–", 13))
		for k in ["apps", "goals", "assists", "clean_sheets", "yellow", "red"]:
			tot[k] += int(r[k])
		tot["est"] += int(r["est_apps"])
	box.add_child(grid)
	if int(tot["est"]) > 0:
		box.add_child(UIKit.muted("* " + Loc.t("TC_ESTIMATED")))
	return UIKit.panel(box)


func _step(delta: int) -> void:
	var rows := table_rows(app().career, db(), sort_key, sort_desc)
	for i in rows.size():
		if (rows[i]["player"] as PlayerData).id == selected_id:
			selected_id = (rows[posmod(i + delta, rows.size())]["player"] as PlayerData).id
			break
	rebuild()
