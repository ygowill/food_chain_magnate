extends RefCounted

const PhaseDefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const SettlementRegistryClass = preload("res://core/rules/settlement_registry.gd")

const Phase = PhaseDefsClass.Phase

func register(registrar) -> Result:
	var r = registrar.register_primary_settlement(Phase.ORDER_OF_BUSINESS, SettlementRegistryClass.Point.ENTER, Callable(self, "_on_oob_enter"))
	if not r.ok:
		return r
	# 覆盖触发点：进入 OrderOfBusiness 时触发 ENTER settlement
	return registrar.register_settlement_triggers_override(Phase.ORDER_OF_BUSINESS, "enter", [SettlementRegistryClass.Point.ENTER], 100)

func _on_oob_enter(state: GameState, _phase_manager: PhaseManager) -> Result:
	if state == null:
		return Result.failure("settlement_trigger_override_test: state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("settlement_trigger_override_test: state.round_state 类型错误（期望 Dictionary）")
	state.round_state["oob_enter_settled"] = true
	return Result.success()
