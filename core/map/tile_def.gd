# 板块定义
# 定义一个 5x5 的地图板块，包含道路、建筑、饮品源等
class_name TileDef
extends RefCounted

const MapUtilsClass = preload("res://core/map/map_utils.gd")

# 板块标准大小
const TILE_SIZE := MapUtilsClass.TILE_SIZE
const _VALID_ROTATIONS = MapUtilsClass.VALID_ROTATIONS
const _VALID_DIRS = MapUtilsClass.DIRECTIONS

# === 基础信息 ===
var id: String = ""
var display_name: String = ""

# === 道路定义 ===
# 5x5 二维数组，每个格子包含道路段数组
# 每个道路段: { "dirs": ["N", "S"], "bridge": false }
# dirs: 该段连接的方向 (N/E/S/W)
# bridge: 是否为桥梁（桥梁不与同格其他段连接）
var road_segments: Array = []  # [y][x] -> Array[Dictionary]

# === 印刷建筑 ===
# 预置的建筑物（房屋、餐厅等）
# { "piece_id": "house", "anchor": Vector2i, "rotation": 0,
#   "house_id": "7", "house_number": 7 }
var printed_structures: Array[Dictionary] = []

# === 饮品源 ===
# { "pos": Vector2i, "type": "beer" }
var drink_sources: Array[Dictionary] = []

# === 禁止放置的格子 ===
var blocked_cells: Array[Vector2i] = []

# === 允许的旋转角度 ===
var allowed_rotations: Array[int] = Array(MapUtilsClass.VALID_ROTATIONS, TYPE_INT, "", null)

# === 工厂方法 ===

static func create_empty(tile_id: String) -> TileDef:
	var tile := TileDef.new()
	tile.id = tile_id
	tile.display_name = tile_id

	# 初始化空的道路网格
	tile.road_segments = []
	for y in TILE_SIZE:
		var row := []
		for x in TILE_SIZE:
			row.append([])
		tile.road_segments.append(row)

	return tile

# === 序列化 ===

func to_dict() -> Dictionary:
	var blocked_cells_arr := []
	for cell in blocked_cells:
		blocked_cells_arr.append([cell.x, cell.y])

	var drink_sources_arr := []
	for source in drink_sources:
		drink_sources_arr.append({
			"pos": [source.pos.x, source.pos.y],
			"type": source.type
		})

	var printed_arr := []
	for struct in printed_structures:
		var struct_dict := struct.duplicate()
		if struct.has("anchor") and struct.anchor is Vector2i:
			struct_dict["anchor"] = [struct.anchor.x, struct.anchor.y]
		printed_arr.append(struct_dict)

	return {
		"id": id,
		"display_name": display_name,
		"road_segments": road_segments,
		"printed_structures": printed_arr,
		"drink_sources": drink_sources_arr,
		"blocked_cells": blocked_cells_arr,
		"allowed_rotations": allowed_rotations
	}

static func from_dict(data: Dictionary) -> Result:
	if not (data is Dictionary):
		return Result.failure("TileDef.from_dict: data 类型错误（期望 Dictionary）")

	var required_keys := [
		"id",
		"display_name",
		"road_segments",
		"printed_structures",
		"drink_sources",
		"blocked_cells",
		"allowed_rotations",
	]
	for key in required_keys:
		if not data.has(key):
			return Result.failure("TileDef 缺少字段: %s" % key)

	var id_val = data.get("id", null)
	if not (id_val is String) or str(id_val).is_empty():
		return Result.failure("TileDef.id 类型错误或为空（期望非空 String）")
	var display_name_val = data.get("display_name", null)
	if not (display_name_val is String) or str(display_name_val).is_empty():
		return Result.failure("TileDef.display_name 类型错误或为空（期望非空 String）")

	var rotations_val = data.get("allowed_rotations", null)
	var rotations_read := _parse_rotation_array(rotations_val, "TileDef.allowed_rotations")
	if not rotations_read.ok:
		return rotations_read

	var road_segments_val = data.get("road_segments", null)
	var road_segments_read := _parse_road_grid(road_segments_val, "TileDef.road_segments")
	if not road_segments_read.ok:
		return road_segments_read

	var blocked_cells_val = data.get("blocked_cells", null)
	var blocked_read := _parse_vec2i_array(blocked_cells_val, "TileDef.blocked_cells")
	if not blocked_read.ok:
		return blocked_read

	var drink_sources_val = data.get("drink_sources", null)
	var drink_sources_read := _parse_drink_sources(drink_sources_val, "TileDef.drink_sources")
	if not drink_sources_read.ok:
		return drink_sources_read

	var printed_val = data.get("printed_structures", null)
	var printed_read := _parse_printed_structures(printed_val, "TileDef.printed_structures")
	if not printed_read.ok:
		return printed_read

	var tile := TileDef.new()
	tile.id = str(id_val)
	tile.display_name = str(display_name_val)
	tile.allowed_rotations = rotations_read.value
	tile.road_segments = road_segments_read.value
	tile.blocked_cells = blocked_read.value
	tile.drink_sources = drink_sources_read.value
	tile.printed_structures = printed_read.value

	return Result.success(tile)

