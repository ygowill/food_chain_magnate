extends RefCounted

const PhaseDefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const PhaseManagerClass = preload("res://core/engine/phase_manager.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")

const Phase = PhaseDefsClass.Phase
const HookType = PhaseManagerClass.HookType

const NIGHT_SHIFT_MANAGER_ID := "night_shift_manager"

func register(registrar) -> Result:
	return registrar.register_phase_hook(
		Phase.WORKING,
		HookType.BEFORE_ENTER,
		Callable(self, "_on_working_before_enter"),
		100
	)

func _on_working_before_enter(state: GameState) -> Result:
	if state == null:
		return Result.failure("night_shift_managers: state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("night_shift_managers: state.round_state 类型错误（期望 Dictionary）")
	if not (state.players is Array):
		return Result.failure("night_shift_managers: state.players 类型错误（期望 Array）")

	var all: Dictionary = {}

	for pid in range(state.players.size()):
		var p_val = state.players[pid]
		if not (p_val is Dictionary):
			return Result.failure("night_shift_managers: players[%d] 类型错误（期望 Dictionary）" % pid)
		var player: Dictionary = p_val
		var employees_val = player.get("employees", null)
		if not (employees_val is Array):
			return Result.failure("night_shift_managers: players[%d].employees 类型错误（期望 Array[String]）" % pid)
		var employees: Array = employees_val

		var has_nsm := false
		for i in range(employees.size()):
			var emp_val = employees[i]
			if not (emp_val is String):
				return Result.failure("night_shift_managers: players[%d].employees[%d] 类型错误（期望 String）" % [pid, i])
			var emp_id: String = str(emp_val)
			if emp_id.is_empty():
				return Result.failure("night_shift_managers: players[%d].employees[%d] 不能为空" % [pid, i])
			if emp_id == NIGHT_SHIFT_MANAGER_ID:
				has_nsm = true
				break

		if not has_nsm:
			continue

		var per_player: Dictionary = {}
		for i in range(employees.size()):
			var emp_val2 = employees[i]
			var emp_id2: String = str(emp_val2)
			if emp_id2 == "ceo":
				continue
			var def = EmployeeRegistryClass.get_def(emp_id2)
			if def == null:
				return Result.failure("night_shift_managers: 未知员工定义: %s" % emp_id2)
			if bool(def.salary):
				continue
			per_player[emp_id2] = 2

		if not per_player.is_empty():
			all[pid] = per_player

	state.round_state["working_employee_multipliers"] = all
	return Result.success()
