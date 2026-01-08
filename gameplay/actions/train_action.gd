# 培训动作（M3 起步）
# 将"待命"员工培训为更高级的职位。
class_name TrainAction
extends ActionExecutor

const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const CompanyStructureValidatorClass = preload("res://gameplay/validators/company_structure_validator.gd")
const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")
const RoundStateCountersClass = preload("res://core/utils/round_state_counters.gd")
const TrainPhaseStartCountsClass = preload("res://gameplay/actions/train/train_phase_start_counts.gd")
const TrainCompanyValidationClass = preload("res://gameplay/actions/train/train_company_validation.gd")
const TrainEmployeeUsageClass = preload("res://gameplay/actions/train/train_employee_usage.gd")

func _init() -> void:
	action_id = "train"
	display_name = "培训"
	description = "将待命员工培训为更高级职位"
	requires_actor = true
	is_mandatory = false
	allowed_phases = ["Working"]
	allowed_sub_phases = ["Train"]

func can_initiate(state: GameState, player_id: int) -> bool:
	if state == null:
		return true
	if state.get_current_player_id() != player_id:
		return false

	var pending_total := int(EmployeeRulesClass.get_immediate_train_pending_total(state, player_id))
	var limit := EmployeeRulesClass.get_train_limit_for_working(state, player_id)
	var used := EmployeeRulesClass.get_action_count(state, player_id, action_id)

	if limit <= 0:
		return pending_total > 0
	if used >= limit:
		return false
	if pending_total > 0:
		return true

	var player := state.get_player(player_id)
	var reserve_val = player.get("reserve_employees", [])
	if reserve_val is Array:
		var reserve: Array = reserve_val
		if not reserve.is_empty():
			return true

	var can_train_from_active := bool(player.get("train_from_active_same_color", false))
	if can_train_from_active:
		var active_val = player.get("employees", [])
		if active_val is Array:
			var active: Array = active_val
			if not active.is_empty():
				return true

	return false

