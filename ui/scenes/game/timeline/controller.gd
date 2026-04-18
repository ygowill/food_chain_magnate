# Game scene：回放/复盘/时间线控制器
# 负责：step_timeline 构建、日志面板时间线交互、ReplayBar 状态、回放引擎切换。
class_name GameTimelineController
extends RefCounted

const UiSignalHelpersClass = preload("res://ui/utils/signal_helpers.gd")
const GameTimelineHistoryStepSupportClass = preload("res://ui/scenes/game/timeline/history_step_timeline_support.gd")
const GameTimelineReplayStepTimelineSupportClass = preload("res://ui/scenes/game/timeline/replay_step_timeline_support.gd")
const GameTimelineReplayBarSupportClass = preload("res://ui/scenes/game/timeline/replay_bar_support.gd")
const GameTimelineOnlineResumeHistoryViewSupportClass = preload("res://ui/scenes/game/timeline/online_resume_history_view_support.gd")
const OnlineResumeFullHistoryAdapterClass = preload("res://ui/scenes/game/timeline/online_resume_full_history_adapter.gd")
const GameTimelineSeekRoutingSupportClass = preload("res://ui/scenes/game/timeline/seek_routing_support.gd")
const GameTimelineUiStateSupportClass = preload("res://ui/scenes/game/timeline/ui_state_support.gd")
const GameTimelineReplaySessionSupportClass = preload("res://ui/scenes/game/timeline/replay_session_support.gd")
const OnlinePerfTraceClass = preload("res://core/debug/online_perf_trace.gd")

var _host: Control = null
var _game_log_panel: Control = null
var _action_panel: Control = null

var _get_game_engine: Callable = Callable()
var _get_runtime_game_engine: Callable = Callable()
var _set_active_game_engine: Callable = Callable()
var _set_display_game_engine: Callable = Callable()
var _update_ui: Callable = Callable()
var _show_confirm: Callable = Callable()
var _show_game_log_panel_in_right_panel: Callable = Callable()
var _open_replay_load_dialog: Callable = Callable()
var _get_online_resync_in_progress: Callable = Callable()

var _replay_mode_active: bool = false
var _replay_original_engine: GameEngine = null
var _replay_original_log_entries: Array[Dictionary] = []
var _replay_file_path: String = ""
var _replay_step_timeline: Dictionary = {} # {initial_state_dict, steps, events}
var _replay_head_step_index: int = -1
var _replay_cursor_step_index: int = -1

# 复盘（非回放）：当 cursor < head 时，切换到 step_index 时间线（支持大阶段切分），并在返回最新时恢复实时日志。
var _history_step_timeline_active: bool = false
var _history_step_timeline: Dictionary = {} # {initial_state_dict, steps, events}
var _history_head_step_index: int = -1
var _history_cursor_step_index: int = -1
var _history_timeline_source: String = "runtime"
var _live_history_dirty: bool = true
var _live_history_refresh_scheduled: bool = false
var _live_history_last_signature: Dictionary = {}

# 时间线编辑模式：允许在 cursor<head 时继续执行命令（将丢弃未来时间线并产生新分支）。
var _timeline_edit_mode_active: bool = false

# 手动回放模式：只有玩家显式开启时，才允许通过日志/ReplayBar 进行时间线 seek（避免误触进入复盘）。
var _manual_replay_enabled: bool = false

var _force_full_panel_sync_next_update: bool = false

var _startup_replay_from_main_menu: bool = false

func _init(
	host: Control,
	game_log_panel: Control,
	action_panel: Control,
	get_game_engine: Callable,
	get_runtime_game_engine: Callable,
	set_active_game_engine: Callable,
	set_display_game_engine: Callable,
	update_ui: Callable,
	show_confirm: Callable,
	show_game_log_panel_in_right_panel: Callable,
	open_replay_load_dialog: Callable,
	get_online_resync_in_progress: Callable
) -> void:
	_host = host
	_game_log_panel = game_log_panel
	_action_panel = action_panel
	_get_game_engine = get_game_engine
	_get_runtime_game_engine = get_runtime_game_engine
	_set_active_game_engine = set_active_game_engine
	_set_display_game_engine = set_display_game_engine
	_update_ui = update_ui
	_show_confirm = show_confirm
	_show_game_log_panel_in_right_panel = show_game_log_panel_in_right_panel
	_open_replay_load_dialog = open_replay_load_dialog
	_get_online_resync_in_progress = get_online_resync_in_progress

