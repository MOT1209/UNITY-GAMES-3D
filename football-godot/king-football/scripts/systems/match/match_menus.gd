class_name MatchMenus
extends RefCounted

## The match's overlays (UX phase 5.4, split out of `MatchManager`): the pause menu and the results
## screen, each on its own CanvasLayer. The manager keeps the match state and the decisions (pause the
## tree, restart, quit, save); this class only builds, wires and removes the views.

const PAUSE_LAYER := 30
const RESULTS_LAYER := 20


## Opens the pause menu over `m` (layer kept running while the tree is paused). Returns the menu.
static func open_pause(m: MatchManager) -> PauseMenu:
	var layer := CanvasLayer.new()
	layer.name = "PauseLayer"
	layer.layer = PAUSE_LAYER
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	m.add_child(layer)
	var menu := PauseMenu.create(m)
	menu.resume_requested.connect(m.resume_match)
	menu.sim_rest_requested.connect(m.simulate_rest)
	menu.restart_requested.connect(m.restart_match)
	menu.quit_requested.connect(m.quit_match)
	menu.save_requested.connect(func() -> void: show_save_note(menu, m.save_match()))
	layer.add_child(menu)
	return menu


## Removes an open pause menu (and its layer).
static func close_pause(menu: PauseMenu) -> void:
	if menu != null and is_instance_valid(menu):
		menu.get_parent().queue_free()


## Result of "save match" under the pause menu's buttons ("" = saved).
static func show_save_note(menu: PauseMenu, err: String) -> void:
	if menu == null or not is_instance_valid(menu):
		return
	var note := UIKit.label(Loc.t("PAUSE_SAVED") if err == "" else err, 14, UIKit.GOOD if err == "" else UIKit.BAD)
	note.name = "SaveNote"
	(menu._main as Control).add_child(note)


## Shows the results screen of the finished match over `m`. Returns the view.
static func show_results(m: MatchManager, report: Dictionary, db: Node) -> MatchResultsView:
	var layer := CanvasLayer.new()
	layer.name = "ResultsLayer"
	layer.layer = RESULTS_LAYER
	m.add_child(layer)
	var view := MatchResultsView.create(report, db)
	view.continue_pressed.connect(m._on_results_continue)
	layer.add_child(view)
	return view
