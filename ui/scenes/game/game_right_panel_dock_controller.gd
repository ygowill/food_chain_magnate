# Game scene：右侧面板 Dock/抽屉控制器
# 负责：DockHost 的抽屉显示、标题、footer 配置与按钮分发。
class_name GameRightPanelDockController
extends RefCounted

var _ensure_right_panel_visible: Callable = Callable()
var _cancel_docked_panel: Callable = Callable()
var _toggle_game_log: Callable = Callable()

var _game_log_panel: Control = null
var _right_panel_default_stack: Control = null
var _right_panel_dock_host: Control = null
var _right_panel_back_button: Button = null
var _right_panel_title_label: Label = null
var _right_panel_footer_row: Control = null
var _right_panel_footer_cancel_button: Button = null
var _right_panel_footer_secondary_button: Button = null
var _right_panel_footer_primary_button: Button = null

var _right_panel_footer_source: Object = null

func _init(
	ensure_right_panel_visible: Callable,
	cancel_docked_panel: Callable,
	toggle_game_log: Callable,
	game_log_panel: Control,
	right_panel_default_stack: Control,
	right_panel_dock_host: Control,
	right_panel_back_button: Button,
	right_panel_title_label: Label,
	right_panel_footer_row: Control,
	right_panel_footer_cancel_button: Button,
	right_panel_footer_secondary_button: Button,
	right_panel_footer_primary_button: Button
) -> void:
	_ensure_right_panel_visible = ensure_right_panel_visible
	_cancel_docked_panel = cancel_docked_panel
	_toggle_game_log = toggle_game_log
	_game_log_panel = game_log_panel
	_right_panel_default_stack = right_panel_default_stack
	_right_panel_dock_host = right_panel_dock_host
	_right_panel_back_button = right_panel_back_button
	_right_panel_title_label = right_panel_title_label
	_right_panel_footer_row = right_panel_footer_row
	_right_panel_footer_cancel_button = right_panel_footer_cancel_button
	_right_panel_footer_secondary_button = right_panel_footer_secondary_button
	_right_panel_footer_primary_button = right_panel_footer_primary_button

func dock_popup(panel: Control) -> bool:
	if panel == null or not is_instance_valid(panel):
		return false
	if not is_instance_valid(_right_panel_dock_host):
		return false

	if _ensure_right_panel_visible.is_valid():
		_ensure_right_panel_visible.call()

	# 避免“首次添加到场景 root 时闪一下/溢出”：先以隐藏状态移动，再在抽屉中显示。
	panel.visible = false
	if panel.get_parent() != _right_panel_dock_host:
		var old_parent := panel.get_parent()
		if is_instance_valid(old_parent):
			old_parent.remove_child(panel)
		_right_panel_dock_host.add_child(panel)

	if panel.has_method("set_embedded_in_right_panel"):
		panel.call("set_embedded_in_right_panel", true)

	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 0
	panel.offset_top = 0
	panel.offset_right = 0
	panel.offset_bottom = 0

	panel.visible = true
	sync_docked_view()
	return true

func sync_docked_view() -> void:
	var active := _get_active_docked_panel()
	var has_docked := active != null

	if is_instance_valid(_right_panel_default_stack):
		_right_panel_default_stack.visible = not has_docked
	if is_instance_valid(_right_panel_dock_host):
		_right_panel_dock_host.visible = has_docked
	if is_instance_valid(_right_panel_back_button):
		_right_panel_back_button.visible = has_docked
	if is_instance_valid(_right_panel_title_label):
		if has_docked and is_instance_valid(active):
			var title := ""
			if active.has_meta("popup_title"):
				title = str(active.get_meta("popup_title")).strip_edges()
			if title.is_empty():
				title = str(active.name)
			_right_panel_title_label.text = title
		else:
			_right_panel_title_label.text = "操作"

	_bind_right_panel_footer_source(active)
	_sync_right_panel_footer(active)

func on_footer_cancel_pressed() -> void:
	if _cancel_docked_panel.is_valid():
		_cancel_docked_panel.call()
	sync_docked_view()

