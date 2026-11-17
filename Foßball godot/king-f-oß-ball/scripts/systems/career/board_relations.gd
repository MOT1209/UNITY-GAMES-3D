class_name BoardRelations
extends RefCounted

## Career phases C2.3 / C2.4: board meetings (requests with a reasoned answer) and promises to the board. Saved with the career.
##   meetings: a request can be made once every MEETING_COOLDOWN weeks; the answer depends on confidence, the club's vision and the
##   finances; two refusals in a row cost a little confidence.
##   promises: at most MAX_PROMISES open at once; kept = confidence and reputation up, broken = down (and can cost the job).

const MEETING_COOLDOWN := 8
const MAX_PROMISES := 2
const REQUESTS := {
	"transfer_budget": {"need": 55, "grant": 0.10},
	"wage_budget": {"need": 60, "grant": 0.08},
}
const PROMISE_KINDS: Array[String] = ["promotion", "youth_players", "profit", "top_half"]

var last_meeting_abs_week := -1000
var refusals_in_a_row := 0
var promises: Array = []            # {kind, target, start, season, status: "open"|"kept"|"broken"}


func can_meet(career: CareerState) -> bool:
	return career.absolute_week() - last_meeting_abs_week >= MEETING_COOLDOWN


## A request to the board. Returns {accepted, reason (translation key), amount}. Applies the grant to the club's ledger.
func request(career: CareerState, kind: String, vision: String) -> Dictionary:
	if not REQUESTS.has(kind):
		return {"accepted": false, "reason": "BOARD_REASON_UNKNOWN", "amount": 0}
	if not can_meet(career):
		return {"accepted": false, "reason": "BOARD_REASON_TOO_SOON", "amount": 0}
	last_meeting_abs_week = career.absolute_week()
	var need := int(REQUESTS[kind]["need"])
	if vision == "profit":
		need += 10                                         # a profit-minded board is harder to talk into spending
	elif vision == "titles" or vision == "promotion":
		need -= 5
	var ledger := career.ledger()
	var reason := ""
	if career.manager.confidence < need:
		reason = "BOARD_REASON_CONFIDENCE"
	elif ledger.balance < 0:
		reason = "BOARD_REASON_FINANCES"
	if reason != "":
		refusals_in_a_row += 1
		if refusals_in_a_row >= 2:
			career.manager.apply_result(-1, 0)
		return {"accepted": false, "reason": reason, "amount": 0}
	refusals_in_a_row = 0
	var amount := 0
	if kind == "transfer_budget":
		amount = int(float(maxi(ledger.transfer_budget, 100000)) * float(REQUESTS[kind]["grant"]))
		ledger.transfer_budget += amount
	else:
		amount = int(float(maxi(ledger.wage_budget, 10000)) * float(REQUESTS[kind]["grant"]))
		ledger.wage_budget += amount
	return {"accepted": true, "reason": "BOARD_REASON_GRANTED", "amount": amount}


## Makes a promise. Returns "" or an error key.
func promise(career: CareerState, kind: String, target: int) -> String:
	if not PROMISE_KINDS.has(kind):
		return "BOARD_PROMISE_UNKNOWN"
	if promises.filter(func(p: Dictionary) -> bool: return p["status"] == "open").size() >= MAX_PROMISES:
		return "BOARD_PROMISE_TOO_MANY"
	if promises.any(func(p: Dictionary) -> bool: return p["status"] == "open" and p["kind"] == kind):
		return "BOARD_PROMISE_DUPLICATE"
	promises.append({"kind": kind, "target": target, "start": career.ledger().balance, "season": career.season, "status": "open"})
	return ""


func open_promises() -> Array:
	return promises.filter(func(p: Dictionary) -> bool: return p["status"] == "open")


## Settles this season's open promises at the end of the season. `rank` = final league position, `promoted` = went up this season.
## Returns [{kind, status}] and applies +confidence/+reputation for kept, -confidence/-reputation for broken promises.
func settle(career: CareerState, rank: int, promoted: bool) -> Array:
	var out: Array = []
	for p in promises:
		if p["status"] != "open" or int(p["season"]) != career.season:
			continue
		var kept := false
		match str(p["kind"]):
			"promotion":
				kept = promoted
			"top_half":
				var size := int(career.manager.objective.get("division_size", 0))
				kept = rank > 0 and size > 0 and rank <= int(ceil(size / 2.0))
			"profit":
				kept = career.ledger().balance >= int(p["start"]) + int(p["target"])
			"youth_players":
				var n := 0
				for pl: PlayerData in career.db.get_squad(career.club_id):
					if pl.age <= 21 and int(career.stats_for(pl.id, career.season)["apps"]) >= 6:
						n += 1
				kept = n >= int(p["target"])
		p["status"] = "kept" if kept else "broken"
		career.manager.apply_result(6 if kept else -12, 2 if kept else -3)
		out.append({"kind": p["kind"], "status": p["status"]})
	return out


func to_dict() -> Dictionary:
	return {"last_meeting": last_meeting_abs_week, "refusals": refusals_in_a_row, "promises": promises.duplicate(true)}


static func from_dict(d: Dictionary) -> BoardRelations:
	var b := BoardRelations.new()
	b.last_meeting_abs_week = int(d.get("last_meeting", -1000))
	b.refusals_in_a_row = int(d.get("refusals", 0))
	for raw in d.get("promises", []):
		if typeof(raw) == TYPE_DICTIONARY and PROMISE_KINDS.has(str(raw.get("kind", ""))):
			b.promises.append({"kind": str(raw["kind"]), "target": int(raw.get("target", 0)), "start": int(raw.get("start", 0)),
					"season": int(raw.get("season", 1)), "status": str(raw.get("status", "open")) if str(raw.get("status", "open")) in ["open", "kept", "broken"] else "open"})
	return b
