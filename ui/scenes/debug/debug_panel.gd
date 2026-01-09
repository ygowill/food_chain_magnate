# 调试面板主控制器
# 管理调试面板的显示、命令执行和标签页切换
class_name DebugPanel
extends Window

signal command_executed(command: String, result_text: String)

const StateCommandsClass = preload("res://core/debug/debug_commands/state_commands.gd")
const GameCommandsClass = preload("res://core/debug/debug_commands/game_commands.gd")
const UtilCommandsClass = preload("res://core/debug/debug_commands/util_commands.gd")
const ActionCommandsClass = preload("res://core/debug/debug_commands/action_commands.gd")

# UI 颜色方案
const COLORS = {
	"background": Color(0.1, 0.1, 0.12, 0.95),
	"panel": Color(0.15, 0.15, 0.18),
	"text": Color(0.9, 0.9, 0.9),
	"text_dim": Color(0.6, 0.6, 0.6),
	"accent": Color(0.3, 0.6, 0.9),
	"success": Color(0.3, 0.8, 0.3),
	"warning": Color(0.9, 0.7, 0.2),
	"error": Color(0.9, 0.3, 0.3),
	"command": Color(0.5, 0.8, 1.0),
	"system": Color(0.7, 0.7, 0.7),
}

# 核心组件
var _command_registry: DebugCommandRegistry
var _game_engine: GameEngine = null

# 命令历史
var _input_history: Array[String] = []
var _history_index: int = -1

# UI 引用
@onready var tab_container: TabContainer = $MainContainer/TabContainer
@onready var command_input: LineEdit = $MainContainer/BottomBar/CommandInput
@onready var execute_button: Button = $MainContainer/BottomBar/ExecuteButton
@onready var status_label: Label = $MainContainer/StatusBar/StatusLabel
@onready var output_text: RichTextLabel = $MainContainer/TabContainer/OutputTab/OutputText

# 标签页引用
@onready var state_tab = $MainContainer/TabContainer/StateTab
@onready var command_tab = $MainContainer/TabContainer/CommandTab
@onready var entity_tab = $MainContainer/TabContainer/EntityTab
@onready var history_tab = $MainContainer/TabContainer/HistoryTab
@onready var settings_tab = $MainContainer/TabContainer/SettingsTab

func _ready() -> void:
	# 初始化命令注册表
	_command_registry = DebugCommandRegistry.new()
	_register_builtin_commands()

	# 连接信号
	command_input.text_submitted.connect(_on_command_submitted)
	execute_button.pressed.connect(_on_execute_pressed)
	close_requested.connect(_on_close_requested)

	# 设置窗口属性
	title = "调试面板"
	size = Vector2i(900, 600)
	min_size = Vector2i(600, 400)

	# 初始化标签页
	_init_tabs()
	_init_tab_titles()

	# 更新状态栏
	_update_status()

func _init_tab_titles() -> void:
	if not is_instance_valid(tab_container):
		return

	var titles := {
		"OutputTab": "输出",
		"StateTab": "状态",
		"CommandTab": "命令",
		"EntityTab": "实体",
		"HistoryTab": "历史",
		"SettingsTab": "设置",
	}

	var tab_count := tab_container.get_tab_count()
	for i in range(tab_count):
		var control := tab_container.get_tab_control(i)
		if control == null:
			continue
		var key: String = str(control.name)
		if titles.has(key):
			tab_container.set_tab_title(i, str(titles[key]))

func _init_tabs() -> void:
	# 初始化各标签页
	if state_tab and state_tab.has_method("init"):
		state_tab.init(_command_registry)
	if command_tab and command_tab.has_method("init"):
		command_tab.init(_command_registry, Callable(self, "execute_command"))
	if entity_tab and entity_tab.has_method("init"):
		entity_tab.init(_command_registry)
	if history_tab and history_tab.has_method("init"):
		history_tab.init(_command_registry)
	if settings_tab and settings_tab.has_method("init"):
		settings_tab.init(_command_registry)

func _register_builtin_commands() -> void:
	# 注册内置命令
	StateCommandsClass.register_all(_command_registry)
	GameCommandsClass.register_all(_command_registry)
	UtilCommandsClass.register_all(_command_registry)
	ActionCommandsClass.register_all(_command_registry)
	GameLog.info("DebugPanel", "已注册 %d 个调试命令" % _command_registry.get_command_names().size())

func set_game_engine(engine: GameEngine) -> void:
	_game_engine = engine
	_command_registry.set_game_engine(engine)
	refresh_state()

func get_game_engine() -> GameEngine:
	return _game_engine

func refresh_state() -> void:
	# 刷新所有标签页
	if state_tab and state_tab.has_method("refresh"):
		state_tab.refresh()
	if entity_tab and entity_tab.has_method("refresh"):
		entity_tab.refresh()
	if history_tab and history_tab.has_method("refresh"):
		history_tab.refresh()

	_update_status()

func execute_command(command_line: String) -> void:
	if command_line.strip_edges().is_empty():
		return

	GameLog.info("DebugPanel", "执行命令: %s" % command_line)

	# 添加到历史
	_input_history.append(command_line)
	_history_index = _input_history.size()

	# 打印命令
	print_output("[CMD] > %s" % command_line, "command")

	# 执行命令
	var result := _command_registry.execute(command_line)

	if result.ok:
		var output: String = str(result.value)
		if output == "__CLEAR__":
			clear_output()
		else:
			print_output(output, "info")
		GameLog.info("DebugPanel", "命令成功: %s" % command_line)
	else:
		print_output("[ERROR] %s" % result.error, "error")
		GameLog.warn("DebugPanel", "命令失败: %s - %s" % [command_line, result.error])

	# 刷新状态
	refresh_state()

	# 发送信号
	command_executed.emit(command_line, str(result.value) if result.ok else result.error)