static func from_json(json_string: String) -> Result:
	var data = JSON.parse_string(json_string)
	if data == null or not (data is Dictionary):
		return Result.failure("TileDef JSON 解析失败")
	return from_dict(data)

static func load_from_file(path: String) -> Result:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return Result.failure("无法打开 TileDef: %s" % path)
	var json := file.get_as_text()
	file.close()
	return from_json(json)

# === 内部方法 ===

func _ensure_road_grid() -> void:
	# 确保道路网格是 5x5
	while road_segments.size() < TILE_SIZE:
		road_segments.append([])

	for y in TILE_SIZE:
		while road_segments[y].size() < TILE_SIZE:
			road_segments[y].append([])

# === 查询方法 ===

# 获取指定位置的道路段
func get_road_segments_at(local_pos: Vector2i) -> Array:
	if local_pos.x < 0 or local_pos.x >= TILE_SIZE:
		return []
	if local_pos.y < 0 or local_pos.y >= TILE_SIZE:
		return []
	return road_segments[local_pos.y][local_pos.x]

# 检查指定位置是否有道路
func has_road_at(local_pos: Vector2i) -> bool:
	return not get_road_segments_at(local_pos).is_empty()

# 检查指定位置是否被阻塞
func is_blocked_at(local_pos: Vector2i) -> bool:
	return blocked_cells.has(local_pos)

# 获取所有有道路的格子
func get_road_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in TILE_SIZE:
		for x in TILE_SIZE:
			if not road_segments[y][x].is_empty():
				cells.append(Vector2i(x, y))
	return cells

# === 编辑方法 (用于板块编辑器) ===

# 添加道路段
func add_road_segment(local_pos: Vector2i, dirs: Array, is_bridge: bool = false) -> void:
	if local_pos.x < 0 or local_pos.x >= TILE_SIZE:
		return
	if local_pos.y < 0 or local_pos.y >= TILE_SIZE:
		return

	road_segments[local_pos.y][local_pos.x].append({
		"dirs": dirs,
		"bridge": is_bridge
	})

# === 严格解析辅助 ===

static func _parse_int(value, path: String) -> Result:
	if value is int:
		return Result.success(int(value))
	if value is float:
		var f: float = float(value)
		if f != floor(f):
			return Result.failure("%s 必须为整数，实际: %s" % [path, str(value)])
		return Result.success(int(f))
	return Result.failure("%s 类型错误（期望整数）" % path)

static func _parse_vec2i(value, path: String) -> Result:
	if not (value is Array) or value.size() != 2:
		return Result.failure("%s 类型错误（期望 [x,y]）" % path)
	var x_read := _parse_int(value[0], "%s[0]" % path)
	if not x_read.ok:
		return x_read
	var y_read := _parse_int(value[1], "%s[1]" % path)
	if not y_read.ok:
		return y_read
	return Result.success(Vector2i(int(x_read.value), int(y_read.value)))

static func _parse_vec2i_array(value, path: String) -> Result:
	if not (value is Array):
		return Result.failure("%s 类型错误（期望 Array[[x,y],...]）" % path)
	var out: Array[Vector2i] = []
	for i in range(value.size()):
		var v_read := _parse_vec2i(value[i], "%s[%d]" % [path, i])
		if not v_read.ok:
			return v_read
		out.append(v_read.value)
	return Result.success(out)

static func _parse_rotation_array(value, path: String) -> Result:
	if not (value is Array):
		return Result.failure("%s 类型错误（期望 Array[int]）" % path)
	var out: Array[int] = []
	for i in range(value.size()):
		var v_read := _parse_int(value[i], "%s[%d]" % [path, i])
		if not v_read.ok:
			return v_read
		var rot: int = int(v_read.value)
		if not _VALID_ROTATIONS.has(rot):
			return Result.failure("%s[%d] 旋转角非法: %d" % [path, i, rot])
		out.append(rot)
	if out.is_empty():
		return Result.failure("%s 不能为空" % path)
	return Result.success(out)

static func _parse_road_grid(value, path: String) -> Result:
	if not (value is Array) or value.size() != TILE_SIZE:
		return Result.failure("%s 类型错误（期望 %dx%d 数组）" % [path, TILE_SIZE, TILE_SIZE])
	for y in range(TILE_SIZE):
		if not (value[y] is Array) or value[y].size() != TILE_SIZE:
			return Result.failure("%s[%d] 类型错误（期望长度=%d 的 Array）" % [path, y, TILE_SIZE])
		for x in range(TILE_SIZE):
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
					if not (d is String) or not _VALID_DIRS.has(str(d)):
						return Result.failure("%s[%d][%d][%d].dirs 含非法方向: %s" % [path, y, x, s, str(d)])
	return Result.success(value)

