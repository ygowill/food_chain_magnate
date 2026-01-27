# 存档载入后日志恢复回归测试（无需渲染）
# 覆盖 issue_tracker：存档加载阶段 EventBus 已发射事件，但 UI 日志面板应能从 EventBus.history 恢复历史日志。
class_name LogRestoreAfterLoadTest
extends RefCounted

const GameEventLogControllerClass = preload("res://ui/scenes/game/game_event_log_controller.gd")
const GameLogPanelClass = preload("res://ui/components/game_log/game_log_panel.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func run() -> Result:
	if EventBus != null:
		EventBus.clear_history()

	# 模拟存档加载的“回放阶段”：EventBus 已经发射了事件，但日志面板尚未 setup()
	EventBus.emit_event(EventBus.EventType.COMMAND_EXECUTED, {"action_id": "noop"})
	EventBus.emit_event(EventBus.EventType.PHASE_CHANGED, {
		"old_phase": DefsClass.PHASE_SETUP,
		"new_phase": DefsClass.PHASE_RESTRUCTURING,
		"round": 1,
	})
	EventBus.emit_event(EventBus.EventType.EMPLOYEE_RECRUITED, {
		"player_id": 0,
		"employee_type": "ceo",
	})

	var panel = GameLogPanelClass.new()
	if panel == null or not is_instance_valid(panel):
		return Result.failure("无法创建 GameLogPanel")

	var controller = GameEventLogControllerClass.new()
	if controller == null or not is_instance_valid(controller):
		panel.free()
		return Result.failure("无法创建 GameEventLogController")

	controller.setup(panel, true)

	var entries: Array[Dictionary] = panel.get_entries()
	if entries.size() < 3:
		_safe_free(panel)
		return Result.failure("日志条目数不足: %d (期望 >= 3: system + 2 restored)" % entries.size())

	var has_restore_summary := false
	var has_phase := false
	var has_recruit := false
	for e in entries:
		var msg := str(e.get("message", ""))
		if msg.contains("已恢复 2 条历史日志"):
			has_restore_summary = true
		if msg.contains("Setup -> Restructuring"):
			has_phase = true
		if msg.contains("玩家1:") and msg.contains("招聘") and (msg.contains("ceo") or msg.contains("CEO")):
			has_recruit = true
		if msg.contains("command_executed"):
			_safe_free(panel)
			return Result.failure("不应恢复/显示 command_executed（应被过滤），但发现: %s" % msg)

	_safe_free(panel)
	if not has_restore_summary:
		return Result.failure("缺少日志恢复汇总条目（应包含：已恢复 2 条历史日志）")
	if not has_phase:
		return Result.failure("缺少阶段切换日志（phase_changed）")
	if not has_recruit:
		return Result.failure("缺少招聘日志（employee_recruited）")

	return Result.success({
		"entries": entries.size(),
	})

static func _safe_free(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.free()
