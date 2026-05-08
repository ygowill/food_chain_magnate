class_name AiEngineFork
extends RefCounted

const BankStateAccessClass = preload("res://core/state/bank_state_access.gd")
const InvariantsClass = preload("res://core/engine/game_engine/invariants.gd")

class _SilentEventSink:
	extends RefCounted

	func emit_event(_event_type: String, _data: Dictionary) -> void:
		pass

	func clear_history_and_reset_sequence() -> void:
		pass

	func clear_history() -> void:
		pass

	func record_event(_event_type: String, _data: Dictionary) -> void:
		pass

static func fork_from_engine(source: GameEngine) -> Result:
	if source == null:
		return Result.failure("AiEngineFork.fork_from_engine: source engine is null")
	var source_state := source.get_state()
	if source_state == null:
		return Result.failure("AiEngineFork.fork_from_engine: source state is null")
	if source.random_manager == null:
		return Result.failure("AiEngineFork.fork_from_engine: source random_manager is null")
	if source.phase_manager == null:
		return Result.failure("AiEngineFork.fork_from_engine: source phase_manager is null")
	if source.action_registry == null:
		return Result.failure("AiEngineFork.fork_from_engine: source action_registry is null")
	if not source.random_manager.has_method("duplicate_manager"):
		return Result.failure("AiEngineFork.fork_from_engine: RandomManager lacks duplicate_manager")
	if not source.phase_manager.has_method("duplicate_runtime"):
		return Result.failure("AiEngineFork.fork_from_engine: PhaseManager lacks duplicate_runtime")
	if not source.action_registry.has_method("duplicate_runtime"):
		return Result.failure("AiEngineFork.fork_from_engine: ActionRegistry lacks duplicate_runtime")

	var fork := GameEngine.new()
	fork.state = source_state.duplicate_state()
	fork.phase_manager = source.phase_manager.duplicate_runtime()
	fork.action_registry = source.action_registry.duplicate_runtime()
	fork.random_manager = source.random_manager.duplicate_manager()
	fork.game_data = source.game_data

	fork.module_plan_v2 = Array(source.module_plan_v2, TYPE_STRING, "", null)
	fork.module_manifests_v2 = source.module_manifests_v2.duplicate(true)
	fork.content_catalog_v2 = source.content_catalog_v2
	fork.ruleset_v2 = source.ruleset_v2
	fork.module_ui_extensions_v2 = source.module_ui_extensions_v2
	fork.modules_v2_base_dir = source.modules_v2_base_dir
	fork.owns_module_runtime_v2 = false
	fork.catalog_registry_bundle = source.catalog_registry_bundle
	fork.rules_registry_bundle = source.rules_registry_bundle
	fork.dependencies = _copy_dependencies_for_fork(source.get_dependencies())

	fork.command_history = _duplicate_command_history(source.command_history)
	fork.current_command_index = int(source.current_command_index)
	fork.checkpoints = source.checkpoints.duplicate(true)
	fork.checkpoint_interval = int(source.checkpoint_interval)
	fork.validate_invariants = bool(source.validate_invariants)
	var invariants_read := _sync_invariant_baselines(fork)
	if not invariants_read.ok:
		return Result.failure("AiEngineFork.fork_from_engine: invariant baseline failed: %s" % invariants_read.error)
	fork.activate_registry_bundles()

	var fork_state := fork.get_state()
	if fork_state == null:
		return Result.failure("AiEngineFork.fork_from_engine: fork state is null")

	var source_hash := str(source_state.compute_hash())
	var fork_hash := str(fork_state.compute_hash())
	if source_hash != fork_hash:
		return Result.failure("AiEngineFork.fork_from_engine: hash mismatch source=%s fork=%s" % [source_hash, fork_hash])
	return Result.success(fork)

static func _copy_dependencies_for_fork(source_dependencies) -> GameEngineDependencies:
	var copy := GameEngineDependencies.new()
	if source_dependencies == null:
		copy.event_sink = _SilentEventSink.new()
		return copy

	copy.action_setup_provider = source_dependencies.action_setup_provider
	copy.command_runner_event_build_provider = source_dependencies.command_runner_event_build_provider
	copy.restaurant_logo_assignment_provider = source_dependencies.restaurant_logo_assignment_provider
	copy.game_config_overrides = _duplicate_dependency_value(source_dependencies.game_config_overrides)
	copy.game_option_overrides = _duplicate_dependency_value(source_dependencies.game_option_overrides)
	copy.command_runner_debug_options = _duplicate_dependency_value(source_dependencies.command_runner_debug_options)
	copy.event_sink = _SilentEventSink.new()
	return copy

static func _duplicate_dependency_value(value):
	if value is Dictionary:
		return Dictionary(value).duplicate(true)
	return value

static func _duplicate_command_history(commands: Array[Command]) -> Array[Command]:
	var out: Array[Command] = []
	for command in commands:
		if command != null:
			out.append(command.duplicate_command())
	return out

static func _sync_invariant_baselines(fork: GameEngine) -> Result:
	if fork == null or fork.get_state() == null:
		return Result.failure("fork/state is null")
	var state := fork.get_state()
	var total_cash_read := InvariantsClass.compute_total_cash(state)
	if not total_cash_read.ok:
		return total_cash_read
	var reserve_added_total_read := BankStateAccessClass.require_reserve_added_total(state, "AiEngineFork")
	if not reserve_added_total_read.ok:
		return reserve_added_total_read
	var removed_total_read := BankStateAccessClass.require_removed_total(state, "AiEngineFork")
	if not removed_total_read.ok:
		return removed_total_read
	fork.set_initial_total_cash_for_invariants(
		int(total_cash_read.value) - int(reserve_added_total_read.value) + int(removed_total_read.value)
	)

	var employee_totals_read := InvariantsClass.compute_employee_base_totals_for_invariants(state)
	if not employee_totals_read.ok:
		return employee_totals_read
	fork.set_initial_employee_totals_for_invariants(employee_totals_read.value)
	return Result.success()
