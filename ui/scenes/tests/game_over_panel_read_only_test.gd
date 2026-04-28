# GameOver：只读时间线（手动回放）下也应展示 GameOver 面板（避免终局软锁）
class_name GameOverPanelReadOnlyTest
extends RefCounted

const EndPanelsClass = preload("res://ui/scenes/game/panel/end_panels.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")

const SAVE_RES_PATH := "res://testdata/saves/manual_cases/logs/event_log_game_over_bankruptcy.json"


class DummyGameScene extends Control:
	var game_engine: GameEngine = null

	func is_timeline_read_only_active() -> bool:
		return true

	func is_replay_mode_active() -> bool:
		return false


static func run() -> Result:
	_clear_event_bus_history()

	var abs_path := ProjectSettings.globalize_path(SAVE_RES_PATH)
	var engine := GameEngine.new()
	var load := engine.load_from_file(abs_path)
	if not load.ok:
		_clear_event_bus_history()
		return Result.failure("load failed: %s" % load.error)

	var state: GameState = engine.get_state()
	if state == null:
		_clear_event_bus_history()
		return Result.failure("load succeeded but state is null")

	var actor_id := int(state.get_current_player_id())
	var skip_sub_r: Result = engine.execute_command(Command.create(ActionIdsClass.SKIP_SUB_PHASE, actor_id))
	if not skip_sub_r.ok:
		_clear_event_bus_history()
		return Result.failure("skip_sub_phase failed: %s" % skip_sub_r.error)

	state = engine.get_state()
	if state == null:
		_clear_event_bus_history()
		return Result.failure("state is null after skip_sub_phase")
	actor_id = int(state.get_current_player_id())

	var skip_r: Result = engine.execute_command(Command.create(ActionIdsClass.SKIP, actor_id))
	if not skip_r.ok:
		_clear_event_bus_history()
		return Result.failure("skip failed: %s" % skip_r.error)

	state = engine.get_state()
	if state == null:
		_clear_event_bus_history()
		return Result.failure("state is null after skip")
	if str(state.phase) != DefsClass.PHASE_GAME_OVER:
		_clear_event_bus_history()
		return Result.failure("expected phase=%s; got %s" % [DefsClass.PHASE_GAME_OVER, str(state.phase)])

	var tree_val = Engine.get_main_loop()
	var tree: SceneTree = tree_val if tree_val is SceneTree else null
	if tree == null or tree.root == null:
		_clear_event_bus_history()
		return Result.failure("SceneTree.root is not available")

	var scene := DummyGameScene.new()
	scene.game_engine = engine
	tree.root.add_child(scene)

	var end_panels = EndPanelsClass.new(scene, null, Callable(), Callable(), Callable(), Callable())
	end_panels.sync(state)

	if end_panels.game_over_panel == null or not is_instance_valid(end_panels.game_over_panel):
		scene.free()
		_clear_event_bus_history()
		return Result.failure("GameOverPanel not created when timeline is read-only")

	if not bool(end_panels.game_over_panel.visible):
		scene.free()
		_clear_event_bus_history()
		return Result.failure("GameOverPanel should be visible when phase=GameOver (even if timeline is read-only)")

	if not end_panels.game_over_panel.has_signal("closed_requested"):
		scene.free()
		_clear_event_bus_history()
		return Result.failure("GameOverPanel 缺少关闭信号")
	end_panels.game_over_panel.emit_signal("closed_requested")
	if bool(end_panels.game_over_panel.visible):
		scene.free()
		_clear_event_bus_history()
		return Result.failure("关闭结算面板后应隐藏 GameOverPanel")
	end_panels.sync(state)
	if bool(end_panels.game_over_panel.visible):
		scene.free()
		_clear_event_bus_history()
		return Result.failure("关闭结算面板后，同一 GameOver 状态不应被 sync 重新弹出")

	scene.free()
	_clear_event_bus_history()
	return Result.success()


static func _clear_event_bus_history() -> void:
	if EventBus == null:
		return
	if EventBus.has_method("clear_history_and_reset_sequence"):
		EventBus.clear_history_and_reset_sequence()
	elif EventBus.has_method("clear_history"):
		EventBus.clear_history()
