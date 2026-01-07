# 招聘动作
# 从员工池招聘员工到玩家公司
class_name RecruitAction
extends ActionExecutor

const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const CompanyStructureValidatorClass = preload("res://gameplay/validators/company_structure_validator.gd")
const RoundStateCountersClass = preload("res://core/utils/round_state_counters.gd")
const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")

func _init() -> void:
	action_id = "recruit"
	display_name = "招聘"
	description = "从员工池招聘员工"
	requires_actor = true
	is_mandatory = false
	allowed_phases = ["Working"]
	allowed_sub_phases = ["Recruit"]

func can_initiate(state: GameState, player_id: int) -> bool:
	if state == null:
		return true
	if state.get_current_player_id() != player_id:
		return false

	var limit := EmployeeRulesClass.get_recruit_limit_for_working(state, player_id)
	var used := EmployeeRulesClass.get_action_count(state, player_id, action_id)
	if used >= limit:
		return false

	var player := state.get_player(player_id)
	var banned: Array = []
	var banned_val = player.get("banned_employee_ids", [])
	if banned_val is Array:
		banned = banned_val

	var train_limit := EmployeeRulesClass.get_train_limit_for_working(state, player_id)
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
		if train_limit > 0 and pending_total < train_limit:
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

	# 检查员工池是否有库存
	var available: int = state.employee_pool.get(employee_type, 0)
	if available <= 0:
		# 允许“缺货预支”：当入门级员工堆为空时，仍可招聘，但必须在紧接的 Train 子阶段立刻培训。
		# 这里不制造“幽灵员工卡”，仅登记待清账；Train 时直接拿目标卡且不归还原卡，以保持供应池守恒不变量。
		var train_limit := EmployeeRulesClass.get_train_limit_for_working(state, command.actor)
		if train_limit <= 0:
			return Result.failure("员工池中没有 %s，且没有可用的培训员进行缺货预支" % employee_type)
		var pending_total := EmployeeRulesClass.get_immediate_train_pending_total(state, command.actor)
		if pending_total >= train_limit:
			return Result.failure("员工池中没有 %s，且缺货预支数量已达可培训上限 (%d)" % [employee_type, train_limit])

	# 检查是否是当前玩家的回合
	var current_player_id := state.get_current_player_id()
	if command.actor != current_player_id:
		return Result.failure("不是你的回合")

	# 检查本子阶段招聘次数（CEO 1 次 + 招聘员加成）
	var player := state.get_player(command.actor)

	# 禁用员工（ban_card）：不能再招聘该员工
	var banned_val = player.get("banned_employee_ids", [])
	if banned_val is Array:
		var banned: Array = banned_val
		if banned.find(employee_type) >= 0:
			return Result.failure("该员工已被禁用，不能招聘: %s" % employee_type)

	var limit := EmployeeRulesClass.get_recruit_limit_for_working(state, command.actor)
	var used := EmployeeRulesClass.get_action_count(state, command.actor, action_id)
	if used >= limit:
		return Result.failure("本子阶段招聘次数已用完: %d/%d" % [used, limit])

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

	var on_credit := int(state.employee_pool.get(employee_type, 0)) <= 0
	if on_credit:
		EmployeeRulesClass.add_immediate_train_pending(state, player_id, employee_type)
	else:
		# 从员工池取出
		var take_result := StateUpdater.take_from_pool(state, employee_type, 1)
		if not take_result.ok:
			return take_result

		# 添加到玩家（进入预备区）
		var add_result := StateUpdater.add_employee(state, player_id, employee_type, true)
		if not add_result.ok:
			return add_result

	EmployeeRulesClass.increment_action_count(state, player_id, action_id)

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
			warnings.append("里程碑触发失败(Recruit): %s" % ms.error)

	# 使用员工：按“招聘次数/容量”推导哪些招聘员必然被使用，并对每次推导出的使用调用一次 UseEmployee。
	var player_now := state.get_player(player_id)
	var total_cap := EmployeeRulesClass.get_recruit_limit_for_working(state, player_id)
	var seen := {}
	var candidates: Array[String] = []
	for emp_val in Array(player_now.get("employees", [])):
		if not (emp_val is String):
			continue
		var emp_id: String = str(emp_val)
		if emp_id.is_empty():
			continue
		if seen.has(emp_id):
			continue
		seen[emp_id] = true
		var def_val = EmployeeRegistryClass.get_def(emp_id)
		if def_val == null or not (def_val is EmployeeDef):
			continue
		var def: EmployeeDef = def_val
		if int(def.recruit_capacity) <= 0:
			continue
		if not def.has_usage_tag("use:recruit"):
			continue
		candidates.append(emp_id)
	candidates.sort()

	for emp_id in candidates:
		var def_val = EmployeeRegistryClass.get_def(emp_id)
		if def_val == null or not (def_val is EmployeeDef):
			continue
		var def: EmployeeDef = def_val
		var active_count := EmployeeRulesClass.count_active(player_now, emp_id)
		if active_count <= 0:
			continue
		var mult := EmployeeRulesClass.get_working_employee_multiplier(state, player_id, emp_id)
		var cap := active_count * int(def.recruit_capacity) * mult
		if cap <= 0:
			continue
		var cap_without := total_cap - cap
		var inferred := mini(cap, maxi(0, recruit_used_now - cap_without))

		var prev_read := RoundStateCountersClass.get_player_key_count(state.round_state, "inferred_use_employee_recruit", player_id, emp_id)
		if not prev_read.ok:
			return prev_read
		var prev: int = int(prev_read.value)
		var delta := inferred - prev
		if delta <= 0:
			continue

		var inc := RoundStateCountersClass.increment_player_key_count(state.round_state, "inferred_use_employee_recruit", player_id, emp_id, delta)
		if not inc.ok:
			return inc

		for _k in range(delta):
			var use_r := MilestoneSystemClass.process_event(state, "UseEmployee", {"player_id": player_id, "id": emp_id})
			if not use_r.ok:
				warnings.append("里程碑触发失败(UseEmployee/%s): %s" % [emp_id, use_r.error])

	var result := Result.success({
		"employee_type": employee_type,
		"player_id": player_id,
		"on_credit": on_credit
	}).with_warnings(warnings)
	if on_credit:
		result.with_warning("缺货预支：必须在 Train 子阶段紧接培训")
	return result

func _generate_specific_events(old_state: GameState, new_state: GameState, command: Command) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var employee_type_result := require_string_param(command, "employee_type")
	assert(employee_type_result.ok, "recruit 缺少/错误参数: employee_type")
	var employee_type: String = employee_type_result.value
	var on_credit := int(old_state.employee_pool.get(employee_type, 0)) <= 0

	events.append({
		"type": EventBus.EventType.EMPLOYEE_RECRUITED,
		"data": {
			"player_id": command.actor,
			"employee_type": employee_type,
			"to_reserve": true,
			"on_credit": on_credit
		}
	})

	return events