func dispose() -> void:
	_disconnect_log_panel_signals()
	_disconnect_replay_bar_signals()
	_replay_mode_active = false
	_manual_replay_enabled = false
	_sync_log_panel_replay_toggle_state(false)
	_replay_original_engine = null
	_replay_original_log_entries.clear()
	_replay_file_path = ""
	_replay_step_timeline.clear()
	_replay_head_step_index = -1
	_replay_cursor_step_index = -1
	_history_step_timeline_active = false
	_history_step_timeline.clear()
	_history_head_step_index = -1
	_history_cursor_step_index = -1
	_history_timeline_source = "runtime"
	_live_history_dirty = true
	_live_history_refresh_scheduled = false
	_live_history_last_signature.clear()

func initialize() -> void:
	_connect_log_panel_signals()
	_connect_replay_bar_signals()
	_sync_online_resume_replay_entry_state()

func set_startup_replay_from_main_menu(active: bool) -> void:
	_startup_replay_from_main_menu = bool(active)

func is_replay_mode_active() -> bool:
	return _replay_mode_active

func is_manual_replay_enabled() -> bool:
	return _manual_replay_enabled

func set_manual_replay_enabled(active: bool) -> void:
	var v := bool(active)
	if _replay_mode_active:
		if not v:
			_exit_replay_mode_with_restore()
		else:
			_sync_log_panel_replay_toggle_state(true)
		return
	if v == _manual_replay_enabled:
		_sync_log_panel_replay_toggle_state(v)
		return
	_manual_replay_enabled = v
	_sync_log_panel_replay_toggle_state(_manual_replay_enabled)

	# 关闭手动回放：若当前处于“复盘”态，自动回到最新，避免被锁在历史快照中。
	if not _manual_replay_enabled and not _replay_mode_active:
		if _history_step_timeline_active and _history_cursor_step_index < _history_head_step_index:
			_exit_history_step_timeline()

	if _update_ui.is_valid():
		_update_ui.call()

func is_history_step_timeline_active() -> bool:
	return _history_step_timeline_active and _history_step_timeline.has("steps")

func is_timeline_edit_mode_active() -> bool:
	return _timeline_edit_mode_active

func set_timeline_edit_mode_active(active: bool) -> void:
	_timeline_edit_mode_active = bool(active)

func request_force_full_panel_sync_next_update() -> void:
	_force_full_panel_sync_next_update = true

func consume_force_full_panel_sync_next_update() -> bool:
	var v := _force_full_panel_sync_next_update
	_force_full_panel_sync_next_update = false
	return v

func _get_runtime_engine() -> GameEngine:
	if _get_runtime_game_engine.is_valid():
		var runtime_engine = _get_runtime_game_engine.call()
		if runtime_engine is GameEngine:
			return runtime_engine
	var engine = _get_game_engine.call() if _get_game_engine.is_valid() else null
	return engine if engine is GameEngine else null

func _is_online_resume_full_history_ready() -> bool:
	return GameTimelineOnlineResumeHistoryViewSupportClass.is_full_history_ready()

func _is_online_resume_full_history_source_active() -> bool:
	return _history_timeline_source == "online_resume_full_history" and _is_online_resume_full_history_ready()

func _is_history_cursor_detached_from_live_head() -> bool:
	if not _history_step_timeline_active or not _history_step_timeline.has("steps"):
		return false
	return _history_cursor_step_index < _history_head_step_index

func _should_use_online_resume_full_history_for_history_view() -> bool:
	if NetContext == null or NetContext.mode != NetContext.Mode.ONLINE_CLIENT:
		return false
	if _replay_mode_active:
		return false
	return _is_online_resume_full_history_ready()

func _restore_runtime_display_engine() -> void:
	var runtime_engine := _get_runtime_engine()
	if runtime_engine == null:
		return
	if _set_display_game_engine.is_valid():
		_set_display_game_engine.call(runtime_engine)

func _sync_online_resume_replay_entry_state() -> void:
	GameTimelineOnlineResumeHistoryViewSupportClass.sync_replay_entry_state(
		_game_log_panel,
		_replay_mode_active
	)

func get_ui_head_cursor(engine: GameEngine) -> Vector2i:
	var head_index := -1
	var cursor_index := -1
	if engine != null:
		head_index = engine.command_history.size() - 1
		cursor_index = int(engine.current_command_index)
	if _replay_mode_active and _replay_step_timeline.has("steps"):
		head_index = _replay_head_step_index
		cursor_index = _replay_cursor_step_index
	elif _should_use_history_step_timeline_for_ui(engine):
		head_index = _history_head_step_index
		cursor_index = _history_cursor_step_index
	return Vector2i(head_index, cursor_index)

func _should_use_history_step_timeline_for_ui(engine: GameEngine) -> bool:
	if not _history_step_timeline_active or not _history_step_timeline.has("steps"):
		return false
	if _manual_replay_enabled:
		return true
	if is_instance_valid(_game_log_panel) and _game_log_panel.visible:
		return true
	if engine != null:
		var head_index := engine.command_history.size() - 1
		var cursor_index := int(engine.current_command_index)
		if cursor_index < head_index:
			return true
	return false

