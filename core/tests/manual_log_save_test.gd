# Manual logs archive replay test
# Covers issue_tracker #49: provide a manual save that can be loaded to review log changes.
class_name ManualLogSaveTest
extends RefCounted

const SAVE_RES_PATH := "res://testdata/saves/manual_cases/logs/event_log_review.json"

static func run() -> Result:
	if EventBus == null:
		return Result.failure("EventBus is not available")
	if EventBus.has_method("clear_history_and_reset_sequence"):
		EventBus.clear_history_and_reset_sequence()
	elif EventBus.has_method("clear_history"):
		EventBus.clear_history()

	var abs_path := ProjectSettings.globalize_path(SAVE_RES_PATH)
	var engine := GameEngine.new()
	var load := engine.load_from_file(abs_path)
	if not load.ok:
		return Result.failure("load failed: %s" % load.error)
	if engine.get_state() == null:
		return Result.failure("load succeeded but state is null")

	var demand_events := EventBus.get_history_by_type(EventBus.EventType.DEMAND_GENERATED)
	if demand_events.is_empty():
		return Result.failure("expected DEMAND_GENERATED event in history after loading: %s" % SAVE_RES_PATH)

	var drinks_events := EventBus.get_history_by_type(EventBus.EventType.DRINKS_PROCURED)
	if drinks_events.is_empty():
		return Result.failure("expected DRINKS_PROCURED event in history after loading: %s" % SAVE_RES_PATH)

	var marketing_events := EventBus.get_history_by_type(EventBus.EventType.MARKETING_PLACED)
	if marketing_events.is_empty():
		return Result.failure("expected MARKETING_PLACED event in history after loading: %s" % SAVE_RES_PATH)

	# Ensure load-time EventBus.history carries per-event command_index, so UI log restore can map entries back to commands.
	var mk_ci_r := _require_event_command_index(marketing_events[0])
	if not mk_ci_r.ok:
		return Result.failure("MARKETING_PLACED missing command_index: %s" % mk_ci_r.error)
	var dr_ci_r := _require_event_command_index(drinks_events[0])
	if not dr_ci_r.ok:
		return Result.failure("DRINKS_PROCURED missing command_index: %s" % dr_ci_r.error)
	var dg_ci_r := _require_event_command_index(demand_events[0])
	if not dg_ci_r.ok:
		return Result.failure("DEMAND_GENERATED missing command_index: %s" % dg_ci_r.error)

	var mk_ci := int(mk_ci_r.value)
	var dr_ci := int(dr_ci_r.value)
	var dg_ci := int(dg_ci_r.value)
	if mk_ci == dr_ci and dr_ci == dg_ci:
		return Result.failure("expected distinct command_index values across events; got mk=%d dr=%d dg=%d" % [mk_ci, dr_ci, dg_ci])

	# Avoid polluting subsequent tests with history from a replay-loaded archive.
	if EventBus.has_method("clear_history_and_reset_sequence"):
		EventBus.clear_history_and_reset_sequence()
	elif EventBus.has_method("clear_history"):
		EventBus.clear_history()

	return Result.success({})

static func _require_event_command_index(event: Dictionary) -> Result:
	if not (event is Dictionary):
		return Result.failure("event type error (expected Dictionary)")
	var data_val = event.get("data", null)
	if not (data_val is Dictionary):
		return Result.failure("event.data type error (expected Dictionary)")
	var data: Dictionary = data_val

	var ci_val = data.get("command_index", null)
	if ci_val is int:
		return Result.success(int(ci_val))
	if ci_val is float:
		var f: float = float(ci_val)
		if f == floor(f):
			return Result.success(int(f))
	return Result.failure("missing command_index")