static func _parse_drink_sources(value, path: String) -> Result:
	if not (value is Array):
		return Result.failure("%s 类型错误（期望 Array[Dictionary]）" % path)
	var out: Array[Dictionary] = []
	for i in range(value.size()):
		var item = value[i]
		if not (item is Dictionary):
			return Result.failure("%s[%d] 类型错误（期望 Dictionary）" % [path, i])
		if not item.has("pos") or not item.has("type"):
			return Result.failure("%s[%d] 缺少字段 pos/type" % [path, i])
		var pos_read := _parse_vec2i(item.get("pos", null), "%s[%d].pos" % [path, i])
		if not pos_read.ok:
			return pos_read
		var t = item.get("type", null)
		if not (t is String) or str(t).is_empty():
			return Result.failure("%s[%d].type 类型错误或为空（期望非空 String）" % [path, i])
		out.append({"pos": pos_read.value, "type": str(t)})
	return Result.success(out)

static func _parse_printed_structures(value, path: String) -> Result:
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
		if not (pid is String) or str(pid).is_empty():
			return Result.failure("%s[%d].piece_id 类型错误或为空（期望非空 String）" % [path, i])
		var anchor_read := _parse_vec2i(item.get("anchor", null), "%s[%d].anchor" % [path, i])
		if not anchor_read.ok:
			return anchor_read
		var rot_read := _parse_int(item.get("rotation", null), "%s[%d].rotation" % [path, i])
		if not rot_read.ok:
			return rot_read
		var rot: int = int(rot_read.value)
		if not _VALID_ROTATIONS.has(rot):
			return Result.failure("%s[%d].rotation 旋转角非法: %d" % [path, i, rot])
		var struct_dict: Dictionary = item.duplicate(true)
		struct_dict["piece_id"] = str(pid)
		struct_dict["anchor"] = anchor_read.value
		struct_dict["rotation"] = rot
		out.append(struct_dict)
	return Result.success(out)

# 清除指定位置的所有道路段
func clear_road_segments(local_pos: Vector2i) -> void:
	if local_pos.x < 0 or local_pos.x >= TILE_SIZE:
		return
	if local_pos.y < 0 or local_pos.y >= TILE_SIZE:
		return
	road_segments[local_pos.y][local_pos.x] = []

# 添加印刷建筑
func add_printed_structure(piece_id: String, anchor: Vector2i, rotation: int = 0,
						   house_id: String = "", house_number = null) -> void:
	var struct := {
		"piece_id": piece_id,
		"anchor": anchor,
		"rotation": rotation
	}
	if not house_id.is_empty():
		struct["house_id"] = house_id
		struct["house_number"] = house_number if house_number != null else 0
	printed_structures.append(struct)

# 添加饮品源
func add_drink_source(local_pos: Vector2i, drink_type: String) -> void:
	drink_sources.append({
		"pos": local_pos,
		"type": drink_type
	})

# 设置格子为阻塞
func set_blocked(local_pos: Vector2i, blocked: bool) -> void:
	var idx := blocked_cells.find(local_pos)
	if blocked and idx == -1:
		blocked_cells.append(local_pos)
	elif not blocked and idx != -1:
		blocked_cells.remove_at(idx)

# === 验证 ===

func validate() -> Result:
	# 检查 ID
	if id.is_empty():
		return Result.failure("板块缺少 ID")

	# 检查道路网格维度
	if road_segments.size() != TILE_SIZE:
		return Result.failure("道路网格行数错误: %d (期望 %d)" % [road_segments.size(), TILE_SIZE])

	for y in TILE_SIZE:
		if road_segments[y].size() != TILE_SIZE:
			return Result.failure("道路网格第 %d 行列数错误: %d (期望 %d)" % [
				y, road_segments[y].size(), TILE_SIZE])

	# 检查道路段方向有效性
	for y in TILE_SIZE:
		for x in TILE_SIZE:
			for segment in road_segments[y][x]:
				var dirs: Array = segment.get("dirs", [])
				for dir in dirs:
					if dir not in ["N", "E", "S", "W"]:
						return Result.failure("无效的道路方向: %s (位置 %d, %d)" % [dir, x, y])

	# 检查印刷建筑锚点
	for struct in printed_structures:
		var anchor = struct.get("anchor")
		if anchor == null:
			return Result.failure("印刷建筑缺少锚点")
		if anchor is Vector2i:
			if anchor.x < 0 or anchor.x >= TILE_SIZE or anchor.y < 0 or anchor.y >= TILE_SIZE:
				return Result.failure("印刷建筑锚点超出范围: %s" % str(anchor))

	return Result.success()

# === 调试 ===

func dump() -> String:
	var output := "=== TileDef: %s ===\n" % id

	# 绘制道路网格
	output += "Roads:\n"
	for y in TILE_SIZE:
		var row_str := "  "
		for x in TILE_SIZE:
			var segments: Array = road_segments[y][x]
			if segments.is_empty():
				row_str += ". "
			else:
				# 简单显示第一个段的方向数
				row_str += "%d " % segments[0].get("dirs", []).size()
		output += row_str + "\n"

	output += "Printed structures: %d\n" % printed_structures.size()
	output += "Drink sources: %d\n" % drink_sources.size()
	output += "Blocked cells: %d\n" % blocked_cells.size()

	return output
