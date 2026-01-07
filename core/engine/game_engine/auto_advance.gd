# GameEngine：自动推进规则（用于运行时与回放/倒带一致性）
# 说明：
# - 这些推进不应依赖 UI，必须完全由 state 决定，且确定性可重放。
# - Replay/rewind 使用 executor.compute_new_state 时不会经过 GameEngine.execute_command，因此需要在回放侧同样执行 auto-advance。
class_name AutoAdvance
extends RefCounted

static func drain(state_in: GameState, phase_manager: PhaseManager, action_registry: ActionRegistry, max_steps: int = 32) -> Result:
	if state_in == null:
		return Result.failure("auto_advance: state 为空")
	if phase_manager == null:
		return Result.failure("auto_advance: phase_manager 为空")
	if action_registry == null:
		return Result.failure("auto_advance: action_registry 为空")
	if max_steps <= 0:
		return Result.failure("auto_advance: max_steps 必须 > 0")

	var warnings: Array[String] = []
	var safety := 0

	while safety < max_steps:
		safety += 1
		var step := try_advance_one(state_in, phase_manager, action_registry)
		if not step.ok:
			return step
		warnings.append_array(step.warnings)
		if not bool(step.value):
			return Result.success().with_warnings(warnings)

	return Result.failure("auto_advance: exceeded max steps (possible loop)").with_warnings(warnings)

static func try_advance_one(state_in: GameState, phase_manager: PhaseManager, action_registry: ActionRegistry) -> Result:
	if state_in == null:
		return Result.failure("auto_advance: state 为空")
	if phase_manager == null:
		return Result.failure("auto_advance: phase_manager 为空")
	if action_registry == null:
		return Result.failure("auto_advance: action_registry 为空")

	# 首轮自动跳过：Restructuring / OrderOfBusiness（保留未来扩展空间）
	if state_in.round_number == 1 and state_in.phase == "Restructuring":
		var blocked_r := _is_phase_blocked_by_pending_actions(state_in, "Restructuring")
		if not blocked_r.ok:
			return blocked_r
		if bool(blocked_r.value):
			return Result.success(false)

		var adv := phase_manager.advance_phase(state_in)
		if not adv.ok:
			return adv
		return Result.success(true).with_warnings(adv.warnings)

	if state_in.round_number == 1 and state_in.phase == "OrderOfBusiness":
		var blocked_r2 := _is_phase_blocked_by_pending_actions(state_in, "OrderOfBusiness")
		if not blocked_r2.ok:
			return blocked_r2
		if bool(blocked_r2.value):
			return Result.success(false)

		var fin := _auto_finalize_order_of_business_round1(state_in)
		if not fin.ok:
			return fin

		var adv2 := phase_manager.advance_phase(state_in)
		if not adv2.ok:
			return adv2

		var warnings2: Array[String] = []
		warnings2.append_array(fin.warnings)
		warnings2.append_array(adv2.warnings)
		return Result.success(true).with_warnings(warnings2)

	# 结算阶段默认自动跳过（无玩家交互）
	if _is_auto_skip_settlement_phase(state_in.phase):
		var blocked_r3 := _is_phase_blocked_by_pending_actions(state_in, str(state_in.phase))
		if not blocked_r3.ok:
			return blocked_r3
		if bool(blocked_r3.value):
			return Result.success(false)

		var adv3: Result
		if not state_in.sub_phase.is_empty():
			adv3 = phase_manager.advance_sub_phase(state_in)
		else:
			adv3 = phase_manager.advance_phase(state_in)
		if not adv3.ok:
			return adv3
		return Result.success(true).with_warnings(adv3.warnings)

	# Working：若当前玩家在当前子阶段无可做动作，则自动推进到下一子阶段
	if state_in.phase == "Working":
		var order_names := phase_manager.get_working_sub_phase_order_names()
		if order_names.is_empty():
			return Result.failure("auto_advance: working_sub_phase_order 未初始化")

		var last_sub_phase: String = str(order_names[order_names.size() - 1])
		if state_in.sub_phase != last_sub_phase:
			var pid := state_in.get_current_player_id()
			if pid < 0:
				return Result.failure("auto_advance: Working 当前玩家无效")

			var initiatable := action_registry.get_player_initiatable_actions(state_in, pid)
			var has_real_actions := false
			for aid in initiatable:
				if aid == "skip" or aid == "skip_sub_phase" or aid == "end_turn" or aid == "advance_phase":
					continue
				has_real_actions = true
				break

			if not has_real_actions:
				var adv4 := phase_manager.advance_sub_phase(state_in)
				if not adv4.ok:
					return adv4
				return Result.success(true).with_warnings(adv4.warnings)

	return Result.success(false)

