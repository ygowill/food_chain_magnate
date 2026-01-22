# 跳过动作
# 玩家确认结束当前阶段/子阶段（UI 文案：确认结束）
class_name SkipAction
extends ActionExecutor

const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const MandatoryActionsRulesClass = preload("res://core/rules/working/mandatory_actions_rules.gd")

var phase_manager: PhaseManager = null

func _init(manager: PhaseManager = null) -> void:
	action_id = "skip"
	display_name = "确认结束"
	description = "确认结束当前阶段/子阶段"
	requires_actor = true
	is_mandatory = false
	phase_manager = manager

func _validate_specific(state: GameState, command: Command) -> Result:
	# OrderOfBusiness 必须完成顺序选择，不能通过“确认结束”跳过
	if state.phase == "OrderOfBusiness":
		return Result.failure("决定顺序阶段不能确认结束，请选择顺序")

	# Restructuring（hotseat 提交制）：禁止使用“确认结束”，避免误操作导致软锁
	if state.phase == "Restructuring" and int(state.round_number) > 1:
		return Result.failure("重组阶段不能确认结束，请使用“确认重组”提交公司结构")

	# 检查是否是当前玩家的回合
	var current_player_id := state.get_current_player_id()
	if command.actor != current_player_id:
		return Result.failure("不是你的回合，当前玩家: %d" % current_player_id)

	# Setup：必须先放置至少 1 个餐厅才能确认结束
	if state.phase == "Setup":
		if str(state.sub_phase) == "ReserveCards":
			return Result.failure("请先选择银行储备卡")
		var player := state.get_player(command.actor)
		if not player.has("restaurants") or not (player["restaurants"] is Array):
			return Result.failure("Setup: player.restaurants 缺失或类型错误（期望 Array）")
		var restaurants: Array = player["restaurants"]
		if restaurants.is_empty():
			return Result.failure("设置阶段必须先放置餐厅才能确认结束")

	# Working：只有在最后一个子阶段才能确认结束（结束该玩家的 Working 回合）
	if state.phase == "Working":
		var last_sub_phase := "PlaceRestaurants"
		if phase_manager != null:
			var order := phase_manager.get_working_sub_phase_order_names()
			if not order.is_empty():
				last_sub_phase = str(order[order.size() - 1])
		if state.sub_phase != last_sub_phase:
			return Result.failure("Working 阶段需要先完成所有子阶段才能确认结束（可使用“跳过子阶段”进入下一步）")

	# Train：存在缺货预支待培训时，相关玩家不能确认结束（否则会软锁）
	if state.phase == "Working" and state.sub_phase == "Train":
		var pending_total := int(EmployeeRulesClass.get_immediate_train_pending_total(state, command.actor))
		if pending_total > 0:
			return Result.failure("存在缺货预支待培训员工，必须先在 Train 子阶段完成培训后才能确认结束")

	# Working 最后子阶段：强制动作未完成时，相关玩家不能确认结束（否则会软锁）
	if state.phase == "Working":
		var last_sub_phase2 := "PlaceRestaurants"
		if phase_manager != null:
			var order2 := phase_manager.get_working_sub_phase_order_names()
			if not order2.is_empty():
				last_sub_phase2 = str(order2[order2.size() - 1])
		if state.sub_phase != last_sub_phase2:
			return Result.success()

		var player := state.get_player(command.actor)
		var required := MandatoryActionsRulesClass.get_required_mandatory_actions(player)
		if not required.is_empty():
			if not (state.round_state is Dictionary):
				return Result.failure("round_state 类型错误（期望 Dictionary）")
			if not state.round_state.has("mandatory_actions_completed"):
				return Result.failure("skip: round_state.mandatory_actions_completed 缺失")
			var mac_val = state.round_state["mandatory_actions_completed"]
			if not (mac_val is Dictionary):
				return Result.failure("skip: round_state.mandatory_actions_completed 类型错误（期望 Dictionary）")
			var mac: Dictionary = mac_val
			if not mac.has(command.actor):
				return Result.failure("skip: mandatory_actions_completed 缺少玩家 key: %d" % command.actor)
			var completed_val = mac[command.actor]
			if not (completed_val is Array):
				return Result.failure("skip: mandatory_actions_completed[%d] 类型错误（期望 Array）" % command.actor)
			var completed: Array = completed_val

			var missing: Array[String] = []
			for action_id in required:
				if not completed.has(action_id):
					missing.append(action_id)

			if not missing.is_empty():
				return Result.failure("存在未完成的强制动作，不能确认结束: %s" % ", ".join(missing))

	return Result.success()

