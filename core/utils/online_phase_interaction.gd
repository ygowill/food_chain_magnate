class_name OnlinePhaseInteraction
extends RefCounted

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const RoundStateSubPhasePassedClass = preload("res://core/utils/round_state_sub_phase_passed.gd")

static func is_online_mode() -> bool:
	if NetContext == null:
		return false
	return NetContext.mode == NetContext.Mode.ONLINE_CLIENT or NetContext.mode == NetContext.Mode.ONLINE_SERVER

static func is_online_parallel_payday(state: GameState) -> bool:
	if state == null:
		return false
	return is_online_mode() and str(state.phase) == DefsClass.PHASE_PAYDAY

static func is_online_parallel_phase(state: GameState) -> bool:
	if state == null:
		return false
	if not is_online_mode():
		return false
	var phase := str(state.phase)
	return phase == DefsClass.PHASE_RESTRUCTURING or phase == DefsClass.PHASE_PAYDAY

static func is_valid_player_id(state: GameState, player_id: int) -> bool:
	return state != null and player_id >= 0 and player_id < state.players.size()

static func get_online_local_player_id(state: GameState, fallback_player_id: int = -1) -> int:
	if not is_online_mode() or NetContext == null:
		return fallback_player_id
	var local_pid := int(NetContext.local_player_id)
	if state == null:
		return local_pid if local_pid >= 0 else fallback_player_id
	if is_valid_player_id(state, local_pid):
		return local_pid
	return fallback_player_id

static func is_player_payday_confirmed(state: GameState, player_id: int) -> bool:
	if not is_online_parallel_payday(state):
		return false
	if not is_valid_player_id(state, player_id):
		return false
	if not (state.round_state is Dictionary):
		return false
	var passed_read := RoundStateSubPhasePassedClass.require_sub_phase_passed(
		state.round_state,
		"OnlinePhaseInteraction.is_player_payday_confirmed"
	)
	if not passed_read.ok:
		return false
	var passed: Dictionary = passed_read.value
	return bool(passed.get(player_id, false))

static func can_player_act_in_online_payday(state: GameState, player_id: int) -> bool:
	if not is_online_parallel_payday(state):
		return false
	return is_valid_player_id(state, player_id) and not is_player_payday_confirmed(state, player_id)

static func can_local_player_act_in_online_phase(state: GameState) -> bool:
	if not is_online_mode():
		return false
	if state == null:
		return false
	var local_pid := get_online_local_player_id(state, -1)
	if local_pid < 0:
		return false
	if str(state.phase) == DefsClass.PHASE_RESTRUCTURING:
		return true
	if str(state.phase) == DefsClass.PHASE_PAYDAY:
		return can_player_act_in_online_payday(state, local_pid)
	return int(state.get_current_player_id()) == local_pid
