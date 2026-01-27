# 板块定义
# 定义一个 5x5 的地图板块，包含道路、建筑、饮品源等
class_name TileDef
extends RefCounted

const MapUtilsClass = preload("res://core/map/map_utils.gd")
const TileDefParserClass = preload("res://core/map/tile_def_parser.gd")

# 板块标准大小
const TILE_SIZE := MapUtilsClass.TILE_SIZE

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
	var fields_read := TileDefParserClass.parse_fields_from_dict(data)
	if not fields_read.ok:
		return fields_read
	var f: Dictionary = fields_read.value

	var tile := TileDef.new()
	tile.id = str(f.get("id", ""))
	tile.display_name = str(f.get("display_name", ""))
	tile.allowed_rotations = f.get("allowed_rotations", [])
	tile.road_segments = f.get("road_segments", [])
	tile.blocked_cells = f.get("blocked_cells", [])
	tile.drink_sources = f.get("drink_sources", [])
	tile.printed_structures = f.get("printed_structures", [])

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

func ensure_road_grid() -> void:
	_ensure_road_grid()

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
