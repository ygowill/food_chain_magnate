extends RefCounted

const DATA_DEFER_KEY := "_timeline_defer"
const DEFER_CLEANUP_AFTER_DISCARDS := "cleanup_after_discards"
const POLICY_DEFER_SETTLEMENT_EFFECTS_UNTIL_PHASE_EXIT := "defer_settlement_effects_until_phase_exit"
const PENDING_META_KEY := "pending_timeline_events"
const PENDING_PHASE_EXIT_EFFECTS_KEY := "phase_exit_effects"
const PENDING_CLEANUP_AFTER_DISCARDS_KEY := "cleanup_after_discards"

static func mark_cleanup_after_discards(data: Dictionary) -> Dictionary:
	var out: Dictionary = data.duplicate(true) if data is Dictionary else {}
	out[DATA_DEFER_KEY] = {
		"kind": DEFER_CLEANUP_AFTER_DISCARDS,
	}
	return out

static func should_defer_cleanup_after_discards(event: Dictionary) -> bool:
	if event == null or not (event is Dictionary):
		return false
	var data_val = event.get("data", null)
	if not (data_val is Dictionary):
		return false
	var data: Dictionary = data_val
	var defer_val = data.get(DATA_DEFER_KEY, null)
	if not (defer_val is Dictionary):
		return false
	var defer_info: Dictionary = defer_val
	return str(defer_info.get("kind", "")).strip_edges() == DEFER_CLEANUP_AFTER_DISCARDS

static func build_defer_settlement_effects_until_phase_exit_policy() -> Dictionary:
	return {
		"kind": POLICY_DEFER_SETTLEMENT_EFFECTS_UNTIL_PHASE_EXIT,
	}

static func is_defer_settlement_effects_until_phase_exit_policy(policy: Dictionary) -> bool:
	if policy == null or not (policy is Dictionary):
		return false
	return str(policy.get("kind", "")).strip_edges() == POLICY_DEFER_SETTLEMENT_EFFECTS_UNTIL_PHASE_EXIT
