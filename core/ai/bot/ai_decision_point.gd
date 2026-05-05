class_name AiDecisionPoint
extends RefCounted

const RESERVE_CARD := "RESERVE_CARD"
const INITIAL_RESTAURANT := "INITIAL_RESTAURANT"
const RESTRUCTURING := "RESTRUCTURING"
const ORDER_OF_BUSINESS := "ORDER_OF_BUSINESS"
const WORKING_SUB_PHASE := "WORKING_SUB_PHASE"
const PAYDAY := "PAYDAY"
const CLEANUP_PENDING := "CLEANUP_PENDING"
const CONFIRM_SETTLEMENT := "CONFIRM_SETTLEMENT"
const NO_DECISION := "NO_DECISION"

static func from_context(context: AiDecisionContext) -> String:
	if context == null:
		return NO_DECISION
	return from_phase(str(context.phase), str(context.sub_phase))

static func from_observation(observation: ObservationState) -> String:
	if observation == null:
		return NO_DECISION
	if _has_pending_confirmation(observation.round_state_public):
		return CONFIRM_SETTLEMENT
	if _has_cleanup_pending(observation.round_state_public):
		return CLEANUP_PENDING
	return from_phase(str(observation.phase), str(observation.sub_phase))

static func from_phase(phase: String, sub_phase: String) -> String:
	match phase:
		"Setup":
			if sub_phase == "ReserveCards":
				return RESERVE_CARD
			return INITIAL_RESTAURANT
		"Restructuring":
			return RESTRUCTURING
		"OrderOfBusiness":
			return ORDER_OF_BUSINESS
		"Working":
			return WORKING_SUB_PHASE
		"Payday":
			return PAYDAY
		"Cleanup":
			return CLEANUP_PENDING
		_:
			return NO_DECISION

static func _has_cleanup_pending(round_state: Dictionary) -> bool:
	var cleanup_val = round_state.get("cleanup", null)
	if cleanup_val is Dictionary:
		var cleanup: Dictionary = cleanup_val
		if cleanup.has("pending_choice_kind") and not str(cleanup.get("pending_choice_kind", "")).is_empty():
			return true
	var pending_val = round_state.get("pending_cleanup_tasks", null)
	return pending_val is Array and not Array(pending_val).is_empty()

static func _has_pending_confirmation(round_state: Dictionary) -> bool:
	var pending_val = round_state.get("pending_phase_actions", null)
	return pending_val is Array and not Array(pending_val).is_empty()
