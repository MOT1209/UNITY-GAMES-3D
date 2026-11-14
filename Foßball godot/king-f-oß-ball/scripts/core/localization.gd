extends Node
class_name Localization

## Central localization manager (autoload "Loc").
##
##  * Stable translation KEYS (e.g. MENU_PLAY) — never the translated text — are
##    the identifiers. Tables live in `res://translations/*.csv`
##    (`key,en,de,ar,...`; every file in the folder is merged; adding a language
##    is one more column + one entry in LANGUAGES).
##  * Lookups: `Loc.t(key)`, `Loc.f(key, args)` (printf `%` array or `{name}`
##    dictionary placeholders), `Loc.tn(base_key, n)` (plural categories).
##    Fallback chain: current language -> English -> the key itself (the key is
##    shown so a gap is visible, and recorded in `missing`).
##  * The same tables are registered with Godot's TranslationServer, so Controls
##    whose text IS a key (scene labels) translate themselves automatically and
##    refresh on language change.
##  * Runtime switching (`set_language`), persisted in `user://settings.cfg`,
##    layout direction (RTL for Arabic) applied to the root window, and the
##    font stack (Latin + Arabic fallbacks) applied through the root theme.

signal language_changed(code: String)

const DEFAULT_LANGUAGE := "en"
const FALLBACK_LANGUAGE := "en"
const SETTINGS_PATH := "user://settings.cfg"
const TRANSLATION_DIR := "res://translations"
const ARABIC_FONT_PATH := "res://assets/fonts/NotoSansArabic.ttf"
## Unicode bidi isolates: keep names/numbers from reordering the surrounding text.
const FSI := "\u2068"
const PDI := "\u2069"
## Left-to-right isolate: numbers, formations ("4-3-3"), signed deltas, ratios, scores and Latin
## abbreviations keep their visual order inside Arabic sentences (closed by PDI).
const LRI := "\u2066"

## code -> {native, rtl}. First-class languages; add entries to support more.
const LANGUAGES := {
	"ar": {"native": "العربية", "rtl": true},
	"de": {"native": "Deutsch", "rtl": false},
	"en": {"native": "English", "rtl": false},
}
const ORDER: Array[String] = ["ar", "de", "en"]

var language: String = DEFAULT_LANGUAGE
var settings_path: String = SETTINGS_PATH
var tables: Dictionary = {}          # code -> {key: text}
var missing: Dictionary = {}         # key -> true (lookups that found nothing anywhere)
var load_errors: Array[String] = []
var arabic_font_loaded := false

var _theme: Theme
var _registered: Array[Translation] = []


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	load_tables()
	var saved := saved_language()
	# Headless runs (automated tests) start from the default language so they never
	# depend on a language a developer once saved; KING_LANGUAGE=xx overrides.
	var forced := OS.get_environment("KING_LANGUAGE")
	if forced != "" and LANGUAGES.has(forced):
		saved = forced
	elif DisplayServer.get_name() == "headless":
		saved = ""
	set_language(saved if saved != "" else DEFAULT_LANGUAGE, false)


# --- tables -------------------------------------------------------------------

## (Re)reads every CSV in TRANSLATION_DIR. Safe to call again (tests, hot reload).
func load_tables(dir: String = TRANSLATION_DIR) -> void:
	tables = {}
	load_errors.clear()
	for code in LANGUAGES:
		tables[code] = {}
	var d := DirAccess.open(dir)
	if d == null:
		load_errors.append("translation folder '%s' not found" % dir)
		return
	var files: Array[String] = []
	for f in d.get_files():
		if f.ends_with(".csv"):
			files.append(f)
	files.sort()
	for f in files:
		_load_csv("%s/%s" % [dir, f])
	_register_with_server()


