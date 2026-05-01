# GameEngine：历史命令单步应用（replay / rewind / timeline rebuild 共用）
extends RefCounted

static func should_force_execute_in_replay(_command: Command, _replay_state: GameState = null) -> bool:
	# Replay/archive/timeline rebuild must be strict: command history is a persisted fact stream,
	# not a runtime debug command source. Runtime debug_force remains handled by CommandRunner
	# only when executing a new command outside replay mode.
	return false

static func apply_replay_command(
	replay_state: GameState,
	command: Command,
	action_registry: ActionRegistry,
	command_index: int,
	context: String
) -> Result:
	var prefix := str(context).strip_edges()
	if prefix.is_empty():
		prefix = "ReplayStepRunner"
	if replay_state == null:
		return Result.failure("%s: replay_state 为空" % prefix)
	if command == null:
		return Result.failure("%s: command_history[%d] 为空" % [prefix, int(command_index)])
	if action_registry == null:
		return Result.failure("%s: action_registry 为空" % prefix)

	var executor := action_registry.get_executor(command.action_id)
	if executor == null:
		return Result.failure("%s: 回放时找不到执行器: %s" % [prefix, str(command.action_id)])

	var force_execute := should_force_execute_in_replay(command, replay_state)
	if force_execute and executor.requires_actor:
		var actor_check := _validate_force_actor(replay_state, command, int(command_index), prefix)
		if not actor_check.ok:
			return actor_check

	var step_result: Result = executor.compute_new_state_force(replay_state, command) if force_execute else executor.compute_new_state(replay_state, command)
	if not step_result.ok:
		return Result.failure("%s: 回放命令 #%d 失败: %s" % [prefix, int(command_index), step_result.error]).with_warnings(step_result.warnings)
	if not (step_result.value is GameState):
		return Result.failure("%s: 回放命令 #%d 失败: state 类型错误（期望 GameState）" % [prefix, int(command_index)]).with_warnings(step_result.warnings)

	return Result.success({
		"old_state": replay_state,
		"state": step_result.value,
		"executor": executor,
		"force_execute": force_execute,
	}).with_warnings(step_result.warnings)

static func _validate_force_actor(state: GameState, command: Command, command_index: int, context: String) -> Result:
	if not (state.players is Array):
		return Result.failure("%s: 回放强制命令 #%d players 类型错误（期望 Array）" % [context, int(command_index)])
	var count := state.players.size()
	if command.actor < 0 or command.actor >= count:
		return Result.failure("%s: 回放强制命令 #%d actor 超出范围: actor=%d players=%d" % [context, int(command_index), command.actor, count])
	return Result.success()
