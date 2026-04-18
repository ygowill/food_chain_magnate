# 阶段推进动作
# 推进游戏到下一阶段或子阶段
class_name AdvancePhaseAction
extends ActionExecutor

const CommandRunnerClass = preload("res://core/engine/game_engine/command_runner.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")
const RoundStateOrderOfBusinessClass = preload("res://core/utils/round_state_order_of_business.gd")
const RoundStateSubPhasePassedClass = preload("res://core/utils/round_state_sub_phase_passed.gd")

var phase_manager: PhaseManager = null

func _init(manager: PhaseManager = null) -> void:
	action_id = ActionIdsClass.ADVANCE_PHASE
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
	if state.phase == DefsClass.PHASE_SETUP:
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
		if state.phase == DefsClass.PHASE_WORKING:
			return Result.success()
		if not (state.round_state is Dictionary):
			return Result.failure("未初始化(round_state)")
		var passed_read := RoundStateSubPhasePassedClass.require_all_player_flags(state.round_state, state.players.size(), "advance_phase")
		if not passed_read.ok:
			return passed_read
		var passed: Dictionary = passed_read.value
		var missing: Array[int] = []
		for pid in range(state.players.size()):
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
		if state.phase == DefsClass.PHASE_ORDER_OF_BUSINESS:
			if not (state.round_state is Dictionary):
				return Result.failure("OrderOfBusiness 未初始化")
			var oob_read := RoundStateOrderOfBusinessClass.require_order_of_business(state.round_state, "advance_phase")
			if not oob_read.ok:
				return Result.failure("OrderOfBusiness 未初始化")
			var oob: Dictionary = oob_read.value
			if oob.is_empty():
				return Result.failure("OrderOfBusiness 未初始化")
			var finalized_read := RoundStateOrderOfBusinessClass.require_finalized(oob, "advance_phase")
			if not finalized_read.ok:
				return finalized_read
			if not bool(finalized_read.value):
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
		if str(old_state.phase) == DefsClass.PHASE_PAYDAY:
			events.append_array(CommandRunnerClass.build_payday_report_events(old_state, new_state))

		# Marketing 结算摘要：在离开 Marketing 时发射（便于 UI 日志从 EventBus.history 恢复）。
		# issue_tracker #48: per board 1 log entry, with details in event data.
		if str(old_state.phase) == DefsClass.PHASE_MARKETING:
			events.append_array(CommandRunnerClass.build_marketing_demand_generated_events(old_state))
			events.append_array(CommandRunnerClass.build_marketing_expired_events(old_state))

		events.append({
			"type": EventBus.EventType.PHASE_CHANGED,
			"data": {
				"old_phase": old_state.phase,
				"new_phase": new_state.phase,
				"round": new_state.round_number
			}
		})

		# Dinnertime 结算报告：在进入 Dinnertime 时发射（结算在 enter hook 运行，报告写入 new_state.round_state.dinnertime）。
		if str(new_state.phase) == DefsClass.PHASE_DINNERTIME:
			var report_dinnertime: Dictionary = {}
			if new_state.round_state is Dictionary:
				var v3 = Dictionary(new_state.round_state).get("dinnertime", null)
				if v3 is Dictionary:
					report_dinnertime = Dictionary(v3).duplicate(true)
			events.append({
				"type": EventBus.EventType.DINNERTIME_REPORT,
				"data": {
					"round": new_state.round_number,
					"from_phase": str(old_state.phase),
					"to_phase": str(new_state.phase),
					"report": report_dinnertime,
				}
			})
			events.append_array(CommandRunnerClass.build_food_sold_events_from_dinnertime_report(new_state, report_dinnertime))

		# Cleanup 库存丢弃：在进入 Cleanup 时发射（清理结算在 Cleanup:enter 运行）。
		if str(new_state.phase) == DefsClass.PHASE_CLEANUP:
			events.append_array(CommandRunnerClass.build_cleanup_inventory_discarded_events(new_state))

		# 回合开始事件
		if old_state.round_number != new_state.round_number:
			events.append({
				"type": EventBus.EventType.ROUND_ENDED,
				"data": {
					"round": old_state.round_number,
					"next_round": new_state.round_number,
				}
			})
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
