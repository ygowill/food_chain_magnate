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
		# float 的失败仅可能是“非整值小数”，保留更具体的错误信息；否则收敛到“非负整数”语义。
		if value is float:
			return r
		return Result.failure("%s 必须为非负整数" % path)
	if int(r.value) < 0:
		return Result.failure("%s 必须 >= 0，实际: %d" % [path, int(r.value)])
	return r

static func parse_positive_int_value(value, path: String) -> Result:
	var r := parse_int_value(value, path)
	if not r.ok:
		# float 的失败仅可能是“非整值小数”，保留更具体的错误信息；否则收敛到“正整数”语义。
		if value is float:
			return r
		return Result.failure("%s 必须为正整数" % path)
	var n: int = int(r.value)
	if n <= 0:
		return Result.failure("%s 必须 > 0，实际: %d" % [path, n])
	return r
