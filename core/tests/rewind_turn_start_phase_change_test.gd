# Rewind turn-start phase-change test
# 目的：当“阶段变化但当前玩家不变”（例如 OrderOfBusiness 自动进入 Working）时，
# find_current_player_turn_start_command_index 仍应返回当前阶段的回合起点，而不是更早阶段/玩家切换点。
class_name RewindTurnStartPhaseChangeTest
extends RefCounted

const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")

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

	var to_oob := TestPhaseUtilsClass.advance_until_phase(engine, DefsClass.PHASE_ORDER_OF_BUSINESS, 400)
	if not to_oob.ok:
		return to_oob

	var state := engine.get_state()
	if str(state.phase) != DefsClass.PHASE_ORDER_OF_BUSINESS:
		return Result.failure("未进入 OrderOfBusiness（当前=%s）" % str(state.phase))

	# 构造：最后选择顺序的玩家成为 Working 起始玩家（玩家不变，但阶段变化）。
	# 2P：P0 先选 position=1，P1 后选 position=0 -> turn_order=[P1,P0]，进入 Working 后当前玩家仍为 P1。
	var pid_a := int(state.get_current_player_id())
	var pick_a := engine.execute_command(Command.create("choose_turn_order", pid_a, {"position": 1}))
	if not pick_a.ok:
		return Result.failure("choose_turn_order(P%d) 失败: %s" % [pid_a + 1, pick_a.error])

	var pid_b := int(engine.get_state().get_current_player_id())
	if pid_b == pid_a:
		return Result.failure("choose_turn_order 未切换当前玩家（pid=%d）" % pid_a)

	var pick_b := engine.execute_command(Command.create("choose_turn_order", pid_b, {"position": 0}))
	if not pick_b.ok:
		return Result.failure("choose_turn_order(P%d) 失败: %s" % [pid_b + 1, pick_b.error])

	state = engine.get_state()
	if str(state.phase) != DefsClass.PHASE_WORKING:
		return Result.failure("choose_turn_order 最后一手应自动进入 Working（当前=%s）" % str(state.phase))
	if int(state.get_current_player_id()) != pid_b:
		return Result.failure("Working 起始玩家不符合前置条件（期望=%d 实际=%d）" % [pid_b, int(state.get_current_player_id())])
	if str(state.sub_phase).is_empty():
		return Result.failure("Working 子阶段为空")

	# 执行一个不会切换玩家的 Working 命令（skip_sub_phase 非最后子阶段会留在当前玩家）。
	var skip_sub := engine.execute_command(Command.create(ActionIdsClass.SKIP_SUB_PHASE, pid_b))
	if not skip_sub.ok:
		return Result.failure("skip_sub_phase 失败: %s" % skip_sub.error)
	if str(engine.get_state().phase) != DefsClass.PHASE_WORKING:
		return Result.failure("skip_sub_phase 后不应离开 Working（当前=%s）" % str(engine.get_state().phase))
	if int(engine.get_state().get_current_player_id()) != pid_b:
		return Result.failure("skip_sub_phase 后不应切换当前玩家（期望=%d 实际=%d）" % [pid_b, int(engine.get_state().get_current_player_id())])

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
