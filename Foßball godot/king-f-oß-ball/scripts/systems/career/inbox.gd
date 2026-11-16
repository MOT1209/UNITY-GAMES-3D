class_name Inbox
extends RefCounted

## Career phase C9.1: the central message box. Every event that needs the manager's attention (or is worth knowing) is a
## message: {id, uid, season, week, category, key, args, sender, needs_decision, blocking, action, read, resolved, shown}.
## `uid` makes a message idempotent (the same offer / match / season end is added once). `action` = {screen, params} is the
## direct action button. A decision message is "resolved" automatically when its condition no longer holds (see CareerFlow.sync).
## Text is `Loc.f(key, args)`, so messages follow the language. Saved with the career.

const MAX_MESSAGES := 300
const CATEGORIES: Array[String] = ["board", "players", "transfers", "staff", "medical", "media", "competitions"]

var messages: Array = []                   # oldest first
var _next_id := 1
var _uids: Dictionary = {}                 # uid -> message id (only for messages still held)


func has_uid(uid: String) -> bool:
	return _uids.has(uid)


## Adds a message unless one with the same uid exists. Returns the message ({} when it was a duplicate).
func add(uid: String, season: int, week: int, category: String, key: String, args: Array = [], opts: Dictionary = {}) -> Dictionary:
	if uid != "" and _uids.has(uid):
		return {}
	var m := {"id": _next_id, "uid": uid, "season": season, "week": week, "category": category if CATEGORIES.has(category) else "board",
			"key": key, "args": args.duplicate(), "sender": str(opts.get("sender", "")), "needs_decision": bool(opts.get("needs_decision", false)),
			"blocking": bool(opts.get("blocking", false)), "action": (opts.get("action", {}) as Dictionary).duplicate(true),
			"read": false, "resolved": false, "shown": false}
	_next_id += 1
	messages.append(m)
	if uid != "":
		_uids[uid] = m["id"]
	while messages.size() > MAX_MESSAGES:
		_drop(0)
	return m


func _drop(index: int) -> void:
	var m: Dictionary = messages[index]
	if str(m["uid"]) != "":
		_uids.erase(m["uid"])
	messages.remove_at(index)


func get_message(id: int) -> Dictionary:
	for m in messages:
		if int(m["id"]) == id:
			return m
	return {}


func mark_read(id: int) -> void:
	var m := get_message(id)
	if not m.is_empty():
		m["read"] = true


func mark_all_read() -> void:
	for m in messages:
		m["read"] = true


func unread_count() -> int:
	var n := 0
	for m in messages:
		if not bool(m["read"]):
			n += 1
	return n


## Decision messages still waiting (newest first when `newest_first`).
func pending_decisions() -> Array:
	var out: Array = messages.filter(func(m: Dictionary) -> bool: return bool(m["needs_decision"]) and not bool(m["resolved"]))
	out.reverse()
	return out


func by_category(category: String) -> Array:
	var out: Array = messages.filter(func(m: Dictionary) -> bool: return category == "" or str(m["category"]) == category)
	out.reverse()
	return out


func resolve(id: int) -> void:
	var m := get_message(id)
	if not m.is_empty():
		m["resolved"] = true
		m["read"] = true


func to_dict() -> Dictionary:
	return {"messages": messages.duplicate(true), "next_id": _next_id}


static func from_dict(d: Dictionary) -> Inbox:
	var ib := Inbox.new()
	ib._next_id = int(d.get("next_id", 1))
	for raw in d.get("messages", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var m: Dictionary = PlayerData._restore_ints((raw as Dictionary).duplicate(true))
		for k in ["needs_decision", "blocking", "read", "resolved", "shown"]:
			m[k] = bool(m.get(k, false))
		ib.messages.append(m)
		if str(m.get("uid", "")) != "":
			ib._uids[str(m["uid"])] = int(m.get("id", 0))
		ib._next_id = maxi(ib._next_id, int(m.get("id", 0)) + 1)
	return ib
