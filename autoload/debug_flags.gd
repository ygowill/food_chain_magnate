# 调试开关
# 控制调试模式、详细日志等开发时功能
extends Node

# 调试模式标志
var debug_mode: bool = false
var verbose_logging: bool = false
var validate_invariants: bool = true  # 每条命令后校验不变量
var show_console: bool = false

# 性能分析
var profile_commands: bool = false

func _ready() -> void:
	# 开发版本默认启用调试模式
	if OS.has_feature("debug"):
		debug_mode = true
		verbose_logging = false  # 按需开启详细日志

func is_debug_mode() -> bool:
	# 发布版本强制禁用调试模式
	if OS.has_feature("release"):
		return false
	return debug_mode

func enable_debug() -> void:
	debug_mode = true
	verbose_logging = true
	validate_invariants = true
	GameLog.set_min_level(GameLog.LEVEL_DEBUG)
	GameLog.info("DebugFlags", "调试模式已启用")

func disable_debug() -> void:
	debug_mode = false
	verbose_logging = false
	GameLog.set_min_level(GameLog.LEVEL_INFO)
	GameLog.info("DebugFlags", "调试模式已禁用")

func toggle_debug() -> void:
	if debug_mode:
		disable_debug()
	else:
		enable_debug()

func toggle_console() -> void:
	show_console = not show_console

func _input(event: InputEvent) -> void:
	# Ctrl+Shift+D 切换调试模式
	if event is InputEventKey and event.pressed:
		if event.ctrl_pressed and event.shift_pressed and event.keycode == KEY_D:
			toggle_debug()

		# ~ 键切换控制台
		if event.keycode == KEY_QUOTELEFT:
			toggle_console()

# 获取当前状态
func get_status() -> Dictionary:
	return {
		"debug_mode": debug_mode,
		"verbose_logging": verbose_logging,
		"validate_invariants": validate_invariants,
		"show_console": show_console,
		"profile_commands": profile_commands
	}