func _load_csv(path: String) -> void:
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		load_errors.append("cannot open '%s'" % path)
		return
	var header := fa.get_csv_line()
	if header.size() < 2 or header[0] != "key":
		load_errors.append("%s: first column must be 'key'" % path)
		return
	while not fa.eof_reached():
		var row := fa.get_csv_line()
		if row.size() == 0 or (row.size() == 1 and row[0].strip_edges() == ""):
			continue
		var key := row[0].strip_edges()
		if key.begins_with("#"):
			continue
		for i in range(1, mini(row.size(), header.size())):
			var code := header[i].strip_edges()
			if not tables.has(code):
				tables[code] = {}
			if tables[code].has(key) and path != "":
				load_errors.append("%s: duplicate key '%s' for '%s'" % [path, key, code])
			tables[code][key] = row[i]


func _register_with_server() -> void:
	for old in _registered:
		TranslationServer.remove_translation(old)    # reload-safe: never stack duplicates
	_registered.clear()
	for code in tables:
		var tr_obj := Translation.new()
		tr_obj.locale = code
		for key in tables[code]:
			if str(tables[code][key]) != "":
				tr_obj.add_message(key, tables[code][key])
		TranslationServer.add_translation(tr_obj)
		_registered.append(tr_obj)


func supported_codes() -> Array[String]:
	var out: Array[String] = []
	for c in ORDER:
		out.append(c)
	return out


func native_name(code: String) -> String:
	return str(LANGUAGES.get(code, {}).get("native", code))


func is_rtl(code: String = "") -> bool:
	var c := language if code == "" else code
	return bool(LANGUAGES.get(c, {}).get("rtl", false))


# --- lookup --------------------------------------------------------------------

func has_key(key: String, code: String = "") -> bool:
	var c := language if code == "" else code
	return tables.has(c) and tables[c].has(key) and str(tables[c][key]) != ""


## Translated text for `key` (fallback chain above).
func t(key: String) -> String:
	if has_key(key):
		return tables[language][key]
	if has_key(key, FALLBACK_LANGUAGE):
		return tables[FALLBACK_LANGUAGE][key]
	missing[key] = true
	return key


## Translated + formatted. `args` is an Array (printf style %d/%s, in order) or a
## Dictionary ({name} placeholders — preferred when word order can differ).
func f(key: String, args: Variant = null) -> String:
	var text := t(key)
	if args == null:
		return text
	if args is Dictionary:
		return text.format(args)
	var arr: Array = (args as Array).duplicate() if args is Array else [args]
	return _group_big_numbers(isolate_numeric_placeholders(text), arr) % arr


## RTL only: wraps every numeric placeholder cluster of a format string — "%d", "%+d", "%d/%d",
## "%d-%d", "%.1f%%", "%%%d" — in one LTR isolate, so the formatted numbers and the symbols between
## them keep their order inside Arabic text ("91/97" not "97/91", "+3" not "3+", "30.6%").
func isolate_numeric_placeholders(text: String) -> String:
	if not is_rtl() or not text.contains("%"):
		return text
	var re := RegEx.new()
	re.compile("(?:%%)?[+\\-]?%[-+0-9.]*[dfx](?:\\s?[/:\\-–]\\s?[+\\-]?%[-+0-9.]*[dfx])*(?:%%)?")
	var out := ""
	var last := 0
	for m in re.search_all(text):
		out += text.substr(last, m.get_start() - last) + LRI + m.get_string() + PDI
		last = m.get_end()
	return out + text.substr(last)


## Whole numbers >= 1,000 (money, budgets, wages) get locale thousands
## separators: the matching "%d" becomes "%s" and the argument its formatted text.
func _group_big_numbers(text: String, arr: Array) -> String:
	var re := RegEx.new()
	re.compile("%[-+0-9.]*[sdfx]")
	var out := ""
	var last := 0
	var i := 0
	for m in re.search_all(text):
		out += text.substr(last, m.get_start() - last)
		var token := m.get_string()
		if token.ends_with("d") and i < arr.size() and arr[i] is int and absi(arr[i]) >= 1000:
			arr[i] = num(arr[i])
			token = "%s"
		out += token
		last = m.get_end()
		i += 1
	return out + text.substr(last)


