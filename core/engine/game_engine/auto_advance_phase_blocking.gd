extends RefCounted

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const TypeHelpersClass = preload("res://core/utils/type_helpers.gd")

static func is_phase_blocked_by_pending_actions(state_in: GameState, phase_name: String) -> Result:
	if state_in == null:
		return Result.failure("pending_phase_actions: state 为空")
	var rs_read := TypeHelpersClass.require_dict(state_in.round_state, "pending_phase_actions: round_state")
	if not rs_read.ok:
		return rs_read
	var rs: Dictionary = rs_read.value
	if not rs.has("pending_phase_actions"):
		return Result.success(false)
	var pending_read := TypeHelpersClass.require_dict(rs.get("pending_phase_actions", null), "pending_phase_actions: round_state.pending_phase_actions")
	if not pending_read.ok:
		return pending_read
	var pending: Dictionary = pending_read.value
	if not pending.has(phase_name):
		return Result.success(false)
	var list_read := TypeHelpersClass.require_array(pending.get(phase_name, null), "pending_phase_actions: round_state.pending_phase_actions[%s]" % phase_name)
	if not list_read.ok:
		return list_read
	var list: Array = list_read.value
	return Result.success(not list.is_empty())

static func is_auto_skip_settlement_phase(phase_name: String) -> bool:
	return phase_name == DefsClass.PHASE_DINNERTIME or phase_name == DefsClass.PHASE_MARKETING or phase_name == DefsClass.PHASE_CLEANUP
