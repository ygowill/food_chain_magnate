# 重组阶段：调整员工在岗/待命
# 新规则：只有放入 company_structure.structure 的员工才算“在岗”(player.employees)。
# 因此本动作仅用于“转入待命”（从 employees 移到 reserve_employees，并同步移出 company_structure.structure）。
# （CEO 不允许移动；忙碌营销员不参与）。
class_name RestructureEmployeeAction
extends ActionExecutor

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const PlayerStateAccessClass = preload("res://core/state/player_state_access.gd")

func _init() -> void:
	action_id = "restructure_employee"
	display_name = "重组员工"
	description = "在重组阶段切换员工的在岗/待命状态"
	requires_actor = true
	is_mandatory = false
	is_internal = true
	allowed_phases = [DefsClass.PHASE_RESTRUCTURING]

func _validate_specific(state: GameState, command: Command) -> Result:
	if state == null:
		return Result.failure("state 为空")

	if command.actor < 0 or command.actor >= state.players.size():
		return Result.failure("玩家不存在: %d" % command.actor)

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
		return Result.failure("缺少参数: to_reserve", Result.ErrorCode.MISSING_PARAMS)
	var to_reserve_val = command.params["to_reserve"]
	if not (to_reserve_val is bool):
		return Result.failure("to_reserve 必须为 bool")
	var to_reserve: bool = bool(to_reserve_val)

	var player := state.get_player(command.actor)
	if player.is_empty():
		return Result.failure("玩家不存在: %d" % command.actor)
	var employees_read := PlayerStateAccessClass.require_employees(player, "player", "")
	if not employees_read.ok:
		return employees_read
	var employees: Array = employees_read.value

	var reserve_read := PlayerStateAccessClass.require_reserve_employees(player, "player", "")
	if not reserve_read.ok:
		return reserve_read
	var reserve: Array = reserve_read.value

	var busy_read := PlayerStateAccessClass.require_busy_marketers(player, "player", "")
	if not busy_read.ok:
		return busy_read
	var busy: Array = busy_read.value

	if to_reserve:
		if employees.has(employee_id):
			return Result.success({"employee_id": employee_id, "to_reserve": true})
		if reserve.has(employee_id):
			return Result.success({"employee_id": employee_id, "to_reserve": true, "no_op": true})
		if busy.has(employee_id):
			return Result.failure("忙碌营销员不能在重组阶段被移动: %s" % employee_id)
		return Result.failure("员工不在在岗区: %s" % employee_id)

	if employees.has(employee_id):
		return Result.success({"employee_id": employee_id, "to_reserve": false, "no_op": true})
	if reserve.has(employee_id):
		return Result.failure("不允许直接激活待命员工：请将员工放入公司结构以激活（employee_id=%s）" % employee_id)
	if busy.has(employee_id):
		return Result.failure("忙碌营销员不能在重组阶段被移动: %s" % employee_id)
	return Result.failure("员工不属于当前玩家: %s" % employee_id)

func _apply_changes(state: GameState, command: Command) -> Result:
	var payload_read := _require_apply_payload(command)
	if not payload_read.ok:
		return payload_read
	var payload: Dictionary = payload_read.value
	var employee_id: String = str(payload.get("employee_id", ""))
	var to_reserve: bool = bool(payload.get("to_reserve", false))
	if not to_reserve:
		return Result.success({"employee_id": employee_id, "to_reserve": false, "no_op": true})

	var player_read := PlayerStateAccessClass.require_player(state, command.actor, "restructure_employee")
	if not player_read.ok:
		return player_read
	var player: Dictionary = player_read.value
	var player_label := "player[%d]" % command.actor
	var from_key := "employees"
	var to_key := "reserve_employees"

	var from_read := PlayerStateAccessClass.require_employees(player, player_label, "restructure_employee")
	if not from_read.ok:
		return from_read
	var to_read := PlayerStateAccessClass.require_reserve_employees(player, player_label, "restructure_employee")
	if not to_read.ok:
		return to_read

	var from_list: Array = from_read.value
	if not from_list.has(employee_id):
		return Result.success({"employee_id": employee_id, "to_reserve": to_reserve, "no_op": true})

	var removed := StateUpdater.remove_from_array(player, from_key, employee_id)
	if not removed:
		return Result.failure("员工不在 %s: %s" % [from_key, employee_id])
	StateUpdater.append_to_array(player, to_key, employee_id)

	# 若员工被移动到待命区，则同步移出 company_structure.structure（避免出现“待命员工仍占用结构槽位”的隐式残留）。
	var cs_val = player.get("company_structure", null)
	if cs_val is Dictionary:
		var cs: Dictionary = cs_val
		var struct_val = cs.get("structure", null)
		if struct_val is Array:
			var structure: Array = struct_val
			if _remove_one_employee_from_structure(structure, employee_id):
				cs["structure"] = structure
				player["company_structure"] = cs

	state.players[command.actor] = player
	return Result.success({"employee_id": employee_id, "to_reserve": to_reserve})

func _require_apply_payload(command: Command) -> Result:
	var employee_id_r := require_string_param(command, "employee_id")
	if not employee_id_r.ok:
		return employee_id_r
	var employee_id: String = employee_id_r.value
	if employee_id == "ceo":
		return Result.failure("restructure_employee: CEO 不能被移动到待命区")
	if not command.params.has("to_reserve"):
		return Result.failure("restructure_employee: 缺少参数: to_reserve", Result.ErrorCode.MISSING_PARAMS)
	var to_reserve_val = command.params["to_reserve"]
	if not (to_reserve_val is bool):
		return Result.failure("restructure_employee: to_reserve 类型错误（期望 bool）")
	return Result.success({
		"employee_id": employee_id,
		"to_reserve": bool(to_reserve_val),
	})

static func _remove_one_employee_from_structure(structure: Array, employee_id: String) -> bool:
	if structure == null:
		return false
	var emp_id := str(employee_id)
	if emp_id.is_empty() or emp_id == "ceo":
		return false

	# 1) 先从 CEO 直属槽移除（清空该槽位及其 reports）
	for i in range(structure.size()):
		var entry_val = structure[i]
		if not (entry_val is Dictionary):
			continue
		var entry: Dictionary = entry_val
		if str(entry.get("employee_id", "")) == emp_id:
			entry["employee_id"] = ""
			entry["reports"] = []
			structure[i] = entry
			return true

	# 2) 再从 reports 移除（仅移除一个实例）
	for i2 in range(structure.size()):
		var entry_val2 = structure[i2]
		if not (entry_val2 is Dictionary):
			continue
		var entry2: Dictionary = entry_val2
		var reps_val = entry2.get("reports", null)
		if not (reps_val is Array):
			continue
		var reps: Array = reps_val
		if reps.has(emp_id):
			reps.erase(emp_id)
			entry2["reports"] = reps
			structure[i2] = entry2
			return true

	return false
