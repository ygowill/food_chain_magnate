# PhaseManager：主阶段推进逻辑（抽离自 advancement.gd）
extends RefCounted

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const WorkingFlowClass = preload("res://core/engine/phase_manager/working_flow.gd")

const Phase = DefsClass.Phase
const PHASE_NAMES = DefsClass.PHASE_NAMES

enum HookType {
	BEFORE_ENTER,
	AFTER_ENTER,
	BEFORE_EXIT,
	AFTER_EXIT
}

# 推进到下一阶段
static func advance_phase(pm, state: GameState) -> Result:
	var current_phase := DefsClass.get_phase_enum(state.phase)
	if current_phase == -1:
		return Result.failure("未知当前阶段: %s" % state.phase)
	if current_phase == Phase.GAME_OVER:
		return Result.failure("游戏已结束")

	# 通用：若当前阶段存在待处理的“阶段内必做动作”，禁止推进到下一阶段（由模块注入）。
	if state.round_state is Dictionary and state.round_state.has("pending_phase_actions"):
		var ppa_val = state.round_state.get("pending_phase_actions", null)
		if not (ppa_val is Dictionary):
			return Result.failure("round_state.pending_phase_actions 类型错误（期望 Dictionary）")
		var pending: Dictionary = ppa_val
		var key := str(state.phase)
		if pending.has(key):
			var list_val = pending.get(key, null)
			if not (list_val is Array):
				return Result.failure("round_state.pending_phase_actions[%s] 类型错误（期望 Array）" % key)
			var list: Array = list_val
			if not list.is_empty():
				return Result.failure("当前阶段仍有待处理动作，无法推进：%s" % key)

	var all_warnings: Array[String] = []
	var old_phase := state.phase
	var old_sub_phase := state.sub_phase
	var old_round_number := state.round_number
	var old_map_snapshot: Dictionary = state.map.duplicate(true)
	var old_marketing_instances_snapshot: Array = state.marketing_instances.duplicate(true)
	var old_bank_snapshot: Dictionary = state.bank.duplicate(true)
	var old_round_state_snapshot: Dictionary = state.round_state.duplicate(true)
	var old_players_snapshot: Array = state.players.duplicate(true)

	# 执行当前阶段退出钩子
	var exit_result = pm._hooks.run_phase_hooks(current_phase, HookType.BEFORE_EXIT, state)
	if not exit_result.ok:
		return exit_result
	all_warnings.append_array(exit_result.warnings)

	# 阶段离开时结算（可由模块覆盖触发点映射）
	var exit_settlements = pm._run_settlement_triggers("exit", current_phase, state)
	if not exit_settlements.ok:
		state.phase = old_phase
		state.sub_phase = old_sub_phase
		state.round_number = old_round_number
		state.map = old_map_snapshot
		state.marketing_instances = old_marketing_instances_snapshot
		state.bank = old_bank_snapshot
		state.round_state = old_round_state_snapshot
		state.players = old_players_snapshot
		return exit_settlements
	all_warnings.append_array(exit_settlements.warnings)

	# 确定下一阶段
	var next_phase: int
	if current_phase == Phase.SETUP:
		# Setup -> Restructuring，同时增加回合数
		next_phase = Phase.RESTRUCTURING
		state.round_number += 1
	elif current_phase == Phase.CLEANUP:
		# Cleanup -> Restructuring（新回合）
		next_phase = Phase.RESTRUCTURING
		state.round_number += 1
	else:
		# 找到当前阶段在顺序中的位置
		var current_index = pm._phase_order_enums.find(current_phase)
		if current_index == -1 or current_index >= pm._phase_order_enums.size() - 1:
			next_phase = Phase.CLEANUP
		else:
			next_phase = pm._phase_order_enums[current_index + 1]

			pass

	# 可选：模块可强制指定 next_phase（用于特殊规则，例如第二次破产后立刻终局）。
	# 约定：写入 round_state.force_next_phase = "<PhaseName>"，在本次推进时生效，之后清空。
	if state.round_state is Dictionary and state.round_state.has("force_next_phase"):
		var f_val = state.round_state.get("force_next_phase", null)
		if not (f_val is String):
			return Result.failure("round_state.force_next_phase 类型错误（期望 String）")
		var f_name: String = str(f_val)
		if f_name.is_empty():
			return Result.failure("round_state.force_next_phase 不能为空")
		var f_enum := DefsClass.get_phase_enum(f_name)
		if f_enum == -1:
			return Result.failure("round_state.force_next_phase 未知阶段: %s" % f_name)
		next_phase = f_enum
		state.round_state.erase("force_next_phase")

	# 更新状态
	state.phase = PHASE_NAMES[next_phase]
	state.sub_phase = ""
	if state.round_state is Dictionary:
		state.round_state["prev_phase"] = old_phase
		state.round_state["prev_sub_phase"] = old_sub_phase
		state.round_state["phase_order"] = pm._phase_order_names.duplicate()
		WorkingFlowClass.reset_sub_phase_passed(state)

	# 执行退出后钩子
	var after_exit_result = pm._hooks.run_phase_hooks(current_phase, HookType.AFTER_EXIT, state)
	if not after_exit_result.ok:
		state.phase = old_phase
		state.sub_phase = old_sub_phase
		state.round_number = old_round_number
		state.map = old_map_snapshot
		state.marketing_instances = old_marketing_instances_snapshot
		state.bank = old_bank_snapshot
		state.round_state = old_round_state_snapshot
		state.players = old_players_snapshot
		return after_exit_result
	all_warnings.append_array(after_exit_result.warnings)

	# 执行新阶段进入钩子
	var before_enter_result = pm._hooks.run_phase_hooks(next_phase, HookType.BEFORE_ENTER, state)
	if not before_enter_result.ok:
		state.phase = old_phase
		state.sub_phase = old_sub_phase
		state.round_number = old_round_number
		state.map = old_map_snapshot
		state.marketing_instances = old_marketing_instances_snapshot
		state.bank = old_bank_snapshot
		state.round_state = old_round_state_snapshot
		state.players = old_players_snapshot
		return before_enter_result
	all_warnings.append_array(before_enter_result.warnings)

	# Marketing 结算：必须在 BEFORE_ENTER hooks 之后执行，便于模块注入结算轮次数等参数。
	# 阶段进入时结算（BEFORE_ENTER hooks 已执行；可由模块覆盖触发点映射）
	var enter_settlements = pm._run_settlement_triggers("enter", next_phase, state)
	if not enter_settlements.ok:
		state.phase = old_phase
		state.sub_phase = old_sub_phase
		state.round_number = old_round_number
		state.map = old_map_snapshot
		state.marketing_instances = old_marketing_instances_snapshot
		state.bank = old_bank_snapshot
		state.round_state = old_round_state_snapshot
		state.players = old_players_snapshot
		return enter_settlements
	all_warnings.append_array(enter_settlements.warnings)

	# Cleanup 阶段：若存在模块注入的子阶段，自动进入第一个子阶段
	if next_phase == Phase.CLEANUP and not pm._cleanup_sub_phase_order_names.is_empty():
		state.sub_phase = pm._cleanup_sub_phase_order_names[0]
		if state.round_state is Dictionary:
			state.round_state["cleanup_sub_phase_order"] = pm._cleanup_sub_phase_order_names.duplicate()
			WorkingFlowClass.reset_sub_phase_passed(state)
		state.current_player_index = 0

		var sub_before_cleanup = pm._run_named_sub_phase_hooks(state.sub_phase, HookType.BEFORE_ENTER, state)
		if not sub_before_cleanup.ok:
			state.phase = old_phase
			state.sub_phase = old_sub_phase
			state.round_number = old_round_number
			state.map = old_map_snapshot
			state.marketing_instances = old_marketing_instances_snapshot
			state.bank = old_bank_snapshot
			state.round_state = old_round_state_snapshot
			state.players = old_players_snapshot
			return sub_before_cleanup
		all_warnings.append_array(sub_before_cleanup.warnings)

		var sub_after_cleanup = pm._run_named_sub_phase_hooks(state.sub_phase, HookType.AFTER_ENTER, state)
		if not sub_after_cleanup.ok:
			state.phase = old_phase
			state.sub_phase = old_sub_phase
			state.round_number = old_round_number
			state.map = old_map_snapshot
			state.marketing_instances = old_marketing_instances_snapshot
			state.bank = old_bank_snapshot
			state.round_state = old_round_state_snapshot
			state.players = old_players_snapshot
			return sub_after_cleanup
		all_warnings.append_array(sub_after_cleanup.warnings)

	# 如果是工作阶段，自动进入第一个子阶段
	if next_phase == Phase.WORKING:
		state.sub_phase = pm._working_sub_phase_order_names[0]
		state.round_state["working_sub_phase_order"] = pm._working_sub_phase_order_names.duplicate()

		var sub_before = pm._run_working_sub_phase_hooks(state.sub_phase, HookType.BEFORE_ENTER, state)
		if not sub_before.ok:
			state.phase = old_phase
			state.sub_phase = old_sub_phase
			state.round_number = old_round_number
			state.map = old_map_snapshot
			state.marketing_instances = old_marketing_instances_snapshot
			state.bank = old_bank_snapshot
			state.round_state = old_round_state_snapshot
			state.players = old_players_snapshot
			return sub_before
		all_warnings.append_array(sub_before.warnings)

		var sub_after = pm._run_working_sub_phase_hooks(state.sub_phase, HookType.AFTER_ENTER, state)
		if not sub_after.ok:
			state.phase = old_phase
			state.sub_phase = old_sub_phase
			state.round_number = old_round_number
			state.map = old_map_snapshot
			state.marketing_instances = old_marketing_instances_snapshot
			state.bank = old_bank_snapshot
			state.round_state = old_round_state_snapshot
			state.players = old_players_snapshot
			return sub_after
		all_warnings.append_array(sub_after.warnings)

	# 其它阶段：若模块为该阶段配置了子阶段顺序，则自动进入第一个子阶段
	if next_phase != Phase.WORKING and next_phase != Phase.CLEANUP and pm._phase_sub_phase_orders.has(next_phase):
		var order_val = pm._phase_sub_phase_orders.get(next_phase, null)
		if not (order_val is Array):
			return Result.failure("phase_sub_phase_order 内部类型错误: %s" % str(PHASE_NAMES.get(next_phase, next_phase)))
		var order: Array = order_val
		if not order.is_empty():
			state.sub_phase = str(order[0])
			if state.round_state is Dictionary:
				var phase_orders: Dictionary = {}
				if state.round_state.has("phase_sub_phase_orders") and (state.round_state["phase_sub_phase_orders"] is Dictionary):
					phase_orders = state.round_state["phase_sub_phase_orders"]
				phase_orders[state.phase] = order.duplicate()
				state.round_state["phase_sub_phase_orders"] = phase_orders
				WorkingFlowClass.reset_sub_phase_passed(state)
			state.current_player_index = 0

			var sub_before_generic = pm._run_named_sub_phase_hooks(state.sub_phase, HookType.BEFORE_ENTER, state)
			if not sub_before_generic.ok:
				state.phase = old_phase
				state.sub_phase = old_sub_phase
				state.round_number = old_round_number
				state.map = old_map_snapshot
				state.marketing_instances = old_marketing_instances_snapshot
				state.bank = old_bank_snapshot
				state.round_state = old_round_state_snapshot
				state.players = old_players_snapshot
				return sub_before_generic
			all_warnings.append_array(sub_before_generic.warnings)

			var sub_after_generic = pm._run_named_sub_phase_hooks(state.sub_phase, HookType.AFTER_ENTER, state)
			if not sub_after_generic.ok:
				state.phase = old_phase
				state.sub_phase = old_sub_phase
				state.round_number = old_round_number
				state.map = old_map_snapshot
				state.marketing_instances = old_marketing_instances_snapshot
				state.bank = old_bank_snapshot
				state.round_state = old_round_state_snapshot
				state.players = old_players_snapshot
				return sub_after_generic
			all_warnings.append_array(sub_after_generic.warnings)

	# 执行进入后钩子
	var after_enter_result = pm._hooks.run_phase_hooks(next_phase, HookType.AFTER_ENTER, state)
	if not after_enter_result.ok:
		state.phase = old_phase
		state.sub_phase = old_sub_phase
		state.round_number = old_round_number
		state.map = old_map_snapshot
		state.marketing_instances = old_marketing_instances_snapshot
		state.bank = old_bank_snapshot
		state.round_state = old_round_state_snapshot
		state.players = old_players_snapshot
		return after_enter_result
	all_warnings.append_array(after_enter_result.warnings)

	GameLog.info("PhaseManager", "阶段推进: %s -> %s (回合 %d)" % [
		old_phase, state.phase, state.round_number
	])

	return Result.success({
		"old_phase": old_phase,
		"new_phase": state.phase,
		"round_number": state.round_number
	}).with_warnings(all_warnings)
