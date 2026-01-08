# 调试命令注册表
# 管理调试命令的注册、查找和执行
class_name DebugCommandRegistry
extends RefCounted

# 命令定义
class CommandDef:
	var name: String
	var description: String
	var usage: String
	var handler: Callable
	var arg_hints: Array[String]

	func _init(p_name: String, p_handler: Callable, p_description: String, p_usage: String = "", p_arg_hints: Array[String] = []) -> void:
		name = p_name
		handler = p_handler
		description = p_description
		usage = p_usage
		arg_hints = p_arg_hints

var _commands: Dictionary = {}  # name -> CommandDef
var _game_engine: GameEngine = null

func _init() -> void:
	pass

func set_game_engine(engine: GameEngine) -> void:
	_game_engine = engine

func get_game_engine() -> GameEngine:
	return _game_engine

# 注册命令
func register(name: String, handler: Callable, description: String, usage: String = "", arg_hints: Array[String] = []) -> void:
	_commands[name] = CommandDef.new(name, handler, description, usage, arg_hints)

# 注销命令
func unregister(name: String) -> void:
	_commands.erase(name)

# 检查命令是否存在
func has_command(name: String) -> bool:
	return _commands.has(name)

# 获取命令定义
func get_command(name: String) -> CommandDef:
	return _commands.get(name, null)

# 获取所有命令名
func get_command_names() -> Array[String]:
	var names: Array[String] = []
	for key in _commands.keys():
		names.append(str(key))
	names.sort()
	return names

# 执行命令行
func execute(command_line: String) -> Result:
	GameLog.debug("DebugRegistry", "执行命令: %s" % command_line)
	var parsed := parse_command_line(command_line)
	if parsed.is_empty():
		GameLog.warn("DebugRegistry", "空命令")
		return Result.failure("空命令")

	var cmd_name: String = parsed[0]
	var args: Array = parsed.slice(1)

	if not _commands.has(cmd_name):
		GameLog.warn("DebugRegistry", "未知命令: %s" % cmd_name)
		return Result.failure("未知命令: %s" % cmd_name)

	var cmd_def: CommandDef = _commands[cmd_name]
	GameLog.debug("DebugRegistry", "调用处理器: %s, 参数: %s" % [cmd_name, str(args)])

	# 调用处理器
	var result = cmd_def.handler.call(args)
	if result is Result:
		if result.ok:
			GameLog.debug("DebugRegistry", "命令成功: %s" % cmd_name)
		else:
			GameLog.warn("DebugRegistry", "命令失败: %s - %s" % [cmd_name, result.error])
		return result
	elif result is String:
		GameLog.debug("DebugRegistry", "命令返回字符串: %s" % cmd_name)
		return Result.success(result)
	else:
		GameLog.debug("DebugRegistry", "命令返回其他: %s" % cmd_name)
		return Result.success(str(result) if result != null else "OK")

# 解析命令行
func parse_command_line(command_line: String) -> Array:
	var result: Array = []
	var current := ""
	var in_quotes := false
	var quote_char := ""

	for i in range(command_line.length()):
		var c := command_line[i]

		if in_quotes:
			if c == quote_char:
				in_quotes = false
				if not current.is_empty():
					result.append(current)
					current = ""
			else:
				current += c
		elif c == '"' or c == "'":
			in_quotes = true
			quote_char = c
		elif c == ' ' or c == '\t':
			if not current.is_empty():
				result.append(current)
				current = ""
		else:
			current += c

	if not current.is_empty():
		result.append(current)

	return result

# 获取命令建议（自动补全）
func get_suggestions(partial: String) -> Array[String]:
	var suggestions: Array[String] = []
	var lower_partial := partial.to_lower()

	for name in _commands.keys():
		var name_str := str(name)
		if name_str.to_lower().begins_with(lower_partial):
			suggestions.append(name_str)

	suggestions.sort()
	return suggestions

# 获取帮助信息
func get_help(command_name: String = "") -> String:
	if command_name.is_empty():
		# 显示所有命令
		var lines: Array[String] = ["可用命令:"]
		var names := get_command_names()
		for name in names:
			var cmd: CommandDef = _commands[name]
			lines.append("  %s - %s" % [name, cmd.description])
		return "\n".join(lines)
	else:
		# 显示特定命令的帮助
		if not _commands.has(command_name):
			return "未知命令: %s" % command_name

		var cmd: CommandDef = _commands[command_name]
		var lines: Array[String] = [
			"命令: %s" % cmd.name,
			"描述: %s" % cmd.description
		]
		if not cmd.usage.is_empty():
			lines.append("用法: %s" % cmd.usage)
		if not cmd.arg_hints.is_empty():
			lines.append("参数: %s" % ", ".join(cmd.arg_hints))
		return "\n".join(lines)
