extends RefCounted

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")
const PhaseBlockingClass = preload("res://core/engine/game_engine/auto_advance_phase_blocking.gd")
const OrderOfBusinessRound1Class = preload("res://core/engine/game_engine/auto_advance_order_of_business_round1.gd")
const WorkingMandatoryClass = preload("res://core/engine/game_engine/auto_advance_working_mandatory.gd")

static func try_advance_one(state_in: GameState, phase_manager: PhaseManager, action_registry: ActionRegistry) -> Result:
	if state_in == null:
		return Result.failure("auto_advance: state 为空")
	if phase_manager == null:
		return Result.failure("auto_advance: phase_manager 为空")
	if action_registry == null:
		return Result.failure("auto_advance: action_registry 为空")

	# 首轮自动跳过：Restructuring / OrderOfBusiness（保留未来扩展空间）
	if state_in.round_number == 1 and state_in.phase == DefsClass.PHASE_RESTRUCTURING:
		var blocked_r: Result = PhaseBlockingClass.is_phase_blocked_by_pending_actions(state_in, DefsClass.PHASE_RESTRUCTURING)
		if not blocked_r.ok:
			return blocked_r
		if bool(blocked_r.value):
			return Result.success(false)

		var adv: Result = phase_manager.advance_phase(state_in)
		if not adv.ok:
			return adv
		return Result.success(true).with_warnings(adv.warnings)

	if state_in.round_number == 1 and state_in.phase == DefsClass.PHASE_ORDER_OF_BUSINESS:
		var blocked_r2: Result = PhaseBlockingClass.is_phase_blocked_by_pending_actions(state_in, DefsClass.PHASE_ORDER_OF_BUSINESS)
		if not blocked_r2.ok:
			return blocked_r2
		if bool(blocked_r2.value):
			return Result.success(false)

		var fin: Result = OrderOfBusinessRound1Class.auto_finalize_order_of_business_round1(state_in)
		if not fin.ok:
			return fin

		var adv2: Result = phase_manager.advance_phase(state_in)
		if not adv2.ok:
			return adv2

		var warnings2: Array[String] = []
		warnings2.append_array(fin.warnings)
		warnings2.append_array(adv2.warnings)
		return Result.success(true).with_warnings(warnings2)

	# Restructuring：所有玩家都确认后，自动进入下一阶段（避免动作内 advance_phase 导致日志归属错乱）。
	if state_in.phase == DefsClass.PHASE_RESTRUCTURING:
		var blocked_r4: Result = PhaseBlockingClass.is_phase_blocked_by_pending_actions(state_in, DefsClass.PHASE_RESTRUCTURING)
		if not blocked_r4.ok:
			return blocked_r4
		if bool(blocked_r4.value):
			return Result.success(false)

		var finalized_r := false
		if state_in.round_state is Dictionary:
			var r_val = Dictionary(state_in.round_state).get("restructuring", null)
			if r_val is Dictionary:
				var r: Dictionary = r_val
				if r.has("finalized") and (r["finalized"] is bool):
					finalized_r = bool(r["finalized"])
		if not finalized_r:
			return Result.success(false)

		var adv_r4: Result = phase_manager.advance_phase(state_in)
		if not adv_r4.ok:
			return adv_r4
		return Result.success(true).with_warnings(adv_r4.warnings)

	# OrderOfBusiness：行动顺序落地后，自动进入 Working（保证日志顺序为“选择顺序 -> 进入 Working”）。
	if state_in.phase == DefsClass.PHASE_ORDER_OF_BUSINESS:
		var blocked_r5: Result = PhaseBlockingClass.is_phase_blocked_by_pending_actions(state_in, DefsClass.PHASE_ORDER_OF_BUSINESS)
		if not blocked_r5.ok:
			return blocked_r5
		if bool(blocked_r5.value):
			return Result.success(false)

		var finalized_oob := false
		if state_in.round_state is Dictionary:
			var oob_val = Dictionary(state_in.round_state).get("order_of_business", null)
			if oob_val is Dictionary:
				var oob: Dictionary = oob_val
				if oob.has("finalized") and (oob["finalized"] is bool):
					finalized_oob = bool(oob["finalized"])
		if not finalized_oob:
			return Result.success(false)

		var adv_r5: Result = phase_manager.advance_phase(state_in)
		if not adv_r5.ok:
			return adv_r5
		return Result.success(true).with_warnings(adv_r5.warnings)

	# 结算阶段默认自动跳过（无玩家交互）
	if PhaseBlockingClass.is_auto_skip_settlement_phase(state_in.phase):
		var blocked_r3: Result = PhaseBlockingClass.is_phase_blocked_by_pending_actions(state_in, str(state_in.phase))
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
	if state_in.phase == DefsClass.PHASE_WORKING:
		# 先自动执行“可无参补完”的强制动作（避免其阻断子阶段 auto-advance：issue #62/#discount_manager）。
		var mandatory_r: Result = WorkingMandatoryClass.try_auto_complete_working_mandatory_actions(state_in, action_registry)
		if not mandatory_r.ok:
			return mandatory_r
		if bool(mandatory_r.value):
			return Result.success(true).with_warnings(mandatory_r.warnings)

		var order_names := phase_manager.get_working_sub_phase_order_names()
		if order_names.is_empty():
			return Result.failure("auto_advance: working_sub_phase_order 未初始化")

		var last_sub_phase: String = str(order_names[order_names.size() - 1])
		if state_in.sub_phase != last_sub_phase:
			var pid := state_in.get_current_player_id()
			if pid < 0:
				return Result.failure("auto_advance: Working 当前玩家无效")

			var initiatable: Array[String] = action_registry.get_player_initiatable_actions(state_in, pid)
			var has_real_actions := false
			for aid in initiatable:
				if aid == ActionIdsClass.SKIP or aid == ActionIdsClass.SKIP_SUB_PHASE or aid == ActionIdsClass.END_TURN or aid == ActionIdsClass.ADVANCE_PHASE:
					continue
				has_real_actions = true
				break

			if not has_real_actions:
				var adv4: Result = phase_manager.advance_sub_phase(state_in)
				if not adv4.ok:
					return adv4
				return Result.success(true).with_warnings(adv4.warnings)

	return Result.success(false)
