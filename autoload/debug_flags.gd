# 调试开关
# 控制调试模式、详细日志等开发时功能
extends Node

signal debug_panel_toggled(visible: bool)
signal debug_setting_changed(setting: String, value: Variant)

# 调试模式标志
var debug_mode: bool = false
var verbose_logging: bool = false
var validate_invariants: bool = true  # 每条命令后校验不变量
var show_console: bool = false

# 显示选项
var show_grid_coords: bool = false
var show_entity_ids: bool = false
var show_collision_boxes: bool = false
var show_fps: bool = false

# 性能分析
var profile_commands: bool = false

func _ready() -> void:
	# 开发版本默认启用调试模式
	if OS.has_feature("debug"):
		debug_mode = true
		verbose_logging = false  # 按需开启详细日志

	# 确保日志级别与开关一致
	GameLog.set_min_level(GameLog.LEVEL_DEBUG if (is_debug_mode() and verbose_logging) else GameLog.LEVEL_INFO)

func is_debug_mode() -> bool:
	# 发布版本强制禁用调试模式
	if OS.has_feature("release"):
		return false
	return debug_mode

func enable_debug() -> void:
	debug_mode = true
	validate_invariants = true
	GameLog.set_min_level(GameLog.LEVEL_DEBUG if verbose_logging else GameLog.LEVEL_INFO)
	debug_setting_changed.emit("debug_mode", debug_mode)
	GameLog.info("DebugFlags", "调试模式已启用")

func disable_debug() -> void:
	debug_mode = false
	set_verbose_logging(false)
	set_show_console(false)
	debug_setting_changed.emit("debug_mode", debug_mode)
	GameLog.info("DebugFlags", "调试模式已禁用")

func toggle_debug() -> void:
	if debug_mode:
		disable_debug()
	else:
		enable_debug()

func toggle_console() -> void:
	set_show_console(not show_console)

func set_show_console(value: bool) -> void:
	# 非调试模式下强制关闭
	if value and not is_debug_mode():
		value = false
	if show_console == value:
		return
	show_console = value
	debug_panel_toggled.emit(show_console)
	debug_setting_changed.emit("show_console", show_console)

func set_verbose_logging(value: bool) -> void:
	if verbose_logging == value:
		return
	verbose_logging = value
	GameLog.set_min_level(GameLog.LEVEL_DEBUG if (is_debug_mode() and verbose_logging) else GameLog.LEVEL_INFO)
	debug_setting_changed.emit("verbose_logging", verbose_logging)

func set_validate_invariants(value: bool) -> void:
	if validate_invariants == value:
		return
	validate_invariants = value
	debug_setting_changed.emit("validate_invariants", validate_invariants)

func set_profile_commands(value: bool) -> void:
	if profile_commands == value:
		return
	profile_commands = value
	debug_setting_changed.emit("profile_commands", profile_commands)

func _input(event: InputEvent) -> void:
	# Ctrl+Shift+D 切换调试模式
	if event is InputEventKey and event.pressed:
		if event.ctrl_pressed and event.shift_pressed and event.keycode == KEY_D:
			toggle_debug()
			get_viewport().set_input_as_handled()

		# ~ 键切换控制台（发送信号，由游戏场景处理）
		# 注意：实际的面板切换由 game.gd 处理，这里只更新标志
		if event.keycode == KEY_QUOTELEFT:
			toggle_console()
			get_viewport().set_input_as_handled()

# 获取当前状态
func get_status() -> Dictionary:
	return {
		"debug_mode": debug_mode,
		"verbose_logging": verbose_logging,
		"validate_invariants": validate_invariants,
		"show_console": show_console,
		"profile_commands": profile_commands,
		"show_grid_coords": show_grid_coords,
		"show_entity_ids": show_entity_ids,
		"show_collision_boxes": show_collision_boxes,
		"show_fps": show_fps
	}
