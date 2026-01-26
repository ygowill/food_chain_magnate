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

static func parse_vec2i_array(value, path: String) -> Result:
	if not (value is Array):
		return Result.failure("%s 类型错误（期望 Array[[x,y],...]）" % path)
	var out: Array[Vector2i] = []
	for i in range(value.size()):
		var v_read := parse_vec2i(value[i], "%s[%d]" % [path, i])
		if not v_read.ok:
			return v_read
		out.append(v_read.value)
	return Result.success(out)

static func parse_rotation_array(value, path: String, valid_rotations: Array) -> Result:
	if not (value is Array):
		return Result.failure("%s 类型错误（期望 Array[int]）" % path)
	if not (valid_rotations is Array):
		return Result.failure("%s 的旋转校验配置类型错误（期望 Array[int]）" % path)
	var out: Array[int] = []
	for i in range(value.size()):
		var v_read := parse_int(value[i], "%s[%d]" % [path, i])
		if not v_read.ok:
			return v_read
		var rot: int = int(v_read.value)
		if not valid_rotations.has(rot):
			return Result.failure("%s[%d] 旋转角非法: %d" % [path, i, rot])
		out.append(rot)
	if out.is_empty():
		return Result.failure("%s 不能为空" % path)
	return Result.success(out)

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

static func parse_tile_placements(value, path: String, valid_rotations: Array = []) -> Result:
	if not (value is Array):
		return Result.failure("%s 类型错误（期望 Array[Dictionary]）" % path)

	var validate_rotation := not valid_rotations.is_empty()
	var out: Array[Dictionary] = []
	for i in range(value.size()):
		var item = value[i]
		if not (item is Dictionary):
			return Result.failure("%s[%d] 类型错误（期望 Dictionary）" % [path, i])
		var tile: Dictionary = item
		for k in ["tile_id", "board_pos", "rotation"]:
			if not tile.has(k):
				return Result.failure("%s[%d] 缺少字段: %s" % [path, i, k])

		var tile_id_val = tile.get("tile_id", null)
		if not (tile_id_val is String) or str(tile_id_val).strip_edges().is_empty():
			return Result.failure("%s[%d].tile_id 类型错误或为空（期望非空 String）" % [path, i])

		var board_pos_read := parse_vec2i(tile.get("board_pos", null), "%s[%d].board_pos" % [path, i])
		if not board_pos_read.ok:
			return board_pos_read

		var rotation_read := parse_int(tile.get("rotation", null), "%s[%d].rotation" % [path, i])
		if not rotation_read.ok:
			return rotation_read
		var rot: int = int(rotation_read.value)
		if validate_rotation and not valid_rotations.has(rot):
			return Result.failure("%s[%d].rotation 非法: %d" % [path, i, rot])

		out.append({
			"tile_id": str(tile_id_val).strip_edges(),
			"board_pos": board_pos_read.value,
			"rotation": rot,
		})

	return Result.success(out)
