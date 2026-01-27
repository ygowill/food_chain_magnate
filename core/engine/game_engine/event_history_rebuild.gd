# GameEngine：EventBus 历史重建（用于 rewind/undo/redo）
# 目标：在“时间线回退”后，将 EventBus.history 重建到目标命令索引，确保 UI 日志可一致恢复。
extends RefCounted

const CommandRunnerClass = preload("res://core/engine/game_engine/command_runner.gd")
const ReplayClass = preload("res://core/engine/game_engine/replay.gd")

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
		var executor := engine.action_registry.get_executor(cmd.action_id)
		if executor == null:
			return Result.failure("EventHistoryRebuild: 回放时找不到执行器: %s" % cmd.action_id)

		var force_execute := ReplayClass.should_force_execute_in_replay(cmd)
		if force_execute and executor.requires_actor:
			# 与 ReplayClass 保持一致：强制命令仍要求 actor 为当前玩家，避免破坏时间线一致性。
			var current_player_id := replay_state.get_current_player_id()
			if cmd.actor != current_player_id:
				return Result.failure("EventHistoryRebuild: 回放强制命令 #%d actor 非当前玩家: actor=%d current=%d" % [i, cmd.actor, current_player_id])

		var step_result := executor.compute_new_state_force(replay_state, cmd) if force_execute else executor.compute_new_state(replay_state, cmd)
		if not step_result.ok:
			return Result.failure("EventHistoryRebuild: 回放命令 #%d 失败: %s" % [i, step_result.error])
		all_warnings.append_array(step_result.warnings)

		var new_state: GameState = step_result.value

		# 生成事件（与 CommandRunner.execute_command 对齐）
		var events := executor.generate_events(replay_state, new_state, cmd)
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

		for e_val in events:
			if not (e_val is Dictionary):
				continue
			var e: Dictionary = e_val
			var d_val = e.get("data", {})
			var d: Dictionary = d_val if (d_val is Dictionary) else {}
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
