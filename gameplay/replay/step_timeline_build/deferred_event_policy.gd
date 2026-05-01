extends RefCounted

const DATA_DEFER_KEY := "_timeline_defer"
const DEFER_CLEANUP_AFTER_DISCARDS := "cleanup_after_discards"

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
