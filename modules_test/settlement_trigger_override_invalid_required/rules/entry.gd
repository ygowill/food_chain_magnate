extends RefCounted

const PhaseDefsClass = preload("res://core/engine/phase_manager/definitions.gd")

const Phase = PhaseDefsClass.Phase

func register(registrar) -> Result:
	# 移除 Dinnertime:enter 的触发点（应导致 init fail）
	return registrar.register_settlement_triggers_override(Phase.DINNERTIME, "enter", [], 100)
