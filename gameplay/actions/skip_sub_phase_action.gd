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
		if str(old_state.phase) == "Dinnertime":
			var report: Dictionary = {}
			if old_state.round_state is Dictionary:
				var v = Dictionary(old_state.round_state).get("dinnertime", null)
				if v is Dictionary:
					report = Dictionary(v).duplicate(true)
			events.append({
				"type": EventBus.EventType.DINNERTIME_REPORT,
				"data": {
					"round": old_state.round_number,
					"from_phase": str(old_state.phase),
					"to_phase": str(new_state.phase),
					"report": report,
				}
			})

		# Marketing 结算摘要：在离开 Marketing 时发射（便于 UI 日志从 EventBus.history 恢复）。
		# issue_tracker #48: per board 1 log entry, with details in event data.
		if str(old_state.phase) == "Marketing":
			events.append_array(_build_marketing_demand_generated_events(old_state))

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

func _build_marketing_demand_generated_events(marketing_state: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if marketing_state == null:
		return out
	if not (marketing_state.round_state is Dictionary):
		return out

	var marketing_val = Dictionary(marketing_state.round_state).get("marketing", null)
	if not (marketing_val is Dictionary):
		return out
	var marketing: Dictionary = marketing_val
	var processed_val = marketing.get("processed", null)
	if not (processed_val is Array):
		return out

	var houses_by_id: Dictionary = {}
	if marketing_state.map is Dictionary:
		var houses_val = Dictionary(marketing_state.map).get("houses", null)
		if houses_val is Dictionary:
			houses_by_id = houses_val

	for p_val in Array(processed_val):
		if not (p_val is Dictionary):
			continue
		var p: Dictionary = p_val

		var board_number := int(p.get("board_number", 0))
		var owner := int(p.get("owner", -1))
		var marketing_type := str(p.get("type", "")).strip_edges()
		var employee_type := str(p.get("employee_type", "")).strip_edges()
		var product := str(p.get("product", "")).strip_edges()
		var demands_added := int(p.get("demands_added", 0))

		var affected_ids: Array[String] = []
		var affected_numbers: Array[int] = []
		var affected_val = p.get("affected_houses", null)
		if affected_val is Array:
			for hid_val in Array(affected_val):
				var hid := str(hid_val).strip_edges()
				if hid.is_empty():
					continue
				affected_ids.append(hid)
				var hn := _try_get_house_number(houses_by_id, hid)
				if hn > 0:
					affected_numbers.append(hn)

		var pos_arr: Array = []
		var wp_val = p.get("world_pos", null)
		if wp_val is Vector2i:
			var wp: Vector2i = wp_val
			pos_arr = [wp.x, wp.y]
		elif wp_val is Array:
			pos_arr = Array(wp_val)

		out.append({
			"type": EventBus.EventType.DEMAND_GENERATED,
			"data": {
				"round": int(marketing_state.round_number),
				"player_id": owner,
				"board_number": board_number,
				"marketing_type": marketing_type,
				"employee_type": employee_type,
				"product": product,
				"demands_added": demands_added,
				"affected_houses": affected_ids,
				"affected_house_numbers": affected_numbers,
				"position": pos_arr,
			}
		})

	return out

func _try_get_house_number(houses_by_id: Dictionary, house_id: String) -> int:
	if houses_by_id == null or houses_by_id.is_empty():
		return -1
	var hid := str(house_id).strip_edges()
	if hid.is_empty():
		return -1
	if not houses_by_id.has(hid):
		return -1
	var h_val = houses_by_id.get(hid, null)
	if not (h_val is Dictionary):
		return -1
	var h: Dictionary = h_val
	var n_val = h.get("house_number", null)
	if n_val is int:
		return int(n_val)
	if n_val is float:
		var f: float = float(n_val)
		if f == floor(f):
			return int(f)
	return -1
