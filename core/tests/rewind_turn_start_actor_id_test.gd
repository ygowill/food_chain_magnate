# Rewind turn-start explicit actor test
# 目的：联机同时阶段中，服务器必须按“发起请求的玩家”定位回合起点，而不是使用 state.current_player_index。
class_name RewindTurnStartActorIdTest
extends RefCounted

const StateUpdaterClass = preload("res://core/state/state_updater.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")

static func run(player_count: int = 2, seed: int = 12345) -> Result:
	if player_count != 2:
		return Result.failure("该测试固定为 2 位玩家（当前=%d）" % player_count)

	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var prep := _enter_round_two_restructuring(engine)
	if not prep.ok:
		return prep

	var p0_submit := engine.execute_command(Command.create("submit_restructuring", 0, {}))
	if not p0_submit.ok:
		return Result.failure("P1 提交重组失败: %s" % p0_submit.error)
	var p0_submit_index := int(engine.current_command_index)

	var state := engine.get_state()
	var take := StateUpdaterClass.take_from_pool(state, "local_manager", 1)
	if not take.ok:
		return Result.failure("取出 local_manager 失败: %s" % take.error)
	var add := StateUpdaterClass.add_employee(state, 1, "local_manager", true)
	if not add.ok:
		return Result.failure("给 P2 添加 local_manager 失败: %s" % add.error)

	var p1_direct := engine.execute_command(Command.create("set_company_structure_direct", 1, {
		"slot_index": 0,
		"employee_id": "local_manager",
	}))
	if not p1_direct.ok:
		return Result.failure("P2 调整公司结构失败: %s" % p1_direct.error)
	var p1_direct_index := int(engine.current_command_index)

	state = engine.get_state()
	state.current_player_index = maxi(0, Array(state.turn_order).find(0))
	if str(state.phase) != DefsClass.PHASE_RESTRUCTURING:
		return Result.failure("测试应停留在 Restructuring，实际: %s" % str(state.phase))
	if int(state.get_current_player_id()) != 0:
		return Result.failure("测试前置应保持 current_player=P1，实际: %d" % int(state.get_current_player_id()))

	var p1_idx_r: Result = engine.find_current_player_turn_start_command_index(1)
	if not p1_idx_r.ok:
		return Result.failure("查询 P2 回合起点失败: %s" % p1_idx_r.error)
	var expected_p1 := p1_direct_index - 1
	if int(p1_idx_r.value) != expected_p1:
		return Result.failure("P2 turn_start 错误：got=%d want=%d" % [int(p1_idx_r.value), expected_p1])
	if int(p1_idx_r.value) <= p0_submit_index - 1:
		return Result.failure("P2 turn_start 不应退到 P1 提交之前: got=%d p0_submit=%d" % [int(p1_idx_r.value), p0_submit_index])

	var p0_idx_r: Result = engine.find_current_player_turn_start_command_index(0)
	if not p0_idx_r.ok:
		return Result.failure("查询 P1 回合起点失败: %s" % p0_idx_r.error)
	var expected_p0 := p0_submit_index - 1
	if int(p0_idx_r.value) != expected_p0:
		return Result.failure("P1 turn_start 错误：got=%d want=%d" % [int(p0_idx_r.value), expected_p0])

	return Result.success()

static func _enter_round_two_restructuring(engine: GameEngine) -> Result:
	if engine == null:
		return Result.failure("engine 为空")
	var state := engine.get_state()
	if state == null:
		return Result.failure("state 为空")
	state.round_number = 1
	var adv := engine.execute_command(Command.create_system(ActionIdsClass.ADVANCE_PHASE))
	if not adv.ok:
		return Result.failure("推进到 Restructuring 失败: %s" % adv.error)
	state = engine.get_state()
	if str(state.phase) != DefsClass.PHASE_RESTRUCTURING:
		return Result.failure("应进入 Restructuring，实际: %s" % str(state.phase))
	if int(state.round_number) != 2:
		return Result.failure("应进入第 2 回合，实际: %d" % int(state.round_number))
	return Result.success()
