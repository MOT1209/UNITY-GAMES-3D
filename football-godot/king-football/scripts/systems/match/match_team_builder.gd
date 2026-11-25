class_name MatchTeamBuilder
extends RefCounted

## Builds one side of a match (UX phase 5.4, split out of `MatchManager`): spawns the eleven bodies from
## the squad (the real goalkeeper scene in slot 0), applies attributes, dresses them in the real kit /
## number / look / armband, registers the entries and wires their kicks into the match statistics.


static func spawn_team(m: MatchManager, side: String) -> void:
	var data: Dictionary = m.sides[side]
	var squad: Squad = data["squad"]
	var packed: PackedScene = load(MatchManager.PLAYER_SCENE)
	var keeper_packed: PackedScene = load(MatchManager.KEEPER_SCENE)
	var team: TeamData = m.db.get_team(data["team_id"])
	# Real kit data: the selected kit slot for the outfield, the goalkeeper slot for the keeper.
	var kit := TeamKit.for_team(m.db, team, data["kit"])
	var gk_kit := TeamKit.for_team(m.db, team, "goalkeeper", Color(0.1, 0.75, 0.3))
	for slot in 11:
		var pid: String = squad.starting[slot]
		var pdata: PlayerData = m.db.get_player(pid)
		var mods := AttributeModifiers.new(pdata)
		var node: CharacterBody3D
		var actions: FootballActions = null
		var ai: AIIntent = null
		if slot == 0:
			# The single goalkeeper implementation: positioning, reading shots,
			# diving, catching and throwing (TeamGoalkeeper); no PlayerAI branch.
			var gk := keeper_packed.instantiate() as TeamGoalkeeper
			gk.attribute_modifiers = mods
			node = gk
		else:
			var outfield := packed.instantiate() as PlayerController
			ai = AIIntent.new()
			outfield.intent = ai
			actions = outfield.get_node("BallActions") as FootballActions
			actions.intent = ai
			outfield.attribute_modifiers = mods
			actions.attribute_modifiers = mods
			node = outfield
		node.name = "%s_%02d_%s" % [side, slot, pid]
		m.add_child(node)
		dress(m, node, pdata, gk_kit if slot == 0 else kit, slot)
		var entry := {"node": node, "actions": actions, "ai": ai, "player_id": pid,
				"pdata": pdata, "slot": slot, "side": side, "mods": mods, "cmd": {},
				"kit": gk_kit if slot == 0 else kit,
				"think": m._rng.randf() * 0.2, "release_at": -1.0, "charging": &""}
		m.entries[side].append(entry)
		if actions != null and m.advanced != null:
			m.advanced.wire(entry)                   # Phase 2: opponents / goals for the advanced mechanics
		_wire_stats(m, node, actions, side, slot)
	m._place_team(side, true)


## Connects the real gameplay signals to the match's single event pipeline (`MatchState`).
## The player id is read from the entry at signal time, so a substitute is credited correctly.
static func _wire_stats(m: MatchManager, node: Node, actions: FootballActions, side: String, slot: int) -> void:
	if actions != null:
		actions.pass_started.connect(func(_p: float) -> void:
			m.state.record_pass(side, entry_id(m, side, slot))
			m.rules.restarts.on_pass(side, entry_id(m, side, slot))
			m.note_human_pass(side, slot, actions.last_pass_target))
		actions.lob_started.connect(func(_p: float, _l: float) -> void:
			m.state.record_pass(side, entry_id(m, side, slot))
			m.rules.restarts.on_pass(side, entry_id(m, side, slot)))
		# Nov 2026 (P0 fix): the human's through ball and cross are passes too. They were never connected, so they were
		# missing from the pass statistics and could never be offside (a through ball is the classic offside pass).
		actions.through_started.connect(func(_p: float) -> void:
			m.state.record_pass(side, entry_id(m, side, slot))
			m.rules.restarts.on_pass(side, entry_id(m, side, slot)))
		actions.cross_started.connect(func(_p: float, _l: float) -> void:
			m.state.record_pass(side, entry_id(m, side, slot))
			m.rules.restarts.on_pass(side, entry_id(m, side, slot)))
		actions.shot_started.connect(func(_p: float, _l: float) -> void: m.state.record_shot(side, entry_id(m, side, slot)))
	if node is TeamGoalkeeper:
		(node as TeamGoalkeeper).ball_caught.connect(func() -> void: m.state.record_keeper_hold(side, entry_id(m, side, slot)))


## The captain of the side that fields `player_id` ("" if the player is on neither side).
static func captain_id(m: MatchManager, player_id: String) -> String:
	for side in m.sides:
		var squad: Squad = m.sides[side]["squad"]
		if player_id in squad.starting:
			return squad.captain_id
	return ""


static func entry_id(m: MatchManager, side: String, slot: int) -> String:
	for e in m.entries[side]:
		if e["slot"] == slot:
			return e["player_id"]
	return ""


## Applies kit colours, shirt number and individual look to a spawned player.
static func dress(m: MatchManager, node: Node, pdata: PlayerData, kit: TeamKit, slot: int) -> void:
	var visual: PlayerCharacterVisual
	if node is TeamGoalkeeper:
		visual = (node as TeamGoalkeeper).visual
	else:
		visual = node.get_node_or_null("VisualRoot") as PlayerCharacterVisual
	if visual == null:
		return
	visual.kit = kit
	visual.number = pdata.shirt_number if pdata.shirt_number > 0 else slot + 1
	visual.back_name = pdata.last_name if pdata.last_name != "" else str(PlayerData.split_name(pdata.display_name)[1])
	visual.look = PlayerAppearance.look_for(pdata)     # stored identity, same as card / portrait
	visual.apply_kit()
	visual.apply_number()
	visual.apply_look()
	visual.set_captain(pdata.id == captain_id(m, pdata.id))
