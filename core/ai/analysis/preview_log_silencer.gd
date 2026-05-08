class_name PreviewLogSilencer
extends RefCounted

const AutoloadAccessClass = preload("res://core/utils/autoload_access.gd")

const ERROR_LOG_LEVEL := 3

static var _stack: Array = []

static func silence(options: Dictionary = {}) -> void:
	if not bool(options.get("suppress_logs", true)):
		_stack.append({"active": false})
		return
	var logger = AutoloadAccessClass.get_autoload("GameLog")
	if logger == null:
		_stack.append({"active": false})
		return
	var previous = logger.get("min_level")
	logger.set("min_level", ERROR_LOG_LEVEL)
	_stack.append({
		"active": true,
		"logger": logger,
		"previous": previous,
	})

static func restore() -> void:
	if _stack.is_empty():
		return
	var token_val = _stack.pop_back()
	if not (token_val is Dictionary):
		return
	var token: Dictionary = token_val
	if not bool(token.get("active", false)):
		return
	var logger = token.get("logger", null)
	if logger == null:
		return
	logger.set("min_level", token.get("previous", 1))
