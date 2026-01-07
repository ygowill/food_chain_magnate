# 跳过子阶段动作（Working）
# - 若不在最后子阶段：推进到下一子阶段（不结束玩家回合）
# - 若在最后子阶段：等价于“确认结束”（结束该玩家的 Working 回合）
class_name SkipSubPhaseAction
extends ActionExecutor

const MandatoryActionsRulesClass = preload("res://core/rules/working/mandatory_actions_rules.gd")

var phase_manager: PhaseManager = null

func _init(manager: PhaseManager = null) -> void:
	action_id = "skip_sub_phase"
	display_name = "跳过子阶段"
	description = "跳过当前子阶段"
	requires_actor = true
	is_mandatory = false
	allowed_phases = ["Working"]
	phase_manager = manager

func _validate_specific(state: GameState, command: Command) -> Result:
	if state == null:
		return Result.failure("state 为空")
	if state.phase != "Working":
		return Result.failure("仅允许在 Working 阶段使用")
	if state.sub_phase.is_empty():
		return Result.failure("Working 子阶段为空，无法跳过")

	var current_player_id := state.get_current_player_id()
	if command.actor != current_player_id:
		return Result.failure("不是你的回合")

	if phase_manager == null:
		return Result.failure("skip_sub_phase: phase_manager 未注入")

	# 若在最后子阶段，则“跳过子阶段”=“确认结束”，需要满足强制动作约束
	var order := phase_manager.get_working_sub_phase_order_names()
	if order.is_empty():
		return Result.failure("skip_sub_phase: working_sub_phase_order 未初始化")
	var last_sub_phase: String = str(order[order.size() - 1])
	if state.sub_phase == last_sub_phase:
		var player := state.get_player(command.actor)
		var required := MandatoryActionsRulesClass.get_required_mandatory_actions(player)
		if not required.is_empty():
			if not (state.round_state is Dictionary):
				return Result.failure("round_state 类型错误（期望 Dictionary）")
			if not state.round_state.has("mandatory_actions_completed"):
				return Result.failure("skip_sub_phase: round_state.mandatory_actions_completed 缺失")
			var mac_val = state.round_state["mandatory_actions_completed"]
			if not (mac_val is Dictionary):
				return Result.failure("skip_sub_phase: round_state.mandatory_actions_completed 类型错误（期望 Dictionary）")
			var mac: Dictionary = mac_val
			if not mac.has(command.actor):
				return Result.failure("skip_sub_phase: mandatory_actions_completed 缺少玩家 key: %d" % command.actor)
			var completed_val = mac[command.actor]
			if not (completed_val is Array):
				return Result.failure("skip_sub_phase: mandatory_actions_completed[%d] 类型错误（期望 Array）" % command.actor)
			var completed: Array = completed_val

			var missing: Array[String] = []
			for action_id in required:
				if not completed.has(action_id):
					missing.append(action_id)
			if not missing.is_empty():
				return Result.failure("存在未完成的强制动作，不能确认结束: %s" % ", ".join(missing))

	return Result.success()

func _apply_changes(state: GameState, command: Command) -> Result:
	if phase_manager == null:
		return Result.failure("skip_sub_phase: phase_manager 未注入")

	var order := phase_manager.get_working_sub_phase_order_names()
	if order.is_empty():
		return Result.failure("skip_sub_phase: working_sub_phase_order 未初始化")
	var last_sub_phase: String = str(order[order.size() - 1])

	# 在最后子阶段：等价于“确认结束”（结束该玩家 Working 回合）
	if state.sub_phase == last_sub_phase:
		if not (state.round_state is Dictionary):
			return Result.failure("round_state 类型错误（期望 Dictionary）")
		assert(state.round_state.has("sub_phase_passed"), "skip_sub_phase: round_state 缺少 sub_phase_passed")
		var passed_val = state.round_state["sub_phase_passed"]
		if not (passed_val is Dictionary):
			return Result.failure("round_state.sub_phase_passed 类型错误（期望 Dictionary）")
		var passed: Dictionary = passed_val
		assert(passed.has(command.actor) and (passed[command.actor] is bool), "skip_sub_phase: sub_phase_passed[%d] 缺失或类型错误（期望 bool）" % command.actor)
		passed[command.actor] = true
		state.round_state["sub_phase_passed"] = passed

	return phase_manager.advance_sub_phase(state)

func _generate_specific_events(old_state: GameState, new_state: GameState, command: Command) -> Array[Dictionary]:
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

	# 若从最后子阶段跳过，则视为结束该玩家的 Working 回合
	if old_state.phase == "Working" and phase_manager != null:
		var order := phase_manager.get_working_sub_phase_order_names()
		if not order.is_empty():
			var last_sub_phase: String = str(order[order.size() - 1])
			if old_state.sub_phase == last_sub_phase:
				events.append({
					"type": EventBus.EventType.PLAYER_TURN_ENDED,
					"data": {
						"player_id": command.actor,
						"action": "skip_sub_phase"
					}
				})

				var next_player_id := new_state.get_current_player_id()
				if next_player_id != command.actor:
					events.append({
						"type": EventBus.EventType.PLAYER_TURN_STARTED,
						"data": {
							"player_id": next_player_id
						}
					})

	return events