static func _is_phase_blocked_by_pending_actions(state_in: GameState, phase_name: String) -> Result:
	if state_in == null:
		return Result.failure("pending_phase_actions: state 为空")
	if not (state_in.round_state is Dictionary):
		return Result.failure("pending_phase_actions: round_state 类型错误（期望 Dictionary）")
	var rs: Dictionary = state_in.round_state
	if not rs.has("pending_phase_actions"):
		return Result.success(false)
	var ppa_val = rs.get("pending_phase_actions", null)
	if not (ppa_val is Dictionary):
		return Result.failure("pending_phase_actions: round_state.pending_phase_actions 类型错误（期望 Dictionary）")
	var pending: Dictionary = ppa_val
	if not pending.has(phase_name):
		return Result.success(false)
	var list_val = pending.get(phase_name, null)
	if not (list_val is Array):
		return Result.failure("pending_phase_actions: round_state.pending_phase_actions[%s] 类型错误（期望 Array）" % phase_name)
	var list: Array = list_val
	return Result.success(not list.is_empty())

static func _is_auto_skip_settlement_phase(phase_name: String) -> bool:
	match phase_name:
		"Dinnertime":
			return true
		"Marketing":
			return true
		"Cleanup":
			return true
		_:
			return false

static func _auto_finalize_order_of_business_round1(state_in: GameState) -> Result:
	if state_in == null:
		return Result.failure("OrderOfBusiness auto finalize: state 为空")
	if not (state_in.round_state is Dictionary):
		return Result.failure("OrderOfBusiness auto finalize: state.round_state 类型错误（期望 Dictionary）")
	if not state_in.round_state.has("order_of_business") or not (state_in.round_state["order_of_business"] is Dictionary):
		return Result.failure("OrderOfBusiness auto finalize: round_state.order_of_business 缺失或类型错误（期望 Dictionary）")
	var oob: Dictionary = state_in.round_state["order_of_business"]

	if not oob.has("finalized") or not (oob["finalized"] is bool):
		return Result.failure("OrderOfBusiness auto finalize: finalized 缺失或类型错误（期望 bool）")
	if bool(oob["finalized"]):
		return Result.success()

	if not oob.has("previous_turn_order") or not (oob["previous_turn_order"] is Array):
		return Result.failure("OrderOfBusiness auto finalize: previous_turn_order 缺失或类型错误（期望 Array）")
	var prev_val: Array = oob["previous_turn_order"]

	var player_count := state_in.players.size()
	if prev_val.size() != player_count:
		return Result.failure("OrderOfBusiness auto finalize: previous_turn_order 长度错误: %d（期望 %d）" % [prev_val.size(), player_count])

	var seen := {}
	var final_order: Array[int] = []
	for i in range(prev_val.size()):
		var pid_val = prev_val[i]
		if not (pid_val is int):
			return Result.failure("OrderOfBusiness auto finalize: previous_turn_order[%d] 类型错误（期望 int）" % i)
		var pid: int = int(pid_val)
		if pid < 0 or pid >= player_count:
			return Result.failure("OrderOfBusiness auto finalize: previous_turn_order[%d] 超出范围: %d" % [i, pid])
		if seen.has(pid):
			return Result.failure("OrderOfBusiness auto finalize: previous_turn_order 重复玩家: %d" % pid)
		seen[pid] = true
		final_order.append(pid)

	var picks: Array = []
	for pid2 in final_order:
		picks.append(pid2)

	oob["picks"] = picks
	oob["finalized"] = true
	state_in.round_state["order_of_business"] = oob

	state_in.turn_order = final_order
	state_in.current_player_index = 0

	return Result.success()
