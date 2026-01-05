# 解雇动作（M3 起步）
# 将员工从玩家公司移除并归还到供应池。
class_name FireAction
extends ActionExecutor

const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")

func _init() -> void:
	action_id = "fire"
	display_name = "解雇"
	description = "将员工从公司移除并归还到员工池"
	requires_actor = true
	is_mandatory = false
	allowed_phases = ["Payday"]

func _validate_specific(state: GameState, command: Command) -> Result:
	var current_player_id := state.get_current_player_id()
	if command.actor != current_player_id:
		return Result.failure("不是你的回合")

	var employee_id_result := require_string_param(command, "employee_id")
	if not employee_id_result.ok:
		return employee_id_result
	var employee_id: String = employee_id_result.value
	if not EmployeeRegistryClass.is_loaded():
		return Result.failure("EmployeeRegistry 未初始化")
	var emp_def = EmployeeRegistryClass.get_def(employee_id)
	if emp_def == null:
		return Result.failure("未知的员工类型: %s" % employee_id)
	if not (emp_def is EmployeeDef):
		return Result.failure("员工定义类型错误（期望 EmployeeDef）: %s" % employee_id)
	var def: EmployeeDef = emp_def
	if not def.can_be_fired:
		return Result.failure("该员工不可解雇: %s" % employee_id)

	var player := state.get_player(command.actor)
	var location := ""
	if command.params.has("location"):
		var location_result := require_string_param(command, "location")
		if not location_result.ok:
			return location_result
		location = location_result.value
	if location.is_empty():
		location = _find_employee_location(player, employee_id)
	if location.is_empty():
		return Result.failure("员工不存在: %s" % employee_id)
	if location != "active" and location != "reserve" and location != "busy":
		return Result.failure("未知 location: %s" % location)

	# Payday 规则：通常忙碌营销员不能解雇；特殊例外（对齐 rules.md）见 _can_fire_busy_marketer。
	if state.phase == "Payday" and location == "busy":
		if not _can_fire_busy_marketer(state, command.actor, employee_id):
			return Result.failure("通常忙碌的营销员不能解雇")

	return Result.success({
		"employee_id": employee_id,
		"location": location
	})

func _apply_changes(state: GameState, command: Command) -> Result:
	var player_id: int = command.actor
	var employee_id_result := require_string_param(command, "employee_id")
	if not employee_id_result.ok:
		return employee_id_result
	var employee_id: String = employee_id_result.value
	var player := state.get_player(player_id)

	var location := ""
	if command.params.has("location"):
		var location_result := require_string_param(command, "location")
		if not location_result.ok:
			return location_result
		location = location_result.value
	if location.is_empty():
		location = _find_employee_location(player, employee_id)
	if location.is_empty():
		return Result.failure("员工不存在: %s" % employee_id)

	var key := _location_to_key(location)
	if key.is_empty():
		return Result.failure("未知 location: %s" % location)

	var removed := StateUpdater.remove_from_array(state.players[player_id], key, employee_id)
	if not removed:
		return Result.failure("员工不在 %s: %s" % [location, employee_id])

	StateUpdater.return_to_pool(state, employee_id, 1)

	return Result.success({
		"player_id": player_id,
		"employee_id": employee_id,
		"location": location
	})

func _generate_specific_events(old_state: GameState, _new_state: GameState, command: Command) -> Array[Dictionary]:
	var employee_id_result := require_string_param(command, "employee_id")
	assert(employee_id_result.ok, "fire 缺少/错误参数: employee_id")
	var employee_id: String = employee_id_result.value

	var location := ""
	if command.params.has("location"):
		var location_result := require_string_param(command, "location")
		assert(location_result.ok, "fire 参数 location 类型错误")
		location = location_result.value
	if location.is_empty():
		location = _find_employee_location(old_state.get_player(command.actor), employee_id)
	assert(not location.is_empty(), "fire 无法推断 location: %s" % employee_id)

	return [{
		"type": EventBus.EventType.EMPLOYEE_FIRED,
		"data": {
			"player_id": command.actor,
			"employee_id": employee_id,
			"location": location
		}
	}]

