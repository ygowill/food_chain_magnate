# 完整事件时间线构建（用于“完整日志时间线/回放”）
# 该文件位于 gameplay 层：属于 UI/回放/日志派生视图构建，不是 core 执行内核。
# - 包含初始化事件（command_index = -1）
# - 为每条事件补齐 command_index，并写入确定性的 sequence/timestamp（用于 UI 稳定排序）
extends RefCounted

const EventHistoryRebuildClass = preload("res://core/engine/game_engine/event_history_rebuild.gd")
const GameStartedEventBuildClass = preload("res://core/engine/game_engine/game_started_event_build.gd")
const TimelineEventHelpersClass = preload("res://gameplay/replay/timeline_event_helpers.gd")

static func build_full(engine: GameEngine) -> Result:
	if engine == null:
		return Result.failure("EventTimelineBuild: engine 为空")

	var init_check := engine.ensure_initialized()
	if not init_check.ok:
		return init_check

	var out: Array[Dictionary] = []
	var warnings: Array[String] = []
	var seq := 0

	# 1) 初始化事件（不属于任何命令）
	var init_event := _build_game_started_event(engine)
	if not init_event.ok:
		return Result.failure("EventTimelineBuild: GAME_STARTED 构建失败: %s" % init_event.error)
	warnings.append_array(init_event.warnings)

	var init_data: Dictionary = init_event.value
	seq = TimelineEventHelpersClass.append_timeline_event(out, EventBus.EventType.GAME_STARTED, init_data, seq, -1)

	# 2) 命令时间线事件（按命令重放生成，稳定顺序）
	var last_index := engine.command_history.size() - 1
	if last_index < 0:
		return Result.success(out).with_warnings(warnings)

	var history_r: Result = EventHistoryRebuildClass.build(engine, last_index)
	if not history_r.ok:
		return Result.failure("EventTimelineBuild: 重建事件失败: %s" % history_r.error).with_warnings(warnings).with_warnings(history_r.warnings)

	var events_val = history_r.value
	var events: Array = events_val if (events_val is Array) else []
	for ev_val in events:
		if not (ev_val is Dictionary):
			continue
		var ev: Dictionary = ev_val
		var t: String = str(ev.get("type", "")).strip_edges()
		if t.is_empty():
			continue
		var d_val = ev.get("data", {})
		var d: Dictionary = d_val if (d_val is Dictionary) else {}
		var cmd_index := int(d.get("command_index", -1))

		seq = TimelineEventHelpersClass.append_timeline_event(out, t, d, seq, cmd_index)

	return Result.success(out).with_warnings(warnings).with_warnings(history_r.warnings)

static func _build_game_started_event(engine: GameEngine) -> Result:
	if engine == null:
		return Result.failure("EventTimelineBuild: engine 为空")
	if engine.state == null:
		return Result.failure("EventTimelineBuild: state 为空")

	# 优先从初始 checkpoint 构建（更贴近 command_index=-1 的语义）。
	if engine.checkpoints.is_empty():
		return Result.failure("EventTimelineBuild: 缺少初始 checkpoint")

	var cp_val = engine.checkpoints[0]
	if not (cp_val is Dictionary):
		return Result.failure("EventTimelineBuild: checkpoints[0] 类型错误（期望 Dictionary）")
	var cp: Dictionary = cp_val
	var state_dict_val = cp.get("state_dict", null)
	if not (state_dict_val is Dictionary):
		return Result.failure("EventTimelineBuild: checkpoints[0].state_dict 缺失或类型错误（期望 Dictionary）")

	var data_read := GameStartedEventBuildClass.build_from_state_dict(state_dict_val, "EventTimelineBuild")
	if not data_read.ok:
		return data_read

	return data_read
