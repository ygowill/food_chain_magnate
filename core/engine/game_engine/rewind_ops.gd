extends RefCounted

const ReplayClass = preload("res://core/engine/game_engine/replay.gd")
const EventHistoryRebuildClass = preload("res://core/engine/game_engine/event_history_rebuild.gd")

static func rewind_to_command(engine, target_index: int) -> Result:
	if engine == null:
		return Result.failure("内部错误：GameEngine 为空")

	var init_check: Result = engine.ensure_initialized()
	if not init_check.ok:
		return init_check

	var replay_result: Result = ReplayClass.rewind_to_command(engine.command_history, engine.checkpoints, engine.action_registry, engine.phase_manager, target_index)
	if not replay_result.ok:
		return replay_result

	var data: Dictionary = replay_result.value
	if not data.has("state") or not (data["state"] is GameState):
		return Result.failure("内部错误: rewind_result.state 类型错误")
	if not data.has("random_manager") or not (data["random_manager"] is RandomManager):
		return Result.failure("内部错误: rewind_result.random_manager 类型错误")
	if not data.has("current_command_index") or not (data["current_command_index"] is int):
		return Result.failure("内部错误: rewind_result.current_command_index 类型错误")

	engine.state = data["state"]
	engine.random_manager = data["random_manager"]
	engine.current_command_index = data["current_command_index"]

	# 重要：回退会改变“当前时间线指针”，需要同步重建 EventBus.history，
	# 否则 UI 日志/回放验证会残留未来事件（undo/redo 视觉上不会真的回到过去）。
	var sink = engine.event_sink
	if sink == null or (not sink.has_method("clear_history_and_reset_sequence")) or (not sink.has_method("record_event")):
		sink = EventBus if (EventBus != null) else null
	if sink != null and sink.has_method("clear_history_and_reset_sequence") and sink.has_method("record_event"):
		var history_r: Result = EventHistoryRebuildClass.build(engine, target_index)
		if not history_r.ok:
			return Result.failure("回退成功，但重建事件历史失败: %s" % history_r.error).with_warnings(replay_result.warnings)
		var events: Array = history_r.value if (history_r.value is Array) else []
		sink.clear_history_and_reset_sequence()
		for ev_val in events:
			if not (ev_val is Dictionary):
				continue
			var ev: Dictionary = ev_val
			var t: String = str(ev.get("type", "")).strip_edges()
			if t.is_empty():
				continue
			var d_val = ev.get("data", {})
			var d: Dictionary = d_val if (d_val is Dictionary) else {}
			sink.record_event(t, d)
		return Result.success(engine.state).with_warnings(replay_result.warnings).with_warnings(history_r.warnings)

	return Result.success(engine.state).with_warnings(replay_result.warnings)

static func full_replay(engine) -> Result:
	if engine == null:
		return Result.failure("内部错误：GameEngine 为空")

	var init_check: Result = engine.ensure_initialized()
	if not init_check.ok:
		return init_check

	if engine.command_history.is_empty():
		return Result.success(engine.state)

	var replay_result: Result = ReplayClass.full_replay(engine.command_history, engine.checkpoints, engine.action_registry, engine.phase_manager)
	if not replay_result.ok:
		return replay_result

	var data: Dictionary = replay_result.value
	if not data.has("state") or not (data["state"] is GameState):
		return Result.failure("内部错误: replay_result.state 类型错误")
	if not data.has("random_manager") or not (data["random_manager"] is RandomManager):
		return Result.failure("内部错误: replay_result.random_manager 类型错误")
	if not data.has("current_command_index") or not (data["current_command_index"] is int):
		return Result.failure("内部错误: replay_result.current_command_index 类型错误")

	engine.state = data["state"]
	engine.random_manager = data["random_manager"]
	engine.current_command_index = data["current_command_index"]
	return Result.success(engine.state)

