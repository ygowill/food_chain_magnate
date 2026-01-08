extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const CompanyStructureValidatorClass = preload("res://gameplay/validators/company_structure_validator.gd")

static func _is_same_role_color(from_employee: String, to_employee: String) -> Result:
	if from_employee.is_empty() or to_employee.is_empty():
		return Result.failure("train: employee_id 不能为空")
	var from_def_val = EmployeeRegistryClass.get_def(from_employee)
	if from_def_val == null or not (from_def_val is EmployeeDef):
		return Result.failure("train: 未知员工定义: %s" % from_employee)
	var to_def_val = EmployeeRegistryClass.get_def(to_employee)
	if to_def_val == null or not (to_def_val is EmployeeDef):
		return Result.failure("train: 未知员工定义: %s" % to_employee)
	var from_def: EmployeeDef = from_def_val
	var to_def: EmployeeDef = to_def_val
	return Result.success(from_def.get_role() == to_def.get_role())

static func _validate_company_structure_replacing_active(state: GameState, player_id: int, remove_employee_id: String, add_employee_id: String) -> Result:
	if state == null:
		return Result.failure("train: state 为空")
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("train: player_id 越界: %d" % player_id)
	if remove_employee_id.is_empty() or add_employee_id.is_empty():
		return Result.failure("train: employee_id 不能为空")

	var old_val = state.players[player_id]
	if not (old_val is Dictionary):
		return Result.failure("train: players[%d] 类型错误（期望 Dictionary）" % player_id)
	var old_player: Dictionary = old_val

	var tmp: Dictionary = old_player.duplicate(true)
	if not tmp.has("employees") or not (tmp["employees"] is Array):
		return Result.failure("train: player.employees 缺失或类型错误（期望 Array）")
	var emps: Array = tmp["employees"]
	var idx := emps.find(remove_employee_id)
	if idx == -1:
		return Result.failure("train: 在岗区不存在员工: %s" % remove_employee_id)
	emps.remove_at(idx)
	tmp["employees"] = emps

	state.players[player_id] = tmp
	var validator = CompanyStructureValidatorClass.new()
	var r := validator.validate(state, player_id, {"employee_id": add_employee_id, "to_reserve": false})
	state.players[player_id] = old_player
	return r