func get_ui_replay_suffix(engine: GameEngine, head_index: int, cursor_index: int) -> String:
	if _replay_mode_active:
		return "（回放）"
	if engine == null:
		return ""
	if cursor_index < head_index:
		return "（时间旅行）" if _timeline_edit_mode_active else "（复盘）"
	return ""

func is_timeline_read_only_active(engine: GameEngine) -> bool:
	if _replay_mode_active:
		return true
	if _manual_replay_enabled:
		return true
	if engine == null:
		return false
	var head_index := engine.command_history.size() - 1
	var cursor_index := int(engine.current_command_index)
	return cursor_index < head_index

func mark_live_log_timeline_dirty() -> void:
	if _replay_mode_active:
		return
	_live_history_dirty = true

func request_live_log_timeline_refresh() -> void:
	if _replay_mode_active:
		return
	_live_history_dirty = true
	if _is_history_cursor_detached_from_live_head():
		return
	if not is_instance_valid(_game_log_panel) or not _game_log_panel.visible:
		return
	if _live_history_refresh_scheduled:
		return
	_live_history_refresh_scheduled = true
	call_deferred("_flush_live_log_timeline_refresh")

func request_live_log_timeline_refresh_deferred() -> void:
	if _replay_mode_active:
		return
	_live_history_dirty = true
	if _live_history_refresh_scheduled:
		return
	_live_history_refresh_scheduled = true
	call_deferred("_flush_live_log_timeline_refresh")

func _flush_live_log_timeline_refresh() -> void:
	_live_history_refresh_scheduled = false
	if _is_history_cursor_detached_from_live_head():
		return
	apply_live_log_timeline_from_engine()

func on_online_resume_full_history_ready() -> void:
	if _replay_mode_active:
		return
	_sync_online_resume_replay_entry_state()

func _build_live_history_signature(runtime_engine: GameEngine) -> Dictionary:
	return {
		"engine_id": int(runtime_engine.get_instance_id()),
		"history_size": int(runtime_engine.command_history.size()),
		"cursor_command_index": int(runtime_engine.current_command_index),
		"history_source": "runtime",
		"timeline_engine_id": int(runtime_engine.get_instance_id()),
		"timeline_history_size": int(runtime_engine.command_history.size()),
	}

func _is_log_panel_visible() -> bool:
	if _game_log_panel == null or not is_instance_valid(_game_log_panel):
		return false
	if _game_log_panel is CanvasItem:
		return bool((_game_log_panel as CanvasItem).is_visible_in_tree())
	if _game_log_panel.has_method("is_visible_in_tree"):
		return bool(_game_log_panel.call("is_visible_in_tree"))
	return bool(_game_log_panel.visible)

func _can_reuse_live_history(signature: Dictionary) -> bool:
	if _live_history_dirty:
		return false
	if not _history_step_timeline_active or not _history_step_timeline.has("steps"):
		return false
	if _history_timeline_source != "runtime":
		return false
	return _live_history_last_signature == signature

func _sync_live_log_timeline_state_to_panel() -> void:
	if not is_instance_valid(_game_log_panel):
		return
	var update_visible_items := _is_log_panel_visible()
	if _game_log_panel.has_method("set_timeline_head_cursor"):
		_game_log_panel.call(
			"set_timeline_head_cursor",
			_history_head_step_index,
			_history_cursor_step_index,
			update_visible_items
		)
		return
	_game_log_panel.call("set_timeline_head", _history_head_step_index, update_visible_items)
	_game_log_panel.call("set_timeline_cursor", _history_cursor_step_index, update_visible_items)

