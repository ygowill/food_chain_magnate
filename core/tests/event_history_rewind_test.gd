# 回退后 EventBus.history 应同步回退（用于 UI 日志一致性）
class_name EventHistoryRewindTest
extends RefCounted

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	if EventBus != null:
		if EventBus.has_method("clear_history_and_reset_sequence"):
			EventBus.clear_history_and_reset_sequence()
		else:
			EventBus.clear_history()

	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	# 清掉 GAME_STARTED 等初始化事件，避免影响后续统计
	if EventBus != null:
		if EventBus.has_method("clear_history_and_reset_sequence"):
			EventBus.clear_history_and_reset_sequence()
		else:
			EventBus.clear_history()

	# 1) 执行两条 end_turn（会各自产生 player_turn_ended 事件）
	var p0 := engine.get_state().get_current_player_id()
	var r1 := engine.execute_command(Command.create("end_turn", p0))
	if not r1.ok:
		return Result.failure("end_turn(1) 失败: %s" % r1.error)

	var p1 := engine.get_state().get_current_player_id()
	var r2 := engine.execute_command(Command.create("end_turn", p1))
	if not r2.ok:
		return Result.failure("end_turn(2) 失败: %s" % r2.error)

	var ended_before := EventBus.get_history_by_type(EventBus.EventType.PLAYER_TURN_ENDED).size() if EventBus != null else -1
	if ended_before != 2:
		return Result.failure("回退前 player_turn_ended 数量错误: %d (期望 2)" % ended_before)

	# 2) 回退到第 0 条命令：EventBus.history 应只保留第 0 条命令产生的事件
	var rewind := engine.rewind_to_command(0)
	if not rewind.ok:
		return Result.failure("rewind_to_command(0) 失败: %s" % rewind.error)
	if int(engine.current_command_index) != 0:
		return Result.failure("current_command_index 错误: %d (期望 0)" % int(engine.current_command_index))

	var ended_after := EventBus.get_history_by_type(EventBus.EventType.PLAYER_TURN_ENDED).size() if EventBus != null else -1
	if ended_after != 1:
		return Result.failure("回退后 player_turn_ended 数量错误: %d (期望 1)" % ended_after)

	# 3) 重做回到第 1 条命令：事件数量应恢复
	var redo := engine.rewind_to_command(1)
	if not redo.ok:
		return Result.failure("rewind_to_command(1) 失败: %s" % redo.error)
	if int(engine.current_command_index) != 1:
		return Result.failure("current_command_index 错误: %d (期望 1)" % int(engine.current_command_index))

	var ended_redo := EventBus.get_history_by_type(EventBus.EventType.PLAYER_TURN_ENDED).size() if EventBus != null else -1
	if ended_redo != 2:
		return Result.failure("重做后 player_turn_ended 数量错误: %d (期望 2)" % ended_redo)

	return Result.success({
		"player_turn_ended_before": ended_before,
		"player_turn_ended_after": ended_after,
		"player_turn_ended_redo": ended_redo,
	})

