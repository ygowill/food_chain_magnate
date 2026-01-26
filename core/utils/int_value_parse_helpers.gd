# 整数值解析辅助（Result 风格）
# 用途：rules/milestone effects 等从 JSON/Dictionary 读取整数值时复用（允许 float 表示整值；禁止小数）。
class_name IntValueParseHelpers
extends RefCounted

static func parse_int_value(value, path: String) -> Result:
	if value is int:
		return Result.success(int(value))
	if value is float:
		var f: float = float(value)
		if f == int(f):
			return Result.success(int(f))
		return Result.failure("%s 必须为整数（不允许小数）" % path)
	return Result.failure("%s 必须为整数" % path)

static func parse_non_negative_int_value(value, path: String) -> Result:
	var r := parse_int_value(value, path)
	if not r.ok:
		return r
	if int(r.value) < 0:
		return Result.failure("%s 必须 >= 0，实际: %d" % [path, int(r.value)])
	return r

