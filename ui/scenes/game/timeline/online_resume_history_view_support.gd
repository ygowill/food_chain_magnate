# Game timeline：联机恢复房完整历史视图支持
# 负责：完整历史 ready 判定、回放入口 UI 状态、以及 live timeline 数据源选择。
extends RefCounted

const StepTimelineBuildHelpersClass = preload("res://ui/scenes/game/timeline/step_timeline_build_helpers.gd")
const OnlineResumeFullHistoryAdapterClass = preload("res://ui/scenes/game/timeline/online_resume_full_history_adapter.gd")
const StepTimelineHelpersClass = preload("res://gameplay/replay/step_timeline_build/helpers.gd")
const META_REPLAY_TOGGLE_AVAILABILITY_SIGNATURE := "_timeline_replay_toggle_availability_signature"

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
	var next_signature := {
		"available": bool(available),
		"inactive_text": str(inactive_text),
		"disabled_reason": str(disabled_reason),
	}
	if game_log_panel.has_meta(META_REPLAY_TOGGLE_AVAILABILITY_SIGNATURE):
		var previous_signature = game_log_panel.get_meta(META_REPLAY_TOGGLE_AVAILABILITY_SIGNATURE)
		if previous_signature is Dictionary and previous_signature == next_signature:
			return
	game_log_panel.set_meta(META_REPLAY_TOGGLE_AVAILABILITY_SIGNATURE, Dictionary(next_signature))
	game_log_panel.call(
		"set_replay_toggle_availability",
		available,
		inactive_text,
		disabled_reason
	)

static func build_live_history_view(
	runtime_engine: GameEngine,
	game_log_panel: Object,
	_previous_history_timeline_source: String,
	previous_history_timeline: Dictionary,
	allow_incremental_append: bool,
	command_index_to_last_step_index: Callable
) -> Result:
	if runtime_engine == null:
		return Result.failure("runtime_engine 为空")
	if not is_instance_valid(game_log_panel):
		return Result.failure("game_log_panel 无效")
	var cached_prebuilt_r := _try_load_single_full_runtime_prebuilt_timeline(
		runtime_engine,
		game_log_panel,
		command_index_to_last_step_index
	)
	if cached_prebuilt_r.ok:
		return cached_prebuilt_r

	var build_r := StepTimelineBuildHelpersClass.build_and_load(
		runtime_engine,
		game_log_panel,
		false,
		previous_history_timeline,
		allow_incremental_append
	)
	if not build_r.ok:
		return build_r
	if not (build_r.value is Dictionary):
		return Result.failure("构建 step 时间线失败（返回类型错误）")

	var info: Dictionary = Dictionary(build_r.value)
	var timeline_val = info.get("timeline", null)
	if not (timeline_val is Dictionary):
		return Result.failure("构建 step 时间线失败（返回结构错误）")

	var timeline: Dictionary = Dictionary(timeline_val)
	var head_step_index := int(info.get("head_step_index", -1))
	var head_cmd := runtime_engine.command_history.size() - 1
	var cursor_cmd := int(runtime_engine.current_command_index)
	var history_cursor_step_index := head_step_index
	if cursor_cmd < 0:
		history_cursor_step_index = -1
	elif cursor_cmd >= head_cmd:
		history_cursor_step_index = head_step_index
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
		"history_timeline_source": "runtime",
		"restore_runtime_display_engine": false,
	})

