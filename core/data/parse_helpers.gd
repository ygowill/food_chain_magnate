# 通用 data JSON 严格解析辅助
# 用途：集中实现 core/data/* 中重复的 _parse_* 逻辑。
class_name DataParseHelpers
extends RefCounted

static func parse_string(value, path: String, allow_empty: bool) -> Result:
	if not (value is String):
		return Result.failure("%s 类型错误（期望 String）" % path)
	# 在数据加载阶段做规范化：去掉首尾空白，避免 UI/规则层反复 strip_edges().
	var s: String = str(value).strip_edges()
	if not allow_empty and s.is_empty():
		return Result.failure("%s 不能为空" % path)
	return Result.success(s)

static func parse_bool(value, path: String) -> Result:
	if not (value is bool):
		return Result.failure("%s 类型错误（期望 bool）" % path)
	return Result.success(bool(value))

static func parse_int(value, path: String) -> Result:
	if value is int:
		return Result.success(int(value))
	if value is float:
		var f: float = float(value)
		if f != floor(f):
			return Result.failure("%s 必须为整数，实际: %s" % [path, str(value)])
		return Result.success(int(f))
	return Result.failure("%s 类型错误（期望整数）" % path)

static func parse_non_negative_int(value, path: String) -> Result:
	var r := parse_int(value, path)
	if not r.ok:
		return r
	if int(r.value) < 0:
		return Result.failure("%s 必须 >= 0，实际: %d" % [path, int(r.value)])
	return r

static func parse_string_array(value, path: String, allow_empty: bool) -> Result:
	if not (value is Array):
		return Result.failure("%s 类型错误（期望 Array[String]）" % path)
	var out: Array[String] = []
	for i in range(value.size()):
		var item = value[i]
		var s_read := parse_string(item, "%s[%d]" % [path, i], false)
		if not s_read.ok:
			return s_read
		out.append(s_read.value)
	if not allow_empty and out.is_empty():
		return Result.failure("%s 不能为空" % path)
	return Result.success(out)

static func parse_vec2i(value, path: String) -> Result:
	if not (value is Array):
		return Result.failure("%s 类型错误（期望 [x,y] Array）" % path)
	var arr: Array = value
	if arr.size() != 2:
		return Result.failure("%s 长度错误（期望 2），实际: %d" % [path, arr.size()])
	var x_read := parse_int(arr[0], "%s[0]" % path)
	if not x_read.ok:
		return x_read
	var y_read := parse_int(arr[1], "%s[1]" % path)
	if not y_read.ok:
		return y_read
	return Result.success(Vector2i(int(x_read.value), int(y_read.value)))

