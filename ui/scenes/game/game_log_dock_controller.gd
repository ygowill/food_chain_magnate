# Game scene：日志面板 Dock 控制器
# 负责：打开/关闭日志面板，并将其嵌入到右侧 DockHost（覆盖 ActionPanel）。
class_name GameLogDockController
extends RefCounted

var _ensure_left_area_visible: Callable = Callable()
var _ensure_right_panel_visible: Callable = Callable()
var _cancel_right_panel_docked_panel: Callable = Callable()
var _sync_right_panel_docked_view: Callable = Callable()
var _dock_popup_into_right_panel: Callable = Callable()

var _game_log_panel: Control = null
var _right_panel_dock_host: Control = null
var _timeline_controller: Object = null

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

	var show_logs: bool = not bool(_game_log_panel.visible)
	if show_logs:
		# 玩家信息与日志需要同屏：确保左侧信息区可见，同时确保右侧面板可见以承载日志。
		if _ensure_left_area_visible.is_valid():
			_ensure_left_area_visible.call()
		if _ensure_right_panel_visible.is_valid():
			_ensure_right_panel_visible.call()

		# M4.3：打开日志时，按当前引擎状态重建 step 时间线视图（保证实时/回放一致）。
		if is_instance_valid(_timeline_controller) and _timeline_controller.has_method("apply_live_log_timeline_from_engine"):
			_timeline_controller.call("apply_live_log_timeline_from_engine")

		# 若右侧已有 docked 操作面板/弹窗，先关闭它们，避免日志被遮挡或出现多个 docked 视图竞争焦点。
		var has_other_docked := _has_other_visible_docked_panels()
		if has_other_docked:
			if _cancel_right_panel_docked_panel.is_valid():
				_cancel_right_panel_docked_panel.call()
			if _sync_right_panel_docked_view.is_valid():
				_sync_right_panel_docked_view.call()

		# 将日志面板嵌入到 RightPanel 抽屉区域（覆盖 ActionPanel），并显示。
		_game_log_panel.set_meta("popup_title", "日志")
		if _dock_popup_into_right_panel.is_valid():
			_dock_popup_into_right_panel.call(_game_log_panel)
	else:
		# 关闭日志：返回默认右侧动作区。
		_game_log_panel.visible = false
		if _sync_right_panel_docked_view.is_valid():
			_sync_right_panel_docked_view.call()

func show_game_log_panel_in_right_panel() -> void:
	# 回放/复盘默认显示日志：避免 ReplayBar/时间线功能“藏在被关闭的面板里”。
	if not is_instance_valid(_game_log_panel):
		return

	# 已在 RightPanel 抽屉中显示
	if _game_log_panel.visible and is_instance_valid(_right_panel_dock_host) and _game_log_panel.get_parent() == _right_panel_dock_host:
		return

	if _ensure_left_area_visible.is_valid():
		_ensure_left_area_visible.call()
	if _ensure_right_panel_visible.is_valid():
		_ensure_right_panel_visible.call()

	# 若右侧已有 docked 操作面板/弹窗，先关闭它们，避免多个 docked 视图竞争焦点。
	var has_other_docked := _has_other_visible_docked_panels()
	if has_other_docked:
		if _cancel_right_panel_docked_panel.is_valid():
			_cancel_right_panel_docked_panel.call()
		if _sync_right_panel_docked_view.is_valid():
			_sync_right_panel_docked_view.call()

	_game_log_panel.set_meta("popup_title", "日志")
	if _dock_popup_into_right_panel.is_valid():
		_dock_popup_into_right_panel.call(_game_log_panel)

func _has_other_visible_docked_panels() -> bool:
	if not is_instance_valid(_right_panel_dock_host):
		return false
	for ch in _right_panel_dock_host.get_children():
		if ch == _game_log_panel:
			continue
		if ch is Control and (ch as Control).visible:
			return true
	return false