## Plural form: looks up "<base>#<category>" (zero/one/two/few/many/other),
## falls back to "<base>#other" then "<base>". `{n}` is replaced by the number.
func tn(base_key: String, n: int, extra: Dictionary = {}) -> String:
	var cat := plural_category(language, n)
	var key := "%s#%s" % [base_key, cat]
	if not has_key(key) and not has_key(key, FALLBACK_LANGUAGE):
		key = "%s#other" % base_key
	if not has_key(key) and not has_key(key, FALLBACK_LANGUAGE):
		key = base_key
	var d := {"n": num(n)}
	d.merge(extra, true)
	return t(key).format(d)


## CLDR plural categories for the three languages.
static func plural_category(code: String, n: int) -> String:
	if code == "ar":
		var m := absi(n)
		if m == 0:
			return "zero"
		if m == 1:
			return "one"
		if m == 2:
			return "two"
		var r := m % 100
		if r >= 3 and r <= 10:
			return "few"
		if r >= 11 and r <= 99:
			return "many"
		return "other"
	return "one" if absi(n) == 1 else "other"   # en, de


## Keeps a name/number from being reordered by the surrounding text in RTL
## mode (Arabic sentence containing a Latin team name, scores, ...).
func iso(text: String) -> String:
	return FSI + text + PDI if is_rtl() else text


## Display name of an enum/data value: key "ENUM_<GROUP>_<VALUE>" (value upper-cased,
## spaces -> "_"). A missing entry is recorded and shows the raw value.
func enum_name(group: String, value: String) -> String:
	var key := "ENUM_%s_%s" % [group, value.to_upper().replace(" ", "_")]
	if has_key(key) or has_key(key, FALLBACK_LANGUAGE):
		return t(key)
	missing[key] = true
	return value


## Country / scouting-region name: translated when the table has ENUM_COUNTRY_<NAME>, otherwise the
## stored name isolated as a proper noun (data packs may bring any country).
func country(stored: String) -> String:
	var key := "ENUM_COUNTRY_%s" % stored.to_upper().replace(" ", "_")
	if has_key(key) or has_key(key, FALLBACK_LANGUAGE):
		return t(key)
	return iso(stored)


func enum_names(group: String, values: Array) -> Array:
	var out: Array = []
	for v in values:
		out.append(enum_name(group, str(v)))
	return out


func traits_text(traits: Array) -> String:
	var out: Array = []
	for tr_name in traits:
		out.append(enum_name("TRAIT", str(tr_name)))
	return ("، " if is_rtl() else ", ").join(out)


# --- locale-aware numbers / money / dates ----------------------------------------------

## Arabic uses Western digits with Western separators: the Arabic separators U+066C / U+066B are
## bidi class AN and made the bidi algorithm reorder digit groups ("82,000,000" showed "000٬82٬000").
func _group_sep() -> String:
	return {"en": ",", "de": "."}.get(language, ",")


func _decimal_sep() -> String:
	return {"en": ".", "de": ","}.get(language, ".")


## Wraps `text` in a left-to-right isolate (LRI ... PDI) in RTL languages only, so a formation
## ("4-3-3"), signed delta ("+3"), ratio ("91/97"), score, time or Latin abbreviation ("GK") is shown
## in its own order inside Arabic text. No-op in LTR languages and for empty / already isolated text.
func ltr(text: String) -> String:
	if not is_rtl() or text == "" or text.begins_with(LRI):
		return text
	return LRI + text + PDI


## Integer with locale thousands separators ("1,234,567" / "1.234.567"; Arabic "1,234,567" isolated LTR).
func num(n: int) -> String:
	return ltr(_num_raw(n))