func on_footer_primary_pressed() -> void:
	var active := _get_active_docked_panel()
	if active == null or not is_instance_valid(active):
		return
	if active.has_method("right_panel_footer_primary"):
		active.call("right_panel_footer_primary")

func on_footer_secondary_pressed() -> void:
	var active := _get_active_docked_panel()
	if active == null or not is_instance_valid(active):
		return
	if active.has_method("right_panel_footer_secondary"):
		active.call("right_panel_footer_secondary")

func on_back_pressed() -> void:
	# 日志面板作为 RightPanel 抽屉视图时：返回键应关闭日志，而不是走“取消当前动作/面板”的逻辑。
	if is_instance_valid(_game_log_panel) and _game_log_panel.visible and is_instance_valid(_right_panel_dock_host) and _game_log_panel.get_parent() == _right_panel_dock_host:
		if _toggle_game_log.is_valid():
			_toggle_game_log.call()
		return
	on_footer_cancel_pressed()

func _get_active_docked_panel() -> Control:
	if not is_instance_valid(_right_panel_dock_host):
		return null
	for ch in _right_panel_dock_host.get_children():
		if not (ch is Control):
			continue
		var c: Control = ch
		if is_instance_valid(c) and c.visible:
			return c
	return null

func _bind_right_panel_footer_source(active_panel: Object) -> void:
	if _right_panel_footer_source == active_panel:
		return

	var handler := Callable(self, "_on_right_panel_footer_changed")

	if is_instance_valid(_right_panel_footer_source) and _right_panel_footer_source.has_signal("right_panel_footer_changed"):
		var old_sig := Signal(_right_panel_footer_source, &"right_panel_footer_changed")
		if old_sig.is_connected(handler):
			old_sig.disconnect(handler)

	_right_panel_footer_source = active_panel

	if is_instance_valid(_right_panel_footer_source) and _right_panel_footer_source.has_signal("right_panel_footer_changed"):
		var new_sig := Signal(_right_panel_footer_source, &"right_panel_footer_changed")
		if not new_sig.is_connected(handler):
			new_sig.connect(handler)

func _on_right_panel_footer_changed() -> void:
	sync_docked_view()

func _sync_right_panel_footer(active_panel: Object) -> void:
	if not is_instance_valid(_right_panel_footer_row):
		return
	if not is_instance_valid(_right_panel_footer_cancel_button) or not is_instance_valid(_right_panel_footer_primary_button) or not is_instance_valid(_right_panel_footer_secondary_button):
		_right_panel_footer_row.visible = false
		return

	if active_panel == null or not is_instance_valid(active_panel):
		_right_panel_footer_row.visible = false
		return

	var config: Dictionary = {}
	if active_panel.has_method("right_panel_get_footer_config"):
		var r = active_panel.call("right_panel_get_footer_config")
		if r is Dictionary:
			config = r

	if config.is_empty():
		_right_panel_footer_row.visible = false
		return

	var show_cancel := bool(config.get("show_cancel", true))
	var cancel_text := str(config.get("cancel_text", "取消"))
	var cancel_enabled := bool(config.get("cancel_enabled", true))

	var show_secondary := bool(config.get("show_secondary", false))
	var secondary_text := str(config.get("secondary_text", ""))
	var secondary_enabled := bool(config.get("secondary_enabled", true))

	var show_primary := bool(config.get("show_primary", true))
	var primary_text := str(config.get("primary_text", ""))
	var primary_enabled := bool(config.get("primary_enabled", true))

	if secondary_text.is_empty():
		show_secondary = false
	if primary_text.is_empty():
		show_primary = false

	_right_panel_footer_row.visible = show_cancel or show_secondary or show_primary

	_right_panel_footer_cancel_button.visible = show_cancel
	_right_panel_footer_cancel_button.text = cancel_text
	_right_panel_footer_cancel_button.disabled = not cancel_enabled

	_right_panel_footer_secondary_button.visible = show_secondary
	_right_panel_footer_secondary_button.text = secondary_text
	_right_panel_footer_secondary_button.disabled = not secondary_enabled

	_right_panel_footer_primary_button.visible = show_primary
	_right_panel_footer_primary_button.text = primary_text
	_right_panel_footer_primary_button.disabled = not primary_enabled