func apply_live_log_timeline_from_engine(force_rebuild: bool = false) -> void:
	# M4.3：正常对局（实时）也使用 step_timeline 来渲染日志结构。
	# - 仅在本地 engine 下使用（回放模式由 apply_full_replay_log_timeline 负责）。
	# - timeline 的结构来自 steps，内容来自 formatter(entries)。
	var span := OnlinePerfTraceClass.begin_span("ui.timeline.apply_live_log", {
		"force_rebuild": bool(force_rebuild),
		"replay_mode_active": bool(_replay_mode_active),
	})
	if _replay_mode_active:
		OnlinePerfTraceClass.end_span(span, {
			"ok": true,
			"skipped": true,
			"reason": "replay_mode_active",
		})
		return
	var runtime_engine := _get_runtime_engine()
	if runtime_engine == null:
		OnlinePerfTraceClass.end_span(span, {
			"ok": true,
			"skipped": true,
			"reason": "runtime_engine_missing",
		})
		return
	if not is_instance_valid(_game_log_panel):
		OnlinePerfTraceClass.end_span(span, {
			"ok": true,
			"skipped": true,
			"reason": "game_log_panel_missing",
		})
		return
	_live_history_refresh_scheduled = false
	var signature := _build_live_history_signature(runtime_engine)
	if not bool(force_rebuild) and _can_reuse_live_history(signature):
		_sync_live_log_timeline_state_to_panel()
		OnlinePerfTraceClass.end_span(span, {
			"ok": true,
			"reused": true,
			"history_size": int(runtime_engine.command_history.size()),
			"cursor_command_index": int(runtime_engine.current_command_index),
		})
		return

	var allow_incremental_append := false
	if _history_step_timeline_active and not _history_step_timeline.is_empty():
		allow_incremental_append = (
			_history_timeline_source == str(signature.get("history_source", "runtime"))
			and int(_live_history_last_signature.get("timeline_engine_id", -1)) == int(signature.get("timeline_engine_id", -2))
			and int(signature.get("timeline_history_size", -1)) > int(_live_history_last_signature.get("timeline_history_size", -1))
		)

	var build_r := GameTimelineOnlineResumeHistoryViewSupportClass.build_live_history_view(
		runtime_engine,
		_game_log_panel,
		_history_timeline_source,
		_history_step_timeline,
		allow_incremental_append,
		Callable(self, "_command_index_to_last_step_index")
	)
	if not build_r.ok:
		OnlinePerfTraceClass.end_span(span, {
			"ok": false,
			"error": str(build_r.error),
			"history_size": int(runtime_engine.command_history.size()),
		})
		GameLog.warn("Game", "构建 step 时间线失败（实时日志将为空/不更新）: %s" % build_r.error)
		return
	if not (build_r.value is Dictionary):
		OnlinePerfTraceClass.end_span(span, {
			"ok": false,
			"error": "build_live_history_view 返回类型错误",
			"history_size": int(runtime_engine.command_history.size()),
		})
		GameLog.warn("Game", "构建 step 时间线失败（返回类型错误）")
		return
	var info: Dictionary = build_r.value
	if bool(info.get("restore_runtime_display_engine", false)):
		_restore_runtime_display_engine()
	_history_step_timeline = Dictionary(info.get("timeline", {})).duplicate(true)
	_history_step_timeline_active = true
	_history_timeline_source = str(info.get("history_timeline_source", "runtime"))
	_history_head_step_index = int(info.get("head_step_index", -1))
	_history_cursor_step_index = int(info.get("cursor_step_index", _history_head_step_index))
	_live_history_last_signature = signature
	_live_history_dirty = false

	_sync_live_log_timeline_state_to_panel()
	OnlinePerfTraceClass.end_span(span, {
		"ok": true,
		"reused": false,
		"incremental_append_requested": bool(allow_incremental_append),
		"history_size": int(runtime_engine.command_history.size()),
		"timeline_history_size": int(signature.get("timeline_history_size", -1)),
		"cursor_command_index": int(runtime_engine.current_command_index),
		"head_step_index": int(_history_head_step_index),
		"cursor_step_index": int(_history_cursor_step_index),
		"history_timeline_source": _history_timeline_source,
	})

func start_replay_from_file(file_path: String) -> void:
	if file_path.is_empty():
		return
	_replay_file_path = file_path
	var started_from_main_menu := _startup_replay_from_main_menu
	var replay_load_playable := false
	if Globals != null:
		replay_load_playable = bool(Globals.replay_load_playable)

	# 若是从对局中进入回放：保留原日志，退出回放时可恢复。
	_replay_original_log_entries = GameTimelineReplaySessionSupportClass.capture_original_log_entries(
		_game_log_panel,
		_replay_mode_active
	)

	var load_r := GameTimelineReplaySessionSupportClass.load_engine_from_file(file_path)
	if not load_r.ok:
		GameLog.error("Game", "回放加载失败: %s" % load_r.error)
		if started_from_main_menu and SceneManager != null and SceneManager.has_method("hide_loading"):
			SceneManager.hide_loading()
		if _show_confirm.is_valid():
			_show_confirm.call("回放加载失败", load_r.error, Callable(), Callable())
		return
	if not (load_r.value is GameEngine):
		if started_from_main_menu and SceneManager != null and SceneManager.has_method("hide_loading"):
			SceneManager.hide_loading()
		if _show_confirm.is_valid():
			_show_confirm.call("回放加载失败", "内部错误：载入结果类型错误", Callable(), Callable())
		return
	var engine: GameEngine = load_r.value

	if started_from_main_menu and Globals != null and Globals.has_method("sync_runtime_config_from_engine"):
		Globals.sync_runtime_config_from_engine(engine)

	if replay_load_playable:
		var to_latest := GameTimelineReplaySessionSupportClass.move_engine_to_latest_state(engine)
		if not to_latest.ok:
			GameLog.error("Game", "回放载入后进入可操作模式失败: %s" % to_latest.error)
			if started_from_main_menu and SceneManager != null and SceneManager.has_method("hide_loading"):
				SceneManager.hide_loading()
			if _show_confirm.is_valid():
				_show_confirm.call("回放加载失败", to_latest.error, Callable(), Callable())
			return
		_enter_loaded_archive_as_playable(engine)
		if started_from_main_menu and SceneManager != null and SceneManager.has_method("hide_loading"):
			SceneManager.hide_loading()
		if started_from_main_menu and _host != null and is_instance_valid(_host):
			_host.call_deferred("_start_background_ui_warmup")
		return

	_enter_replay_mode(engine)
	_apply_full_replay_log_timeline(engine)
	if _show_game_log_panel_in_right_panel.is_valid():
		_show_game_log_panel_in_right_panel.call()

	if started_from_main_menu and SceneManager != null and SceneManager.has_method("hide_loading"):
		SceneManager.hide_loading()
	if started_from_main_menu and _host != null and is_instance_valid(_host):
		_host.call_deferred("_start_background_ui_warmup")

