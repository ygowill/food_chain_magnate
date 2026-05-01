# 生产食物动作（GET_FOOD 子阶段）
# 厨师/主厨生产食物到玩家库存
# 生产信息从 EmployeeRegistry 的 JSON 定义中读取
class_name ProduceFoodAction
extends ActionExecutor

const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")
const EmployeeUsageHelperClass = preload("res://gameplay/actions/employee_usage_helper.gd")
const RoundStateCountersClass = preload("res://core/utils/round_state_counters.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const StaffStateClass = preload("res://core/state/staff_state.gd")

var _inventory_adder = null

func _init(inventory_adder = null) -> void:
	action_id = "produce_food"
	display_name = "生产食物"
	description = "使用厨师/主厨生产食物"
	requires_actor = true
	is_mandatory = false
	allowed_phases = [DefsClass.PHASE_WORKING]
	allowed_sub_phases = [DefsClass.SUB_PHASE_GET_FOOD]
	_inventory_adder = inventory_adder if inventory_adder != null else StateUpdater

func can_initiate(state: GameState, player_id: int) -> bool:
	if state == null:
		return true
	if state.get_current_player_id() != player_id:
		return false
	var providers_read := EmployeeRulesClass.try_get_food_producers_for_working(state, player_id)
	if not providers_read.ok:
		return false
	for provider_val in providers_read.value:
		if not (provider_val is Dictionary):
			continue
		if int(Dictionary(provider_val).get("remaining", 0)) > 0:
			return true
	return false

func _read_optional_staff_id(command: Command) -> Result:
	if command == null:
		return Result.failure("command 为空")
	if not command.params.has("staff_id"):
		return Result.success(-1)
	var staff_id_result := require_int_param(command, "staff_id")
	if not staff_id_result.ok:
		return staff_id_result
	var staff_id := int(staff_id_result.value)
	if staff_id <= 0:
		return Result.failure("staff_id 必须 > 0，实际: %d" % staff_id)
	return Result.success(staff_id)

func _validate_specific(state: GameState, command: Command) -> Result:
	# 检查必需参数
	var employee_type_result := require_string_param(command, "employee_type")
	if not employee_type_result.ok:
		return employee_type_result
	var employee_type: String = employee_type_result.value

	var food_type := ""
	if command.params.has("food_type"):
		var ft_val = command.params.get("food_type", null)
		if not (ft_val is String):
			return Result.failure("food_type 类型错误（期望 String）")
		food_type = str(ft_val).strip_edges()

	# 从 EmployeeRegistry 获取员工定义
	var emp_def = EmployeeRegistryClass.get_def(employee_type)
	if emp_def == null:
		return Result.failure("未知的员工类型: %s" % employee_type)

	# 检查该员工是否能生产食物
	if not emp_def.can_produce():
		return Result.failure("该员工类型不能生产食物: %s" % employee_type)

	var fixed_food_type: String = str(emp_def.produces_food_type)
	var fixed_amount: int = int(emp_def.produces_amount)
	var is_fixed := (not fixed_food_type.is_empty()) and fixed_amount > 0
	if is_fixed:
		if not food_type.is_empty() and food_type != fixed_food_type:
			return Result.failure("food_type 与员工生产类型不匹配: %s != %s" % [food_type, fixed_food_type])
	else:
		# 多选生产（例如 kitchen_trainee）：必须显式提供 food_type 且在选项内
		var options: Array[String] = []
		if emp_def is EmployeeDef:
			options = (emp_def as EmployeeDef).get_production_food_options()
		if food_type.is_empty():
			return Result.failure("该员工需要指定 food_type")
		if not options.has(food_type):
			return Result.failure("该员工不能生产: %s" % food_type)

	# 检查是否是当前玩家的回合
	var current_player_id := state.get_current_player_id()
	if command.actor != current_player_id:
		return Result.failure("不是你的回合")

	var requested_staff_read := _read_optional_staff_id(command)
	if not requested_staff_read.ok:
		return requested_staff_read
	var requested_staff_id := int(requested_staff_read.value)
	var provider_read := EmployeeRulesClass.try_resolve_food_producer(
		state,
		command.actor,
		employee_type,
		requested_staff_id
	)
	if not provider_read.ok:
		return provider_read

	return Result.success()

static func _require_add_inventory_payload(value, prefix: String) -> Result:
	if not (value is Dictionary):
		return Result.failure("%s: StateUpdater.add_inventory 返回值类型错误（期望 Dictionary）" % prefix)
	var payload: Dictionary = value
	if not payload.has("new_amount"):
		return Result.failure("%s: StateUpdater.add_inventory 缺少字段 new_amount" % prefix)
	var new_amount_val = payload["new_amount"]
	if not (new_amount_val is int):
		return Result.failure("%s: StateUpdater.add_inventory.new_amount 类型错误（期望 int）" % prefix)
	return Result.success({"new_amount": int(new_amount_val)})

func _apply_changes(state: GameState, command: Command) -> Result:
	var employee_type_result := require_string_param(command, "employee_type")
	if not employee_type_result.ok:
		return employee_type_result
	var employee_type: String = employee_type_result.value
	var player_id: int = command.actor
	var warnings: Array[String] = []
	var requested_staff_read := _read_optional_staff_id(command)
	if not requested_staff_read.ok:
		return requested_staff_read
	var requested_staff_id := int(requested_staff_read.value)
	var provider_read := EmployeeRulesClass.try_resolve_food_producer(
		state,
		player_id,
		employee_type,
		requested_staff_id
	)
	if not provider_read.ok:
		return provider_read
	var provider: Dictionary = provider_read.value
	var producer_staff_id := int(provider.get("staff_id", -1))
	var producer_employee_type := str(provider.get("employee_type", employee_type)).strip_edges()
	if producer_staff_id <= 0 or producer_employee_type.is_empty():
		return Result.failure("produce_food: 生产员工解析结果无效: %s" % str(provider))

	# 从 EmployeeRegistry 获取生产信息
	var emp_def = EmployeeRegistryClass.get_def(employee_type)
	if emp_def == null or not emp_def.can_produce():
		return Result.failure("无法获取 %s 的生产信息" % employee_type)

	var food_type := ""
	var amount := 0
	var fixed_food_type: String = str(emp_def.produces_food_type)
	var fixed_amount: int = int(emp_def.produces_amount)
	var is_fixed := (not fixed_food_type.is_empty()) and fixed_amount > 0
	if is_fixed:
		food_type = fixed_food_type
		amount = fixed_amount
	else:
		var food_type_val = command.params.get("food_type", "")
		food_type = str(food_type_val).strip_edges()
		if food_type.is_empty():
			return Result.failure("缺少参数: food_type", Result.ErrorCode.MISSING_PARAMS)
		var options: Array[String] = []
		if emp_def is EmployeeDef:
			options = (emp_def as EmployeeDef).get_production_food_options()
		if not options.has(food_type):
			return Result.failure("该员工不能生产: %s" % food_type)
		amount = 1

	# 添加食物到玩家库存
	var add_result = _inventory_adder.add_inventory(state, player_id, food_type, amount)
	if not add_result.ok:
		return add_result
	var add_payload_read := _require_add_inventory_payload(add_result.value, "produce_food")
	if not add_payload_read.ok:
		return add_payload_read
	var add_payload: Dictionary = add_payload_read.value
	var new_amount: int = int(add_payload.get("new_amount", 0))

	# 增加生产计数
	var inc_result := RoundStateCountersClass.increment_player_key_count(
		state.round_state, "production_counts", player_id, employee_type, 1
	)
	if not inc_result.ok:
		return inc_result
	var use_staff := StaffStateClass.increment_staff_track_usage(state, producer_staff_id, action_id, 1)
	if not use_staff.ok:
		return use_staff

	# 使用员工：用于“first_*_used”等里程碑
	var use_employee := EmployeeUsageHelperClass.apply_use_employee_event(state, player_id, producer_employee_type)
	if not use_employee.ok:
		return use_employee
	warnings.append_array(use_employee.warnings)

	var ms := MilestoneSystemClass.process_event(state, "Produce", {
		"player_id": player_id,
		"product": food_type
	})
	if not ms.ok:
		return Result.failure("里程碑触发失败(Produce): %s" % ms.error).with_warnings(warnings).with_warnings(ms.warnings)
	warnings.append_array(ms.warnings)

	var result := Result.success({
		"employee_type": employee_type,
		"staff_id": producer_staff_id,
		"producer_staff_id": producer_staff_id,
		"producer_employee_type": producer_employee_type,
		"food_type": food_type,
		"amount": amount,
		"player_id": player_id,
		"new_inventory": new_amount
	}).with_warnings(warnings)
	return result

func _generate_specific_events(_old_state: GameState, _new_state: GameState, command: Command) -> Array[Dictionary]:
	var events: Array[Dictionary] = []

	var employee_type_result := require_string_param(command, "employee_type")
	if not employee_type_result.ok:
		return events
	var employee_type: String = str(employee_type_result.value).strip_edges()
	if employee_type.is_empty():
		return events
	var emp_def = EmployeeRegistryClass.get_def(employee_type)
	if emp_def == null or not emp_def.can_produce():
		return events

	var food_type := ""
	var amount := 0
	var producer_staff_id := -1
	var fixed_food_type: String = str(emp_def.produces_food_type)
	var fixed_amount: int = int(emp_def.produces_amount)
	var is_fixed := (not fixed_food_type.is_empty()) and fixed_amount > 0
	if is_fixed:
		food_type = fixed_food_type
		amount = fixed_amount
	else:
		var food_type_result := require_string_param(command, "food_type")
		if not food_type_result.ok:
			return events
		food_type = str(food_type_result.value).strip_edges()
		if food_type.is_empty():
			return events
		amount = 1

	var provider_read := EmployeeRulesClass.try_resolve_food_producer(
		_old_state,
		command.actor,
		employee_type,
		int(command.params.get("staff_id", -1))
	)
	if provider_read.ok and provider_read.value is Dictionary:
		producer_staff_id = int(Dictionary(provider_read.value).get("staff_id", -1))

	var data := {
		"player_id": command.actor,
		"employee_type": employee_type,
		"food_type": food_type,
		"amount": amount,
	}
	if producer_staff_id > 0:
		data["staff_id"] = producer_staff_id

	events.append({
		"type": EventBus.EventType.FOOD_PRODUCED,
		"data": data
	})

	return events
