class_name CleanupPreview
extends RefCounted

const AiEngineForkClass = preload("res://core/ai/simulation/ai_engine_fork.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const PreviewLogSilencerClass = preload("res://core/ai/analysis/preview_log_silencer.gd")

const KIND_CONFIRM_DINNERTIME := "confirm_dinnertime"

static func preview_after_commands(
	engine: GameEngine,
	commands: Array[Command],
	options: Dictionary = {}
) -> Result:
	if engine == null:
		return Result.failure("CleanupPreview.preview_after_commands: engine is null")

	PreviewLogSilencerClass.silence(options)
	var fork_read := AiEngineForkClass.fork_from_engine(engine)
	if not fork_read.ok:
		_restore_source_registries(engine)
		return fork_read
	var fork: GameEngine = fork_read.value
	var commands_executed: Array = []
	var fallback_commands: Array = []
	var warnings: Array[String] = []

	for i in range(commands.size()):
		var command := commands[i]
		if command == null:
			_restore_source_registries(engine)
			return Result.failure("CleanupPreview.preview_after_commands: command[%d] is null" % i)
		var command_copy := command.duplicate_command()
		var exec_read := _execute_command_for_preview(fork, command_copy)
		if not exec_read.ok:
			_restore_source_registries(engine)
			return Result.failure("CleanupPreview.preview_after_commands: command[%d] failed: %s" % [i, exec_read.error])
		warnings.append_array(exec_read.warnings)
		commands_executed.append(command_copy.to_dict())
		var report_read := _try_extract_report(fork)
		if report_read.ok:
			var payload := _build_payload(fork, report_read.value, commands_executed, fallback_commands, warnings)
			_restore_source_registries(engine)
			return Result.success(payload)

	var initial_report := _try_extract_report(fork)
	if initial_report.ok:
		var payload2 := _build_payload(fork, initial_report.value, commands_executed, fallback_commands, warnings)
		_restore_source_registries(engine)
		return Result.success(payload2)

	var max_steps := int(options.get("max_steps", 48))
	if max_steps <= 0:
		_restore_source_registries(engine)
		return Result.failure("CleanupPreview.preview_after_commands: max_steps must be positive")

	for _step in range(max_steps):
		var state := fork.get_state()
		if state == null:
			_restore_source_registries(engine)
			return Result.failure("CleanupPreview.preview_after_commands: fork state is null")

		var fallback_read := _build_fallback_command(fork)
		if not fallback_read.ok:
			var failure := Result.failure("CleanupPreview.preview_after_commands: cannot reach Cleanup report: %s" % fallback_read.error).with_value({
				"engine": fork,
				"state": state,
				"commands_executed": commands_executed,
				"fallback_commands_executed": fallback_commands,
				"warnings": warnings,
			})
			_restore_source_registries(engine)
			return failure
		var fallback: Command = fallback_read.value
		var exec_fallback := _execute_command_for_preview(fork, fallback)
		if not exec_fallback.ok:
			_restore_source_registries(engine)
			return Result.failure("CleanupPreview.preview_after_commands: fallback failed: %s" % exec_fallback.error)
		warnings.append_array(exec_fallback.warnings)
		fallback_commands.append(fallback.to_dict())

		var report_read2 := _try_extract_report(fork)
		if report_read2.ok:
			var payload3 := _build_payload(fork, report_read2.value, commands_executed, fallback_commands, warnings)
			_restore_source_registries(engine)
			return Result.success(payload3)

	var max_steps_failure := Result.failure("CleanupPreview.preview_after_commands: max_steps reached before Cleanup report").with_value({
		"engine": fork,
		"state": fork.get_state(),
		"commands_executed": commands_executed,
		"fallback_commands_executed": fallback_commands,
		"warnings": warnings,
	})
	_restore_source_registries(engine)
	return max_steps_failure

static func _execute_command_for_preview(engine: GameEngine, command: Command) -> Result:
	if engine == null:
		return Result.failure("engine is null")
	if command == null:
		return Result.failure("command is null")
	var state := engine.get_state()
	if state == null:
		return Result.failure("state is null")
	if str(state.phase) == DefsClass.PHASE_CLEANUP and str(command.action_id) != ActionIdsClass.ADVANCE_PHASE:
		return _execute_cleanup_command_without_auto_skip(engine, command)
	if str(command.action_id) == ActionIdsClass.ADVANCE_PHASE and _should_direct_advance_without_auto_skip(str(state.phase)):
		return _execute_phase_advance_without_auto_skip(engine, command)
	return engine.execute_command(command)

static func _should_direct_advance_without_auto_skip(phase_name: String) -> bool:
	return phase_name == DefsClass.PHASE_PAYDAY or phase_name == DefsClass.PHASE_MARKETING

static func _execute_phase_advance_without_auto_skip(engine: GameEngine, command: Command) -> Result:
	var state := engine.get_state()
	if state == null:
		return Result.failure("state is null")
	if not _should_direct_advance_without_auto_skip(str(state.phase)):
		return Result.failure("direct advance is not supported from phase %s" % str(state.phase))
	if not str(state.sub_phase).is_empty():
		return Result.failure("%s sub_phase is not empty" % str(state.phase))
	var target := str(command.params.get("target", "phase"))
	if target != "phase":
		return Result.failure("direct advance only supports target=phase")
	if not _command_validates(engine, command):
		return Result.failure("%s advance command does not validate" % str(state.phase))
	if command.phase.is_empty():
		command.phase = state.phase
	if command.sub_phase.is_empty():
		command.sub_phase = state.sub_phase
	if command.timestamp < 0:
		command.timestamp = DefsClass.compute_timestamp(state)
	var advance := engine.phase_manager.advance_phase(state)
	if not advance.ok:
		return advance
	return Result.success(state).with_warnings(advance.warnings)

static func _execute_cleanup_command_without_auto_skip(engine: GameEngine, command: Command) -> Result:
	var state := engine.get_state()
	if state == null:
		return Result.failure("state is null")
	if str(state.phase) != DefsClass.PHASE_CLEANUP:
		return Result.failure("not in Cleanup")
	if engine.action_registry == null:
		return Result.failure("action registry is null")
	var executor := engine.action_registry.get_executor(command.action_id)
	if executor == null:
		return Result.failure("unknown action: %s" % str(command.action_id))
	if command.phase.is_empty():
		command.phase = state.phase
	if command.sub_phase.is_empty():
		command.sub_phase = state.sub_phase
	if command.timestamp < 0:
		command.timestamp = DefsClass.compute_timestamp(state)
	var gate := engine.action_registry.run_validators(state, command)
	if not gate.ok:
		return gate
	var compute := executor.compute_new_state(state, command)
	if not compute.ok:
		return compute
	engine.state = compute.value
	return Result.success(engine.state).with_warnings(compute.warnings)

static func _try_extract_report(engine: GameEngine) -> Result:
	if engine == null:
		return Result.failure("CleanupPreview._try_extract_report: engine is null")
	var state := engine.get_state()
	if state == null:
		return Result.failure("CleanupPreview._try_extract_report: state is null")
	if not (state.round_state is Dictionary):
		return Result.failure("CleanupPreview._try_extract_report: round_state is not Dictionary")
	var report_val = Dictionary(state.round_state).get("cleanup", null)
	if not (report_val is Dictionary):
		return Result.failure("CleanupPreview._try_extract_report: round_state.cleanup is missing")
	var report: Dictionary = Dictionary(report_val).duplicate(true)
	for key in ["inventory_discarded", "fridge_choice_pending"]:
		if not report.has(key):
			return Result.failure("CleanupPreview._try_extract_report: cleanup.%s is missing" % key)
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
		"inventory_discarded": _copy_array(report.get("inventory_discarded", [])),
		"fridge_choice_pending": bool(report.get("fridge_choice_pending", false)),
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
			var pending_dinner := _pending_player_for_kind(state, DefsClass.PHASE_DINNERTIME, KIND_CONFIRM_DINNERTIME)
			if not pending_dinner.ok:
				return pending_dinner
			var pending_actor := int(pending_dinner.value)
			if pending_actor >= 0:
				var confirm := Command.create(KIND_CONFIRM_DINNERTIME, pending_actor, {})
				if _command_validates(engine, confirm):
					return Result.success(confirm)
				return Result.failure("pending Dinnertime confirm command does not validate for player %d" % pending_actor)
			var advance_dinner := Command.create_system(ActionIdsClass.ADVANCE_PHASE)
			if _command_validates(engine, advance_dinner):
				return Result.success(advance_dinner)
			return Result.failure("no valid Dinnertime fallback command")
		DefsClass.PHASE_PAYDAY:
			var advance_payday := Command.create_system(ActionIdsClass.ADVANCE_PHASE)
			if _command_validates(engine, advance_payday):
				return Result.success(advance_payday)
			return Result.failure("no valid Payday fallback command")
		DefsClass.PHASE_MARKETING:
			var advance_marketing := Command.create_system(ActionIdsClass.ADVANCE_PHASE)
			if _command_validates(engine, advance_marketing):
				return Result.success(advance_marketing)
			return Result.failure("no valid Marketing fallback command")
		DefsClass.PHASE_CLEANUP:
			return Result.failure("Cleanup reached without report")
		_:
			return Result.failure("phase requires player choice before preview: %s/%s" % [str(state.phase), str(state.sub_phase)])

static func _pending_player_for_kind(state: GameState, phase_name: String, kind: String) -> Result:
	if state == null:
		return Result.failure("state is null")
	if not (state.round_state is Dictionary):
		return Result.failure("round_state is not Dictionary")
	var rs: Dictionary = state.round_state
	var ppa_val = rs.get("pending_phase_actions", null)
	if ppa_val == null:
		return Result.success(-1)
	if not (ppa_val is Dictionary):
		return Result.failure("round_state.pending_phase_actions is not Dictionary")
	var ppa: Dictionary = ppa_val
	var list_val = ppa.get(phase_name, null)
	if list_val == null:
		return Result.success(-1)
	if not (list_val is Array):
		return Result.failure("round_state.pending_phase_actions[%s] is not Array" % phase_name)
	var list: Array = list_val
	for i in range(list.size()):
		var item_val = list[i]
		if item_val is String:
			if str(item_val) == kind:
				return Result.failure("round_state.pending_phase_actions[%s] legacy global %s is unsupported" % [phase_name, kind])
			continue
		if not (item_val is Dictionary):
			return Result.failure("round_state.pending_phase_actions[%s][%d] is not Dictionary" % [phase_name, i])
		var item: Dictionary = item_val
		if str(item.get("kind", "")) != kind:
			continue
		var pid_val = item.get("player_id", null)
		if pid_val is int:
			return Result.success(int(pid_val))
		if pid_val is float:
			var f: float = float(pid_val)
			if f == floor(f):
				return Result.success(int(f))
		return Result.failure("round_state.pending_phase_actions[%s][%d].player_id is not int" % [phase_name, i])
	return Result.success(-1)

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

static func _restore_source_registries(engine: GameEngine) -> void:
	PreviewLogSilencerClass.restore()
	if engine != null:
		engine.activate_registry_bundles()
