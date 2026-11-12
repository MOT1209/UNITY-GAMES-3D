extends HubScreen

## Player Collection (Phase V8-D): browse the managed club's players (first team
## + academy) as cards. Search, position / rating / category filters, sorting,
## detail view and profile access. A management view of the club's own squad —
## no packs, no rewards, nothing random.

const SORTS := ["ovr", "name", "age", "pos"]

var _search := ""
var _position := -1            # -1 = all, else PlayerData.Position
var _min_ovr := 0
var _category := -1            # -1 = all, else CardCategory.Kind
var _sort := 0


func build() -> void:
	if not header(Loc.t("CARD_COLLECTION_TITLE"), true):
		return
	var pool := club_players()
	add_child(_filter_bar())
	var shown := filter_and_sort(pool, _search, _position, _min_ovr, _category, SORTS[_sort])
	add_child(UIKit.muted(Loc.f("CARD_COLLECTION_COUNT", [shown.size(), pool.size()])))
	if shown.is_empty():
		add_child(UIKit.empty_state(Loc.t("CARD_COLLECTION_EMPTY")))
		return
	var flow := HFlowContainer.new()
	flow.name = "CardFlow"
	flow.add_theme_constant_override("h_separation", 12)
	flow.add_theme_constant_override("v_separation", 12)
	for p: PlayerData in shown:
		var card := PlayerCard.new(150.0)
		card.name = "Card_%s" % p.id
		card.setup(PlayerCardData.from_data(db(), p), db())
		card.pressed.connect(_show_detail)
		flow.add_child(card)
	add_child(UIKit.scroll(flow))


## First team + academy prospects of the managed club (same PlayerData objects
## every other screen uses).
func club_players() -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	out.append_array(db().get_squad(app().user_team_id))
	var ac: Academy = app().academy()
	if ac != null:
		for pid in ac.roster_ids:
			var p: PlayerData = db().get_player(pid)
			if p != null and not out.has(p):
				out.append(p)
	return out


## Pure filter + sort (static so tests can call it without a UI).
static func filter_and_sort(pool: Array, search: String, position: int, min_ovr: int,
		category: int, sort_key: String) -> Array:
	var needle := search.strip_edges().to_lower()
	var out: Array = pool.filter(func(p: PlayerData) -> bool:
		if needle != "" and not p.display_name.to_lower().contains(needle):
			return false
		if position >= 0 and int(p.position) != position:
			return false
		if p.get_overall() < min_ovr:
			return false
		if category >= 0 and int(CardCategory.for_player(p)) != category:
			return false
		return true)
	out.sort_custom(func(a: PlayerData, b: PlayerData) -> bool: return _less(a, b, sort_key))
	return out


static func _less(a: PlayerData, b: PlayerData, sort_key: String) -> bool:
	var oa := a.get_overall()
	var ob := b.get_overall()
	if sort_key == "name":
		return a.display_name.naturalnocasecmp_to(b.display_name) < 0
	if sort_key == "age":
		return a.age < b.age if a.age != b.age else a.id < b.id
	if sort_key == "pos":
		return a.position < b.position if a.position != b.position else oa > ob
	return oa > ob if oa != ob else a.id < b.id


func _filter_bar() -> Control:
	var bar := UIKit.hbox(8)
	var search := LineEdit.new()
	search.name = "Search"
	search.placeholder_text = Loc.t("CARD_COLLECTION_SEARCH")
	search.text = _search
	search.custom_minimum_size = Vector2(200, 36)
	search.text_submitted.connect(func(t: String) -> void:
		_search = t
		rebuild())
	bar.add_child(search)
	var pos_names: Array = [Loc.t("CARD_COLLECTION_ALL_POSITIONS")]
	pos_names.append_array(PlayerData.Position.keys())
	var pos := UIKit.option(pos_names, _position + 1, func(i: int) -> void:
		_position = i - 1
		rebuild())
	pos.name = "PositionFilter"
	bar.add_child(pos)
	var cat_names: Array = [Loc.t("CARD_COLLECTION_ALL_CATEGORIES")]
	for k in CardCategory.all_kinds():
		cat_names.append(Loc.t(CardCategory.loc_key(k)))
	var cat := UIKit.option(cat_names, _category + 1, func(i: int) -> void:
		_category = i - 1
		rebuild())
	cat.name = "CategoryFilter"
	bar.add_child(cat)
	var ovr_names: Array = []
	for v in [0, 50, 60, 70, 80, 90]:
		ovr_names.append(Loc.f("CARD_COLLECTION_MIN_OVR", v))
	var ovr := UIKit.option(ovr_names, [0, 50, 60, 70, 80, 90].find(_min_ovr), func(i: int) -> void:
		_min_ovr = [0, 50, 60, 70, 80, 90][i]
		rebuild())
	ovr.name = "RatingFilter"
	bar.add_child(ovr)
	var sort := UIKit.option([Loc.t("CARD_COLLECTION_SORT_OVR"), Loc.t("CARD_COLLECTION_SORT_NAME"),
			Loc.t("CARD_COLLECTION_SORT_AGE"), Loc.t("CARD_COLLECTION_SORT_POS")], _sort, func(i: int) -> void:
		_sort = i
		rebuild())
	sort.name = "SortOption"
	bar.add_child(sort)
	return bar


func _show_detail(player_id: String) -> void:
	var view := CardDetailView.open(hub, db(), player_id)
	if view != null:
		view.open_profile.connect(func(pid: String) -> void: go("player_profile", {"player_id": pid}))
