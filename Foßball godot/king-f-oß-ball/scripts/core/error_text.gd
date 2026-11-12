class_name ErrorText
extends RefCounted

## Localises system-layer error messages (see `ErrorTextRules`). Use at the UI boundary only:
## `say(ErrorText.localize(err, db), true)`.

static var _compiled: Array = []
static var unmatched: Dictionary = {}      # message -> count (audit aid; stays empty in a healthy run)


static func _ensure() -> void:
	if not _compiled.is_empty():
		return
	for rule in ErrorTextRules.RULES:
		var re := RegEx.new()
		re.compile(rule[0])
		_compiled.append([re, rule[1]])


## Translation key for a message ("" if no rule matches).
static func key_for(message: String) -> String:
	_ensure()
	for c in _compiled:
		if (c[0] as RegEx).search(message) != null:
			return c[1]
	return ""


## Localised text for `message`. `db` (optional) turns player / team ids in the message into names.
static func localize(message: String, db: Node = null) -> String:
	_ensure()
	for c in _compiled:
		var m: RegExMatch = (c[0] as RegEx).search(message)
		if m == null:
			continue
		var args: Array = []
		for i in range(1, m.get_group_count() + 1):
			var raw := m.get_string(i)
			if raw == "":
				continue
			args.append(_arg(raw, db))
		var text := Loc.t(c[1])
		var placeholders := text.count("%s") + text.count("%d")
		if args.size() > placeholders:
			args = args.slice(0, placeholders)
		while args.size() < placeholders:
			args.append("")
		return Loc.f(c[1], args) if placeholders > 0 else text
	if message.contains(" ") and not _has_non_ascii(message):          # an English system message nobody mapped yet
		unmatched[message] = int(unmatched.get(message, 0)) + 1
	return message


static func _arg(raw: String, db: Node) -> Variant:
	if raw.is_valid_int():
		return int(raw)
	if db != null:
		var p: PlayerData = db.get_player(raw)
		if p != null:
			return p.display_name
		var t: TeamData = db.get_team(raw)
		if t != null:
			return t.display_name
	return raw


static func _has_non_ascii(text: String) -> bool:
	for i in text.length():
		if text.unicode_at(i) > 127:
			return true
	return false
