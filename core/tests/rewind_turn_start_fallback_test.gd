# Rewind turn-start fallback test
# 目的：当 EventBus.history 缺失/被清空时，仍能正确定位“当前玩家回合开始”的命令索引。
class_name RewindTurnStartFallbackTest
extends RefCounted

const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")

static func run(player_count: int = 2, seed: int = 12345) -> Result:
	if EventBus == null:
		return Result.failure("EventBus is not available")
	if player_count < 2:
		return Result.failure("该测试需要至少 2 位玩家")

	_clear_event_history()

	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var to_working := TestPhaseUtilsClass.advance_until_phase(engine, "Working", 200)
	if not to_working.ok:
		return to_working

	var state := engine.get_state()
	if str(state.phase) != "Working":
		return Result.failure("未进入 Working（当前=%s）" % str(state.phase))
	if str(state.sub_phase).is_empty():
		return Result.failure("Working 子阶段为空")

	# 确保当前不在最后子阶段，避免 skip_sub_phase 导致回合切换。
	var order := engine.phase_manager.get_working_sub_phase_order_names() if engine.phase_manager != null else []
	if order is Array and not order.is_empty():
		var last_sub := str(order[order.size() - 1])
		if str(state.sub_phase) == last_sub:
			return Result.failure("当前处于最后子阶段（%s），测试前置条件不满足" % last_sub)

	var pid_a := int(state.get_current_player_id())
	var end_turn := engine.execute_command(Command.create("end_turn", pid_a))
	if not end_turn.ok:
		return Result.failure("end_turn 失败: %s" % end_turn.error)

	var pid_b := int(engine.get_state().get_current_player_id())
	if pid_b == pid_a:
		return Result.failure("end_turn 未切换当前玩家（pid=%d）" % pid_a)

	var skip_sub := engine.execute_command(Command.create("skip_sub_phase", pid_b))
	if not skip_sub.ok:
		return Result.failure("skip_sub_phase 失败: %s" % skip_sub.error)
	if int(engine.get_state().get_current_player_id()) != pid_b:
		return Result.failure("skip_sub_phase 后当前玩家发生变化（期望=%d 实际=%d）" % [pid_b, int(engine.get_state().get_current_player_id())])

	var expected_turn_start := int(engine.current_command_index) - 1
	if expected_turn_start < -1:
		return Result.failure("expected_turn_start 计算错误: %d" % expected_turn_start)

	# 清空 EventBus.history，强制走引擎回放推导分支。
	_clear_event_history()

	var idx_r: Result = engine.find_current_player_turn_start_command_index()
	if not idx_r.ok:
		return Result.failure("find_current_player_turn_start_command_index 失败: %s" % idx_r.error)
	var got := int(idx_r.value)
	if got != expected_turn_start:
		return Result.failure("turn_start_index=%d（期望=%d）" % [got, expected_turn_start])

	return Result.success({})

static func _clear_event_history() -> void:
	if EventBus == null:
		return
	if EventBus.has_method("clear_history_and_reset_sequence"):
		EventBus.clear_history_and_reset_sequence()
	elif EventBus.has_method("clear_history"):
		EventBus.clear_history()