func _num_raw(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = _group_sep() + out
	return ("-" if n < 0 else "") + out


func decimal(v: float, places: int = 1) -> String:
	return ltr(_decimal_raw(v, places))


func _decimal_raw(v: float, places: int) -> String:
	var whole := int(floor(absf(v)))
	var frac := str(snappedf(absf(v) - whole, pow(10.0, -places))).trim_prefix("0.").trim_prefix("0")
	var frac_txt := frac.pad_zeros(places).substr(0, places) if places > 0 else ""
	return ("-" if v < 0.0 else "") + _num_raw(whole) + (_decimal_sep() + frac_txt if places > 0 else "")


func percent(ratio: float) -> String:
	return ltr(_num_raw(roundi(ratio * 100.0)) + "%")


## Money in the game currency (euro). en "€1,234,567", de "1.234.567 €", ar "1,234,567 €" (LTR isolate).
func money(amount: int) -> String:
	var n := _num_raw(amount)
	return "€" + n if language == "en" else ltr(n + " €")


## Signed whole-number delta ("+3", "-2", "+0"), isolated in RTL so the sign stays in front.
func signed(n: int) -> String:
	return ltr("%+d" % n)


## Two whole numbers as a ratio ("91/97": overall/potential, "2/20"), isolated in RTL.
func ratio(a: int, b: int) -> String:
	return ltr("%d/%d" % [a, b])


## Score between the two team names. LTR: "2 - 1" (home first). RTL: the home team is read first and
## sits on the right, so its goals must sit on the right too: the isolated text is "away - home".
func score(home: int, away: int) -> String:
	if is_rtl():
		return ltr("%d - %d" % [away, home])
	return "%d - %d" % [home, away]


## Short position code (GK, CB, RW ...) of a PlayerData.Position value, isolated in RTL.
func position_code(position: int) -> String:
	var keys: Array = PlayerData.Position.keys()
	return ltr(str(keys[position]) if position >= 0 and position < keys.size() else "?")


## Godot's numeral localisation would turn SpinBox / LineEdit / Label digits into Eastern Arabic
## digits in Arabic while the rest of the game shows Western digits: switched off for every node.
func _on_node_added(node: Node) -> void:
	if node is SpinBox:
		(node as SpinBox).localize_numeral_system = false        # SpinBox formats its own text
		(node as SpinBox).get_line_edit().localize_numeral_system = false
	elif node is LineEdit:
		(node as LineEdit).localize_numeral_system = false
	elif node is Label:
		(node as Label).localize_numeral_system = false
	elif node is Button:
		(node as Button).localize_numeral_system = false
	elif node is RichTextLabel:
		(node as RichTextLabel).localize_numeral_system = false
	elif node is TextEdit:
		(node as TextEdit).localize_numeral_system = false


## Date from a unix timestamp. en 11/12/2026, de 12.11.2026, ar 12/11/2026.
func date(unix: int) -> String:
	var d := Time.get_datetime_dict_from_unix_time(unix)
	match language:
		"en":
			return "%02d/%02d/%04d" % [d["month"], d["day"], d["year"]]
		"de":
			return "%02d.%02d.%04d" % [d["day"], d["month"], d["year"]]
		_:
			return "%02d/%02d/%04d" % [d["day"], d["month"], d["year"]]


func match_clock(minute: float) -> String:
	var m := int(minute)
	var s := int((minute - m) * 60.0)
	return ltr("%02d:%02d" % [m, s])


# --- language switching ---------------------------------------------------------------

## Switches language at runtime. Returns "" or an error. `persist` stores the choice.
func set_language(code: String, persist: bool = true) -> String:
	if not LANGUAGES.has(code):
		return "unsupported language '%s'" % code
	language = code
	TranslationServer.set_locale(code)
	_apply_direction()
	_apply_fonts()
	if persist:
		_save_language(code)
	language_changed.emit(code)
	return ""


func _apply_direction() -> void:
	var tree := get_tree()
	if tree == null:
		return
	tree.root.set_layout_direction(Window.LAYOUT_DIRECTION_RTL if is_rtl() else Window.LAYOUT_DIRECTION_LTR)


## Latin base font + Arabic fallbacks (bundled Noto Sans Arabic when present,
## then system Arabic-capable fonts), installed as the root theme's default font.
func _apply_fonts() -> void:
	var tree := get_tree()
	if tree == null:
		return
	if _theme == null:
		# The game's UI theme (colours, button states, spacing; resources/theme/main_theme.tres) with the
		# font stack added, so every screen shares one look.
		_theme = (load(UIKit.THEME_PATH) as Theme).duplicate() if ResourceLoader.exists(UIKit.THEME_PATH) else Theme.new()
		var base := FontVariation.new()
		base.base_font = ThemeDB.fallback_font
		var fallbacks: Array[Font] = []
		if ResourceLoader.exists(ARABIC_FONT_PATH):
			var ff := load(ARABIC_FONT_PATH) as Font
			if ff != null:
				fallbacks.append(ff)
				arabic_font_loaded = true
		var sys := SystemFont.new()
		sys.font_names = PackedStringArray(["Segoe UI", "Tahoma", "Noto Sans Arabic", "Noto Naskh Arabic", "Arial", "DejaVu Sans"])
		fallbacks.append(sys)
		base.fallbacks = fallbacks
		_theme.default_font = base
	tree.root.theme = _theme


# --- persistence ----------------------------------------------------------------------

func saved_language() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) != OK:
		return ""
	var code := str(cfg.get_value("game", "language", ""))
	return code if LANGUAGES.has(code) else ""