func _enter_loaded_archive_as_playable(engine: GameEngine) -> void:
	if engine == null:
		return

	# “可继续操作”模式不是只读回放，不应再沿用“退出回放返回主菜单”的行为。
	_startup_replay_from_main_menu = false

	_replay_mode_active = false
	_replay_original_engine = null
	_replay_original_log_entries.clear()
	_replay_step_timeline.clear()
	_replay_head_step_index = -1
	_replay_cursor_step_index = -1
	_history_step_timeline_active = false
	_history_step_timeline.clear()
	_history_head_step_index = -1
	_history_cursor_step_index = -1
	_live_history_dirty = true
	_live_history_last_signature.clear()
	_timeline_edit_mode_active = false
	_manual_replay_enabled = false
	_sync_log_panel_replay_toggle_state(false)
	_hide_replay_bar()

	if _set_active_game_engine.is_valid():
		_set_active_game_engine.call(engine)
	apply_live_log_timeline_from_engine()
	_force_full_panel_sync_next_update = true
	if _update_ui.is_valid():
		_update_ui.call()

func sync_timeline_ui(head_index: int, cursor_index: int, state: GameState) -> void:
	_sync_online_resume_replay_entry_state()
	GameTimelineUiStateSupportClass.sync_ui(
		_game_log_panel,
		_action_panel,
		head_index,
		cursor_index,
		state,
		_replay_mode_active,
		_manual_replay_enabled,
		_timeline_edit_mode_active,
		_get_online_resync_in_progress,
		Callable(self, "_set_replay_bar_state"),
		Callable(self, "_hide_replay_bar")
	)

func _connect_log_panel_signals() -> void:
	if not is_instance_valid(_game_log_panel):
		return
	UiSignalHelpersClass.safe_connect(_game_log_panel, "log_entry_clicked", Callable(self, "_on_log_entry_clicked"))
	if _game_log_panel.has_signal("timeline_seek_requested"):
		UiSignalHelpersClass.safe_connect(_game_log_panel, "timeline_seek_requested", Callable(self, "_on_timeline_seek_requested"))

func _disconnect_log_panel_signals() -> void:
	if _game_log_panel == null or not is_instance_valid(_game_log_panel):
		return
	var cb_entry := Callable(self, "_on_log_entry_clicked")
	if _game_log_panel.has_signal("log_entry_clicked") and _game_log_panel.is_connected("log_entry_clicked", cb_entry):
		_game_log_panel.disconnect("log_entry_clicked", cb_entry)
	var cb_seek := Callable(self, "_on_timeline_seek_requested")
	if _game_log_panel.has_signal("timeline_seek_requested") and _game_log_panel.is_connected("timeline_seek_requested", cb_seek):
		_game_log_panel.disconnect("timeline_seek_requested", cb_seek)

func _connect_replay_bar_signals() -> void:
	GameTimelineReplayBarSupportClass.connect_seek_signal(
		_game_log_panel,
		self,
		"_on_replay_bar_seek_requested"
	)

func _disconnect_replay_bar_signals() -> void:
	GameTimelineReplayBarSupportClass.disconnect_seek_signal(
		_game_log_panel,
		self,
		"_on_replay_bar_seek_requested"
	)

func _set_replay_bar_state(head_index: int, cursor_index: int, read_only: bool) -> void:
	GameTimelineReplayBarSupportClass.set_state(
		_game_log_panel,
		_replay_mode_active,
		_replay_step_timeline,
		_history_step_timeline_active,
		_history_step_timeline,
		head_index,
		cursor_index,
		read_only
	)

