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

static func parse_road_grid(value, path: String, tile_size: int, valid_dirs: Array) -> Result:
	if not (value is Array) or value.size() != tile_size:
		return Result.failure("%s 类型错误（期望 %dx%d 数组）" % [path, tile_size, tile_size])
	for y in range(tile_size):
		if not (value[y] is Array) or value[y].size() != tile_size:
			return Result.failure("%s[%d] 类型错误（期望长度=%d 的 Array）" % [path, y, tile_size])
		for x in range(tile_size):
			var cell = value[y][x]
			if not (cell is Array):
				return Result.failure("%s[%d][%d] 类型错误（期望 Array）" % [path, y, x])
			for s in range(cell.size()):
				var seg = cell[s]
				if not (seg is Dictionary):
					return Result.failure("%s[%d][%d][%d] 类型错误（期望 Dictionary）" % [path, y, x, s])
				if not seg.has("dirs") or not (seg.get("dirs", null) is Array):
					return Result.failure("%s[%d][%d][%d].dirs 缺失或类型错误（期望 Array[String]）" % [path, y, x, s])
				if not seg.has("bridge") or not (seg.get("bridge", null) is bool):
					return Result.failure("%s[%d][%d][%d].bridge 缺失或类型错误（期望 bool）" % [path, y, x, s])
				var dirs: Array = seg.get("dirs", [])
				for d in dirs:
					if not (d is String) or not valid_dirs.has(str(d)):
						return Result.failure("%s[%d][%d][%d].dirs 含非法方向: %s" % [path, y, x, s, str(d)])
	return Result.success(value)

static func parse_drink_sources(value, path: String) -> Result:
	if not (value is Array):
		return Result.failure("%s 类型错误（期望 Array[Dictionary]）" % path)
	var out: Array[Dictionary] = []
	for i in range(value.size()):
		var item = value[i]
		if not (item is Dictionary):
			return Result.failure("%s[%d] 类型错误（期望 Dictionary）" % [path, i])
		if not item.has("pos") or not item.has("type"):
			return Result.failure("%s[%d] 缺少字段 pos/type" % [path, i])
		var pos_read := parse_vec2i(item.get("pos", null), "%s[%d].pos" % [path, i])
		if not pos_read.ok:
			return pos_read
		var t = item.get("type", null)
		if not (t is String) or str(t).strip_edges().is_empty():
			return Result.failure("%s[%d].type 类型错误或为空（期望非空 String）" % [path, i])
		out.append({"pos": pos_read.value, "type": str(t).strip_edges()})
	return Result.success(out)

static func parse_printed_structures(value, path: String, valid_rotations: Array) -> Result:
	if not (value is Array):
		return Result.failure("%s 类型错误（期望 Array[Dictionary]）" % path)
	var out: Array[Dictionary] = []
	for i in range(value.size()):
		var item = value[i]
		if not (item is Dictionary):
			return Result.failure("%s[%d] 类型错误（期望 Dictionary）" % [path, i])
		if not item.has("piece_id") or not item.has("anchor") or not item.has("rotation"):
			return Result.failure("%s[%d] 缺少字段 piece_id/anchor/rotation" % [path, i])
		var pid = item.get("piece_id", null)
		if not (pid is String) or str(pid).strip_edges().is_empty():
			return Result.failure("%s[%d].piece_id 类型错误或为空（期望非空 String）" % [path, i])
		var anchor_read := parse_vec2i(item.get("anchor", null), "%s[%d].anchor" % [path, i])
		if not anchor_read.ok:
			return anchor_read
		var rot_read := parse_int(item.get("rotation", null), "%s[%d].rotation" % [path, i])
		if not rot_read.ok:
			return rot_read
		var rot: int = int(rot_read.value)
		if not valid_rotations.has(rot):
			return Result.failure("%s[%d].rotation 旋转角非法: %d" % [path, i, rot])
		var struct_dict: Dictionary = item.duplicate(true)
		struct_dict["piece_id"] = str(pid).strip_edges()
		struct_dict["anchor"] = anchor_read.value
		struct_dict["rotation"] = rot
		out.append(struct_dict)
	return Result.success(out)
