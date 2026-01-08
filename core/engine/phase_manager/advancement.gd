# PhaseManager：阶段/子阶段推进逻辑下沉
class_name PhaseManagerAdvancement
extends RefCounted

const AdvancePhaseClass = preload("res://core/engine/phase_manager/advance_phase.gd")
const AdvanceSubPhaseClass = preload("res://core/engine/phase_manager/advance_sub_phase.gd")

static func advance_phase(pm, state: GameState) -> Result:
	return AdvancePhaseClass.advance_phase(pm, state)

static func advance_sub_phase(pm, state: GameState) -> Result:
	return AdvanceSubPhaseClass.advance_sub_phase(pm, state)