func _hide_replay_bar() -> void:
	GameTimelineReplayBarSupportClass.hide(_game_log_panel)

func _apply_full_replay_log_timeline(engine: GameEngine) -> void:
	if engine == null or not is_instance_valid(engine):
		return
	var load_r := GameTimelineReplayStepTimelineSupportClass.load_for_engine(engine, _game_log_panel)
	if not load_r.ok:
		GameLog.error("Game", "构建 step 时间线失败: %s" % load_r.error)
		if _show_confirm.is_valid():
			_show_confirm.call("回放加载失败", "构建 step 时间线失败: %s" % load_r.error, Callable(), Callable())
		return
	if not (load_r.value is Dictionary):
		if _show_confirm.is_valid():
			_show_confirm.call("回放加载失败", "构建 step 时间线失败: 内部错误（返回类型错误）", Callable(), Callable())
		return

	var info: Dictionary = Dictionary(load_r.value)
	_replay_step_timeline = Dictionary(info.get("timeline", {})).duplicate(true)
	_replay_head_step_index = int(info.get("head_step_index", -1))
	_replay_cursor_step_index = int(info.get("cursor_step_index", _replay_head_step_index))
	_set_replay_bar_state(_replay_head_step_index, _replay_cursor_step_index, true)

func _command_index_to_last_step_index(command_index: int, timeline: Dictionary) -> int:
	var cmd := int(command_index)
	if cmd < 0:
		return -1
	if timeline == null or timeline.is_empty():
		return -1
	var steps_val = timeline.get("steps", null)
	if not (steps_val is Array):
		return -1
	var steps: Array = steps_val
	for idx in range(steps.size() - 1, -1, -1):
		var s_val = steps[idx]
		if not (s_val is Dictionary):
			continue
		var s: Dictionary = s_val
		if int(s.get("anchor_command_index", -999)) == cmd:
			return idx
	return -1

func _is_timeline_seek_enabled() -> bool:
	return GameTimelineSeekRoutingSupportClass.is_seek_enabled(
		_replay_mode_active,
		_history_step_timeline_active,
		_history_step_timeline,
		_history_cursor_step_index,
		_history_head_step_index,
		_manual_replay_enabled
	)

func _on_log_entry_clicked(entry_id: int) -> void:
	if not _is_timeline_seek_enabled():
		return
	var engine: GameEngine = _get_game_engine.call() if _get_game_engine.is_valid() else null
	if engine == null:
		return
	var idx := GameTimelineSeekRoutingSupportClass.get_entry_timeline_index(_game_log_panel, entry_id)
	if idx < -1:
		return
	_on_replay_bar_seek_requested(idx)

func _on_timeline_seek_requested(timeline_index: int) -> void:
	if not _is_timeline_seek_enabled():
		return
	_on_replay_bar_seek_requested(int(timeline_index))

func _on_replay_bar_seek_requested(target_index: int) -> void:
	if not _is_timeline_seek_enabled():
		return
	var engine: GameEngine = _get_game_engine.call() if _get_game_engine.is_valid() else null
	if engine == null:
		return
	var online_seek_r := GameTimelineSeekRoutingSupportClass.ensure_online_seek_allowed(
		NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT,
		_replay_mode_active,
		_is_online_resume_full_history_ready()
	)
	if not online_seek_r.ok:
		GameLog.warn("Game", str(online_seek_r.error))
		return
	# 通过 ReplayBar/日志 seek 进入的“查看历史”一律保持只读（避免 step 快照状态用于分支编辑）。
	_timeline_edit_mode_active = false
	var plan: Dictionary = GameTimelineSeekRoutingSupportClass.resolve_seek_plan(
		engine,
		int(target_index),
		_replay_mode_active,
		_replay_step_timeline,
		_history_step_timeline_active,
		_history_step_timeline
	)
	match str(plan.get("kind", "")):
		"replay_step":
			_seek_to_replay_step(int(plan.get("target_step_index", target_index)))
			return
		"history_step":
			_seek_to_history_step(int(plan.get("target_step_index", target_index)))
			return
		"enter_history":
			var target_command := int(plan.get("target_command_index", target_index))
			var step_target := _enter_history_step_timeline_for_command(target_command)
			if step_target >= -1:
				_seek_to_history_step(step_target)
				return
			if bool(plan.get("fallback_to_rewind", false)):
				var rewind_r := engine.rewind_to_command(target_command)
				if not rewind_r.ok:
					GameLog.warn("Game", "时间线 seek 失败: %s" % rewind_r.error)
					return
				_force_full_panel_sync_next_update = true
			elif bool(plan.get("update_ui_when_enter_fail", false)) and _update_ui.is_valid():
				_update_ui.call()
				return
		"rewind_command":
			var rewind_target := int(plan.get("target_command_index", target_index))
			var rewind_r := engine.rewind_to_command(rewind_target)
			if not rewind_r.ok:
				GameLog.warn("Game", "时间线 seek 失败: %s" % rewind_r.error)
				return
			_force_full_panel_sync_next_update = true
		"refresh_only":
			if _update_ui.is_valid():
				_update_ui.call()
			return
		_:
			return
	if _update_ui.is_valid():
		_update_ui.call()

