# Game timeline：联机恢复房完整历史视图支持
# 负责：完整历史 ready 判定、回放入口 UI 状态、以及 live timeline 数据源选择。
extends RefCounted

const StepTimelineBuildHelpersClass = preload("res://ui/scenes/game/timeline/step_timeline_build_helpers.gd")
const OnlineResumeFullHistoryAdapterClass = preload("res://ui/scenes/game/timeline/online_resume_full_history_adapter.gd")

static func is_full_history_ready() -> bool:
	return OnlineResumeFullHistoryAdapterClass.is_ready()

static func is_full_history_pending() -> bool:
	if not OnlineResumeFullHistoryAdapterClass.is_applicable():
		return false
	return not is_full_history_ready()

static func sync_replay_entry_state(game_log_panel: Object, replay_mode_active: bool) -> void:
	if not is_instance_valid(game_log_panel):
		return
	if not game_log_panel.has_method("set_replay_toggle_availability"):
		return
	var available := true
	var inactive_text := "进入回放"
	var disabled_reason := ""
	if not bool(replay_mode_active) and is_full_history_pending():
		available = false
		inactive_text = "完整历史加载中"
		disabled_reason = "联机完整历史加载中，请稍后再试"
	game_log_panel.call(
		"set_replay_toggle_availability",
		available,
		inactive_text,
		disabled_reason
	)

static func build_live_history_view(
	runtime_engine: GameEngine,
	game_log_panel: Object,
	previous_history_timeline_source: String,
	command_index_to_last_step_index: Callable
) -> Result:
	if runtime_engine == null:
		return Result.failure("runtime_engine 为空")
	if not is_instance_valid(game_log_panel):
		return Result.failure("game_log_panel 无效")

	var restore_runtime_display_engine := false
	var next_history_timeline_source := str(previous_history_timeline_source).strip_edges()
	if OnlineResumeFullHistoryAdapterClass.is_applicable() \
		and not is_full_history_ready() \
		and next_history_timeline_source == "online_resume_full_history":
		restore_runtime_display_engine = true
		next_history_timeline_source = "runtime"

	var build_r: Result
	var cursor_step_index := -1
	if is_full_history_ready():
		build_r = OnlineResumeFullHistoryAdapterClass.build_history_timeline(game_log_panel, false)
	else:
		build_r = StepTimelineBuildHelpersClass.build_and_load(runtime_engine, game_log_panel, false)
	if not build_r.ok:
		return build_r
	if not (build_r.value is Dictionary):
		return Result.failure("构建 step 时间线失败（返回类型错误）")

	var info: Dictionary = Dictionary(build_r.value)
	var timeline_val = info.get("timeline", null)
	if not (timeline_val is Dictionary):
		return Result.failure("构建 step 时间线失败（返回结构错误）")

	var timeline: Dictionary = Dictionary(timeline_val)
	var full_history_source_active := is_full_history_ready()
	next_history_timeline_source = "online_resume_full_history" if full_history_source_active else "runtime"

	var head_step_index := int(info.get("head_step_index", -1))
	var head_cmd := runtime_engine.command_history.size() - 1
	var cursor_cmd := int(runtime_engine.current_command_index)
	if full_history_source_active:
		cursor_step_index = OnlineResumeFullHistoryAdapterClass.map_runtime_command_index_to_step_index(
			cursor_cmd,
			timeline
		)

	var history_cursor_step_index := head_step_index
	if cursor_cmd < 0:
		history_cursor_step_index = -1
	elif cursor_cmd >= head_cmd and not full_history_source_active:
		history_cursor_step_index = head_step_index
	elif full_history_source_active:
		history_cursor_step_index = head_step_index if cursor_step_index < -1 else cursor_step_index
	else:
		history_cursor_step_index = -999
		if command_index_to_last_step_index.is_valid():
			history_cursor_step_index = int(command_index_to_last_step_index.call(cursor_cmd, timeline))
		if history_cursor_step_index < -1:
			history_cursor_step_index = head_step_index

	return Result.success({
		"timeline": timeline,
		"head_step_index": head_step_index,
		"cursor_step_index": history_cursor_step_index,
		"history_timeline_source": next_history_timeline_source,
		"restore_runtime_display_engine": restore_runtime_display_engine,
	})
