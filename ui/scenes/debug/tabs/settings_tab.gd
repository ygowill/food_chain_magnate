# 设置标签页
# 调试相关的设置选项
extends MarginContainer

var _registry: DebugCommandRegistry = null

@onready var settings_content: VBoxContainer = $ScrollContainer/SettingsContent

# 设置控件引用
var _debug_mode_check: CheckBox
var _verbose_logging_check: CheckBox
var _validate_invariants_check: CheckBox
var _force_execute_commands_check: CheckBox
var _profile_commands_check: CheckBox
var _show_console_check: CheckBox

var _is_syncing: bool = false

func init(registry: DebugCommandRegistry) -> void:
	_registry = registry

func _ready() -> void:
	_build_ui()
	_sync_from_flags()

func _build_ui() -> void:
	if not is_instance_valid(settings_content):
		return

	# 清空现有内容
	for child in settings_content.get_children():
		child.queue_free()

	# 调试选项
	_create_section_label("═══ 调试选项 ═══")

	_debug_mode_check = _create_checkbox("调试模式", _on_debug_mode_toggled)
	_verbose_logging_check = _create_checkbox("详细日志", _on_verbose_logging_toggled)
	_validate_invariants_check = _create_checkbox("命令后校验不变量", _on_validate_invariants_toggled)
	_force_execute_commands_check = _create_checkbox("强制执行命令（跳过校验）", _on_force_execute_commands_toggled)
	_create_info_label("  ⚠️ 跳过动作可用性/校验器/回合阶段等限制；可能导致状态不一致，仅用于开发调试")
	_profile_commands_check = _create_checkbox("性能分析", _on_profile_commands_toggled)
	_show_console_check = _create_checkbox("显示控制台", _on_show_console_toggled)

	# 分隔
	settings_content.add_child(HSeparator.new())

	# 快捷键说明
	_create_section_label("═══ 快捷键 ═══")
	_create_info_label("~ : 切换调试面板")
	_create_info_label("Ctrl+Shift+D : 切换调试模式")
	_create_info_label("Ctrl+Enter : 执行命令")
	_create_info_label("↑/↓ : 浏览命令历史")
	_create_info_label("Tab : 自动补全")
	_create_info_label("Ctrl+S : 快速保存快照")
	_create_info_label("Ctrl+L : 清空输出")
	_create_info_label("Ctrl+Z : 撤销命令（焦点不在输入框）")
	_create_info_label("Ctrl+Shift+Z : 重做命令（焦点不在输入框）")
	_create_info_label("Escape : 关闭面板")

	# 分隔
	settings_content.add_child(HSeparator.new())

	# 操作按钮
	_create_section_label("═══ 操作 ═══")

	var button_container := HBoxContainer.new()
	settings_content.add_child(button_container)

	var reset_btn := Button.new()
	reset_btn.text = "重置设置"
	reset_btn.pressed.connect(_on_reset_pressed)
	button_container.add_child(reset_btn)

	var apply_btn := Button.new()
	apply_btn.text = "应用设置"
	apply_btn.pressed.connect(_on_apply_pressed)
	button_container.add_child(apply_btn)

func _create_section_label(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_content.add_child(label)

func _create_info_label(text: String) -> void:
	var label := Label.new()
	label.text = "  " + text
	label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	settings_content.add_child(label)

func _create_checkbox(text: String, callback: Callable) -> CheckBox:
	var checkbox := CheckBox.new()
	checkbox.text = text
	checkbox.toggled.connect(callback)
	settings_content.add_child(checkbox)
	return checkbox

func _sync_from_flags() -> void:
	_is_syncing = true

	if is_instance_valid(_debug_mode_check):
		_debug_mode_check.button_pressed = DebugFlags.debug_mode
	if is_instance_valid(_verbose_logging_check):
		_verbose_logging_check.button_pressed = DebugFlags.verbose_logging
	if is_instance_valid(_validate_invariants_check):
		_validate_invariants_check.button_pressed = DebugFlags.validate_invariants
	if is_instance_valid(_force_execute_commands_check):
		_force_execute_commands_check.button_pressed = DebugFlags.force_execute_commands
		_force_execute_commands_check.disabled = not DebugFlags.is_debug_mode()
	if is_instance_valid(_profile_commands_check):
		_profile_commands_check.button_pressed = DebugFlags.profile_commands
	if is_instance_valid(_show_console_check):
		_show_console_check.button_pressed = DebugFlags.show_console

	_is_syncing = false

func _on_debug_mode_toggled(pressed: bool) -> void:
	if _is_syncing:
		return
	if pressed:
		DebugFlags.enable_debug()
	else:
		DebugFlags.disable_debug()
	_sync_from_flags()

func _on_verbose_logging_toggled(pressed: bool) -> void:
	if _is_syncing:
		return
	DebugFlags.set_verbose_logging(pressed)
	_sync_from_flags()

func _on_validate_invariants_toggled(pressed: bool) -> void:
	if _is_syncing:
		return
	DebugFlags.set_validate_invariants(pressed)

func _on_force_execute_commands_toggled(pressed: bool) -> void:
	if _is_syncing:
		return
	DebugFlags.set_force_execute_commands(pressed)
	_sync_from_flags()

func _on_profile_commands_toggled(pressed: bool) -> void:
	if _is_syncing:
		return
	DebugFlags.set_profile_commands(pressed)

func _on_show_console_toggled(pressed: bool) -> void:
	if _is_syncing:
		return
	DebugFlags.set_show_console(pressed)
	_sync_from_flags()

func _on_reset_pressed() -> void:
	DebugFlags.enable_debug()
	DebugFlags.set_verbose_logging(false)
	DebugFlags.set_validate_invariants(true)
	DebugFlags.set_force_execute_commands(false)
	DebugFlags.set_profile_commands(false)
	DebugFlags.set_show_console(false)
	_sync_from_flags()

func _on_apply_pressed() -> void:
	# 设置已经通过 toggled 信号实时应用
	GameLog.info("DebugPanel", "设置已应用")