func _apply_changes(state: GameState, command: Command) -> Result:
	var player_id := command.actor

	# 记录“已确认结束”（用于“所有玩家都确认结束 -> 自动推进子阶段/阶段”逻辑）
	# 注意：skip 不应写入 mandatory_actions_completed（强制动作完成记录）。
	if not (state.round_state is Dictionary):
		return Result.failure("round_state 类型错误（期望 Dictionary）")
	assert(state.round_state.has("sub_phase_passed"), "skip: round_state 缺少 sub_phase_passed")
	var passed_val = state.round_state["sub_phase_passed"]
	if not (passed_val is Dictionary):
		return Result.failure("round_state.sub_phase_passed 类型错误（期望 Dictionary）")
	var passed: Dictionary = passed_val
	assert(passed.has(player_id) and (passed[player_id] is bool), "skip: sub_phase_passed[%d] 缺失或类型错误（期望 bool）" % player_id)
	passed[player_id] = true
	state.round_state["sub_phase_passed"] = passed

	# Working：确认结束当前玩家的 Working 回合（由 PhaseManager 负责：最后子阶段 -> 下一玩家回合 / 全员结束 -> 离开 Working）
	if state.phase == "Working":
		if phase_manager == null:
			return Result.failure("skip: phase_manager 未注入")
		var adv0 := phase_manager.advance_sub_phase(state)
		if not adv0.ok:
			return adv0
		return Result.success().with_warnings(adv0.warnings)

	# 推进到下一位“未确认结束”的玩家；若全部已确认结束，则保持现状（等待自动推进阶段逻辑处理）
	var size := state.turn_order.size()
	if size <= 0:
		return Result.failure("turn_order 为空")

	var all_passed := true
	for pid in range(state.players.size()):
		assert(passed.has(pid) and (passed[pid] is bool), "skip: sub_phase_passed[%d] 缺失或类型错误（期望 bool）" % pid)
		if not bool(passed[pid]):
			all_passed = false
			break

	if all_passed and phase_manager != null:
		# 有子阶段：推进子阶段；无子阶段：推进主阶段（OrderOfBusiness 已在 validate 阻止）
		var adv: Result
		if not state.sub_phase.is_empty():
			adv = phase_manager.advance_sub_phase(state)
		else:
			adv = phase_manager.advance_phase(state)
		if not adv.ok:
			return adv
		return Result.success().with_warnings(adv.warnings)

	for offset in range(1, size + 1):
		var idx: int
		if state.phase == "Setup":
			# 初始餐厅放置：逆序轮转（从顺序轨最后一位开始）
			idx = state.current_player_index - offset
			while idx < 0:
				idx += size
		else:
			idx = state.current_player_index + offset
			if idx >= size:
				idx = idx % size
		var pid_val = state.turn_order[idx]
		if not (pid_val is int):
			continue
		var pid2: int = int(pid_val)
		if not bool(passed.get(pid2, false)):
			state.current_player_index = idx
			return Result.success()

	return Result.success()

func _generate_specific_events(old_state: GameState, new_state: GameState, command: Command) -> Array[Dictionary]:
	var events: Array[Dictionary] = []

	# 阶段变化事件（当“全员确认结束”触发自动推进时）
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

	# 玩家回合结束
	events.append({
		"type": EventBus.EventType.PLAYER_TURN_ENDED,
		"data": {
			"player_id": command.actor,
			"action": "skip"
		}
	})

	# 下一个玩家回合开始
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
