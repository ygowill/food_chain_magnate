class_name DinnerPreview
extends RefCounted

const AiEngineForkClass = preload("res://core/ai/simulation/ai_engine_fork.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

static func preview_after_commands(
	engine: GameEngine,
	commands: Array[Command],
	options: Dictionary = {}
) -> Result:
	if engine == null:
		return Result.failure("DinnerPreview.preview_after_commands: engine is null")

	var fork_read := AiEngineForkClass.fork_from_engine(engine)
	if not fork_read.ok:
		return fork_read
	var fork: GameEngine = fork_read.value
	var commands_executed: Array = []
	var fallback_commands: Array = []
	var warnings: Array[String] = []

	for i in range(commands.size()):
		var command := commands[i]
		if command == null:
			return Result.failure("DinnerPreview.preview_after_commands: command[%d] is null" % i)
		var command_copy := command.duplicate_command()
		var exec_read := fork.execute_command(command_copy)
		if not exec_read.ok:
			return Result.failure("DinnerPreview.preview_after_commands: command[%d] failed: %s" % [i, exec_read.error])
		warnings.append_array(exec_read.warnings)
		commands_executed.append(command_copy.to_dict())
		var report_read := _try_extract_report(fork)
		if report_read.ok:
			return Result.success(_build_payload(fork, report_read.value, commands_executed, fallback_commands, warnings))

	var initial_report := _try_extract_report(fork)
	if initial_report.ok:
		return Result.success(_build_payload(fork, initial_report.value, commands_executed, fallback_commands, warnings))

	var max_steps := int(options.get("max_steps", 32))
	if max_steps <= 0:
		return Result.failure("DinnerPreview.preview_after_commands: max_steps must be positive")

	for _step in range(max_steps):
		var state := fork.get_state()
		if state == null:
			return Result.failure("DinnerPreview.preview_after_commands: fork state is null")

		var fallback_read := _build_fallback_command(fork)
		if not fallback_read.ok:
			return Result.failure("DinnerPreview.preview_after_commands: cannot reach Dinnertime: %s" % fallback_read.error).with_value({
				"engine": fork,
				"state": state,
				"commands_executed": commands_executed,
				"fallback_commands_executed": fallback_commands,
				"warnings": warnings,
			})
		var fallback: Command = fallback_read.value
		var exec_fallback := fork.execute_command(fallback)
		if not exec_fallback.ok:
			return Result.failure("DinnerPreview.preview_after_commands: fallback failed: %s" % exec_fallback.error)
		warnings.append_array(exec_fallback.warnings)
		fallback_commands.append(fallback.to_dict())

		var report_read2 := _try_extract_report(fork)
		if report_read2.ok:
			return Result.success(_build_payload(fork, report_read2.value, commands_executed, fallback_commands, warnings))

	return Result.failure("DinnerPreview.preview_after_commands: max_steps reached before Dinnertime report").with_value({
		"engine": fork,
		"state": fork.get_state(),
		"commands_executed": commands_executed,
		"fallback_commands_executed": fallback_commands,
		"warnings": warnings,
	})

static func _try_extract_report(engine: GameEngine) -> Result:
	if engine == null:
		return Result.failure("DinnerPreview._try_extract_report: engine is null")
	var state := engine.get_state()
	if state == null:
		return Result.failure("DinnerPreview._try_extract_report: state is null")
	if not (state.round_state is Dictionary):
		return Result.failure("DinnerPreview._try_extract_report: round_state is not Dictionary")
	var report_val = Dictionary(state.round_state).get("dinnertime", null)
	if not (report_val is Dictionary):
		return Result.failure("DinnerPreview._try_extract_report: round_state.dinnertime is missing")
	var report: Dictionary = Dictionary(report_val).duplicate(true)
	for key in ["sales", "skipped", "income_sales", "income_tips", "income_cfo_bonus", "total_income", "bankruptcy_events"]:
		if not report.has(key):
			return Result.failure("DinnerPreview._try_extract_report: dinnertime.%s is missing" % key)
	return Result.success(report)

static func _build_payload(
	engine: GameEngine,
	report: Dictionary,
	commands_executed: Array,
	fallback_commands: Array,
	warnings: Array[String]
) -> Dictionary:
	return {
		"engine": engine,
		"state": engine.get_state() if engine != null else null,
		"report": report.duplicate(true),
		"sales": _copy_array(report.get("sales", [])),
		"skipped": _copy_array(report.get("skipped", [])),
		"income_sales": _copy_array(report.get("income_sales", [])),
		"income_tips": _copy_array(report.get("income_tips", [])),
		"income_cfo_bonus": _copy_array(report.get("income_cfo_bonus", [])),
		"total_income": _copy_array(report.get("total_income", [])),
		"bankruptcy_events": _copy_array(report.get("bankruptcy_events", [])),
		"commands_executed": commands_executed.duplicate(true),
		"fallback_commands_executed": fallback_commands.duplicate(true),
		"warnings": warnings.duplicate(),
	}

static func _build_fallback_command(engine: GameEngine) -> Result:
	var state := engine.get_state()
	if state == null:
		return Result.failure("state is null")
	match str(state.phase):
		DefsClass.PHASE_WORKING:
			var actor := state.get_current_player_id()
			if actor < 0:
				return Result.failure("Working current player is invalid")
			for action_id in [ActionIdsClass.SKIP_SUB_PHASE, ActionIdsClass.SKIP]:
				var command := Command.create(action_id, actor, {})
				if _command_validates(engine, command):
					return Result.success(command)
			return Result.failure("no valid Working fallback command")
		DefsClass.PHASE_DINNERTIME:
			return Result.failure("Dinnertime reached without report")
		DefsClass.PHASE_PAYDAY:
			return Result.failure("Payday reached without Dinnertime report")
		_:
			return Result.failure("phase requires player choice before preview: %s/%s" % [str(state.phase), str(state.sub_phase)])

static func _command_validates(engine: GameEngine, command: Command) -> bool:
	if engine == null or command == null:
		return false
	var state := engine.get_state()
	if state == null or engine.action_registry == null:
		return false
	var executor := engine.action_registry.get_executor(command.action_id)
	if executor == null:
		return false
	var gate := engine.action_registry.run_validators(state, command)
	if not gate.ok:
		return false
	var validate := executor.validate(state, command)
	return validate.ok

static func _copy_array(value) -> Array:
	if value is Array:
		return Array(value).duplicate(true)
	return []
