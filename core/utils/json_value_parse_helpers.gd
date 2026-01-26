# JSON 值解析辅助（Result 风格）
# 用途：集中实现“JSON 数值允许用 float 表示，但必须是整值”的重复校验逻辑，供存档/回放/命令解析等复用。
class_name JsonValueParseHelpers
extends RefCounted

static func parse_int_value(value, path: String) -> Result:
	if value is int:
		return Result.success(int(value))
	if value is float:
		var f: float = float(value)
		if f != floor(f):
			return Result.failure("%s 必须为整数（不允许小数），实际: %s" % [path, str(value)])
		return Result.success(int(f))
	return Result.failure("%s 类型错误（期望整数），实际: %s" % [path, typeof(value)])

static func parse_non_negative_int_value(value, path: String) -> Result:
	var r := parse_int_value(value, path)
	if not r.ok:
		return r
	var n: int = int(r.value)
	if n < 0:
		return Result.failure("%s 不能为负数: %d" % [path, n])
	return r
