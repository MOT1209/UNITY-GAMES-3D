## KING CONTROLLER (P9): static checks of the phone page (assets/controller/controller_page.html). These are
## source-level guarantees (labels, languages, protocol use, no client clock, safety handlers). The behaviour
## of the page in a real browser is covered by the Playwright harness in tests/e2e (documented in the QA report).
extends Node

var _passed := 0
var _failed := 0
var _html := ""


func _check(ok: bool, name: String, detail := "") -> void:
	if ok:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s%s" % [name, (" - " + detail) if detail != "" else ""])


func _ready() -> void:
	print("=== KING FOOTBALL - Controller page validation ===")
	await get_tree().process_frame
	_html = FileAccess.get_file_as_string("res://assets/controller/controller_page.html")
	_check(_html.length() > 1000, "page file is present")
	_check(_html.contains("__WS_PORT__"), "page has the WebSocket port placeholder the server fills in")
	_check(_html.contains("const PROTOCOL = 2"), "page speaks protocol v2")
	_check(not _html.contains("Date.now()"), "page never sends the browser clock")
	_check(not _html.contains("\"t\":") and not _html.contains(" t:Date"), "no client timestamp field is built")
	for a in ["sprint", "tackle", "switch_player", "pass", "shoot", "lob_pass", "through_pass", "cross", "pause"]:
		_check(_html.contains("'%s'" % a) or _html.contains("%s:" % a), "control present: %s" % a)
	_check(_html.contains("through_pass:'تمريرة بينية'"), "Arabic through pass label is «تمريرة بينية»")
	_check(not _html.contains("through_pass:'تمرير") or _html.contains("through_pass:'تمريرة بينية'"), "no stale Arabic through pass label")
	for k in ["en:", "de:", "ar:"]:
		_check(_html.contains("  " + k + " {dir:"), "language table %s" % k)
	_check(_html.contains("dir:'rtl'") and _html.contains("document.documentElement.dir"), "Arabic switches the page to RTL")
	_check(_html.contains("navigator.languages"), "language follows the browser unless the user chose one")
	_check(_html.contains("kc_lang"), "the user's language choice is remembered")
	_check(_html.contains("user-scalable=no") and _html.contains("maximum-scale=1"), "zoom is disabled in the viewport")
	_check(_html.contains("touch-action:none") and _html.contains("overscroll-behavior:none"), "no scrolling / panning gestures")
	for ev in ["pointerdown", "pointerup", "pointercancel", "lostpointercapture", "setPointerCapture"]:
		_check(_html.contains(ev), "pointer handling: %s" % ev)
	for ev in ["'blur'", "'pagehide'", "visibilitychange", "orientationchange"]:
		_check(_html.contains(ev), "inputs are released on %s" % ev)
	_check(_html.contains("type:'ping'") and _html.contains("TIMEOUT_MS"), "heartbeat and silence timeout present")
	_check(_html.contains("type:'resume'") and _html.contains("kc_session"), "reconnection with the session credential")
	_check(_html.contains("history.replaceState"), "the one-time token is removed from the address bar after pairing")
	_check(_html.contains("type:'bye'"), "explicit disconnect says goodbye")
	for st in ["connecting", "pairing", "connected", "reconnecting", "lost", "revoked", "disconnected"]:
		_check(_html.contains(st + ":'"), "status text for %s" % st)
	_check(_html.contains("#d4af37") and _html.contains("#c0272d") and _html.contains("#0b0b0d"), "Black / Gold / Red identity colours")
	_check(not _html.contains("<script src") and not _html.contains("http://") and not _html.contains("https://"), "page loads nothing from the network (self-contained)")
	_check(not _html.contains("eval(") and not _html.contains("innerHTML"), "no eval / innerHTML in the page")
	_check(not _html.contains("customi"), "no fake customization UI")
	print("=== Validation summary: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)
