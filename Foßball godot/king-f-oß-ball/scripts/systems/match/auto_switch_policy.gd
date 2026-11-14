class_name AutoSwitchPolicy
extends RefCounted

## Decides when the human's controlled player changes on its own (pure logic, no nodes):
##  * a team-mate of the human gains the ball (the pass receiver, a won loose ball) -> he becomes
##    the selected player ("auto" and "semi"),
##  * the human side loses the ball to the opponent -> the outfield player closest to the ball
##    is selected ("auto" only),
##  * never more often than every COOLDOWN seconds, never while the selected player charges a kick,
##  * "manual": only the switch button changes the player.

const COOLDOWN := 0.4

var mode: String = "auto"
var human_side: String = "home"
var _last_owner_side: String = ""
var _last_switch_at: float = -INF


func _init(p_mode: String = "auto", p_human_side: String = "home") -> void:
	mode = p_mode if p_mode in GameSettings.SWITCH_MODES else "auto"
	human_side = p_human_side


## Records a manual switch (Tab) so an automatic one cannot follow straight away.
func note_switch(now: float) -> void:
	_last_switch_at = now


## Called whenever a player controls the ball. `owner` = that entry ({side, slot, player_id, ...});
## `selected_id` = the human's current player; `charging` = he is charging a kick.
## Returns "receiver" (select the owner), "closest" (select the closest to the ball) or "".
func on_owner(owner: Dictionary, selected_id: String, charging: bool, now: float) -> String:
	var side := str(owner.get("side", ""))
	var previous := _last_owner_side
	_last_owner_side = side
	if mode == "manual" or human_side == "none" or side == "":
		return ""
	if charging or now - _last_switch_at < COOLDOWN:
		return ""
	if side == human_side:
		if str(owner.get("player_id", "")) != selected_id and int(owner.get("slot", 0)) != 0:
			_last_switch_at = now
			return "receiver"
		return ""
	if mode == "auto" and previous == human_side:
		_last_switch_at = now
		return "closest"
	return ""
