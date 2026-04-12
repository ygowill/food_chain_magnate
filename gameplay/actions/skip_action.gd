# 跳过动作
# 玩家确认结束当前阶段/子阶段（UI 文案：确认结束）
class_name SkipAction
extends ActionExecutor

const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const MandatoryActionsRulesClass = preload("res://core/rules/working/mandatory_actions_rules.gd")
const CommandRunnerClass = preload("res://core/engine/game_engine/command_runner.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")
const PlayerStateAccessClass = preload("res://core/state/player_state_access.gd")
const OnlinePhaseInteractionClass = preload("res://core/utils/online_phase_interaction.gd")
const RoundStatePlayerStringListsClass = preload("res://core/utils/round_state_player_string_lists.gd")
const RoundStateSubPhasePassedClass = preload("res://core/utils/round_state_sub_phase_passed.gd")

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
	if OnlinePhaseInteractionClass.is_online_parallel_payday(state):
		if command.actor < 0 or command.actor >= state.players.size():
			return Result.failure("无效玩家: %d" % command.actor)
		if not (state.round_state is Dictionary):
			return Result.failure("round_state 类型错误（期望 Dictionary）")
		var passed_read := RoundStateSubPhasePassedClass.require_all_player_flags(state.round_state, state.players.size(), "skip")
		if not passed_read.ok:
			return passed_read
		var passed: Dictionary = passed_read.value
		if bool(passed.get(command.actor, false)):
			return Result.failure("你已经确认结束发薪日")
	elif command.actor != current_player_id:
		return Result.failure("不是你的回合，当前玩家: %d" % current_player_id)

	# Setup：必须先放置至少 1 个餐厅才能确认结束
	if state.phase == DefsClass.PHASE_SETUP:
		if str(state.sub_phase) == DefsClass.SUB_PHASE_RESERVE_CARDS:
			return Result.failure("请先选择银行储备卡")
		var player := state.get_player(command.actor)
		var restaurants_read := PlayerStateAccessClass.require_restaurants(player, "player", "Setup")
		if not restaurants_read.ok:
			return restaurants_read
		var restaurants: Array = restaurants_read.value
		if restaurants.is_empty() and not bool(player.get("forfeited", false)):
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
			var completed_read := RoundStatePlayerStringListsClass.require_player_string_array(
				state.round_state,
				"mandatory_actions_completed",
				command.actor,
				"skip"
			)
			if not completed_read.ok:
				return completed_read
			var completed: Array = completed_read.value

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
	var set_passed := RoundStateSubPhasePassedClass.set_player_passed(state.round_state, player_id, true, "skip")
	if not set_passed.ok:
		return set_passed
	var passed_read := RoundStateSubPhasePassedClass.require_all_player_flags(state.round_state, state.players.size(), "skip")
	if not passed_read.ok:
		return passed_read
	var passed: Dictionary = passed_read.value

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

	if OnlinePhaseInteractionClass.is_online_parallel_payday(state):
		return Result.success()

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
	var should_emit_turn_started := _should_emit_player_turn_started(str(new_state.phase))
	if OnlinePhaseInteractionClass.is_online_parallel_payday(old_state) and str(new_state.phase) == DefsClass.PHASE_PAYDAY:
		should_emit_turn_started = false
	if next_player_id != command.actor and should_emit_turn_started:
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
