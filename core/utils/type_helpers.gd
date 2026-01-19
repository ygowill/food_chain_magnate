# 通用类型读取辅助（Result 风格）
# 用途：集中实现“读取值 + 类型校验 + 统一错误消息”的样板，减少大量 *_val 中间变量。
class_name TypeHelpers
extends RefCounted

static func require_dict(value, path: String) -> Result:
	if not (value is Dictionary):
		return Result.failure("%s 类型错误（期望 Dictionary）" % path)
	return Result.success(value)

static func require_array(value, path: String) -> Result:
	if not (value is Array):
		return Result.failure("%s 类型错误（期望 Array）" % path)
	return Result.success(value)

static func require_bool(value, path: String) -> Result:
	if not (value is bool):
		return Result.failure("%s 类型错误（期望 bool）" % path)
	return Result.success(bool(value))

static func require_int(value, path: String) -> Result:
	if not (value is int):
		return Result.failure("%s 类型错误（期望 int）" % path)
	return Result.success(int(value))

static func require_string(value, path: String, require_non_empty: bool = false) -> Result:
	if not (value is String):
		return Result.failure("%s 类型错误（期望 String）" % path)
	var s: String = str(value)
	if require_non_empty and s.is_empty():
		return Result.failure("%s 不能为空字符串" % path)
	return Result.success(s)

