# PhaseManager：子阶段推进逻辑（抽离自 advancement.gd）
extends RefCounted

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const WorkingFlowClass = preload("res://core/engine/phase_manager/working_flow.gd")

enum HookType {
	BEFORE_ENTER,
	AFTER_ENTER,
	BEFORE_EXIT,
	AFTER_EXIT
}

# 推进子阶段（Working 或模块注入的 Cleanup 子阶段）
static func advance_sub_phase(pm, state: GameState) -> Result:
	if state.phase == "Working":
		return _advance_working_sub_phase(pm, state)
	if state.phase == "Cleanup":
		return _advance_cleanup_sub_phase(pm, state)
	var phase_enum: int = DefsClass.get_phase_enum(state.phase)
	if phase_enum == -1:
		return Result.failure("未知当前阶段: %s" % state.phase)
	var order = pm.get_phase_sub_phase_order_names(phase_enum)
	if order.is_empty():
		return Result.failure("当前阶段不支持推进子阶段: %s" % state.phase)
	return _advance_generic_sub_phase(pm, state, order)
	return Result.failure("当前阶段不支持推进子阶段: %s" % state.phase)

static func _advance_generic_sub_phase(pm, state: GameState, order_names: Array[String]) -> Result:
	var current_name: String = state.sub_phase
	var current_index := order_names.find(current_name)
	if current_index == -1:
		return Result.failure("未知当前子阶段: %s" % current_name)

	var all_warnings: Array[String] = []
	var old_sub := state.sub_phase
	var old_round_state_snapshot: Dictionary = state.round_state.duplicate(true)

	var before_exit = pm._run_named_sub_phase_hooks(current_name, HookType.BEFORE_EXIT, state)
	if not before_exit.ok:
		return before_exit
	all_warnings.append_array(before_exit.warnings)

	if current_index >= order_names.size() - 1:
		var after_exit_last = pm._run_named_sub_phase_hooks(current_name, HookType.AFTER_EXIT, state)
		if not after_exit_last.ok:
			state.sub_phase = old_sub
			state.round_state = old_round_state_snapshot
			return after_exit_last
		all_warnings.append_array(after_exit_last.warnings)

		var adv = pm.advance_phase(state)
		if adv.ok:
			adv.with_warnings(all_warnings)
		return adv

	state.sub_phase = str(order_names[current_index + 1])
	WorkingFlowClass.reset_sub_phase_passed(state)
	var phase_orders: Dictionary = {}
	if state.round_state.has("phase_sub_phase_orders") and (state.round_state["phase_sub_phase_orders"] is Dictionary):
		phase_orders = state.round_state["phase_sub_phase_orders"]
	phase_orders[state.phase] = order_names.duplicate()
	state.round_state["phase_sub_phase_orders"] = phase_orders

	var after_exit = pm._run_named_sub_phase_hooks(current_name, HookType.AFTER_EXIT, state)
	if not after_exit.ok:
		state.sub_phase = old_sub
		state.round_state = old_round_state_snapshot
		return after_exit
	all_warnings.append_array(after_exit.warnings)

	var sub_before_enter = pm._run_named_sub_phase_hooks(state.sub_phase, HookType.BEFORE_ENTER, state)
	if not sub_before_enter.ok:
		state.sub_phase = old_sub
		state.round_state = old_round_state_snapshot
		return sub_before_enter
	all_warnings.append_array(sub_before_enter.warnings)

	var sub_after_enter = pm._run_named_sub_phase_hooks(state.sub_phase, HookType.AFTER_ENTER, state)
	if not sub_after_enter.ok:
		state.sub_phase = old_sub
		state.round_state = old_round_state_snapshot
		return sub_after_enter
	all_warnings.append_array(sub_after_enter.warnings)

	GameLog.info("PhaseManager", "子阶段推进: %s -> %s" % [old_sub, state.sub_phase])
	return Result.success({
		"old_sub_phase": old_sub,
		"new_sub_phase": state.sub_phase
	}).with_warnings(all_warnings)

