extends RefCounted

const PhaseDefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const SettlementRegistryClass = preload("res://core/rules/settlement_registry.gd")
const PlayerStateAccessClass = preload("res://core/state/player_state_access.gd")

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

	var marketing_rounds_check := _validate_existing_marketing_rounds(state.round_state)
	if not marketing_rounds_check.ok:
		return marketing_rounds_check

	var active_count := 0
	for i in range(state.players.size()):
		var employees_read := PlayerStateAccessClass.require_player_employees(state, i, "mass_marketeers")
		if not employees_read.ok:
			return employees_read
		var employees: Array = employees_read.value
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

static func _validate_existing_marketing_rounds(round_state: Dictionary) -> Result:
	if not (round_state is Dictionary):
		return Result.failure("mass_marketeers: state.round_state 类型错误（期望 Dictionary）")
	if not round_state.has("marketing_rounds"):
		return Result.success()
	var mr_val = round_state.get("marketing_rounds", null)
	if mr_val is int:
		if int(mr_val) <= 0:
			return Result.failure("mass_marketeers: round_state.marketing_rounds 必须 > 0，实际: %d" % int(mr_val))
		return Result.success()
	if mr_val is float:
		var f: float = float(mr_val)
		if f != floor(f):
			return Result.failure("mass_marketeers: round_state.marketing_rounds 必须为整数，实际: %s" % str(mr_val))
		if int(f) <= 0:
			return Result.failure("mass_marketeers: round_state.marketing_rounds 必须 > 0，实际: %d" % int(f))
		return Result.success()
	return Result.failure("mass_marketeers: round_state.marketing_rounds 类型错误（期望 int），实际: %s" % str(typeof(mr_val)))
