# Game scene：回放/复盘/时间线控制器
# 负责：step_timeline 构建、日志面板时间线交互、ReplayBar 状态、回放引擎切换。
class_name GameTimelineController
extends RefCounted

const UiSignalHelpersClass = preload("res://ui/utils/signal_helpers.gd")
const StepTimelineBuildClass = preload("res://gameplay/replay/step_timeline_build.gd")
const GameTimelineLogEntriesBuilderClass = preload("res://ui/scenes/game/game_timeline_log_entries_builder.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

var _host: Control = null
var _game_log_panel: Control = null
var _action_panel: Control = null

var _get_game_engine: Callable = Callable()
var _set_active_game_engine: Callable = Callable()
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
	set_active_game_engine: Callable,
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
	_set_active_game_engine = set_active_game_engine
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

func initialize() -> void:
	_connect_log_panel_signals()
	_connect_replay_bar_signals()

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

func get_ui_head_cursor(engine: GameEngine) -> Vector2i:
	var head_index := -1
	var cursor_index := -1
	if engine != null:
		head_index = engine.command_history.size() - 1
		cursor_index = int(engine.current_command_index)
	if _replay_mode_active and _replay_step_timeline.has("steps"):
		head_index = _replay_head_step_index
		cursor_index = _replay_cursor_step_index
	elif _history_step_timeline_active and _history_step_timeline.has("steps"):
		head_index = _history_head_step_index
		cursor_index = _history_cursor_step_index
	return Vector2i(head_index, cursor_index)

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

func apply_live_log_timeline_from_engine() -> void:
	# M4.3：正常对局（实时）也使用 step_timeline 来渲染日志结构。
	# - 仅在本地 engine 下使用（回放模式由 apply_full_replay_log_timeline 负责）。
	# - timeline 的结构来自 steps，内容来自 formatter(entries)。
	if _replay_mode_active:
		return
	var engine: GameEngine = _get_game_engine.call() if _get_game_engine.is_valid() else null
	if engine == null:
		return
	if not is_instance_valid(_game_log_panel):
		return

	var build_r: Result = StepTimelineBuildClass.build_full(engine)
	if not build_r.ok:
		GameLog.warn("Game", "构建 step 时间线失败（实时日志将为空/不更新）: %s" % build_r.error)
		return
	if not (build_r.value is Dictionary):
		GameLog.warn("Game", "构建 step 时间线失败（返回类型错误）")
		return

	_history_step_timeline = Dictionary(build_r.value).duplicate(true)
	_history_step_timeline_active = true

	var events_val = _history_step_timeline.get("events", [])
	var events: Array = events_val if (events_val is Array) else []
	var entries := GameTimelineLogEntriesBuilderClass.build(events)
	if _game_log_panel.has_method("load_step_timeline"):
		# 保留 UI-only 日志（例如动作失败提示），避免 rebuild 覆盖用户可见反馈。
		_game_log_panel.call("load_step_timeline", _history_step_timeline, entries, false)
	else:
		_game_log_panel.call("load_entries", entries)

	var steps_val = _history_step_timeline.get("steps", [])
	var steps: Array = steps_val if (steps_val is Array) else []
	_history_head_step_index = steps.size() - 1

	# 默认定位到“当前引擎指针”的稳定落点：
	# - 若在最新：cursor=head_step；
	# - 若在历史：cursor=该 command_index 对应的最后一个 step（通常是该命令链路结束后的稳定状态）。
	var head_cmd := engine.command_history.size() - 1
	var cursor_cmd := int(engine.current_command_index)
	if cursor_cmd < 0:
		_history_cursor_step_index = -1
	elif cursor_cmd >= head_cmd:
		_history_cursor_step_index = _history_head_step_index
	else:
		_history_cursor_step_index = _command_index_to_last_step_index(cursor_cmd, _history_step_timeline)
		if _history_cursor_step_index < -1:
			_history_cursor_step_index = _history_head_step_index

	_game_log_panel.call("set_timeline_head", _history_head_step_index)
	_game_log_panel.call("set_timeline_cursor", _history_cursor_step_index)

func start_replay_from_file(file_path: String) -> void:
	if file_path.is_empty():
		return
	_replay_file_path = file_path

	# 若是从对局中进入回放：保留原日志，退出回放时可恢复。
	if not _replay_mode_active and is_instance_valid(_game_log_panel) and _game_log_panel.has_method("get_entries"):
		_replay_original_log_entries = _game_log_panel.call("get_entries")

	var engine := GameEngine.new()
	var load_result: Result = engine.load_from_file(file_path)
	if not load_result.ok:
		GameLog.error("Game", "回放加载失败: %s" % load_result.error)
		if _startup_replay_from_main_menu and SceneManager != null and SceneManager.has_method("hide_loading"):
			SceneManager.hide_loading()
		if _show_confirm.is_valid():
			_show_confirm.call("回放加载失败", load_result.error, Callable(), Callable())
		return

	if _startup_replay_from_main_menu and Globals != null and Globals.has_method("sync_runtime_config_from_engine"):
		Globals.sync_runtime_config_from_engine(engine)

	_enter_replay_mode(engine)
	_apply_full_replay_log_timeline(engine)
	if _show_game_log_panel_in_right_panel.is_valid():
		_show_game_log_panel_in_right_panel.call()

	if _startup_replay_from_main_menu and SceneManager != null and SceneManager.has_method("hide_loading"):
		SceneManager.hide_loading()
	if _startup_replay_from_main_menu and _host != null and is_instance_valid(_host):
		_host.call_deferred("_start_background_ui_warmup")

func sync_timeline_ui(head_index: int, cursor_index: int, state: GameState) -> void:
	if is_instance_valid(_game_log_panel):
		_game_log_panel.call("set_timeline_head", head_index)
		_game_log_panel.call("set_timeline_cursor", cursor_index)

	var show_bar := _replay_mode_active or cursor_index < head_index or _manual_replay_enabled
	if show_bar:
		_set_replay_bar_state(head_index, cursor_index, _replay_mode_active or _manual_replay_enabled)
	else:
		_hide_replay_bar()

	# 回放/查看历史：禁用 ActionPanel（避免时间线分支与误操作）。
	if is_instance_valid(_action_panel) and _action_panel.has_method("set_globally_disabled"):
		var reason := ""
		if _replay_mode_active or _manual_replay_enabled:
			reason = "回放中不可操作"
		elif cursor_index < head_index and not _timeline_edit_mode_active:
			reason = "查看历史中不可操作"
		elif NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT:
			var online_resync := false
			if _get_online_resync_in_progress.is_valid():
				online_resync = bool(_get_online_resync_in_progress.call())
			if online_resync:
				reason = "联机：同步中"
			elif state == null:
				reason = "联机：等待同步"
			elif NetContext.local_player_id < 0:
				reason = "联机：身份未就绪"
			elif str(state.phase) != DefsClass.PHASE_RESTRUCTURING and state.get_current_player_id() != int(NetContext.local_player_id):
				reason = "联机：等待其他玩家操作"
		_action_panel.call("set_globally_disabled", reason)

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
	if _game_log_panel == null or not is_instance_valid(_game_log_panel):
		return
	if not _game_log_panel.has_method("get_replay_bar"):
		return
	var rb = _game_log_panel.call("get_replay_bar")
	if rb == null or not is_instance_valid(rb):
		return

	if rb.has_signal("seek_requested"):
		UiSignalHelpersClass.safe_connect(rb, "seek_requested", Callable(self, "_on_replay_bar_seek_requested"))

	if rb.has_method("set_active"):
		rb.call("set_active", false)

func _disconnect_replay_bar_signals() -> void:
	if _game_log_panel == null or not is_instance_valid(_game_log_panel):
		return
	if not _game_log_panel.has_method("get_replay_bar"):
		return
	var rb = _game_log_panel.call("get_replay_bar")
	if rb == null or not is_instance_valid(rb):
		return

	_disconnect_rb_signal(rb, "seek_requested", "_on_replay_bar_seek_requested")

func _disconnect_rb_signal(rb: Object, signal_name: String, method_name: String) -> void:
	if rb == null or not is_instance_valid(rb):
		return
	var cb := Callable(self, method_name)
	if rb.has_signal(signal_name) and rb.is_connected(signal_name, cb):
		rb.disconnect(signal_name, cb)

func _set_replay_bar_state(head_index: int, cursor_index: int, read_only: bool) -> void:
	if _game_log_panel == null or not is_instance_valid(_game_log_panel):
		return
	if not _game_log_panel.has_method("get_replay_bar"):
		return
	var rb = _game_log_panel.call("get_replay_bar")
	if rb == null or not is_instance_valid(rb):
		return

	if rb.has_method("set_active"):
		rb.call("set_active", true)
	if rb.has_method("set_timeline"):
		var extra := ""
		if _replay_mode_active and _replay_step_timeline.has("steps"):
			extra = _build_replay_bar_status_extra(cursor_index, _replay_step_timeline)
		elif _history_step_timeline_active and _history_step_timeline.has("steps"):
			extra = _build_replay_bar_status_extra(cursor_index, _history_step_timeline)
		rb.call("set_timeline", head_index, cursor_index, read_only, extra)

func _build_replay_bar_status_extra(step_index: int, timeline: Dictionary) -> String:
	# M4.3：不展示 step/cmd，仅展示“当前阶段”。
	if timeline == null or timeline.is_empty():
		return ""

	var idx := int(step_index)
	var phase := ""
	if idx < 0:
		var init_val = timeline.get("initial_state_dict", null)
		if init_val is Dictionary:
			phase = str(Dictionary(init_val).get("phase", "")).strip_edges()
	else:
		var steps_val = timeline.get("steps", null)
		if not (steps_val is Array):
			return ""
		var steps: Array = steps_val
		if idx >= steps.size():
			return ""
		var s_val = steps[idx]
		if not (s_val is Dictionary):
			return ""
		phase = str(Dictionary(s_val).get("phase", "")).strip_edges()

	var display_name = GameLogPanel.PHASE_DISPLAY_NAMES.get(phase, phase)
	if str(display_name).strip_edges().is_empty():
		return "初始"
	return "阶段：%s" % str(display_name)

func _hide_replay_bar() -> void:
	if _game_log_panel == null or not is_instance_valid(_game_log_panel):
		return
	if not _game_log_panel.has_method("get_replay_bar"):
		return
	var rb = _game_log_panel.call("get_replay_bar")
	if rb == null or not is_instance_valid(rb):
		return
	if rb.has_method("set_active"):
		rb.call("set_active", false)

func _apply_full_replay_log_timeline(engine: GameEngine) -> void:
	if engine == null or not is_instance_valid(engine):
		return
	if not is_instance_valid(_game_log_panel):
		return

	# M4.2：构建 step_index 时间线（阶段切分点 + 状态快照），用于回放步进与日志高亮。
	var build_r: Result = StepTimelineBuildClass.build_full(engine)
	if not build_r.ok:
		GameLog.error("Game", "构建 step 时间线失败: %s" % build_r.error)
		if _show_confirm.is_valid():
			_show_confirm.call("回放加载失败", "构建 step 时间线失败: %s" % build_r.error, Callable(), Callable())
		return

	var timeline_val = build_r.value
	if not (timeline_val is Dictionary):
		if _show_confirm.is_valid():
			_show_confirm.call("回放加载失败", "构建 step 时间线失败: 内部错误（返回类型错误）", Callable(), Callable())
		return

	_replay_step_timeline = Dictionary(timeline_val).duplicate(true)

	var events_val = _replay_step_timeline.get("events", [])
	var events: Array = events_val if (events_val is Array) else []
	var entries := GameTimelineLogEntriesBuilderClass.build(events)
	if _game_log_panel.has_method("load_step_timeline"):
		_game_log_panel.call("load_step_timeline", _replay_step_timeline, entries, true)
	else:
		_game_log_panel.call("load_entries", entries)

	var steps_val = _replay_step_timeline.get("steps", [])
	var steps: Array = steps_val if (steps_val is Array) else []
	_replay_head_step_index = steps.size() - 1
	_replay_cursor_step_index = _replay_head_step_index

	_game_log_panel.call("set_timeline_head", _replay_head_step_index)
	_game_log_panel.call("set_timeline_cursor", _replay_cursor_step_index)
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
	if _replay_mode_active:
		return true
	if _history_step_timeline_active and _history_step_timeline.has("steps") and _history_cursor_step_index < _history_head_step_index:
		return true
	return _manual_replay_enabled

func _on_log_entry_clicked(entry_id: int) -> void:
	if not _is_timeline_seek_enabled():
		return
	var engine: GameEngine = _get_game_engine.call() if _get_game_engine.is_valid() else null
	if engine == null:
		return
	if _game_log_panel == null or not is_instance_valid(_game_log_panel):
		return
	if not _game_log_panel.has_method("get_entry_timeline_index"):
		return
	var idx := int(_game_log_panel.call("get_entry_timeline_index", entry_id))
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
	# 联机：禁止本地时间线回退/复盘（否则会与 server 命令流产生状态不一致）。
	if NetContext != null and NetContext.mode == NetContext.Mode.ONLINE_CLIENT and not _replay_mode_active:
		GameLog.warn("Game", "联机模式下不支持时间线回退/复盘（避免状态不一致）")
		return
	# 通过 ReplayBar/日志 seek 进入的“查看历史”一律保持只读（避免 step 快照状态用于分支编辑）。
	_timeline_edit_mode_active = false

	# M4.2：回放模式采用 step_index（阶段切分点）seek，直接用快照覆盖 game_engine.state（只读）。
	if _replay_mode_active and _replay_step_timeline.has("steps"):
		_seek_to_replay_step(int(target_index))
		return

	# 复盘（非回放）：当 step 时间线激活时，seek 参数为 step_index。
	if _history_step_timeline_active and _history_step_timeline.has("steps"):
		_seek_to_history_step(int(target_index))
		return

	var head_index := engine.command_history.size() - 1
	var target := clampi(int(target_index), -1, head_index)
	if target == int(engine.current_command_index):
		# 若已经通过其它路径回退到历史命令（cursor<head），也允许“原地切换”为 step 时间线，
		# 以便把该命令链路中的 auto-advance 大阶段拆分成可步进点（避免看起来仍被打包在一个位置）。
		if not _history_step_timeline_active and target < head_index:
			var step_target2 := _enter_history_step_timeline_for_command(target)
			if step_target2 >= -1:
				_seek_to_history_step(step_target2)
				return
		if _update_ui.is_valid():
			_update_ui.call()
		return

	# 首次进入复盘：从命令时间线切换到 step 时间线（用于大阶段切分）。
	if target < head_index:
		var step_target := _enter_history_step_timeline_for_command(target)
		if step_target >= -1:
			_seek_to_history_step(step_target)
			return

	var r := engine.rewind_to_command(target)
	if not r.ok:
		GameLog.warn("Game", "时间线 seek 失败: %s" % r.error)
		return

	_force_full_panel_sync_next_update = true
	if _update_ui.is_valid():
		_update_ui.call()

func _enter_history_step_timeline_for_command(target_command_index: int) -> int:
	if _history_step_timeline_active and _history_step_timeline.has("steps"):
		return _history_command_index_to_step_index(int(target_command_index))
	var engine: GameEngine = _get_game_engine.call() if _get_game_engine.is_valid() else null
	if engine == null:
		return -999
	if not is_instance_valid(_game_log_panel):
		return -999

	var build_r: Result = StepTimelineBuildClass.build_full(engine)
	if not build_r.ok:
		GameLog.warn("Game", "构建 step 时间线失败（复盘模式将回退到命令时间线）: %s" % build_r.error)
		return -999
	if not (build_r.value is Dictionary):
		GameLog.warn("Game", "构建 step 时间线失败（返回类型错误）")
		return -999

	_history_step_timeline = Dictionary(build_r.value).duplicate(true)
	_history_step_timeline_active = true

	var events_val = _history_step_timeline.get("events", [])
	var events: Array = events_val if (events_val is Array) else []
	var entries := GameTimelineLogEntriesBuilderClass.build(events)
	if _game_log_panel.has_method("load_step_timeline"):
		_game_log_panel.call("load_step_timeline", _history_step_timeline, entries, false)
	else:
		_game_log_panel.call("load_entries", entries)

	var steps_val = _history_step_timeline.get("steps", [])
	var steps: Array = steps_val if (steps_val is Array) else []
	_history_head_step_index = steps.size() - 1
	_history_cursor_step_index = _history_head_step_index

	_game_log_panel.call("set_timeline_head", _history_head_step_index)
	_game_log_panel.call("set_timeline_cursor", _history_cursor_step_index)
	_set_replay_bar_state(_history_head_step_index, _history_cursor_step_index, false)
	if _show_game_log_panel_in_right_panel.is_valid():
		_show_game_log_panel_in_right_panel.call()

	return _history_command_index_to_step_index(int(target_command_index))

func _history_command_index_to_step_index(command_index: int) -> int:
	if not _history_step_timeline.has("steps"):
		return -999
	var steps_val = _history_step_timeline.get("steps", null)
	if not (steps_val is Array):
		return -999
	var steps: Array = steps_val
	var cmd := int(command_index)
	if cmd < 0:
		return -1
	for idx in range(steps.size()):
		var s_val = steps[idx]
		if not (s_val is Dictionary):
			continue
		var s: Dictionary = s_val
		if str(s.get("kind", "")).strip_edges() != "command":
			continue
		if int(s.get("anchor_command_index", -999)) == cmd:
			return idx
	return -999

func _seek_to_history_step(target_step_index: int) -> void:
	var engine: GameEngine = _get_game_engine.call() if _get_game_engine.is_valid() else null
	if engine == null:
		return
	if not _history_step_timeline.has("steps"):
		return

	var steps_val = _history_step_timeline.get("steps", null)
	if not (steps_val is Array):
		return
	var steps: Array = steps_val

	_history_head_step_index = steps.size() - 1
	var target := clampi(int(target_step_index), -1, _history_head_step_index)
	if target == _history_cursor_step_index:
		if _update_ui.is_valid():
			_update_ui.call()
		return

	var state_dict: Dictionary = {}
	var anchor_cmd := -1
	if target < 0:
		var init_val = _history_step_timeline.get("initial_state_dict", null)
		if init_val is Dictionary:
			state_dict = Dictionary(init_val)
	else:
		if target >= steps.size():
			return
		var step_val = steps[target]
		if step_val is Dictionary:
			var step: Dictionary = step_val
			anchor_cmd = int(step.get("anchor_command_index", -1))
			var sd_val = step.get("state_dict", null)
			if sd_val is Dictionary:
				state_dict = Dictionary(sd_val)

	if state_dict.is_empty():
		GameLog.warn("Game", "复盘 step seek 失败：缺少 state 快照: step=%d" % target)
		return

	var restore_r := GameState.from_dict(state_dict)
	if not restore_r.ok:
		GameLog.warn("Game", "复盘 step seek 失败：恢复 state 失败: %s" % restore_r.error)
		return
	var restored: GameState = restore_r.value
	if restored == null:
		GameLog.warn("Game", "复盘 step seek 失败：恢复 state 为空")
		return

	# 复盘态：允许用 step 快照覆盖 state；动作面板仍保持禁用，避免产生新分支。
	engine.state = restored
	engine.current_command_index = anchor_cmd
	_history_cursor_step_index = target

	_force_full_panel_sync_next_update = true
	if _update_ui.is_valid():
		_update_ui.call()

func _exit_history_step_timeline() -> void:
	# M4.3：正常对局也使用 step 时间线视图；“退出复盘”仅意味着跳回最新 step。
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
	if not _replay_step_timeline.has("steps"):
		return

	var steps_val = _replay_step_timeline.get("steps", null)
	if not (steps_val is Array):
		return
	var steps: Array = steps_val

	_replay_head_step_index = steps.size() - 1
	var target := clampi(int(target_step_index), -1, _replay_head_step_index)
	if target == _replay_cursor_step_index:
		if _update_ui.is_valid():
			_update_ui.call()
		return

	var state_dict: Dictionary = {}
	var anchor_cmd := -1
	if target < 0:
		var init_val = _replay_step_timeline.get("initial_state_dict", null)
		if init_val is Dictionary:
			state_dict = Dictionary(init_val)
	else:
		if target >= steps.size():
			return
		var step_val = steps[target]
		if step_val is Dictionary:
			var step: Dictionary = step_val
			anchor_cmd = int(step.get("anchor_command_index", -1))
			var sd_val = step.get("state_dict", null)
			if sd_val is Dictionary:
				state_dict = Dictionary(sd_val)

	if state_dict.is_empty():
		GameLog.warn("Game", "回放 step seek 失败：缺少 state 快照: step=%d" % target)
		return

	var restore_r := GameState.from_dict(state_dict)
	if not restore_r.ok:
		GameLog.warn("Game", "回放 step seek 失败：恢复 state 失败: %s" % restore_r.error)
		return
	var restored: GameState = restore_r.value
	if restored == null:
		GameLog.warn("Game", "回放 step seek 失败：恢复 state 为空")
		return

	# 只读回放：允许直接覆盖 state（不改写 command_history/checkpoints）。
	engine.state = restored
	engine.current_command_index = anchor_cmd
	_replay_cursor_step_index = target

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
	if not _replay_original_log_entries.is_empty() and is_instance_valid(_game_log_panel):
		_game_log_panel.call("load_entries", _replay_original_log_entries)
	_replay_original_log_entries.clear()

	var engine: GameEngine = _get_game_engine.call() if _get_game_engine.is_valid() else null
	if engine != null and is_instance_valid(_game_log_panel):
		var head_index := engine.command_history.size() - 1
		var cursor_index := int(engine.current_command_index)
		_game_log_panel.call("set_timeline_head", head_index)
		_game_log_panel.call("set_timeline_cursor", cursor_index)
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