static func _try_load_single_full_runtime_prebuilt_timeline(
	runtime_engine: GameEngine,
	game_log_panel: Object,
	command_index_to_last_step_index: Callable
) -> Result:
	if NetContext == null or NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return Result.failure("not_online_client")
	if str(NetContext.room_state.get("room_mode", "")).strip_edges() != "resume_archive":
		return Result.failure("not_resume_archive")
	if NetClient == null or not NetClient.has_method("get_online_resume_session_snapshot"):
		return Result.failure("session_snapshot_unavailable")
	var snapshot: Dictionary = Dictionary(NetClient.get_online_resume_session_snapshot()).duplicate(true)
	if not bool(snapshot.get("single_full_engine_mode", false)):
		return Result.failure("single_full_engine_mode_disabled")
	if not bool(snapshot.get("full_replay_step_timeline_ready", false)):
		return Result.failure("cached_timeline_missing")
	if not bool(snapshot.get("full_replay_step_timeline_entries_ready", false)):
		return Result.failure("cached_entries_missing")
	var cached_timeline := OnlineResumeFullHistoryAdapterClass.get_cached_history_timeline()
	if cached_timeline.is_empty():
		return Result.failure("cached_timeline_empty")
	var cached_processed_count := StepTimelineHelpersClass.read_processed_command_count(cached_timeline)
	var runtime_command_count := int(runtime_engine.command_history.size())
	if cached_processed_count < runtime_command_count:
		return Result.failure("cached_timeline_stale")
	var cached_entries := OnlineResumeFullHistoryAdapterClass.get_cached_history_timeline_entries()
	var load_r := StepTimelineBuildHelpersClass.load_prebuilt_timeline_with_entries(
		cached_timeline,
		cached_entries,
		game_log_panel,
		false
	)
	if not load_r.ok:
		return load_r
	if not (load_r.value is Dictionary):
		return Result.failure("prebuilt timeline 返回类型错误")
	var info: Dictionary = Dictionary(load_r.value)
	var timeline_val = info.get("timeline", null)
	if not (timeline_val is Dictionary):
		return Result.failure("prebuilt timeline 返回结构错误")
	var timeline: Dictionary = Dictionary(timeline_val)
	var head_step_index := int(info.get("head_step_index", -1))
	var head_cmd := runtime_engine.command_history.size() - 1
	var cursor_cmd := int(runtime_engine.current_command_index)
	var history_cursor_step_index := head_step_index
	if cursor_cmd < 0:
		history_cursor_step_index = -1
	elif cursor_cmd >= head_cmd:
		history_cursor_step_index = head_step_index
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
		"history_timeline_source": "runtime",
		"restore_runtime_display_engine": false,
	})

static func build_online_resume_full_history_view_for_command(
	runtime_engine: GameEngine,
	game_log_panel: Object,
	target_runtime_command_index: int,
	previous_history_timeline: Dictionary = {},
	allow_incremental_append: bool = true
) -> Result:
	if runtime_engine == null:
		return Result.failure("runtime_engine 为空")
	if not is_instance_valid(game_log_panel):
		return Result.failure("game_log_panel 无效")
	if not OnlineResumeFullHistoryAdapterClass.is_applicable():
		return Result.failure("当前不是恢复房完整历史场景")
	if not is_full_history_ready():
		return Result.failure("联机完整历史尚未就绪")

	var build_r := OnlineResumeFullHistoryAdapterClass.build_history_timeline(
		game_log_panel,
		false,
		previous_history_timeline,
		allow_incremental_append
	)
	if not build_r.ok:
		return build_r
	if not (build_r.value is Dictionary):
		return Result.failure("构建完整历史 step 时间线失败（返回类型错误）")

	var info: Dictionary = Dictionary(build_r.value)
	var timeline_val = info.get("timeline", null)
	if not (timeline_val is Dictionary):
		return Result.failure("构建完整历史 step 时间线失败（返回结构错误）")

	var timeline: Dictionary = Dictionary(timeline_val)
	var head_step_index := int(info.get("head_step_index", -1))
	var target_step_index := OnlineResumeFullHistoryAdapterClass.map_runtime_command_index_to_step_index(
		int(target_runtime_command_index),
		timeline
	)
	if target_step_index < -1:
		target_step_index = head_step_index

	return Result.success({
		"timeline": timeline,
		"head_step_index": head_step_index,
		"cursor_step_index": head_step_index,
		"target_step_index": target_step_index,
		"history_timeline_source": "online_resume_full_history",
		"restore_runtime_display_engine": false,
	})
