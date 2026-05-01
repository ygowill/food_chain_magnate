# GameEngine：EventBus 历史重建（用于 rewind/undo/redo）
# 目标：在“时间线回退”后，将 EventBus.history 重建到目标命令索引，确保 UI 日志可一致恢复。
extends RefCounted

const CommandRunnerClass = preload("res://core/engine/game_engine/command_runner.gd")
const ReplayStepRunnerClass = preload("res://core/engine/game_engine/replay_step_runner.gd")

static func build(engine: GameEngine, target_index: int) -> Result:
	if engine == null:
		return Result.failure("EventHistoryRebuild: engine 为空")

	var init_check := engine.ensure_initialized()
	if not init_check.ok:
		return init_check

	if target_index < -1 or target_index >= engine.command_history.size():
		return Result.failure("EventHistoryRebuild: 无效的命令索引: %d" % target_index)
	if engine.checkpoints.is_empty():
		return Result.failure("EventHistoryRebuild: 缺少初始校验点")

	# 从初始校验点恢复（尚未执行任何命令）
	var initial_checkpoint := engine.checkpoints[0]
	var restore_result := GameState.from_dict(initial_checkpoint.state_dict)
	if not restore_result.ok:
		return Result.failure("EventHistoryRebuild: 恢复 initial_checkpoint 失败: %s" % restore_result.error)
	var replay_state: GameState = restore_result.value

	var all_events: Array[Dictionary] = []
	var all_warnings: Array[String] = []

	if target_index < 0:
		return Result.success(all_events)

	for i in range(target_index + 1):
		var cmd: Command = engine.command_history[i]
		var step_result := ReplayStepRunnerClass.apply_replay_command(replay_state, cmd, engine.action_registry, i, "EventHistoryRebuild")
		if not step_result.ok:
			return step_result.with_warnings(all_warnings)
		all_warnings.append_array(step_result.warnings)
		var step_info: Dictionary = Dictionary(step_result.value)
		var executor = step_info.get("executor", null)
		if executor == null:
			return Result.failure("EventHistoryRebuild: 回放命令 #%d executor 为空" % i).with_warnings(all_warnings)

		var new_state: GameState = step_info.get("state", null)

		# 生成事件（与 CommandRunner.execute_command 对齐）
		var events: Array = executor.generate_events(replay_state, new_state, cmd)
		events.append_array(CommandRunnerClass.build_player_cash_changed_events(replay_state, new_state, cmd))

		var auto_r: Result = CommandRunnerClass.drain_auto_advances(engine, new_state)
		if not auto_r.ok:
			return Result.failure("EventHistoryRebuild: auto_advance 失败(命令 #%d): %s" % [i, auto_r.error])
		all_warnings.append_array(auto_r.warnings)

		if auto_r.value is Dictionary:
			var auto_info: Dictionary = auto_r.value
			var auto_events_val = auto_info.get("events", null)
			if auto_events_val is Array:
				events.append_array(Array(auto_events_val))
			var auto_state_val = auto_info.get("state", null)
			if auto_state_val is GameState:
				new_state = auto_state_val

		events.append_array(CommandRunnerClass.build_milestone_achieved_events(replay_state, new_state, cmd))

		var normalized_events_r := CommandRunnerClass.normalize_event_list(events, "EventHistoryRebuild command #%d" % i)
		if not normalized_events_r.ok:
			return Result.failure("EventHistoryRebuild: %s" % normalized_events_r.error).with_warnings(all_warnings)
		var normalized_events: Array = normalized_events_r.value
		for e_val in normalized_events:
			var e: Dictionary = e_val
			var d: Dictionary = Dictionary(e.get("data")).duplicate(true)
			d["command_index"] = i
			e["data"] = d
			all_events.append(e)

		# 额外的“命令已执行”事件（便于回放验证与 UI 过滤/恢复）
		all_events.append({
			"type": "command_executed",
			"data": {
				"command_index": i,
				"action_id": str(cmd.action_id),
				"actor": int(cmd.actor),
			}
		})

		replay_state = new_state

	return Result.success(all_events).with_warnings(all_warnings)
