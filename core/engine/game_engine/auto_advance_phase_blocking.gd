extends RefCounted

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const RoundStatePendingPhaseActionsClass = preload("res://core/utils/round_state_pending_phase_actions.gd")

static func is_phase_blocked_by_pending_actions(state_in: GameState, phase_name: String) -> Result:
	if state_in == null:
		return Result.failure("pending_phase_actions: state 为空")
	return RoundStatePendingPhaseActionsClass.is_phase_blocked(state_in.round_state, phase_name, "pending_phase_actions")

static func is_auto_skip_settlement_phase(phase_name: String) -> bool:
	return phase_name == DefsClass.PHASE_DINNERTIME or phase_name == DefsClass.PHASE_MARKETING or phase_name == DefsClass.PHASE_CLEANUP
