extends RefCounted

const PhaseDefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const SettlementRegistryClass = preload("res://core/rules/settlement_registry.gd")

const Phase = PhaseDefsClass.Phase

const EMPLOYEE_ID := "mass_marketeer"

func register(registrar) -> Result:
	return registrar.register_extension_settlement(
		Phase.MARKETING,
		SettlementRegistryClass.Point.ENTER,
		Callable(self, "_on_marketing_before_primary"),
		50
	)

func _on_marketing_before_primary(state: GameState, _phase_manager: PhaseManager) -> Result:
	if state == null:
		return Result.failure("mass_marketeers: state 为空")
	if not (state.players is Array):
		return Result.failure("mass_marketeers: state.players 类型错误（期望 Array）")
	if not (state.round_state is Dictionary):
		return Result.failure("mass_marketeers: state.round_state 类型错误（期望 Dictionary）")

	var active_count := 0
	for i in range(state.players.size()):
		var p_val = state.players[i]
		if not (p_val is Dictionary):
			return Result.failure("mass_marketeers: players[%d] 类型错误（期望 Dictionary）" % i)
		var p: Dictionary = p_val
		var employees_val = p.get("employees", null)
		if not (employees_val is Array):
			return Result.failure("mass_marketeers: players[%d].employees 类型错误（期望 Array[String]）" % i)
		var employees: Array = employees_val
		for e_i in range(employees.size()):
			var emp_val = employees[e_i]
			if not (emp_val is String):
				return Result.failure("mass_marketeers: players[%d].employees[%d] 类型错误（期望 String）" % [i, e_i])
			var emp: String = str(emp_val)
			if emp.is_empty():
				return Result.failure("mass_marketeers: players[%d].employees[%d] 不能为空" % [i, e_i])
			if emp == EMPLOYEE_ID:
				active_count += 1

	state.round_state["marketing_rounds"] = 1 + active_count
	return Result.success()

