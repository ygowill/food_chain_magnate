# 日志系统
# 提供统一的日志输出，支持级别过滤和历史记录
extends Node

enum Level { DEBUG, INFO, WARN, ERROR }

# 公开级别常量（便于通过 Autoload 单例 `GameLog` 访问）
const LEVEL_DEBUG: Level = Level.DEBUG
const LEVEL_INFO: Level = Level.INFO
const LEVEL_WARN: Level = Level.WARN
const LEVEL_ERROR: Level = Level.ERROR

# 配置
var min_level: Level = Level.INFO
var log_to_file: bool = false
var log_file_path: String = "user://game.log"

# 历史记录
var log_history: Array[Dictionary] = []
const MAX_HISTORY := 1000

# 级别名称映射
const LEVEL_NAMES := {
	Level.DEBUG: "DEBUG",
	Level.INFO: "INFO",
	Level.WARN: "WARN",
	Level.ERROR: "ERROR"
}

# 级别颜色（用于控制台输出）
const LEVEL_COLORS := {
	Level.DEBUG: "gray",
	Level.INFO: "white",
	Level.WARN: "yellow",
	Level.ERROR: "red"
}

func _ready() -> void:
	print("[Logger] 日志系统初始化完成")

# 核心日志方法
func _log(level: Level, category: String, message: String) -> void:
	if level < min_level:
		return

	var timestamp := Time.get_datetime_string_from_system()
	var entry := {
		"timestamp": timestamp,
		"unix_time": Time.get_unix_time_from_system(),
		"level": level,
		"level_name": LEVEL_NAMES[level],
		"category": category,
		"message": message
	}

	# 添加到历史
	log_history.append(entry)
	if log_history.size() > MAX_HISTORY:
		log_history.pop_front()

	# 格式化输出
	var formatted := "[%s][%s][%s] %s" % [timestamp, LEVEL_NAMES[level], category, message]

	# 输出到控制台
	match level:
		Level.ERROR:
			push_error(formatted)
		Level.WARN:
			push_warning(formatted)
		_:
			print(formatted)

	# 可选：输出到文件
	if log_to_file:
		_write_to_file(formatted)

# 便捷方法
func debug(category: String, message: String) -> void:
	_log(Level.DEBUG, category, message)

func info(category: String, message: String) -> void:
	_log(Level.INFO, category, message)

func warn(category: String, message: String) -> void:
	_log(Level.WARN, category, message)

func error(category: String, message: String) -> void:
	_log(Level.ERROR, category, message)

# 获取历史记录
func get_history(level_filter: Level = Level.DEBUG, limit: int = 100) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in log_history:
		if entry.level >= level_filter:
			result.append(entry)

	if result.size() > limit:
		return result.slice(-limit)
	return result

# 清空历史
func clear_history() -> void:
	log_history.clear()

# 设置日志级别
func set_min_level(level: Level) -> void:
	min_level = level
	info("Logger", "日志级别设置为: %s" % LEVEL_NAMES[level])

# 写入文件
func _write_to_file(message: String) -> void:
	var file: FileAccess = null
	if FileAccess.file_exists(log_file_path):
		file = FileAccess.open(log_file_path, FileAccess.READ_WRITE)
	else:
		file = FileAccess.open(log_file_path, FileAccess.WRITE)

	if file == null:
		return

	file.seek_end()
	file.store_line(message)
	file.close()

# 导出日志
func export_log() -> String:
	var output := ""
	for entry in log_history:
		output += "[%s][%s][%s] %s\n" % [
			entry.timestamp,
			entry.level_name,
			entry.category,
			entry.message
		]
	return output
