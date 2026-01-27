# 回放完整日志：未来日志可见性测试（无需渲染）
# - 构建完整时间线日志后，cursor 回退不应改变日志总条目数（仍包含未来）
# - 可区分 future/past（通过 command_index 与 cursor 比较）
class_name ReplayLogFutureVisibilityTest
extends RefCounted

const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")
const EventTimelineBuildClass = preload("res://gameplay/replay/event_timeline_build.gd")
const GameEventLogFormatterClass = preload("res://ui/scenes/game/game_event_log_formatter.gd")
const GameLogPanelClass = preload("res://ui/components/game_log/game_log_panel.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")

static func run(player_count: int = 2, seed_val: int = 12345, min_commands: int = 12) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var setup := TestPhaseUtilsClass.complete_setup(engine)
	if not setup.ok:
		return Result.failure("complete_setup 失败: %s" % setup.error)

	var safety := 0
	while engine.command_history.size() < min_commands:
		safety += 1
		if safety > min_commands * 3:
			return Result.failure("生成命令超出安全上限: %d" % safety)
		var pid := engine.get_state().get_current_player_id()
		var r := engine.execute_command(Command.create(ActionIdsClass.END_TURN, pid))
		if not r.ok:
			return Result.failure("end_turn 失败: %s" % r.error)

	var head_index := engine.command_history.size() - 1
	if head_index < 1:
		return Result.failure("命令数量不足: %d" % engine.command_history.size())

	var build_r: Result = EventTimelineBuildClass.build_full(engine)
	if not build_r.ok:
		return Result.failure("build_full 失败: %s" % build_r.error)

	var events_val = build_r.value
	if not (events_val is Array):
		return Result.failure("build_full.value 类型错误（期望 Array）")
	var events: Array = events_val
	if events.is_empty():
		return Result.failure("build_full 事件为空")

	var panel = GameLogPanelClass.new()
	if panel == null or not is_instance_valid(panel):
		return Result.failure("无法创建 GameLogPanel")

	var formatter = GameEventLogFormatterClass.new()
	if formatter == null or not is_instance_valid(formatter):
		_safe_free(panel)
		return Result.failure("无法创建 GameEventLogFormatter")

	# 构建完整日志（一次性）；随后仅移动 cursor，不重建日志。
	for ev_val in events:
		if not (ev_val is Dictionary):
			continue
		var ev: Dictionary = ev_val
		var cmd_index := int(ev.get("command_index", -999999))
		var entries: Array = formatter.format(ev)
		for e_val in entries:
			if not (e_val is Dictionary):
				continue
			var e: Dictionary = e_val
			var log_type := int(e.get("type", GameLogPanel.LogType.DEBUG))
			var msg := str(e.get("message", ""))
			var details_val = e.get("details", {})
			var details: Dictionary = details_val if (details_val is Dictionary) else {}
			var entry_id := panel.add_log(log_type, msg, details)
			panel.set_entry_command_index(entry_id, cmd_index)

	var total := panel.get_entries().size()
	if total <= 0:
		_safe_free(panel)
		return Result.failure("日志条目为空")

	panel.set_timeline_head(head_index)

	var cursor_index := maxi(0, head_index - 3)
	panel.set_timeline_cursor(cursor_index)

	var total_after := panel.get_entries().size()
	if total_after != total:
		_safe_free(panel)
		return Result.failure("移动 cursor 后日志总条目数不应变化: before=%d after=%d" % [total, total_after])

	var future := 0
	var past := 0
	for entry in panel.get_entries():
		var ci := int(entry.get("command_index", -999999))
		if ci > cursor_index:
			future += 1
		elif ci >= -1:
			past += 1

	_safe_free(panel)
	if future <= 0:
		return Result.failure("cursor=%d head=%d 时应存在未来日志，但 future=0" % [cursor_index, head_index])
	if past <= 0:
		return Result.failure("past 日志数量异常: %d" % past)

	return Result.success({
		"entries": total,
		"future": future,
		"past": past,
		"cursor": cursor_index,
		"head": head_index,
	})

static func _safe_free(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.free()
