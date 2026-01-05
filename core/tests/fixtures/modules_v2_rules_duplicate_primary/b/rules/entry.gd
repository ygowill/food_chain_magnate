extends RefCounted

const PhaseDefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const SettlementRegistryClass = preload("res://core/rules/settlement_registry.gd")

const Phase = PhaseDefsClass.Phase

func register(registrar) -> Result:
	# 与模块 a 重复注册同一 primary（应 fail-fast）
	return registrar.register_primary_settlement(Phase.PAYDAY, SettlementRegistryClass.Point.EXIT, Callable(self, "_noop"))

func _noop(_state: GameState, _phase_manager: PhaseManager) -> Result:
	return Result.success()

