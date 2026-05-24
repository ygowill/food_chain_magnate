# Game scene：日志面板 Dock 控制器
# 负责：打开/关闭日志面板，并将其嵌入到右侧 DockHost（覆盖 ActionPanel）。
class_name GameLogDockController
extends RefCounted

const OnlinePerfTraceClass = preload("res://core/debug/online_perf_trace.gd")

var _ensure_left_area_visible: Callable = Callable()
var _ensure_right_panel_visible: Callable = Callable()
var _cancel_right_panel_docked_panel: Callable = Callable()
var _sync_right_panel_docked_view: Callable = Callable()
var _dock_popup_into_right_panel: Callable = Callable()

var _game_log_panel: Control = null
var _right_panel_dock_host: Control = null
var _timeline_controller: Object = null
var _restore_panel_after_close: Control = null

func _init(
	ensure_left_area_visible: Callable,
	ensure_right_panel_visible: Callable,
	cancel_right_panel_docked_panel: Callable,
	sync_right_panel_docked_view: Callable,
	dock_popup_into_right_panel: Callable,
	game_log_panel: Control,
	right_panel_dock_host: Control,
	timeline_controller: Object
) -> void:
	_ensure_left_area_visible = ensure_left_area_visible
	_ensure_right_panel_visible = ensure_right_panel_visible
	_cancel_right_panel_docked_panel = cancel_right_panel_docked_panel
	_sync_right_panel_docked_view = sync_right_panel_docked_view
	_dock_popup_into_right_panel = dock_popup_into_right_panel
	_game_log_panel = game_log_panel
	_right_panel_dock_host = right_panel_dock_host
	_timeline_controller = timeline_controller

func dispose() -> void:
	_ensure_left_area_visible = Callable()
	_ensure_right_panel_visible = Callable()
	_cancel_right_panel_docked_panel = Callable()
	_sync_right_panel_docked_view = Callable()
	_dock_popup_into_right_panel = Callable()
	_game_log_panel = null
	_right_panel_dock_host = null
	_timeline_controller = null

func toggle_game_log() -> void:
	if not is_instance_valid(_game_log_panel):
		return

	var show_logs: bool = not is_game_log_visible_in_right_panel()
	var span := OnlinePerfTraceClass.begin_span("ui.game_log.toggle", {
		"show_logs": bool(show_logs),
		"was_visible": not bool(show_logs),
		"had_other_docked_panels": bool(_has_other_visible_docked_panels()),
	})
	if show_logs:
		# 玩家信息与日志需要同屏：确保左侧信息区可见，同时确保右侧面板可见以承载日志。
		if _ensure_left_area_visible.is_valid():
			_ensure_left_area_visible.call()
		if _ensure_right_panel_visible.is_valid():
			_ensure_right_panel_visible.call()

		# 若右侧 DockHost 内已有可见面板（例如当前动作 UI），先临时隐藏，避免多个 docked 视图竞争焦点。
		_hide_other_visible_docked_panels()

		# 将日志面板嵌入到 RightPanel 抽屉区域（覆盖 ActionPanel），并显示。
		_game_log_panel.set_meta("popup_title", "日志")
		if _dock_popup_into_right_panel.is_valid():
			_dock_popup_into_right_panel.call(_game_log_panel)
		_request_log_refresh_after_show()
	else:
		# 关闭日志：返回默认右侧动作区。
		hide_game_log_panel_in_right_panel(true)
	OnlinePerfTraceClass.end_span(span, {
		"show_logs": bool(show_logs),
		"visible_after": bool(is_game_log_visible_in_right_panel()),
	})

func is_game_log_visible_in_right_panel() -> bool:
	if not is_instance_valid(_game_log_panel):
		return false
	if not is_instance_valid(_right_panel_dock_host):
		return false
	return _game_log_panel.visible and _game_log_panel.get_parent() == _right_panel_dock_host

