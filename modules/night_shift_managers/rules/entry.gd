extends RefCounted

const PhaseDefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const PhaseManagerClass = preload("res://core/engine/phase_manager.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const PlayerStateAccessClass = preload("res://core/state/player_state_access.gd")

const Phase = PhaseDefsClass.Phase
const HookType = PhaseManagerClass.HookType

const NIGHT_SHIFT_MANAGER_ID := "night_shift_manager"
const WORKING_EMPLOYEE_MULTIPLIERS_KEY := "working_employee_multipliers"
const STATE_SCHEMA_ID_WORKING_EMPLOYEE_MULTIPLIERS := "night_shift_managers:round_state_int_keys:working_employee_multipliers"

func register(registrar) -> Result:
	var r: Result = registrar.register_phase_hook(
		Phase.WORKING,
		HookType.BEFORE_ENTER,
		Callable(self, "_on_working_before_enter"),
		100
	)
	if not r.ok:
		return r

	r = registrar.register_round_state_int_key_dict_schema(STATE_SCHEMA_ID_WORKING_EMPLOYEE_MULTIPLIERS, [WORKING_EMPLOYEE_MULTIPLIERS_KEY], 100)
	if not r.ok:
		return r

	return Result.success()

func _on_working_before_enter(state: GameState) -> Result:
	if state == null:
		return Result.failure("night_shift_managers: state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("night_shift_managers: state.round_state 类型错误（期望 Dictionary）")
	if not (state.players is Array):
		return Result.failure("night_shift_managers: state.players 类型错误（期望 Array）")

	var all: Dictionary = {}

	for pid in range(state.players.size()):
		var employees_read := PlayerStateAccessClass.require_player_employees(state, pid, "night_shift_managers")
		if not employees_read.ok:
			return employees_read
		var employees: Array = employees_read.value

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

	state.round_state[WORKING_EMPLOYEE_MULTIPLIERS_KEY] = all
	return Result.success()
