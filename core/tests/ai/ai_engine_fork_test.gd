class_name AiEngineForkTest
extends RefCounted

const AiEngineForkClass = preload("res://core/ai/simulation/ai_engine_fork.gd")
const AutoloadAccessClass = preload("res://core/utils/autoload_access.gd")

class _RecordingEventSink:
	extends RefCounted

	var events: Array[Dictionary] = []
	var clear_calls: int = 0

	func emit_event(event_type: String, data: Dictionary) -> void:
		events.append({
			"type": event_type,
			"data": data.duplicate(true),
		})

	func clear_history_and_reset_sequence() -> void:
		clear_calls += 1
		events.clear()

	func clear_history() -> void:
		clear_calls += 1
		events.clear()

static func run(_player_count: int = 2, seed_val: int = 12345) -> Result:
	var sink := _RecordingEventSink.new()
	var engine := GameEngine.new()
	engine.set_event_sink(sink)
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("engine initialize failed: %s" % init.error)
	var source_event_count_after_init := sink.events.size()
	if source_event_count_after_init <= 0:
		return Result.failure("source event sink did not receive init events")

	var bus = AutoloadAccessClass.get_autoload("EventBus")
	var event_bus_marker_count := -1
	if bus != null and bus.has_method("clear_history_and_reset_sequence") and bus.has_method("record_event") and bus.has_method("get_history"):
		bus.clear_history_and_reset_sequence()
		bus.record_event("ai_engine_fork_marker", {"value": 1})
		event_bus_marker_count = bus.get_history().size()

	var fork_read := AiEngineForkClass.fork_from_engine(engine)
	if not fork_read.ok:
		return fork_read
	if sink.events.size() != source_event_count_after_init:
		return Result.failure("fork creation wrote to source event sink")
	if event_bus_marker_count >= 0 and bus.get_history().size() != event_bus_marker_count:
		return Result.failure("fork creation changed EventBus history")

	var fork: GameEngine = fork_read.value
	var source_hash_before := str(engine.get_state().compute_hash())
	if str(fork.get_state().compute_hash()) != source_hash_before:
		return Result.failure("fork hash should match source before simulation")

	var source_rng_next := engine.random_manager.randi()
	var fork_rng_next := fork.random_manager.randi()
	if fork_rng_next != source_rng_next:
		return Result.failure("fork RNG sequence mismatch: source=%d fork=%d" % [source_rng_next, fork_rng_next])

	var actor := engine.get_state().get_current_player_id()
	var command := Command.create("select_reserve_card", actor, {"selected_index": 0})
	var fork_exec := fork.execute_command(command.duplicate_command())
	if not fork_exec.ok:
		return Result.failure("fork execute failed: %s" % fork_exec.error)
	if str(engine.get_state().compute_hash()) != source_hash_before:
		return Result.failure("source hash changed after fork execute")
	if sink.events.size() != source_event_count_after_init:
		return Result.failure("fork execute wrote to source event sink")
	if event_bus_marker_count >= 0 and bus.get_history().size() != event_bus_marker_count:
		return Result.failure("fork execute changed EventBus history")
	var fork_hash_after := str(fork.get_state().compute_hash())

	fork.dispose()
	if engine.action_registry == null or engine.action_registry.get_executor("select_reserve_card") == null:
		return Result.failure("source action registry was invalidated by fork dispose")
	if engine.content_catalog_v2 == null:
		return Result.failure("source content catalog was invalidated by fork dispose")

	var source_exec := engine.execute_command(command.duplicate_command())
	if not source_exec.ok:
		return Result.failure("source execute failed: %s" % source_exec.error)
	if str(engine.get_state().compute_hash()) != fork_hash_after:
		return Result.failure("source/fork hash mismatch after same command")
	if sink.events.size() <= source_event_count_after_init:
		return Result.failure("source execute did not emit to source event sink")
	if event_bus_marker_count >= 0 and bus.has_method("clear_history_and_reset_sequence"):
		bus.clear_history_and_reset_sequence()
	return Result.success()
