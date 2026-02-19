# Game scene：右侧面板 Dock/抽屉控制器
# 负责：DockHost 的抽屉显示、标题、footer 配置与按钮分发。
class_name GameRightPanelDockController
extends RefCounted

const UiStylesClass = preload("res://ui/utils/ui_styles.gd")

const _GUIDED_ACTION_FOOTER_SCRIPT_PATHS := {
	"res://ui/components/recruit_panel/recruit_panel.gd": true,
	"res://ui/components/train_panel/train_panel.gd": true,
	"res://ui/components/marketing_panel/marketing_panel.gd": true,
	"res://ui/components/production_panel/production_panel.gd": true,
}

var _ensure_right_panel_visible: Callable = Callable()
var _cancel_docked_panel: Callable = Callable()
var _toggle_game_log: Callable = Callable()
var _request_action: Callable = Callable()
var _get_flow_controls_config: Callable = Callable()

var _game_log_panel: Control = null
var _right_panel_default_stack: Control = null
var _right_panel_dock_host: Control = null
var _right_panel_header_row: Control = null
var _right_panel_back_button: Button = null
var _right_panel_title_label: Label = null
var _right_panel_footer_row: Control = null
var _right_panel_footer_cancel_button: Button = null
var _right_panel_footer_secondary_button: Button = null
var _right_panel_footer_primary_button: Button = null

var _right_panel_footer_source: Object = null
var _footer_secondary_action_id: String = ""
var _footer_secondary_disabled_reason: String = ""
var _footer_secondary_button_meta_key: StringName = &"action_id"

func _init(
	ensure_right_panel_visible: Callable,
	cancel_docked_panel: Callable,
	toggle_game_log: Callable,
	game_log_panel: Control,
	right_panel_default_stack: Control,
	right_panel_dock_host: Control,
	right_panel_header_row: Control,
	right_panel_back_button: Button,
	right_panel_title_label: Label,
	right_panel_footer_row: Control,
	right_panel_footer_cancel_button: Button,
	right_panel_footer_secondary_button: Button,
	right_panel_footer_primary_button: Button,
	request_action: Callable,
	get_flow_controls_config: Callable
) -> void:
	_ensure_right_panel_visible = ensure_right_panel_visible
	_cancel_docked_panel = cancel_docked_panel
	_toggle_game_log = toggle_game_log
	_request_action = request_action
	_get_flow_controls_config = get_flow_controls_config
	_game_log_panel = game_log_panel
	_right_panel_default_stack = right_panel_default_stack
	_right_panel_dock_host = right_panel_dock_host
	_right_panel_header_row = right_panel_header_row
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
	var hide_header_for_log := has_docked and is_instance_valid(_game_log_panel) and active == _game_log_panel

	if is_instance_valid(_right_panel_default_stack):
		_right_panel_default_stack.visible = not has_docked
	if is_instance_valid(_right_panel_dock_host):
		_right_panel_dock_host.visible = has_docked
	if is_instance_valid(_right_panel_header_row):
		_right_panel_header_row.visible = not hide_header_for_log
	if is_instance_valid(_right_panel_back_button):
		# v2 guided action flow：不允许通过“返回”退出当前动作
		_right_panel_back_button.visible = false
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
	if _footer_secondary_action_id == "skip_sub_phase" and _request_action.is_valid():
		_request_action.call("skip_sub_phase", {})
		return
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

func _is_guided_action_panel(active_panel: Object) -> bool:
	if active_panel == null or not is_instance_valid(active_panel):
		return false
	if not (active_panel is Node):
		return false
	var scr = (active_panel as Node).get_script()
	if scr == null or not (scr is Script):
		return false
	return _GUIDED_ACTION_FOOTER_SCRIPT_PATHS.has(str((scr as Script).resource_path))

func _get_skip_step_config() -> Dictionary:
	if not _get_flow_controls_config.is_valid():
		return {}
	var v = _get_flow_controls_config.call()
	if not (v is Dictionary):
		return {}
	var cfg: Dictionary = v
	var ss_val = cfg.get("skip_step", null)
	if not (ss_val is Dictionary):
		return {}
	return Dictionary(ss_val)

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

	_footer_secondary_action_id = ""
	_footer_secondary_disabled_reason = ""
	var is_guided_action_panel := _is_guided_action_panel(active_panel)

	var show_cancel := bool(config.get("show_cancel", true))
	var cancel_text := str(config.get("cancel_text", "取消"))
	var cancel_enabled := bool(config.get("cancel_enabled", true))
	# guided action flow：不允许通过 footer 取消退出当前动作
	show_cancel = false

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

	# guided action flow：把“跳过子阶段”放入 footer，与确认在同一行（跳过在左，确认在右）。
	if is_guided_action_panel and not show_secondary:
		var ss_cfg := _get_skip_step_config()
		if not ss_cfg.is_empty() and bool(ss_cfg.get("visible", false)):
			show_secondary = true
			secondary_text = str(ss_cfg.get("text", "")).strip_edges()
			secondary_enabled = bool(ss_cfg.get("enabled", true))
			_footer_secondary_action_id = "skip_sub_phase"
			_footer_secondary_disabled_reason = str(ss_cfg.get("disabled_reason", "")).strip_edges()

	_right_panel_footer_row.visible = show_cancel or show_secondary or show_primary

	_right_panel_footer_cancel_button.visible = show_cancel
	_right_panel_footer_cancel_button.text = cancel_text
	_right_panel_footer_cancel_button.disabled = not cancel_enabled

	_right_panel_footer_secondary_button.visible = show_secondary
	_right_panel_footer_secondary_button.text = secondary_text
	_right_panel_footer_secondary_button.disabled = not secondary_enabled
	if _right_panel_footer_secondary_button.disabled and not _footer_secondary_disabled_reason.is_empty():
		_right_panel_footer_secondary_button.tooltip_text = "不可用：%s" % _footer_secondary_disabled_reason
	else:
		_right_panel_footer_secondary_button.tooltip_text = ""
	if show_secondary and not _footer_secondary_action_id.is_empty():
		_right_panel_footer_secondary_button.set_meta(_footer_secondary_button_meta_key, _footer_secondary_action_id)
	elif _right_panel_footer_secondary_button.has_meta(_footer_secondary_button_meta_key):
		_right_panel_footer_secondary_button.remove_meta(_footer_secondary_button_meta_key)

	_right_panel_footer_primary_button.visible = show_primary
	_right_panel_footer_primary_button.text = primary_text
	_right_panel_footer_primary_button.disabled = not primary_enabled

	# 视觉样式：确认按钮使用“跳过”同款 secondary 样式；其它面板保持 primary 风格。
	UiStylesClass.apply_button_secondary(_right_panel_footer_cancel_button)
	UiStylesClass.apply_button_secondary(_right_panel_footer_secondary_button)
	if is_guided_action_panel:
		UiStylesClass.apply_button_secondary(_right_panel_footer_primary_button)
	else:
		UiStylesClass.apply_button_primary(_right_panel_footer_primary_button)
