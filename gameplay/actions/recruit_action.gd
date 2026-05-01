# 招聘动作
# 从员工池招聘员工到玩家公司
class_name RecruitAction
extends ActionExecutor

const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const CompanyStructureValidatorClass = preload("res://gameplay/validators/company_structure_validator.gd")
const RoundStateCountersClass = preload("res://core/utils/round_state_counters.gd")
const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")
const EmployeeUsageHelperClass = preload("res://gameplay/actions/employee_usage_helper.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const StaffStateClass = preload("res://core/state/staff_state.gd")

static func _compute_min_steps_to_any_in_stock_target(
	from_employee: String,
	max_steps: int,
	employee_pool: Dictionary,
	banned: Array
) -> int:
	if from_employee.is_empty():
		return -1
	if max_steps <= 0:
		return -1
	if not EmployeeRegistryClass.is_loaded():
		return -1

	var visited := {}
	visited[from_employee] = 0
	var queue: Array[String] = [from_employee]
	var qi := 0

	while qi < queue.size():
		var cur := queue[qi]
		qi += 1
		var dist := int(visited.get(cur, 0))
		if dist >= max_steps:
			continue

		var def_val = EmployeeRegistryClass.get_def(cur)
		if def_val == null or not (def_val is EmployeeDef):
			continue
		var def: EmployeeDef = def_val
		for nxt_val in def.train_to:
			var nxt := str(nxt_val)
			if nxt.is_empty():
				continue
			if visited.has(nxt):
				continue
			var ndist := dist + 1
			if ndist > max_steps:
				continue
			visited[nxt] = ndist

			# 目标职位必须有卡可用；中间卡不要求有库存（multi-step/hire+immediately train 规则）
			if not banned.is_empty() and banned.find(nxt) >= 0:
				queue.append(nxt)
				continue
			if int(employee_pool.get(nxt, 0)) > 0:
				return ndist

			queue.append(nxt)

	return -1

func _init() -> void:
	action_id = "recruit"
	display_name = "招聘"
	description = "从员工池招聘员工"
	requires_actor = true
	is_mandatory = false
	allowed_phases = [DefsClass.PHASE_WORKING]
	allowed_sub_phases = [DefsClass.SUB_PHASE_RECRUIT]

func can_initiate(state: GameState, player_id: int) -> bool:
	if state == null:
		return true
	if state.get_current_player_id() != player_id:
		return false

	var limit_read := EmployeeRulesClass.try_get_recruit_limit_for_working(state, player_id)
	if not limit_read.ok:
		return false
	var limit := int(limit_read.value)
	var used_read := EmployeeRulesClass.try_get_action_count(state, player_id, action_id)
	if not used_read.ok:
		return false
	var used := int(used_read.value)
	if used >= limit:
		return false
	var provider_read := EmployeeRulesClass.try_resolve_recruit_provider(state, player_id)
	if not provider_read.ok:
		return false

	var player := state.get_player(player_id)
	var banned: Array = []
	var banned_val = player.get("banned_employee_ids", [])
	if banned_val is Array:
		banned = banned_val

	var train_limit_read := EmployeeRulesClass.try_get_train_limit_for_working(state, player_id)
	if not train_limit_read.ok:
		return false
	var train_limit := int(train_limit_read.value)
	var pending_total := int(EmployeeRulesClass.get_immediate_train_pending_total(state, player_id))

	for emp_val in state.employee_pool.keys():
		if not (emp_val is String):
			continue
		var emp_id: String = str(emp_val)
		if emp_id.is_empty():
			continue
		if not EmployeeRulesClass.is_entry_level(emp_id):
			continue
		if banned.has(emp_id):
			continue

		var available := int(state.employee_pool.get(emp_id, 0))
		if available > 0:
			return true
		if train_limit > 0:
			var max_steps_one := EmployeeRulesClass.get_max_train_steps_for_single_employee_for_working(state, player_id)
			var steps_min := _compute_min_steps_to_any_in_stock_target(emp_id, maxi(1, max_steps_one), state.employee_pool, banned)
			if steps_min > 0 and pending_total + steps_min <= train_limit:
				return true

	return false

func _validate_specific(state: GameState, command: Command) -> Result:
	# 检查必需参数
	var employee_type_result := require_string_param(command, "employee_type")
	if not employee_type_result.ok:
		return employee_type_result
	var employee_type: String = employee_type_result.value

	# 仅允许招聘入门级员工（其余通过培训获得）
	if not EmployeeRulesClass.is_entry_level(employee_type):
		return Result.failure("只能招聘入门级员工: %s" % employee_type)

	# 员工必须属于本局的员工池（区分“不在本局池中”与“池中缺货可预支”）
	if not state.employee_pool.has(employee_type):
		return Result.failure("该员工不在本局员工池中: %s" % employee_type)

	var player := state.get_player(command.actor)
	var banned: Array = []
	var banned_val = player.get("banned_employee_ids", [])
	if banned_val is Array:
		banned = banned_val

	# 检查员工池是否有库存
	var available: int = state.employee_pool.get(employee_type, 0)
	if available <= 0:
		# 允许“缺货预支”：当入门级员工堆为空时，仍可招聘，但必须在紧接的 Train 子阶段立刻培训。
		# 这里不制造“幽灵员工卡”，仅登记待清账；Train 时直接拿目标卡且不归还原卡，以保持供应池守恒不变量。
		var train_limit_read := EmployeeRulesClass.try_get_train_limit_for_working(state, command.actor)
		if not train_limit_read.ok:
			return train_limit_read
		var train_limit := int(train_limit_read.value)
		if train_limit <= 0:
			return Result.failure("员工池中没有 %s，且没有可用的培训员进行缺货预支" % employee_type)
		var max_steps_read := EmployeeRulesClass.try_get_max_train_steps_for_single_employee_for_working(state, command.actor)
		if not max_steps_read.ok:
			return max_steps_read
		var max_steps_one := int(max_steps_read.value)
		var steps_min := _compute_min_steps_to_any_in_stock_target(employee_type, maxi(1, max_steps_one), state.employee_pool, banned)
		if steps_min <= 0:
			return Result.failure("员工池中没有 %s，且无法找到可用培训目标用于缺货预支" % employee_type)
		var pending_total_read := EmployeeRulesClass.try_get_immediate_train_pending_total(state, command.actor)
		if not pending_total_read.ok:
			return pending_total_read
		var pending_total := int(pending_total_read.value)
		if pending_total + steps_min > train_limit:
			return Result.failure("员工池中没有 %s，且缺货预支数量已达可培训上限 (%d)" % [employee_type, train_limit])

	# 检查是否是当前玩家的回合
	var current_player_id := state.get_current_player_id()
	if command.actor != current_player_id:
		return Result.failure("不是你的回合")

	# 检查本子阶段招聘次数（CEO 1 次 + 招聘员加成）
	# 禁用员工（ban_card）：不能再招聘该员工
	if banned.find(employee_type) >= 0:
		return Result.failure("该员工已被禁用，不能招聘: %s" % employee_type)

	var limit_read := EmployeeRulesClass.try_get_recruit_limit_for_working(state, command.actor)
	if not limit_read.ok:
		return limit_read
	var limit := int(limit_read.value)
	var used_read := EmployeeRulesClass.try_get_action_count(state, command.actor, action_id)
	if not used_read.ok:
		return used_read
	var used := int(used_read.value)
	if used >= limit:
		return Result.failure("本子阶段招聘次数已用完: %d/%d" % [used, limit])

	var staff_id := -1
	if command.params.has("staff_id"):
		var staff_id_result := require_int_param(command, "staff_id")
		if not staff_id_result.ok:
			return staff_id_result
		staff_id = int(staff_id_result.value)
		if staff_id <= 0:
			return Result.failure("staff_id 必须 > 0，实际: %d" % staff_id)
	var provider_read := EmployeeRulesClass.try_resolve_recruit_provider(state, command.actor, staff_id)
	if not provider_read.ok:
		return provider_read

	# 公司结构校验（唯一员工约束等）
	var validator = CompanyStructureValidatorClass.new()
	var validation: Result = validator.validate(state, command.actor, {
		"employee_id": employee_type,
		"to_reserve": true
	})
	if not validation.ok:
		return validation

	return Result.success()

func _apply_changes(state: GameState, command: Command) -> Result:
	var employee_type_result := require_string_param(command, "employee_type")
	if not employee_type_result.ok:
		return employee_type_result
	var employee_type: String = employee_type_result.value
	var player_id: int = command.actor
	var warnings: Array[String] = []
	var action_count_read := EmployeeRulesClass.try_get_action_count(state, player_id, action_id)
	if not action_count_read.ok:
		return action_count_read

	var staff_id := -1
	if command.params.has("staff_id"):
		var staff_id_result := require_int_param(command, "staff_id")
		if not staff_id_result.ok:
			return staff_id_result
		staff_id = int(staff_id_result.value)
		if staff_id <= 0:
			return Result.failure("staff_id 必须 > 0，实际: %d" % staff_id)
	var provider_read := EmployeeRulesClass.try_resolve_recruit_provider(state, player_id, staff_id)
	if not provider_read.ok:
		return provider_read
	var provider: Dictionary = provider_read.value
	var recruiter_staff_id := int(provider.get("staff_id", -1))
	var recruiter_employee_type := str(provider.get("employee_type", "")).strip_edges()
	if recruiter_staff_id <= 0 or recruiter_employee_type.is_empty():
		return Result.failure("recruit: 招聘员工解析结果无效: %s" % str(provider))

	var on_credit := int(state.employee_pool.get(employee_type, 0)) <= 0
	if on_credit:
		var add_pending := EmployeeRulesClass.try_add_immediate_train_pending(state, player_id, employee_type)
		if not add_pending.ok:
			return add_pending
	else:
		# 从员工池取出
		var take_result := StateUpdater.take_from_pool(state, employee_type, 1)
		if not take_result.ok:
			return take_result

		# 添加到玩家（进入预备区）
		var add_result := StateUpdater.add_employee(state, player_id, employee_type, true)
		if not add_result.ok:
			return add_result

	var inc_action := EmployeeRulesClass.try_increment_action_count(state, player_id, action_id)
	if not inc_action.ok:
		return inc_action

	# 记录本回合 Recruit 子阶段的招聘次数（用于 Payday 薪资折扣计算；不会在子阶段切换时清空）
	var inc_result := RoundStateCountersClass.increment_player_count(
		state.round_state, "recruit_used", player_id, 1
	)
	if not inc_result.ok:
		return inc_result
	var recruit_used_now: int = int(inc_result.value)
	if recruit_used_now == 3:
		var ms := MilestoneSystemClass.process_event(state, "Recruit", {
			"player_id": player_id,
			"count": recruit_used_now,
		})
		if not ms.ok:
			return Result.failure("里程碑触发失败(Recruit): %s" % ms.error).with_warnings(warnings).with_warnings(ms.warnings)
		warnings.append_array(ms.warnings)

	var use_staff := StaffStateClass.increment_staff_track_usage(state, recruiter_staff_id, "recruit", 1)
	if not use_staff.ok:
		return use_staff
	var use_employee := EmployeeUsageHelperClass.apply_use_employee_event(state, player_id, recruiter_employee_type)
	if not use_employee.ok:
		return use_employee
	warnings.append_array(use_employee.warnings)

	var result := Result.success({
		"employee_type": employee_type,
		"player_id": player_id,
		"on_credit": on_credit,
		"recruiter_staff_id": recruiter_staff_id,
		"recruiter_employee_type": recruiter_employee_type
	}).with_warnings(warnings)
	if on_credit:
		result.with_warning("缺货预支：必须在 Train 子阶段紧接培训")
	return result

func _generate_specific_events(old_state: GameState, new_state: GameState, command: Command) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var employee_type_result := require_string_param(command, "employee_type")
	if not employee_type_result.ok:
		return events
	var employee_type: String = str(employee_type_result.value).strip_edges()
	if employee_type.is_empty():
		return events
	var on_credit := int(old_state.employee_pool.get(employee_type, 0)) <= 0
	var recruiter_staff_id := -1
	var provider_read := EmployeeRulesClass.try_resolve_recruit_provider(
		old_state,
		command.actor,
		int(command.params.get("staff_id", -1))
	)
	if provider_read.ok:
		var provider: Dictionary = provider_read.value
		recruiter_staff_id = int(provider.get("staff_id", -1))

	events.append({
		"type": EventBus.EventType.EMPLOYEE_RECRUITED,
		"data": {
			"player_id": command.actor,
			"employee_type": employee_type,
			"to_reserve": true,
			"on_credit": on_credit,
			"recruiter_staff_id": recruiter_staff_id
		}
	})

	return events
