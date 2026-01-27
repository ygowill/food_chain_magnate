# 跳过动作
# 玩家确认结束当前阶段/子阶段（UI 文案：确认结束）
class_name SkipAction
extends ActionExecutor

const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const MandatoryActionsRulesClass = preload("res://core/rules/working/mandatory_actions_rules.gd")
const CommandRunnerClass = preload("res://core/engine/game_engine/command_runner.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")

var phase_manager: PhaseManager = null

func _init(manager: PhaseManager = null) -> void:
	action_id = ActionIdsClass.SKIP
	display_name = "确认结束"
	description = "确认结束当前阶段/子阶段"
	requires_actor = true
	is_mandatory = false
	phase_manager = manager

func _validate_specific(state: GameState, command: Command) -> Result:
	# OrderOfBusiness 必须完成顺序选择，不能通过“确认结束”跳过
	if state.phase == DefsClass.PHASE_ORDER_OF_BUSINESS:
		return Result.failure("决定顺序阶段不能确认结束，请选择顺序")

	# Restructuring（hotseat 提交制）：禁止使用“确认结束”，避免误操作导致软锁
	if state.phase == DefsClass.PHASE_RESTRUCTURING and int(state.round_number) > 1:
		return Result.failure("重组阶段不能确认结束，请使用“确认重组”提交公司结构")

	# 检查是否是当前玩家的回合
	var current_player_id := state.get_current_player_id()
	if command.actor != current_player_id:
		return Result.failure("不是你的回合，当前玩家: %d" % current_player_id)

	# Setup：必须先放置至少 1 个餐厅才能确认结束
	if state.phase == DefsClass.PHASE_SETUP:
		if str(state.sub_phase) == "ReserveCards":
			return Result.failure("请先选择银行储备卡")
		var player := state.get_player(command.actor)
		if not player.has("restaurants") or not (player["restaurants"] is Array):
			return Result.failure("Setup: player.restaurants 缺失或类型错误（期望 Array）")
		var restaurants: Array = player["restaurants"]
		if restaurants.is_empty():
			return Result.failure("设置阶段必须先放置餐厅才能确认结束")

	# Working：只有在最后一个子阶段才能确认结束（结束该玩家的 Working 回合）
	if state.phase == DefsClass.PHASE_WORKING:
		var last_sub_phase := DefsClass.SUB_PHASE_PLACE_RESTAURANTS
		if phase_manager != null:
			var order := phase_manager.get_working_sub_phase_order_names()
			if not order.is_empty():
				last_sub_phase = str(order[order.size() - 1])
		if state.sub_phase != last_sub_phase:
			return Result.failure("Working 阶段需要先完成所有子阶段才能确认结束（可使用“跳过子阶段”进入下一步）")

	# Train：存在缺货预支待培训时，相关玩家不能确认结束（否则会软锁）
	if state.phase == DefsClass.PHASE_WORKING and state.sub_phase == DefsClass.SUB_PHASE_TRAIN:
		var pending_total := int(EmployeeRulesClass.get_immediate_train_pending_total(state, command.actor))
		if pending_total > 0:
			return Result.failure("存在缺货预支待培训员工，必须先在 Train 子阶段完成培训后才能确认结束")

	# Working 最后子阶段：强制动作未完成时，相关玩家不能确认结束（否则会软锁）
	if state.phase == DefsClass.PHASE_WORKING:
		var last_sub_phase2 := DefsClass.SUB_PHASE_PLACE_RESTAURANTS
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
	if state.phase == DefsClass.PHASE_WORKING:
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
		if state.phase == DefsClass.PHASE_SETUP:
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

	# 先记录“玩家确认结束/结束回合”，再记录子阶段/阶段推进事件。
	# 这样可保证日志时间线符合语义顺序（玩家先结束 -> 系统推进）。
	events.append({
		"type": EventBus.EventType.PLAYER_TURN_ENDED,
		"data": {
			"player_id": command.actor,
			"action": ActionIdsClass.SKIP
		}
	})

	# 子阶段变化事件（Working：PlaceRestaurants -> Recruit 等）
	if old_state.sub_phase != new_state.sub_phase and not new_state.sub_phase.is_empty():
		events.append({
			"type": EventBus.EventType.SUB_PHASE_CHANGED,
			"data": {
				"old_sub_phase": old_state.sub_phase,
				"new_sub_phase": new_state.sub_phase
			}
		})

	# 阶段变化事件（当“全员确认结束”触发自动推进时）
	if old_state.phase != new_state.phase:
		if str(old_state.phase) == DefsClass.PHASE_DINNERTIME:
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
			events.append_array(CommandRunnerClass.build_food_sold_events_from_dinnertime_report(old_state, report))

		if str(old_state.phase) == DefsClass.PHASE_PAYDAY:
			var report_payday: Dictionary = {}
			if new_state.round_state is Dictionary:
				var v2 = Dictionary(new_state.round_state).get("payday", null)
				if v2 is Dictionary:
					report_payday = Dictionary(v2).duplicate(true)
			events.append({
				"type": EventBus.EventType.PAYDAY_REPORT,
				"data": {
					"round": old_state.round_number,
					"from_phase": str(old_state.phase),
					"to_phase": str(new_state.phase),
					"report": report_payday,
				}
			})

		# Marketing 结算摘要：在离开 Marketing 时发射（便于 UI 日志从 EventBus.history 恢复）。
		# issue_tracker #48: per board 1 log entry, with details in event data.
		if str(old_state.phase) == DefsClass.PHASE_MARKETING:
			events.append_array(CommandRunnerClass.build_marketing_demand_generated_events(old_state))
			events.append_array(CommandRunnerClass.build_marketing_expired_events(old_state))

		if str(old_state.phase) == DefsClass.PHASE_CLEANUP:
			events.append_array(CommandRunnerClass.build_cleanup_inventory_discarded_events(old_state))

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

	# 下一个玩家回合开始
	var next_player_id := new_state.get_current_player_id()
	if next_player_id != command.actor and _should_emit_player_turn_started(str(new_state.phase)):
		events.append({
			"type": EventBus.EventType.PLAYER_TURN_STARTED,
			"data": {
				"player_id": next_player_id
			}
		})

	return events

static func _should_emit_player_turn_started(phase_name: String) -> bool:
	match str(phase_name).strip_edges():
		DefsClass.PHASE_DINNERTIME:
			return false
		DefsClass.PHASE_MARKETING:
			return false
		DefsClass.PHASE_CLEANUP:
			return false
		DefsClass.PHASE_GAME_OVER:
			return false
		_:
			return true
