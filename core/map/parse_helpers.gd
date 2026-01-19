# 地图相关 JSON/Dictionary 严格解析辅助
# 用途：集中实现 MapDef/TileDef/PieceDef/MapOptionDef 等脚本中重复的 _parse_* 逻辑。
class_name MapParseHelpers
extends RefCounted

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
	var n: int = int(r.value)
	if n < 0:
		return Result.failure("%s 不能为负数: %d" % [path, n])
	return Result.success(n)

static func parse_vec2i(value, path: String) -> Result:
	if not (value is Array) or value.size() != 2:
		return Result.failure("%s 类型错误（期望 [x,y]）" % path)
	var x_read := parse_int(value[0], "%s[0]" % path)
	if not x_read.ok:
		return x_read
	var y_read := parse_int(value[1], "%s[1]" % path)
	if not y_read.ok:
		return y_read
	return Result.success(Vector2i(int(x_read.value), int(y_read.value)))

static func parse_string_array(value, path: String, require_non_empty: bool) -> Result:
	if not (value is Array):
		return Result.failure("%s 类型错误（期望 Array[String]）" % path)
	var out: Array[String] = []
	for i in range(value.size()):
		var item = value[i]
		if not (item is String):
			return Result.failure("%s[%d] 类型错误（期望 String）" % [path, i])
		# 在数据加载阶段做规范化：去掉首尾空白，避免 callsite 反复 strip_edges().
		var s := str(item).strip_edges()
		if s.is_empty():
			return Result.failure("%s[%d] 不能为空字符串" % [path, i])
		out.append(s)
	if require_non_empty and out.is_empty():
		return Result.failure("%s 不能为空" % path)
	return Result.success(out)