func hide_game_log_panel_in_right_panel(restore_hidden_panels: bool = true) -> void:
	if not is_game_log_visible_in_right_panel():
		if not restore_hidden_panels:
			_restore_panel_after_close = null
		return
	_game_log_panel.visible = false
	if restore_hidden_panels:
		_restore_hidden_docked_panels()
	else:
		_restore_panel_after_close = null
	if _sync_right_panel_docked_view.is_valid():
		_sync_right_panel_docked_view.call()

func show_game_log_panel_in_right_panel() -> void:
	# 回放/复盘默认显示日志：避免 ReplayBar/时间线功能“藏在被关闭的面板里”。
	if not is_instance_valid(_game_log_panel):
		return

	# 已在 RightPanel 抽屉中显示
	if _game_log_panel.visible and is_instance_valid(_right_panel_dock_host) and _game_log_panel.get_parent() == _right_panel_dock_host:
		return
	var span := OnlinePerfTraceClass.begin_span("ui.game_log.show_in_right_panel", {
		"had_other_docked_panels": bool(_has_other_visible_docked_panels()),
	})

	if _ensure_left_area_visible.is_valid():
		_ensure_left_area_visible.call()
	if _ensure_right_panel_visible.is_valid():
		_ensure_right_panel_visible.call()

	# 若右侧 DockHost 内已有可见面板（例如当前动作 UI），先临时隐藏，避免多个 docked 视图竞争焦点。
	_hide_other_visible_docked_panels()

	_game_log_panel.set_meta("popup_title", "日志")
	if _dock_popup_into_right_panel.is_valid():
		_dock_popup_into_right_panel.call(_game_log_panel)
	_request_log_refresh_after_show()
	OnlinePerfTraceClass.end_span(span, {
		"visible_after": bool(is_game_log_visible_in_right_panel()),
	})

func _request_log_refresh_after_show() -> void:
	# GameLogPanel 在隐藏状态 load_step_timeline() 时会清空显示节点并延后构建；
	# 因此日志必须先 dock/可见，再在下一帧按当前引擎状态强制重建一次。
	call_deferred("_apply_log_refresh_after_show")

func _apply_log_refresh_after_show() -> void:
	if not is_game_log_visible_in_right_panel():
		return
	if is_instance_valid(_timeline_controller):
		if _timeline_controller.has_method("apply_live_log_timeline_from_engine"):
			_timeline_controller.call("apply_live_log_timeline_from_engine", true)
		elif _timeline_controller.has_method("request_live_log_timeline_refresh_deferred"):
			_timeline_controller.call("request_live_log_timeline_refresh_deferred")
		elif _timeline_controller.has_method("request_live_log_timeline_refresh"):
			_timeline_controller.call("request_live_log_timeline_refresh")
	if is_instance_valid(_game_log_panel) and _game_log_panel.has_method("ensure_display_ready"):
		_game_log_panel.call("ensure_display_ready")

func _has_other_visible_docked_panels() -> bool:
	if not is_instance_valid(_right_panel_dock_host):
		return false
	for ch in _right_panel_dock_host.get_children():
		if ch == _game_log_panel:
			continue
		if ch is Control and (ch as Control).visible:
			return true
	return false

func _hide_other_visible_docked_panels() -> void:
	_restore_panel_after_close = null
	if not is_instance_valid(_right_panel_dock_host):
		return
	for ch in _right_panel_dock_host.get_children():
		if ch == _game_log_panel:
			continue
		if not (ch is Control):
			continue
		var c: Control = ch
		if not c.visible:
			continue
		if _restore_panel_after_close == null:
			_restore_panel_after_close = c
		c.visible = false

func _restore_hidden_docked_panels() -> void:
	if _restore_panel_after_close == null or not is_instance_valid(_restore_panel_after_close):
		_restore_panel_after_close = null
		return
	_restore_panel_after_close.visible = true
	_restore_panel_after_close = null