func _enter_history_step_timeline_for_command(target_command_index: int) -> int:
	var use_online_full_history := _should_use_online_resume_full_history_for_history_view()
	if _history_step_timeline_active and _history_step_timeline.has("steps"):
		if use_online_full_history and _history_timeline_source == "online_resume_full_history":
			return _history_command_index_to_step_index(int(target_command_index))
		if not use_online_full_history and _history_timeline_source == "runtime":
			return _history_command_index_to_step_index(int(target_command_index))
	var runtime_engine := _get_runtime_engine()
	if runtime_engine == null:
		return -999
	var enter_r: Result
	if use_online_full_history:
		var previous_full_history_timeline: Dictionary = {}
		if _history_timeline_source == "online_resume_full_history":
			previous_full_history_timeline = _history_step_timeline
		enter_r = GameTimelineOnlineResumeHistoryViewSupportClass.build_online_resume_full_history_view_for_command(
			runtime_engine,
			_game_log_panel,
			int(target_command_index),
			previous_full_history_timeline,
			true
		)
	else:
		enter_r = GameTimelineHistoryStepSupportClass.enter_for_command(
			runtime_engine,
			_game_log_panel,
			int(target_command_index)
		)
	if not enter_r.ok:
		GameLog.warn("Game", "构建 step 时间线失败（复盘模式将回退到命令时间线）: %s" % enter_r.error)
		return -999
	if not (enter_r.value is Dictionary):
		GameLog.warn("Game", "构建 step 时间线失败（返回类型错误）")
		return -999

	var info: Dictionary = Dictionary(enter_r.value)
	_history_step_timeline = Dictionary(info.get("timeline", {})).duplicate(true)
	_history_step_timeline_active = true
	_history_timeline_source = str(info.get("history_timeline_source", "runtime"))
	_history_head_step_index = int(info.get("head_step_index", -1))
	_history_cursor_step_index = int(info.get("cursor_step_index", _history_head_step_index))
	_set_replay_bar_state(_history_head_step_index, _history_cursor_step_index, false)
	if _show_game_log_panel_in_right_panel.is_valid():
		_show_game_log_panel_in_right_panel.call()

	return int(info.get("target_step_index", -999))

func _history_command_index_to_step_index(command_index: int) -> int:
	if _is_online_resume_full_history_source_active():
		return OnlineResumeFullHistoryAdapterClass.map_runtime_command_index_to_step_index(
			int(command_index),
			_history_step_timeline
		)
	return GameTimelineHistoryStepSupportClass.map_command_index_to_step_index(
		_history_step_timeline,
		int(command_index)
	)

func _seek_to_history_step(target_step_index: int) -> void:
	var use_online_full_history := _is_online_resume_full_history_source_active()
	if use_online_full_history and target_step_index >= _history_head_step_index:
		_restore_runtime_display_engine()
		_force_full_panel_sync_next_update = true
		apply_live_log_timeline_from_engine(true)
		if _update_ui.is_valid():
			_update_ui.call()
		return
	var runtime_engine: GameEngine = _get_game_engine.call() if _get_game_engine.is_valid() else null
	var engine: GameEngine = GameTimelineHistoryStepSupportClass.resolve_seek_engine(
		runtime_engine,
		use_online_full_history
	)
	if engine == null:
		return
	var seek_r := GameTimelineHistoryStepSupportClass.seek_to_step(
		_history_step_timeline,
		engine,
		_history_cursor_step_index,
		int(target_step_index),
		use_online_full_history
	)
	if not seek_r.ok:
		GameLog.warn("Game", "复盘 step seek 失败：%s" % seek_r.error)
		return
	if not (seek_r.value is Dictionary):
		GameLog.warn("Game", "复盘 step seek 失败：内部错误（返回类型错误）")
		return

	var info: Dictionary = Dictionary(seek_r.value)
	_history_head_step_index = int(info.get("head_step_index", _history_head_step_index))
	_history_cursor_step_index = int(info.get("cursor_step_index", _history_cursor_step_index))
	if bool(info.get("restore_runtime_display_engine", false)):
		_restore_runtime_display_engine()
	elif bool(info.get("set_display_history_engine", false)) and _set_display_game_engine.is_valid():
		_set_display_game_engine.call(engine)

	if bool(info.get("force_full_panel_sync", false)):
		_force_full_panel_sync_next_update = true
	if _update_ui.is_valid():
		_update_ui.call()