func _validate_specific(state: GameState, command: Command) -> Result:
	# 检查是否是当前玩家的回合
	var current_player_id := state.get_current_player_id()
	if command.actor != current_player_id:
		return Result.failure("不是你的回合")

	var from_result := require_string_param(command, "from_employee")
	if not from_result.ok:
		return from_result
	var to_result := require_string_param(command, "to_employee")
	if not to_result.ok:
		return to_result
	var from_employee: String = from_result.value
	var to_employee: String = to_result.value

	# 检查训练次数
	var player := state.get_player(command.actor)
	# 禁用员工（ban_card）：不能再获得/培训该员工
	var banned_val = player.get("banned_employee_ids", [])
	if banned_val is Array:
		var banned: Array = banned_val
		if banned.find(to_employee) >= 0:
			return Result.failure("该员工已被禁用，不能培训: %s" % to_employee)

	var limit := EmployeeRulesClass.get_train_limit_for_working(state, command.actor)
	if limit <= 0:
		return Result.failure("没有可用的培训员")
	var used := EmployeeRulesClass.get_action_count(state, command.actor, action_id)
	if used >= limit:
		return Result.failure("本子阶段培训次数已用完: %d/%d" % [used, limit])

	# 仅允许培训“待命”员工
	assert(player.has("reserve_employees") and (player["reserve_employees"] is Array), "train: player.reserve_employees 缺失或类型错误（期望 Array[String]）")
	var reserve: Array = player["reserve_employees"]
	for i in range(reserve.size()):
		assert(reserve[i] is String, "train: player.reserve_employees[%d] 类型错误（期望 String）" % i)
	var pending_total := EmployeeRulesClass.get_immediate_train_pending_total(state, command.actor)
	var pending_count := EmployeeRulesClass.get_immediate_train_pending_count(state, command.actor, from_employee)
	var has_reserve := reserve.find(from_employee) >= 0
	var has_pending := pending_count > 0
	var has_active := EmployeeRulesClass.count_active(player, from_employee) > 0
	var can_train_from_active := bool(player.get("train_from_active_same_color", false))

	# 若存在“缺货预支”待培训员工，则必须优先清账（避免占用培训次数导致无法离开 Train 子阶段）
	if pending_total > 0 and not has_pending:
		return Result.failure("存在缺货预支待培训员工，必须先在 Train 子阶段完成培训")

	if not has_reserve and not has_pending and not has_active:
		return Result.failure("待命区不存在员工: %s" % from_employee)
	if has_active and not has_reserve and not has_pending and not can_train_from_active:
		return Result.failure("该员工在岗，且未启用“在岗同色培训”能力: %s" % from_employee)

	# 默认：不能在同一 Train 子阶段连续培训“本子阶段新培训得到”的员工（里程碑允许例外）
	var multi_val = player.get("multi_trainer_on_one", false)
	if not (multi_val is bool):
		return Result.failure("train: player.multi_trainer_on_one 类型错误（期望 bool）")
	var multi: bool = bool(multi_val)
	if not multi:
		# 默认：不能使用“本子阶段通过培训获得的职位”继续培训（由于按 employee_type 选择，无法区分具体卡，保守禁止链式培训）
		var gained_read := RoundStateCountersClass.get_player_key_count(state.round_state, "train_to_gained", command.actor, from_employee)
		if not gained_read.ok:
			return gained_read
		if int(gained_read.value) > 0:
			return Result.failure("默认规则下不应允许链式培训（%s -> %s）" % [from_employee, to_employee])

		var start_count_read := TrainPhaseStartCountsClass._get_train_phase_start_count(state, command.actor, reserve, from_employee)
		if not start_count_read.ok:
			return start_count_read
		var start_count: int = int(start_count_read.value)

		var used_from_read := RoundStateCountersClass.get_player_key_count(state.round_state, "train_from_used", command.actor, from_employee)
		if not used_from_read.ok:
			return used_from_read
		var used_from: int = int(used_from_read.value)

		if used_from >= start_count:
			return Result.failure("本子阶段不能连续培训同一员工（需要里程碑允许）: %s" % from_employee)

	# 目标职位必须有卡可用（当前仅检查最终职位堆）
	var available: int = state.employee_pool.get(to_employee, 0)
	if available <= 0:
		return Result.failure("员工池中没有 %s" % to_employee)

	# 公司结构校验（唯一员工约束等）- 校验培训后的目标员工
	var validator = CompanyStructureValidatorClass.new()
	var to_reserve := true
	if can_train_from_active and has_active and not has_reserve and not has_pending:
		# FIRST LEMONADE SOLD：在岗同色培训时，若旧员工未被使用，则新员工可立刻在岗
		var from_used := TrainEmployeeUsageClass._is_employee_used_before_training(state, command.actor, from_employee)
		to_reserve = from_used

		# 同色限制：不允许颜色变化
		var color_ok := TrainCompanyValidationClass._is_same_role_color(from_employee, to_employee)
		if not color_ok.ok:
			return color_ok
		if not bool(color_ok.value):
			return Result.failure("在岗培训不允许改变颜色: %s -> %s" % [from_employee, to_employee])

		if not to_reserve:
			var cap_check := TrainCompanyValidationClass._validate_company_structure_replacing_active(state, command.actor, from_employee, to_employee)
			if not cap_check.ok:
				return cap_check

	var validation: Result = validator.validate(state, command.actor, {
		"employee_id": to_employee,
		"to_reserve": to_reserve
	})
	if not validation.ok:
		return validation

	return Result.success()