static func _advance_working_sub_phase(pm, state: GameState) -> Result:
	if pm._working_sub_phase_order_names.is_empty():
		return Result.failure("working_sub_phase_order 未初始化")
	var current_name: String = state.sub_phase
	var current_index = pm._working_sub_phase_order_names.find(current_name)
	if current_index == -1:
		return Result.failure("未知当前子阶段: %s" % current_name)

	var all_warnings: Array[String] = []
	var old_sub := state.sub_phase
	var old_round_state_snapshot: Dictionary = state.round_state.duplicate(true)

	# 执行当前子阶段退出钩子
	var before_exit = pm._run_working_sub_phase_hooks(current_name, HookType.BEFORE_EXIT, state)
	if not before_exit.ok:
		return before_exit
	all_warnings.append_array(before_exit.warnings)

	# 确定下一子阶段
	if current_index >= pm._working_sub_phase_order_names.size() - 1:
		# 最后一个子阶段：结束当前玩家的 Working 回合 -> 下一位玩家从第一个子阶段开始；
		# 若所有玩家都已确认结束，则离开 Working 进入下一主阶段。
		var after_exit_last = pm._run_working_sub_phase_hooks(current_name, HookType.AFTER_EXIT, state)
		if not after_exit_last.ok:
			state.sub_phase = old_sub
			state.round_state = old_round_state_snapshot
			return after_exit_last
		all_warnings.append_array(after_exit_last.warnings)

		if not (state.round_state is Dictionary):
			return Result.failure("Working: round_state 类型错误（期望 Dictionary）")
		if not state.round_state.has("sub_phase_passed"):
			return Result.failure("Working: round_state.sub_phase_passed 缺失")
		var passed_val = state.round_state["sub_phase_passed"]
		if not (passed_val is Dictionary):
			return Result.failure("Working: round_state.sub_phase_passed 类型错误（期望 Dictionary）")
		var passed: Dictionary = passed_val

		var all_passed := true
		for pid in range(state.players.size()):
			assert(passed.has(pid) and (passed[pid] is bool), "Working: sub_phase_passed[%d] 缺失或类型错误（期望 bool）" % pid)
			if not bool(passed[pid]):
				all_passed = false
				break

		if all_passed:
			var adv = pm.advance_phase(state)
			if adv.ok:
				adv.with_warnings(all_warnings)
			return adv

		var size := state.turn_order.size()
		if size <= 0:
			return Result.failure("turn_order 为空")

		var next_idx := -1
		for offset in range(1, size + 1):
			var idx := state.current_player_index + offset
			if idx >= size:
				idx = idx % size
			var pid_val = state.turn_order[idx]
			if not (pid_val is int):
				continue
			var pid2: int = int(pid_val)
			if not bool(passed.get(pid2, false)):
				next_idx = idx
				break

		if next_idx == -1:
			return Result.failure("Working: 未找到下一位未确认结束的玩家（sub_phase_passed 可能损坏）")

		state.current_player_index = next_idx
		state.sub_phase = pm._working_sub_phase_order_names[0]
		WorkingFlowClass.reset_working_sub_phase_state(state)
		state.round_state["working_sub_phase_order"] = pm._working_sub_phase_order_names.duplicate()

		var sub_before_enter0 = pm._run_working_sub_phase_hooks(state.sub_phase, HookType.BEFORE_ENTER, state)
		if not sub_before_enter0.ok:
			state.sub_phase = old_sub
			state.round_state = old_round_state_snapshot
			return sub_before_enter0
		all_warnings.append_array(sub_before_enter0.warnings)

		var sub_after_enter0 = pm._run_working_sub_phase_hooks(state.sub_phase, HookType.AFTER_ENTER, state)
		if not sub_after_enter0.ok:
			state.sub_phase = old_sub
			state.round_state = old_round_state_snapshot
			return sub_after_enter0
		all_warnings.append_array(sub_after_enter0.warnings)

		GameLog.info("PhaseManager", "Working 回合切换：进入玩家 %d，从子阶段 %s 开始" % [
			state.get_current_player_id(),
			state.sub_phase
		])

		return Result.success({
			"old_sub_phase": old_sub,
			"new_sub_phase": state.sub_phase
		}).with_warnings(all_warnings)

	state.sub_phase = pm._working_sub_phase_order_names[current_index + 1]
	WorkingFlowClass.reset_working_sub_phase_state(state)
	state.round_state["working_sub_phase_order"] = pm._working_sub_phase_order_names.duplicate()

	# 执行退出后钩子
	var after_exit = pm._run_working_sub_phase_hooks(current_name, HookType.AFTER_EXIT, state)
	if not after_exit.ok:
		state.sub_phase = old_sub
		state.round_state = old_round_state_snapshot
		return after_exit
	all_warnings.append_array(after_exit.warnings)

	# 执行新子阶段进入钩子
	var sub_before_enter = pm._run_working_sub_phase_hooks(state.sub_phase, HookType.BEFORE_ENTER, state)
	if not sub_before_enter.ok:
		state.sub_phase = old_sub
		state.round_state = old_round_state_snapshot
		return sub_before_enter
	all_warnings.append_array(sub_before_enter.warnings)

	var sub_after_enter = pm._run_working_sub_phase_hooks(state.sub_phase, HookType.AFTER_ENTER, state)
	if not sub_after_enter.ok:
		state.sub_phase = old_sub
		state.round_state = old_round_state_snapshot
		return sub_after_enter
	all_warnings.append_array(sub_after_enter.warnings)

	GameLog.info("PhaseManager", "子阶段推进: %s -> %s" % [old_sub, state.sub_phase])

	return Result.success({
		"old_sub_phase": old_sub,
		"new_sub_phase": state.sub_phase
	}).with_warnings(all_warnings)