func has_saved_language() -> bool:
	return saved_language() != ""


func _save_language(code: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(settings_path)          # keep other settings
	cfg.set_value("game", "language", code)
	cfg.save(settings_path)


func forget_saved_language() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) == OK:
		cfg.erase_section_key("game", "language")
		cfg.save(settings_path)


# --- validation -----------------------------------------------------------------------

## Parity/quality report: every key exists and is non-empty in every language,
## no placeholder-looking text, placeholders match across languages.
func validate() -> Array[String]:
	var problems: Array[String] = []
	problems.append_array(load_errors)
	var all_keys := {}
	for code in tables:
		for k in tables[code]:
			all_keys[k] = true
	for key in all_keys:
		var counts := {}
		for code in ORDER:
			var text := str(tables.get(code, {}).get(key, ""))
			if text.strip_edges() == "":
				if _optional_plural(key, code):
					continue
				problems.append("[%s] '%s' is missing or empty" % [code, key])
				continue
			if text == key or text.begins_with("TODO") or text.begins_with("[[") or text.begins_with("XXX"):
				problems.append("[%s] '%s' looks untranslated (%s)" % [code, key, text])
			counts[code] = _placeholders(text)
		var ref: Array = counts.get("en", [])
		for code in counts:
			if key.contains("#") and str(tables.get("en", {}).get(key, "")) == "":
				continue            # plural category English does not use: nothing to compare against
			if counts[code] != ref:
				problems.append("[%s] '%s' placeholders %s differ from en %s" % [code, key, counts[code], ref])
	return problems


## Plural categories a language does not use (e.g. en/de have no "#few") may be empty.
static func _optional_plural(key: String, code: String) -> bool:
	if not key.contains("#"):
		return false
	var cat := key.get_slice("#", 1)
	if cat == "other" or cat == "one":
		return false
	return code != "ar"        # zero/two/few/many are Arabic-only


static func _placeholders(text: String) -> Array:
	var found: Array = []
	var re := RegEx.new()
	re.compile("%[sdfx]|\\{[a-z_0-9]+\\}")
	for m in re.search_all(text):
		found.append(m.get_string())
	found.sort()
	return found
