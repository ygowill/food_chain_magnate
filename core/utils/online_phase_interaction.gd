class_name OnlinePhaseInteraction
extends RefCounted

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const RoundStatePlayerBoolFlagsClass = preload("res://core/utils/round_state_player_bool_flags.gd")
const RoundStateSubPhasePassedClass = preload("res://core/utils/round_state_sub_phase_passed.gd")
const KIND_CONFIRM_DINNERTIME := "confirm_dinnertime"

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
	return phase == DefsClass.PHASE_RESTRUCTURING \
		or phase == DefsClass.PHASE_PAYDAY \
		or phase == DefsClass.PHASE_DINNERTIME

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

static func can_player_act_in_online_dinnertime(state: GameState, player_id: int) -> bool:
	if state == null:
		return false
	if str(state.phase) != DefsClass.PHASE_DINNERTIME:
		return false
	if not is_valid_player_id(state, player_id):
		return false

	var pending := _read_dinnertime_pending_list(state)
	if pending.is_empty():
		return false
	if _is_legacy_confirm_dinnertime_pending(pending):
		return true
	if _is_only_player_confirm_dinnertime_pending(pending):
		return _list_has_player_confirm_dinnertime_pending(pending, player_id)

	var first_val = pending[0]
	if not (first_val is Dictionary):
		return false
	var first: Dictionary = first_val
	if _read_integral_player_id(first.get("player_id", null)) == player_id:
		return true
	return _read_integral_player_id(first.get("seller", null)) == player_id

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
	if str(state.phase) == DefsClass.PHASE_DINNERTIME:
		return can_player_act_in_online_dinnertime(state, local_pid)
	return int(state.get_current_player_id()) == local_pid

static func _read_dinnertime_pending_list(state: GameState) -> Array:
	if state == null:
		return []
	if not (state.round_state is Dictionary):
		return []
	var rs: Dictionary = state.round_state
	var ppa_val = rs.get("pending_phase_actions", null)
	if not (ppa_val is Dictionary):
		return []
	var ppa: Dictionary = ppa_val
	var list_val = ppa.get(DefsClass.PHASE_DINNERTIME, null)
	if not (list_val is Array):
		return []
	return Array(list_val)

static func _is_legacy_confirm_dinnertime_pending(list: Array) -> bool:
	return list.size() == 1 and (list[0] is String) and str(list[0]) == KIND_CONFIRM_DINNERTIME

static func _is_only_player_confirm_dinnertime_pending(list: Array) -> bool:
	if list.is_empty():
		return false
	for item_val in list:
		if not (item_val is Dictionary):
			return false
		var item: Dictionary = item_val
		if str(item.get("kind", "")).strip_edges() != KIND_CONFIRM_DINNERTIME:
			return false
		if _read_integral_player_id(item.get("player_id", null)) < 0:
			return false
	return true

static func _list_has_player_confirm_dinnertime_pending(list: Array, player_id: int) -> bool:
	for item_val in list:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if str(item.get("kind", "")).strip_edges() != KIND_CONFIRM_DINNERTIME:
			continue
		if _read_integral_player_id(item.get("player_id", null)) == player_id:
			return true
	return false

static func _read_integral_player_id(value) -> int:
	if value is int:
		return int(value)
	if value is float:
		var f: float = float(value)
		if f == floor(f):
			return int(f)
	return -1

static func can_player_reopen_online_restructuring(state: GameState, player_id: int) -> bool:
	if state == null:
		return false
	if not is_online_mode():
		return false
	if str(state.phase) != DefsClass.PHASE_RESTRUCTURING:
		return false
	if not is_valid_player_id(state, player_id):
		return false
	if not (state.round_state is Dictionary):
		return false
	var restructuring_val = state.round_state.get("restructuring", null)
	if not (restructuring_val is Dictionary):
		return false
	var restructuring: Dictionary = restructuring_val
	if bool(restructuring.get("finalized", false)):
		return false
	var submitted_read := RoundStatePlayerBoolFlagsClass.get_player_flag(
		state.round_state,
		["restructuring", "submitted"],
		player_id,
		"OnlinePhaseInteraction.can_player_reopen_online_restructuring"
	)
	if not submitted_read.ok:
		return false
	return bool(submitted_read.value)

static func clear_player_restructuring_submission_for_online_reopen(state: GameState, player_id: int) -> void:
	if not can_player_reopen_online_restructuring(state, player_id):
		return
	if not (state.round_state is Dictionary):
		return
	var _set_r := RoundStatePlayerBoolFlagsClass.set_player_flag(
		state.round_state,
		["restructuring", "submitted"],
		player_id,
		false,
		"OnlinePhaseInteraction.clear_player_restructuring_submission_for_online_reopen"
	)
	var restructuring_val = state.round_state.get("restructuring", null)
	if restructuring_val is Dictionary:
		var restructuring: Dictionary = restructuring_val
		restructuring["finalized"] = false
