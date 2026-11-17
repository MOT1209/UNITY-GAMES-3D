class_name NameIndex
extends RefCounted

## Set of names with duplicate and look-alike detection (letters/accents/case ignored).
## `check(name)` returns "" when the name is free, else why it is not ("duplicate of X" /
## "too similar to X": at most MAX_DISTANCE letters apart). Look-alike search only compares names
## with the same first letter and similar length, so indexing 10,000 names stays fast.

const MAX_DISTANCE := 1
const ACCENTS := {"á": "a", "à": "a", "â": "a", "ä": "a", "ã": "a", "å": "a", "é": "e", "è": "e", "ê": "e", "ë": "e",
		"í": "i", "ì": "i", "î": "i", "ï": "i", "ó": "o", "ò": "o", "ô": "o", "ö": "o", "õ": "o", "ø": "o", "ú": "u",
		"ù": "u", "û": "u", "ü": "u", "ç": "c", "ñ": "n", "ß": "ss", "æ": "ae", "œ": "oe"}

var _exact: Dictionary = {}        # normalized -> display name
var _buckets: Dictionary = {}      # first letter -> Array[String] of normalized names


static func normalize(name: String) -> String:
	var out := ""
	for ch in name.to_lower():
		if ACCENTS.has(ch):
			out += ACCENTS[ch]
		elif (ch >= "a" and ch <= "z") or ch == " ":
			out += ch
		elif ch == "-" or ch == "'":
			out += " " if ch == "-" else ""
	return " ".join(out.split(" ", false))


static func distance(a: String, b: String) -> int:
	if absi(a.length() - b.length()) > 3:
		return 99
	var prev: Array = range(b.length() + 1)
	for i in a.length():
		var cur: Array = [i + 1]
		for j in b.length():
			cur.append(mini(mini(int(cur[j]) + 1, int(prev[j + 1]) + 1), int(prev[j]) + (0 if a[i] == b[j] else 1)))
		prev = cur
	return int(prev[b.length()])


## True when `a` and `b` are at most ONE edit apart (substitution, insertion or deletion). Linear time:
## the look-alike search compares thousands of names, so it avoids the full edit-distance table.
static func within_one_edit(a: String, b: String) -> bool:
	var la := a.length()
	var lb := b.length()
	if absi(la - lb) > 1:
		return false
	var i := 0
	var j := 0
	var edits := 0
	while i < la and j < lb:
		if a[i] == b[j]:
			i += 1
			j += 1
			continue
		edits += 1
		if edits > 1:
			return false
		if la > lb:
			i += 1
		elif lb > la:
			j += 1
		else:
			i += 1
			j += 1
	return edits + (la - i) + (lb - j) <= 1


func size() -> int:
	return _exact.size()


func add(name: String) -> void:
	var n := normalize(name)
	if n == "" or _exact.has(n):
		return
	_exact[n] = name
	var key := n.substr(0, 1)
	if not _buckets.has(key):
		_buckets[key] = []
	(_buckets[key] as Array).append(n)


func check(name: String) -> String:
	var n := normalize(name)
	if n == "":
		return "empty name"
	if _exact.has(n):
		return "duplicate of '%s'" % _exact[n]
	for other: String in _buckets.get(n.substr(0, 1), []):
		if within_one_edit(n, other):
			return "too similar to '%s'" % _exact[other]
	return ""


## Every pair of names in `names` that is a duplicate or look-alike: [[a, b, reason], ...].
static func find_conflicts(names: Array) -> Array:
	var out: Array = []
	var idx := NameIndex.new()
	for n in names:
		var why := idx.check(str(n))
		if why != "":
			out.append([str(n), why])
		idx.add(str(n))
	return out
