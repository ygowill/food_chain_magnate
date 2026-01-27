# Autoload 单例访问（可选依赖）
# 用途：core/ 代码避免直接引用 Autoload 全局变量（例如 GameLog/DebugFlags/EventBus），
# 改为运行时从 /root/<name> 取节点，从而降低“硬依赖”并便于复用。
class_name AutoloadAccess
extends RefCounted

static func get_autoload(name: String):
	if name.is_empty():
		return null

	var loop = Engine.get_main_loop()
	if not (loop is SceneTree):
		return null
	var tree: SceneTree = loop

	var root = tree.root
	if root == null:
		return null

	return root.get_node_or_null(name)

static func log_debug(category: String, message: String) -> void:
	var logger = get_autoload("GameLog")
	if logger != null and logger.has_method("debug"):
		logger.debug(category, message)
		return
	print("[DEBUG][%s] %s" % [category, message])

static func log_info(category: String, message: String) -> void:
	var logger = get_autoload("GameLog")
	if logger != null and logger.has_method("info"):
		logger.info(category, message)
		return
	print("[INFO][%s] %s" % [category, message])

static func log_warn(category: String, message: String) -> void:
	var logger = get_autoload("GameLog")
	if logger != null and logger.has_method("warn"):
		logger.warn(category, message)
		return
	push_warning("[WARN][%s] %s" % [category, message])

static func log_error(category: String, message: String) -> void:
	var logger = get_autoload("GameLog")
	if logger != null and logger.has_method("error"):
		logger.error(category, message)
		return
	push_error("[ERROR][%s] %s" % [category, message])

static func _read_bool_property(obj, property_name: String, default_value: bool) -> bool:
	if obj == null:
		return default_value
	var v = obj.get(property_name)
	if v is bool:
		return bool(v)
	return default_value

static func is_verbose_logging() -> bool:
	return _read_bool_property(get_autoload("DebugFlags"), "verbose_logging", false)

static func validate_invariants_enabled() -> bool:
	return _read_bool_property(get_autoload("DebugFlags"), "validate_invariants", true)

static func force_execute_commands_enabled() -> bool:
	return _read_bool_property(get_autoload("DebugFlags"), "force_execute_commands", false)

static func is_debug_mode() -> bool:
	var flags = get_autoload("DebugFlags")
	if flags != null and flags.has_method("is_debug_mode"):
		return bool(flags.is_debug_mode())
	if OS.has_feature("release"):
		return false
	return OS.has_feature("debug")
