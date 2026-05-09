class_name ForwardSimulator
extends RefCounted

const AiEngineForkClass = preload("res://core/ai/simulation/ai_engine_fork.gd")

static func simulate_command(source: GameEngine, command: Command, options: Dictionary = {}) -> Result:
	if command == null:
		return Result.failure("ForwardSimulator.simulate_command: command is null")
	return simulate_commands(source, [command], options)

static func simulate_commands(source: GameEngine, commands: Array[Command], options: Dictionary = {}) -> Result:
	if source == null:
		return Result.failure("ForwardSimulator.simulate_commands: source engine is null")
	if commands.is_empty():
		return Result.failure("ForwardSimulator.simulate_commands: commands is empty")
	var mode := str(options.get("mode", "after_command"))
	if mode != "after_command":
		return Result.failure("ForwardSimulator.simulate_commands: unsupported mode: %s" % mode)
	var budget_val = options.get("budget", null)
	var budget: TimeBudget = budget_val if budget_val is TimeBudget else null

	var fork_read := AiEngineForkClass.fork_from_engine(source)
	if not fork_read.ok:
		_restore_source_registries(source)
		return fork_read
	var fork: GameEngine = fork_read.value

	var executed: Array = []
	var all_warnings: Array[String] = []
	for i in range(commands.size()):
		if budget != null and budget.expired():
			_restore_source_registries(source)
			return Result.failure("ForwardSimulator.simulate_commands: budget expired before command[%d]" % i).with_value(_failure_payload(fork, executed, i, "budget expired", all_warnings))
		var command := commands[i]
		if command == null:
			_restore_source_registries(source)
			return Result.failure("ForwardSimulator.simulate_commands: command[%d] is null" % i).with_value(_failure_payload(fork, executed, i, "command is null", all_warnings))
		var command_copy := command.duplicate_command()
		var exec_read := fork.execute_command(command_copy)
		if not exec_read.ok:
			_restore_source_registries(source)
			return Result.failure("ForwardSimulator.simulate_commands: command[%d] failed: %s" % [i, exec_read.error]).with_value(_failure_payload(fork, executed, i, exec_read.error, all_warnings))
		all_warnings.append_array(exec_read.warnings)
		executed.append(command_copy.to_dict())

	_restore_source_registries(source)
	return Result.success({
		"engine": fork,
		"state": fork.get_state(),
		"commands_executed": executed,
		"warnings": all_warnings,
		"failed_command_index": -1,
		"error": "",
		"budget_expired": budget != null and budget.expired(),
	})

static func _failure_payload(
	fork: GameEngine,
	executed: Array,
	failed_command_index: int,
	error: String,
	warnings: Array[String]
) -> Dictionary:
	return {
		"engine": fork,
		"state": fork.get_state() if fork != null else null,
		"commands_executed": executed,
		"warnings": warnings.duplicate(),
		"failed_command_index": failed_command_index,
		"error": error,
	}

static func _restore_source_registries(source: GameEngine) -> void:
	if source != null:
		source.activate_registry_bundles()
