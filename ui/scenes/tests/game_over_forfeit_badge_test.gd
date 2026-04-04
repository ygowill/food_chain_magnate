# GameOver：弃权导致终局时，结算面板应明确显示“弃权”
class_name GameOverForfeitBadgeTest
extends RefCounted

const GameOverPanelScene = preload("res://ui/components/game_over/game_over_panel.tscn")
const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")


static func run() -> Result:
	_clear_event_bus_history()
	if Globals != null:
		Globals.reset_game_config()

	var engine := GameEngine.new()
	var init_r := engine.initialize(2, 12345)
	if not init_r.ok:
		_clear_event_bus_history()
		return Result.failure("initialize 失败: %s" % init_r.error)
	var setup_r := TestPhaseUtilsClass.complete_setup(engine)
	if not setup_r.ok:
		_clear_event_bus_history()
		return Result.failure("complete_setup 失败: %s" % setup_r.error)

	var forfeit_r := engine.execute_command(Command.create("forfeit_player", 0, {}))
	if not forfeit_r.ok:
		_clear_event_bus_history()
		return Result.failure("forfeit_player 失败: %s" % forfeit_r.error)

	var state: GameState = engine.get_state()
	if state == null:
		_clear_event_bus_history()
		return Result.failure("forfeit 后 state 为空")
	if str(state.phase) != DefsClass.PHASE_GAME_OVER:
		_clear_event_bus_history()
		return Result.failure("应进入 GameOver，实际: %s" % str(state.phase))

	var tree_val = Engine.get_main_loop()
	var tree: SceneTree = tree_val if tree_val is SceneTree else null
	if tree == null or tree.root == null:
		_clear_event_bus_history()
		return Result.failure("SceneTree.root 不可用")

	var panel = GameOverPanelScene.instantiate()
	if panel == null or not is_instance_valid(panel):
		_clear_event_bus_history()
		return Result.failure("GameOverPanel 实例化失败")
	tree.root.add_child(panel)
	await tree.process_frame

	if panel.has_method("set_final_state"):
		panel.call("set_final_state", state)
	await tree.process_frame

	var found_forfeit_badge := false
	for text in _collect_label_texts(panel):
		if text == "弃权":
			found_forfeit_badge = true
			break
	if not found_forfeit_badge:
		_cleanup_panel(panel)
		_clear_event_bus_history()
		return Result.failure("GameOverPanel 未显示弃权标签")

	_cleanup_panel(panel)
	_clear_event_bus_history()
	if Globals != null:
		Globals.reset_game_config()
	return Result.success()


static func _collect_label_texts(root: Node) -> Array[String]:
	var texts: Array[String] = []
	if root == null or not is_instance_valid(root):
		return texts
	if root is Label:
		texts.append(str((root as Label).text))
	for child in root.get_children():
		if child is Node:
			texts.append_array(_collect_label_texts(child as Node))
	return texts


static func _cleanup_panel(panel: Node) -> void:
	if panel == null or not is_instance_valid(panel):
		return
	panel.queue_free()


static func _clear_event_bus_history() -> void:
	if EventBus == null:
		return
	if EventBus.has_method("clear_history_and_reset_sequence"):
		EventBus.clear_history_and_reset_sequence()
	elif EventBus.has_method("clear_history"):
		EventBus.clear_history()
