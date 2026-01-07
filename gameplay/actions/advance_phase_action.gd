# 阶段推进动作
# 推进游戏到下一阶段或子阶段
class_name AdvancePhaseAction
extends ActionExecutor

var phase_manager: PhaseManager = null

func _init(manager: PhaseManager = null) -> void:
	action_id = "advance_phase"
	display_name = "推进阶段"
	description = "推进游戏到下一阶段或子阶段"
	requires_actor = false  # 系统动作
	is_mandatory = false
	phase_manager = manager if manager != null else PhaseManager.new()

func _validate_specific(state: GameState, command: Command) -> Result:
	var target_result := optional_string_param(command, "target", "phase")
	if not target_result.ok:
		return target_result
	var target: String = target_result.value
	if target != "phase" and target != "sub_phase":
		return Result.failure("未知推进目标: %s" % target)

	# 检查是否在 Setup 阶段（需要特殊处理）
	if state.phase == "Setup":
		# Setup 没有子阶段
		if target == "sub_phase":
			return Result.failure("Setup 阶段没有子阶段")
		# Setup 阶段可以直接推进
		return Result.success()

	# 推进子阶段：要求存在 sub_phase，并要求所有玩家已选择 pass（skip）
	if target == "sub_phase":
		if state.sub_phase.is_empty():
			return Result.failure("子阶段为空，无法推进")
		# Working：子阶段推进是“单玩家流转”，不要求所有玩家 pass
		if state.phase == "Working":
			return Result.success()
		if not (state.round_state is Dictionary):
			return Result.failure("未初始化(round_state)")
		assert(state.round_state.has("sub_phase_passed"), "advance_phase: round_state 缺少 sub_phase_passed")
		var passed_val = state.round_state["sub_phase_passed"]
		if not (passed_val is Dictionary):
			return Result.failure("round_state.sub_phase_passed 类型错误（期望 Dictionary）")
		var passed: Dictionary = passed_val
		var missing: Array[int] = []
		for pid in range(state.players.size()):
			assert(passed.has(pid) and (passed[pid] is bool), "advance_phase: sub_phase_passed[%d] 缺失或类型错误（期望 bool）" % pid)
			if not bool(passed[pid]):
				missing.append(pid)
		if not missing.is_empty():
			return Result.failure("仍有玩家未结束当前子阶段: %s" % str(missing))
		return Result.success()

	# 仅当推进主阶段时检查阶段完成条件；推进子阶段不在此处限制
	if target != "sub_phase":
		# 若当前存在子阶段，则必须通过子阶段推进（避免绕过子阶段顺序/强制动作）
		if not state.sub_phase.is_empty():
			return Result.failure("当前存在子阶段，请使用 target=sub_phase 推进")

		# 决定顺序阶段：必须先完成所有玩家的顺序选择
		if state.phase == "OrderOfBusiness":
			if not (state.round_state is Dictionary):
				return Result.failure("OrderOfBusiness 未初始化")
			if not state.round_state.has("order_of_business"):
				return Result.failure("OrderOfBusiness 未初始化")
			var oob_val = state.round_state["order_of_business"]
			if not (oob_val is Dictionary):
				return Result.failure("OrderOfBusiness 未初始化")
			var oob: Dictionary = oob_val
			if oob.is_empty():
				return Result.failure("OrderOfBusiness 未初始化")
			if not oob.has("finalized") or not (oob["finalized"] is bool):
				return Result.failure("OrderOfBusiness finalized 缺失或类型错误")
			if not bool(oob["finalized"]):
				return Result.failure("OrderOfBusiness 未完成选择，无法推进到下一阶段")

	return Result.success()

func _apply_changes(state: GameState, command: Command) -> Result:
	var target_result := optional_string_param(command, "target", "phase")
	if not target_result.ok:
		return target_result
	var target: String = target_result.value

	if target == "sub_phase":
		return _advance_sub_phase(state)
	return _advance_phase(state)

func _advance_phase(state: GameState) -> Result:
	return phase_manager.advance_phase(state)

func _advance_sub_phase(state: GameState) -> Result:
	return phase_manager.advance_sub_phase(state)

func _generate_specific_events(old_state: GameState, new_state: GameState, _command: Command) -> Array[Dictionary]:
	var events: Array[Dictionary] = []

	# 阶段变化事件
	if old_state.phase != new_state.phase:
		events.append({
			"type": EventBus.EventType.PHASE_CHANGED,
			"data": {
				"old_phase": old_state.phase,
				"new_phase": new_state.phase,
				"round": new_state.round_number
			}
		})

		# 回合开始事件
		if old_state.round_number != new_state.round_number:
			events.append({
				"type": EventBus.EventType.ROUND_STARTED,
				"data": {
					"round": new_state.round_number
				}
			})

	# 子阶段变化事件
	if old_state.sub_phase != new_state.sub_phase and not new_state.sub_phase.is_empty():
		events.append({
			"type": EventBus.EventType.SUB_PHASE_CHANGED,
			"data": {
				"old_sub_phase": old_state.sub_phase,
				"new_sub_phase": new_state.sub_phase
			}
		})

	return events
