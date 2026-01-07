# 生产食物动作（GET_FOOD 子阶段）
# 厨师/主厨生产食物到玩家库存
# 生产信息从 EmployeeRegistry 的 JSON 定义中读取
class_name ProduceFoodAction
extends ActionExecutor

const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")
const RoundStateCountersClass = preload("res://core/utils/round_state_counters.gd")

func _init() -> void:
	action_id = "produce_food"
	display_name = "生产食物"
	description = "使用厨师/主厨生产食物"
	requires_actor = true
	is_mandatory = false
	allowed_phases = ["Working"]
	allowed_sub_phases = ["GetFood"]

func can_initiate(state: GameState, player_id: int) -> bool:
	if state == null:
		return true
	if state.get_current_player_id() != player_id:
		return false

	var player := state.get_player(player_id)
	var employees_val = player.get("employees", [])
	if not (employees_val is Array):
		return true
	var employees: Array = employees_val

	var seen := {}
	for emp_val in employees:
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
		if not def.can_produce():
			continue

		var active_count := EmployeeRulesClass.count_active_for_working(state, player, player_id, emp_id)
		if active_count <= 0:
			continue

		var used_result := RoundStateCountersClass.get_player_key_count(
			state.round_state, "production_counts", player_id, emp_id
		)
		if not used_result.ok:
			return true
		if int(used_result.value) < active_count:
			return true

	return false

func _validate_specific(state: GameState, command: Command) -> Result:
	# 检查必需参数
	var employee_type_result := require_string_param(command, "employee_type")
	if not employee_type_result.ok:
		return employee_type_result
	var employee_type: String = employee_type_result.value

	# 从 EmployeeRegistry 获取员工定义
	var emp_def = EmployeeRegistryClass.get_def(employee_type)
	if emp_def == null:
		return Result.failure("未知的员工类型: %s" % employee_type)

	# 检查该员工是否能生产食物
	if not emp_def.can_produce():
		return Result.failure("该员工类型不能生产食物: %s" % employee_type)

	# 检查是否是当前玩家的回合
	var current_player_id := state.get_current_player_id()
	if command.actor != current_player_id:
		return Result.failure("不是你的回合")

	# 检查玩家是否拥有该类型的厨师
	var player := state.get_player(command.actor)
	var active_count := EmployeeRulesClass.count_active_for_working(state, player, command.actor, employee_type)
	if active_count <= 0:
		return Result.failure("你没有激活的 %s" % employee_type)

	# 检查本子阶段该厨师类型的生产次数
	var used_result := RoundStateCountersClass.get_player_key_count(
		state.round_state, "production_counts", command.actor, employee_type
	)
	if not used_result.ok:
		return used_result
	var used := int(used_result.value)
	if used >= active_count:
		return Result.failure("所有 %s 本子阶段已生产完毕: %d/%d" % [employee_type, used, active_count])

	return Result.success()

func _apply_changes(state: GameState, command: Command) -> Result:
	var employee_type_result := require_string_param(command, "employee_type")
	if not employee_type_result.ok:
		return employee_type_result
	var employee_type: String = employee_type_result.value
	var player_id: int = command.actor
	var warnings: Array[String] = []

	# 从 EmployeeRegistry 获取生产信息
	var emp_def = EmployeeRegistryClass.get_def(employee_type)
	if emp_def == null or not emp_def.can_produce():
		return Result.failure("无法获取 %s 的生产信息" % employee_type)

	var food_type: String = emp_def.produces_food_type
	var amount: int = emp_def.produces_amount

	# 添加食物到玩家库存
	var add_result := StateUpdater.add_inventory(state, player_id, food_type, amount)
	if not add_result.ok:
		return add_result
	assert(add_result.value is Dictionary, "StateUpdater.add_inventory: value 类型错误（期望 Dictionary）")
	var add_payload: Dictionary = add_result.value
	assert(add_payload.has("new_amount"), "StateUpdater.add_inventory: 缺少字段 new_amount")
	var new_amount_val = add_payload["new_amount"]
	assert(new_amount_val is int, "StateUpdater.add_inventory: new_amount 类型错误（期望 int）")
	var new_amount: int = int(new_amount_val)

	# 增加生产计数
	var inc_result := RoundStateCountersClass.increment_player_key_count(
		state.round_state, "production_counts", player_id, employee_type, 1
	)
	if not inc_result.ok:
		return inc_result

	# 使用员工：用于“first_*_used”等里程碑
	var ms_use := MilestoneSystemClass.process_event(state, "UseEmployee", {"player_id": player_id, "id": employee_type})
	if not ms_use.ok:
		warnings.append("里程碑触发失败(UseEmployee/%s): %s" % [employee_type, ms_use.error])

	var ms := MilestoneSystemClass.process_event(state, "Produce", {
		"player_id": player_id,
		"product": food_type
	})

	var result := Result.success({
		"employee_type": employee_type,
		"food_type": food_type,
		"amount": amount,
		"player_id": player_id,
		"new_inventory": new_amount
	}).with_warnings(warnings)
	if not ms.ok:
		result.with_warning("里程碑触发失败(Produce): %s" % ms.error)
	return result

func _generate_specific_events(_old_state: GameState, _new_state: GameState, command: Command) -> Array[Dictionary]:
	var events: Array[Dictionary] = []

	var employee_type_result := require_string_param(command, "employee_type")
	assert(employee_type_result.ok, "produce_food 缺少/错误参数: employee_type")
	var employee_type: String = employee_type_result.value
	var emp_def = EmployeeRegistryClass.get_def(employee_type)
	assert(emp_def != null, "produce_food 未知的员工类型: %s" % employee_type)
	assert(emp_def.can_produce(), "produce_food 该员工类型不能生产食物: %s" % employee_type)

	var food_type: String = emp_def.produces_food_type
	var amount: int = emp_def.produces_amount

	events.append({
		"type": EventBus.EventType.FOOD_PRODUCED,
		"data": {
			"player_id": command.actor,
			"employee_type": employee_type,
			"food_type": food_type,
			"amount": amount
		}
	})

	return events
