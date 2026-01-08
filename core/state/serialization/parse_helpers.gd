extends RefCounted

static func parse_int(value, path: String) -> Result:
	if value is int:
		return Result.success(int(value))
	if value is float:
		var f: float = float(value)
		if f != floor(f):
			return Result.failure("%s 必须为整数，实际: %s" % [path, str(value)])
		return Result.success(int(f))
	return Result.failure("%s 缺失或类型错误（期望整数）" % path)

static func parse_non_negative_int(value, path: String) -> Result:
	var r := parse_int(value, path)
	if not r.ok:
		return r
	var n: int = int(r.value)
	if n < 0:
		return Result.failure("%s 不能为负数: %d" % [path, n])
	return Result.success(n)

static func parse_int_array(value, path: String) -> Result:
	if not (value is Array):
		return Result.failure("%s 缺失或类型错误（期望 Array[int]）" % path)
	var out: Array[int] = []
	for i in range(value.size()):
		var item_read := parse_int(value[i], "%s[%d]" % [path, i])
		if not item_read.ok:
			return item_read
		out.append(int(item_read.value))
	return Result.success(out)

static func parse_non_negative_int_dict(value, path: String) -> Result:
	if not (value is Dictionary):
		return Result.failure("%s 缺失或类型错误（期望 Dictionary）" % path)
	var out := {}
	for k in value.keys():
		if not (k is String):
			return Result.failure("%s key 类型错误（期望 String）" % path)
		var key := str(k)
		var v_read := parse_non_negative_int(value.get(k, null), "%s.%s" % [path, key])
		if not v_read.ok:
			return v_read
		out[key] = int(v_read.value)
	return Result.success(out)

