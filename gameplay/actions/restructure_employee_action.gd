# 重组阶段：调整员工在岗/待命
# 将员工在 employees 与 reserve_employees 之间移动（CEO 不允许移动；忙碌营销员不参与）。
class_name RestructureEmployeeAction
extends ActionExecutor

func _init() -> void:
	action_id = "restructure_employee"
	display_name = "重组员工"
	description = "在重组阶段切换员工的在岗/待命状态"
	requires_actor = true
	is_mandatory = false
	is_internal = true
	allowed_phases = ["Restructuring"]

func _validate_specific(state: GameState, command: Command) -> Result:
	if state == null:
		return Result.failure("state 为空")

	# 重组：仍沿用“轮到谁谁操作”的通用回合逻辑（由 skip/end_turn 驱动）
	var current_player_id := state.get_current_player_id()
	if command.actor != current_player_id:
		return Result.failure("不是你的回合")

	# 已提交后禁止修改
	if state.round_state is Dictionary:
		var r_val = state.round_state.get("restructuring", null)
		if r_val is Dictionary:
			var r: Dictionary = r_val
			if r.has("submitted") and (r["submitted"] is Dictionary):
				var submitted: Dictionary = r["submitted"]
				if bool(submitted.get(command.actor, false)):
					return Result.failure("已提交重组，无法再调整员工")

	var employee_id_r := require_string_param(command, "employee_id")
	if not employee_id_r.ok:
		return employee_id_r
	var employee_id: String = employee_id_r.value
	if employee_id == "ceo":
		return Result.failure("CEO 不能被移动到待命区")

	if not command.params.has("to_reserve"):
		return Result.failure("缺少参数: to_reserve")
	var to_reserve_val = command.params["to_reserve"]
	if not (to_reserve_val is bool):
		return Result.failure("to_reserve 必须为 bool")
	var to_reserve: bool = bool(to_reserve_val)

	var player := state.get_player(command.actor)
	if player.is_empty():
		return Result.failure("玩家不存在: %d" % command.actor)
	if not player.has("employees") or not (player["employees"] is Array):
		return Result.failure("player.employees 缺失或类型错误（期望 Array）")
	if not player.has("reserve_employees") or not (player["reserve_employees"] is Array):
		return Result.failure("player.reserve_employees 缺失或类型错误（期望 Array）")
	if not player.has("busy_marketers") or not (player["busy_marketers"] is Array):
		return Result.failure("player.busy_marketers 缺失或类型错误（期望 Array）")

	var employees: Array = player["employees"]
	var reserve: Array = player["reserve_employees"]
	var busy: Array = player["busy_marketers"]

	if busy.has(employee_id):
		return Result.failure("忙碌营销员不能在重组阶段被移动: %s" % employee_id)

	if to_reserve:
		if employees.has(employee_id):
			return Result.success({"employee_id": employee_id, "to_reserve": true})
		if reserve.has(employee_id):
			return Result.success({"employee_id": employee_id, "to_reserve": true, "no_op": true})
		return Result.failure("员工不在在岗区: %s" % employee_id)

	if reserve.has(employee_id):
		return Result.success({"employee_id": employee_id, "to_reserve": false})
	if employees.has(employee_id):
		return Result.success({"employee_id": employee_id, "to_reserve": false, "no_op": true})
	return Result.failure("员工不在待命区: %s" % employee_id)

func _apply_changes(state: GameState, command: Command) -> Result:
	var employee_id_r := require_string_param(command, "employee_id")
	if not employee_id_r.ok:
		return employee_id_r
	var employee_id: String = employee_id_r.value
	assert(employee_id != "ceo", "restructure_employee: validate 应已阻止移动 CEO")

	assert(command.params.has("to_reserve"), "restructure_employee: 缺少参数: to_reserve")
	var to_reserve_val = command.params["to_reserve"]
	assert(to_reserve_val is bool, "restructure_employee: to_reserve 类型错误（期望 bool）")
	var to_reserve: bool = bool(to_reserve_val)

	var player_id: int = command.actor
	var key_from := "employees" if to_reserve else "reserve_employees"
	var key_to := "reserve_employees" if to_reserve else "employees"

	var from_val = state.players[player_id].get(key_from, null)
	var to_val = state.players[player_id].get(key_to, null)
	if not (from_val is Array):
		return Result.failure("player.%s 类型错误（期望 Array）" % key_from)
	if not (to_val is Array):
		return Result.failure("player.%s 类型错误（期望 Array）" % key_to)

	var from_list: Array = from_val
	if not from_list.has(employee_id):
		return Result.success({"employee_id": employee_id, "to_reserve": to_reserve, "no_op": true})

	var removed := StateUpdater.remove_from_array(state.players[player_id], key_from, employee_id)
	if not removed:
		return Result.failure("员工不在 %s: %s" % [key_from, employee_id])
	StateUpdater.append_to_array(state.players[player_id], key_to, employee_id)

	return Result.success({"employee_id": employee_id, "to_reserve": to_reserve})
