# Manual logs archive replay test
# Covers issue_tracker #49: provide a manual save that can be loaded to review log changes.
class_name ManualLogSaveTest
extends RefCounted

const SAVE_RES_PATH := "res://.savings/manual_cases/logs/event_log_review.json"

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

	# Avoid polluting subsequent tests with history from a replay-loaded archive.
	if EventBus.has_method("clear_history_and_reset_sequence"):
		EventBus.clear_history_and_reset_sequence()
	elif EventBus.has_method("clear_history"):
		EventBus.clear_history()

	return Result.success({})