func _exit_history_step_timeline() -> void:
	# M4.3：正常对局也使用 step 时间线视图；“退出复盘”仅意味着跳回最新 step。
	if _is_online_resume_full_history_source_active():
		_restore_runtime_display_engine()
		_force_full_panel_sync_next_update = true
		apply_live_log_timeline_from_engine(true)
		if _update_ui.is_valid():
			_update_ui.call()
		return
	var engine: GameEngine = _get_game_engine.call() if _get_game_engine.is_valid() else null
	if engine == null:
		return
	if not _history_step_timeline_active or not _history_step_timeline.has("steps"):
		_on_replay_bar_seek_requested(engine.command_history.size() - 1)
		return
	_seek_to_history_step(_history_head_step_index)

func _seek_to_replay_step(target_step_index: int) -> void:
	var engine: GameEngine = _get_game_engine.call() if _get_game_engine.is_valid() else null
	if engine == null:
		return
	var seek_r := GameTimelineReplayStepTimelineSupportClass.seek_to_step(
		_replay_step_timeline,
		engine,
		_replay_cursor_step_index,
		int(target_step_index)
	)
	if not seek_r.ok:
		GameLog.warn("Game", "回放 step seek 失败：%s" % seek_r.error)
		return
	if not (seek_r.value is Dictionary):
		GameLog.warn("Game", "回放 step seek 失败：内部错误（返回类型错误）")
		return

	var info: Dictionary = Dictionary(seek_r.value)
	_replay_head_step_index = int(info.get("head_step_index", _replay_head_step_index))
	_replay_cursor_step_index = int(info.get("cursor_step_index", _replay_cursor_step_index))
	if bool(info.get("force_full_panel_sync", false)):
		_force_full_panel_sync_next_update = true
	if _update_ui.is_valid():
		_update_ui.call()

func _exit_replay_mode_with_restore() -> void:
	if _startup_replay_from_main_menu:
		Globals.reset_game_config()
		SceneManager.goto_main_menu()
		return

	# 对局内“查看历史”态：关闭等价于“返回最新”。
	if not _replay_mode_active:
		var engine: GameEngine = _get_game_engine.call() if _get_game_engine.is_valid() else null
		if engine == null:
			return
		if _history_step_timeline_active and _history_step_timeline.has("steps"):
			_exit_history_step_timeline()
		else:
			_on_replay_bar_seek_requested(engine.command_history.size() - 1)
		_manual_replay_enabled = false
		_sync_log_panel_replay_toggle_state(false)
		if _update_ui.is_valid():
			_update_ui.call()
		return

	_hide_replay_bar()
	_exit_replay_mode()

	# 恢复对局内进入回放前的日志（避免依赖已被回放覆盖的 EventBus.history）。
	GameTimelineReplaySessionSupportClass.restore_original_log_entries(
		_game_log_panel,
		_replay_original_log_entries
	)
	_replay_original_log_entries.clear()
	_live_history_dirty = true
	_live_history_last_signature.clear()
	_history_step_timeline_active = false
	_history_step_timeline.clear()
	_history_head_step_index = -1
	_history_cursor_step_index = -1

	var engine: GameEngine = _get_game_engine.call() if _get_game_engine.is_valid() else null
	GameTimelineReplaySessionSupportClass.sync_log_panel_cursor_from_engine(_game_log_panel, engine)
	_sync_log_panel_replay_toggle_state(false)

func _enter_replay_mode(engine: GameEngine) -> void:
	if engine == null:
		return
	if not _replay_mode_active:
		var current: GameEngine = _get_game_engine.call() if _get_game_engine.is_valid() else null
		_replay_original_engine = current

	_replay_mode_active = true
	_sync_log_panel_replay_toggle_state(true)
	if _set_active_game_engine.is_valid():
		_set_active_game_engine.call(engine)
	if _update_ui.is_valid():
		_update_ui.call()

func _exit_replay_mode() -> void:
	if not _replay_mode_active:
		return

	_replay_mode_active = false
	_replay_step_timeline.clear()
	_replay_head_step_index = -1
	_replay_cursor_step_index = -1
	_sync_log_panel_replay_toggle_state(false)

	var restore_engine := _replay_original_engine
	_replay_original_engine = null

	if restore_engine != null and _set_active_game_engine.is_valid():
		_set_active_game_engine.call(restore_engine)
	if _update_ui.is_valid():
		_update_ui.call()

func _sync_log_panel_replay_toggle_state(active: bool) -> void:
	if not is_instance_valid(_game_log_panel):
		return
	if _game_log_panel.has_method("set_replay_toggle_active"):
		_game_log_panel.call("set_replay_toggle_active", bool(active))
	_sync_online_resume_replay_entry_state()