func _find_employee_location(player: Dictionary, employee_id: String) -> String:
	assert(player.has("employees") and (player["employees"] is Array), "fire: player.employees 缺失或类型错误（期望 Array[String]）")
	var active: Array = player["employees"]
	for i in range(active.size()):
		assert(active[i] is String, "fire: player.employees[%d] 类型错误（期望 String）" % i)
	if active.find(employee_id) >= 0:
		return "active"
	assert(player.has("reserve_employees") and (player["reserve_employees"] is Array), "fire: player.reserve_employees 缺失或类型错误（期望 Array[String]）")
	var reserve: Array = player["reserve_employees"]
	for i in range(reserve.size()):
		assert(reserve[i] is String, "fire: player.reserve_employees[%d] 类型错误（期望 String）" % i)
	if reserve.find(employee_id) >= 0:
		return "reserve"
	assert(player.has("busy_marketers") and (player["busy_marketers"] is Array), "fire: player.busy_marketers 缺失或类型错误（期望 Array[String]）")
	var busy: Array = player["busy_marketers"]
	for i in range(busy.size()):
		assert(busy[i] is String, "fire: player.busy_marketers[%d] 类型错误（期望 String）" % i)
	if busy.find(employee_id) >= 0:
		return "busy"
	return ""

func _location_to_key(location: String) -> String:
	match location:
		"active":
			return "employees"
		"reserve":
			return "reserve_employees"
		"busy":
			return "busy_marketers"
		_:
			return ""

func _can_fire_busy_marketer(state: GameState, player_id: int, employee_id: String) -> bool:
	var player := state.get_player(player_id)
	if player.is_empty():
		return false

	assert(player.has("busy_marketers") and (player["busy_marketers"] is Array), "fire: player.busy_marketers 缺失或类型错误（期望 Array[String]）")
	var busy: Array = player["busy_marketers"]
	for i in range(busy.size()):
		assert(busy[i] is String, "fire: player.busy_marketers[%d] 类型错误（期望 String）" % i)
	if busy.find(employee_id) < 0:
		return false

	# 特殊例外仅适用于“需要薪水”的忙碌营销员
	if not EmployeeRulesClass.requires_salary(employee_id, player):
		return false

	# 必须已解雇所有其他需要薪水的员工（在岗/待命）
	assert(player.has("employees") and (player["employees"] is Array), "fire: player.employees 缺失或类型错误（期望 Array[String]）")
	var active: Array = player["employees"]
	for i in range(active.size()):
		assert(active[i] is String, "fire: player.employees[%d] 类型错误（期望 String）" % i)
		var emp_id: String = active[i]
		assert(not emp_id.is_empty(), "fire: player.employees[%d] 不应为空字符串" % i)
		if EmployeeRulesClass.requires_salary(emp_id, player):
			return false

	assert(player.has("reserve_employees") and (player["reserve_employees"] is Array), "fire: player.reserve_employees 缺失或类型错误（期望 Array[String]）")
	var reserve: Array = player["reserve_employees"]
	for i in range(reserve.size()):
		assert(reserve[i] is String, "fire: player.reserve_employees[%d] 类型错误（期望 String）" % i)
		var emp_id2: String = reserve[i]
		assert(not emp_id2.is_empty(), "fire: player.reserve_employees[%d] 不应为空字符串" % i)
		if EmployeeRulesClass.requires_salary(emp_id2, player):
			return false

	# 仍无力支付所有忙碌营销员的薪水时，允许解雇其中一名
	assert(player.has("cash") and (player["cash"] is int), "fire: player.cash 缺失或类型错误（期望 int）")
	var cash: int = int(player["cash"])
	var salary_cost := state.get_rule_int("salary_cost")
	var busy_due := 0
	for i in range(busy.size()):
		var emp_id3: String = busy[i]
		assert(not emp_id3.is_empty(), "fire: player.busy_marketers[%d] 不应为空字符串" % i)
		if EmployeeRulesClass.requires_salary(emp_id3, player):
			busy_due += salary_cost

	return cash < busy_due