func _apply_changes(state: GameState, command: Command) -> Result:
	var player_id: int = command.actor
	var from_result := require_string_param(command, "from_employee")
	if not from_result.ok:
		return from_result
	var to_result := require_string_param(command, "to_employee")
	if not to_result.ok:
		return to_result
	var from_employee: String = from_result.value
	var to_employee: String = to_result.value

	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return Result.failure("train: player 类型错误: players[%d]（期望 Dictionary）" % player_id)
	var player: Dictionary = player_val

	var multi_val = player.get("multi_trainer_on_one", false)
	if not (multi_val is bool):
		return Result.failure("train: player.multi_trainer_on_one 类型错误（期望 bool）")
	var multi: bool = bool(multi_val)
	var can_train_from_active := bool(player.get("train_from_active_same_color", false))
	var from_used_before := TrainEmployeeUsageClass._is_employee_used_before_training(state, player_id, from_employee)
	var target_to_reserve := true
	if can_train_from_active and EmployeeRulesClass.count_active(player, from_employee) > 0 and int(EmployeeRulesClass.get_immediate_train_pending_count(state, player_id, from_employee)) <= 0:
		target_to_reserve = from_used_before
	if not multi:
		var reserve_read := TrainPhaseStartCountsClass._require_player_string_array(player, "reserve_employees", "train: player.reserve_employees")
		if not reserve_read.ok:
			return reserve_read
		var reserve: Array = reserve_read.value
		var write_start := TrainPhaseStartCountsClass._ensure_train_phase_start_counts(state, player_id, reserve)
		if not write_start.ok:
			return write_start

		var inc_used := RoundStateCountersClass.increment_player_key_count(state.round_state, "train_from_used", player_id, from_employee, 1)
		if not inc_used.ok:
			return inc_used

	var use_pending := EmployeeRulesClass.get_immediate_train_pending_count(state, player_id, from_employee) > 0
	if use_pending:
		var consumed := EmployeeRulesClass.consume_immediate_train_pending(state, player_id, from_employee)
		if not consumed:
			return Result.failure("缺货预支待清账员工不存在: %s" % from_employee)
	else:
		# 优先从待命区移除；否则允许从在岗移除（FIRST LEMONADE SOLD）
		var removed := StateUpdater.remove_from_array(state.players[player_id], "reserve_employees", from_employee)
		if not removed:
			if can_train_from_active:
				removed = StateUpdater.remove_from_array(state.players[player_id], "employees", from_employee)
		if not removed:
			return Result.failure("待命区/在岗区不存在员工: %s" % from_employee)

		# 原卡回供应区（简化：假设培训会归还原卡）
		StateUpdater.return_to_pool(state, from_employee, 1)

	# 取出目标员工
	var take_result := StateUpdater.take_from_pool(state, to_employee, 1)
	if not take_result.ok:
		return take_result

	# 培训后的员工：默认进待命；FIRST LEMONADE SOLD 且旧员工未使用时可直接在岗
	var add_result := StateUpdater.add_employee(state, player_id, to_employee, target_to_reserve)
	if not add_result.ok:
		return add_result

	# 记录“本子阶段通过培训获得的职位类型”，用于默认禁止链式培训（multi_trainer_on_one 例外）
	var gained_write := RoundStateCountersClass.increment_player_key_count(state.round_state, "train_to_gained", player_id, to_employee, 1)
	if not gained_write.ok:
		return gained_write

	EmployeeRulesClass.increment_action_count(state, player_id, action_id)

	# 记录训练事件（供模块在 Train 子阶段注入“训练后可选动作窗口”等逻辑使用）
	if state.round_state is Dictionary:
		if not state.round_state.has("train_events"):
			state.round_state["train_events"] = []
		var te_val = state.round_state.get("train_events", null)
		if not (te_val is Array):
			return Result.failure("train: round_state.train_events 类型错误（期望 Array）")
		var train_events: Array = te_val
		train_events.append({
			"player_id": player_id,
			"from_employee": from_employee,
			"to_employee": to_employee,
			"from_pending": use_pending,
		})
		state.round_state["train_events"] = train_events

	var ms := MilestoneSystemClass.process_event(state, "Train", {"player_id": player_id})

	# 使用员工：按“培训次数/容量”推导哪些培训员必然被使用，并对每次推导出的使用调用一次 UseEmployee。
	var warnings: Array[String] = []
	var inferred_use := TrainEmployeeUsageClass.apply_inferred_use_employee_train(state, player_id)
	if not inferred_use.ok:
		return inferred_use
	warnings.append_array(inferred_use.warnings)

	var result := Result.success({
		"player_id": player_id,
		"from_employee": from_employee,
		"to_employee": to_employee,
		"from_pending": use_pending
	})
	if not ms.ok:
		result.with_warning("里程碑触发失败(Train): %s" % ms.error)
	result.with_warnings(warnings)
	return result

func _generate_specific_events(old_state: GameState, new_state: GameState, command: Command) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var from_result := require_string_param(command, "from_employee")
	assert(from_result.ok, "train 缺少/错误参数: from_employee")
	var to_result := require_string_param(command, "to_employee")
	assert(to_result.ok, "train 缺少/错误参数: to_employee")
	events.append({
		"type": EventBus.EventType.EMPLOYEE_TRAINED,
		"data": {
			"player_id": command.actor,
			"from_employee": from_result.value,
			"to_employee": to_result.value
		}
	})
	return events
