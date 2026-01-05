extends RefCounted

const PhaseDefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const SettlementRegistryClass = preload("res://core/rules/settlement_registry.gd")

const Phase = PhaseDefsClass.Phase

func register(registrar) -> Result:
	var r = registrar.register_primary_settlement(Phase.RESTRUCTURING, SettlementRegistryClass.Point.EXIT, Callable(self, "_on_restructuring_exit"))
	if not r.ok:
		return r
	return registrar.register_settlement_triggers_override(Phase.RESTRUCTURING, "exit", [SettlementRegistryClass.Point.EXIT], 100)

func _on_restructuring_exit(state: GameState, _phase_manager: PhaseManager) -> Result:
	if state == null:
		return Result.failure("settlement_trigger_override_exit_test: state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("settlement_trigger_override_exit_test: state.round_state 类型错误（期望 Dictionary）")
	state.round_state["restructuring_exit_settled"] = true
	return Result.success()