func print_output(text: String, type: String = "info") -> void:
	if not is_instance_valid(output_text):
		return

	var color: Color
	match type:
		"info":
			color = COLORS["text"]
		"success":
			color = COLORS["success"]
		"warning":
			color = COLORS["warning"]
		"error":
			color = COLORS["error"]
		"command":
			color = COLORS["command"]
		"system":
			color = COLORS["system"]
		_:
			color = COLORS["text"]

	output_text.push_color(color)
	output_text.append_text(text + "\n")
	output_text.pop()

	# 滚动到底部
	output_text.scroll_to_line(output_text.get_line_count() - 1)

func clear_output() -> void:
	if is_instance_valid(output_text):
		output_text.clear()

func _update_status() -> void:
	if not is_instance_valid(status_label):
		return

	var status_parts: Array[String] = []

	# 调试模式状态
	if DebugFlags.is_debug_mode():
		status_parts.append("调试模式: 开启")
	else:
		status_parts.append("调试模式: 关闭")

	# 强制执行
	status_parts.append("强制执行: %s" % ("开启" if DebugFlags.force_execute_commands else "关闭"))

	# 命令数
	if _game_engine != null:
		var cmd_count := _game_engine.get_command_history().size()
		status_parts.append("命令数: %d" % cmd_count)

		# 状态哈希
		var state := _game_engine.get_state()
		if state != null:
			var hash_str := state.compute_hash().substr(0, 8)
			status_parts.append("Hash: %s" % hash_str)

	status_label.text = " | ".join(status_parts)

func _on_command_submitted(text: String) -> void:
	execute_command(text)
	command_input.clear()

func _on_execute_pressed() -> void:
	execute_command(command_input.text)
	command_input.clear()

func _on_close_requested() -> void:
	DebugFlags.set_show_console(false)

func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventKey and event.pressed:
		# 命令历史导航
		if command_input.has_focus():
			# Ctrl+Enter 执行命令（Enter 已由 text_submitted 覆盖，这里补齐设计中的 Ctrl+Enter）
			if event.ctrl_pressed and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER):
				_on_execute_pressed()
				get_viewport().set_input_as_handled()
				return

			if event.keycode == KEY_UP:
				_navigate_history(-1)
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_DOWN:
				_navigate_history(1)
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_TAB:
				_autocomplete()
				get_viewport().set_input_as_handled()

		# Ctrl+S 快速保存快照
		if event.ctrl_pressed and event.keycode == KEY_S:
			execute_command("snapshot")
			get_viewport().set_input_as_handled()

		# Ctrl+Z / Ctrl+Shift+Z 撤销/重做（避免与输入框的文本撤销冲突）
		if event.ctrl_pressed and not command_input.has_focus():
			if not event.shift_pressed and event.keycode == KEY_Z:
				execute_command("undo")
				get_viewport().set_input_as_handled()
			elif event.shift_pressed and event.keycode == KEY_Z:
				execute_command("redo")
				get_viewport().set_input_as_handled()

		# Escape 关闭面板
		if event.keycode == KEY_ESCAPE:
			DebugFlags.set_show_console(false)
			get_viewport().set_input_as_handled()

		# Ctrl+L 清空输出
		if event.ctrl_pressed and event.keycode == KEY_L:
			clear_output()
			get_viewport().set_input_as_handled()

func _navigate_history(direction: int) -> void:
	if _input_history.is_empty():
		return

	_history_index = clamp(_history_index + direction, 0, _input_history.size())

	if _history_index < _input_history.size():
		command_input.text = _input_history[_history_index]
		command_input.caret_column = command_input.text.length()
	else:
		command_input.clear()

func _autocomplete() -> void:
	var text := command_input.text
	if text.is_empty():
		return

	var parts := text.split(" ")
	if parts.is_empty():
		return

	var cmd_name: String = str(parts[0])

	# 1) 命令名补全（支持公共前缀扩展）
	if parts.size() == 1:
		var suggestions := _command_registry.get_suggestions(cmd_name)
		if suggestions.is_empty():
			return
		if suggestions.size() == 1:
			command_input.text = suggestions[0] + " "
			command_input.caret_column = command_input.text.length()
			return

		var prefix := _common_prefix(suggestions)
		if prefix.length() > cmd_name.length():
			command_input.text = prefix
			command_input.caret_column = command_input.text.length()
			return

		print_output("建议: %s" % ", ".join(suggestions), "system")
		return

	# 2) 参数提示（按 Tab 输出 usage/arg_hints）
	if not _command_registry.has_command(cmd_name):
		return
	var def = _command_registry.get_command(cmd_name)
	if def == null:
		return

	var lines: Array[String] = []
	var usage: String = str(def.usage)
	if not usage.is_empty():
		lines.append("用法: %s" % usage)
	var hints: Array[String] = []
	for h in def.arg_hints:
		hints.append(str(h))
	if not hints.is_empty():
		lines.append("参数: %s" % " ".join(hints))
	if lines.is_empty():
		return

	print_output("\n".join(lines), "system")

static func _common_prefix(list: Array[String]) -> String:
	if list.is_empty():
		return ""
	var prefix: String = list[0]
	for s in list:
		var t: String = str(s)
		while not prefix.is_empty() and not t.begins_with(prefix):
			prefix = prefix.substr(0, prefix.length() - 1)
		if prefix.is_empty():
			break
	return prefix
