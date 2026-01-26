# Rewind turn-start reenter test
# 目的：当同一阶段内“当前玩家”发生临时切换后又切回时，
# find_current_player_turn_start_command_index 仍应回到该玩家在该阶段内的首次动作之前，
# 以保证“一键回退当前玩家回合”能够撤销其在本阶段内的全部操作。
class_name RewindTurnStartReenterTest
extends RefCounted

const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")

static func run(player_count: int = 2, seed: int = 12345) -> Result:
	if EventBus == null:
		return Result.failure("EventBus is not available")
	if player_count != 2:
		return Result.failure("该测试固定为 2 位玩家（当前=%d）" % player_count)

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

	# 使用 end_turn（内部动作）制造“同一阶段内临时切换当前玩家后又切回”的场景。
	var pid_a := int(state.get_current_player_id())
	if pid_a < 0:
		return Result.failure("当前玩家无效")

	var end_a := engine.execute_command(Command.create("end_turn", pid_a))
	if not end_a.ok:
		return Result.failure("end_turn(P%d) 失败: %s" % [pid_a + 1, end_a.error])
	var pid_a_first_cmd_index := int(engine.current_command_index)

	var pid_b := int(engine.get_state().get_current_player_id())
	if pid_b == pid_a:
		return Result.failure("end_turn 未切换当前玩家（pid=%d）" % pid_a)

	var end_b := engine.execute_command(Command.create("end_turn", pid_b))
	if not end_b.ok:
		return Result.failure("end_turn(P%d) 失败: %s" % [pid_b + 1, end_b.error])

	state = engine.get_state()
	if int(state.get_current_player_id()) != pid_a:
		return Result.failure("end_turn(P%d) 后应切回玩家 %d（实际=%d）" % [pid_b + 1, pid_a, int(state.get_current_player_id())])

	var expected_turn_start := pid_a_first_cmd_index - 1
	if expected_turn_start < -1:
		return Result.failure("expected_turn_start 计算错误: %d" % expected_turn_start)

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