static func _advance_cleanup_sub_phase(pm, state: GameState) -> Result:
	if pm._cleanup_sub_phase_order_names.is_empty():
		return Result.failure("cleanup_sub_phase_order 未初始化")
	var current_name: String = state.sub_phase
	var current_index = pm._cleanup_sub_phase_order_names.find(current_name)
	if current_index == -1:
		return Result.failure("未知当前子阶段: %s" % current_name)

	var all_warnings: Array[String] = []
	var old_sub := state.sub_phase
	var old_round_state_snapshot: Dictionary = state.round_state.duplicate(true)

	var before_exit = pm._run_named_sub_phase_hooks(current_name, HookType.BEFORE_EXIT, state)
	if not before_exit.ok:
		return before_exit
	all_warnings.append_array(before_exit.warnings)

	if current_index >= pm._cleanup_sub_phase_order_names.size() - 1:
		var after_exit_last = pm._run_named_sub_phase_hooks(current_name, HookType.AFTER_EXIT, state)
		if not after_exit_last.ok:
			state.sub_phase = old_sub
			state.round_state = old_round_state_snapshot
			return after_exit_last
		all_warnings.append_array(after_exit_last.warnings)

		var adv = pm.advance_phase(state)
		if adv.ok:
			adv.with_warnings(all_warnings)
		return adv

	state.sub_phase = pm._cleanup_sub_phase_order_names[current_index + 1]
	if state.round_state is Dictionary:
		state.round_state["cleanup_sub_phase_order"] = pm._cleanup_sub_phase_order_names.duplicate()
		WorkingFlowClass.reset_sub_phase_passed(state)
	state.current_player_index = 0

	var after_exit = pm._run_named_sub_phase_hooks(current_name, HookType.AFTER_EXIT, state)
	if not after_exit.ok:
		state.sub_phase = old_sub
		state.round_state = old_round_state_snapshot
		return after_exit
	all_warnings.append_array(after_exit.warnings)

	var sub_before_enter = pm._run_named_sub_phase_hooks(state.sub_phase, HookType.BEFORE_ENTER, state)
	if not sub_before_enter.ok:
		state.sub_phase = old_sub
		state.round_state = old_round_state_snapshot
		return sub_before_enter
	all_warnings.append_array(sub_before_enter.warnings)

	var sub_after_enter = pm._run_named_sub_phase_hooks(state.sub_phase, HookType.AFTER_ENTER, state)
	if not sub_after_enter.ok:
		state.sub_phase = old_sub
		state.round_state = old_round_state_snapshot
		return sub_after_enter
	all_warnings.append_array(sub_after_enter.warnings)

	GameLog.info("PhaseManager", "子阶段推进(Cleanup): %s -> %s" % [old_sub, state.sub_phase])

	return Result.success({
		"old_sub_phase": old_sub,
		"new_sub_phase": state.sub_phase
	}).with_warnings(all_warnings)
