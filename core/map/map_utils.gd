# 地图坐标工具
# 提供坐标变换、旋转等通用功能
class_name MapUtils
extends RefCounted

# 标准板块大小 (5x5 格子)
const TILE_SIZE := 5

# 合法旋转角（度）
const VALID_ROTATIONS := [0, 90, 180, 270]

# 方向常量
const DIR_N := "N"
const DIR_E := "E"
const DIR_S := "S"
const DIR_W := "W"
const DIRECTIONS := [DIR_N, DIR_E, DIR_S, DIR_W]

# 方向到偏移量的映射
const DIR_OFFSETS := {
	"N": Vector2i(0, -1),
	"E": Vector2i(1, 0),
	"S": Vector2i(0, 1),
	"W": Vector2i(-1, 0)
}

# 对向方向映射
const OPPOSITE_DIRS := {
	"N": "S",
	"E": "W",
	"S": "N",
	"W": "E"
}

# 旋转方向映射 (顺时针)
const ROTATION_MAP := {
	0: {"N": "N", "E": "E", "S": "S", "W": "W"},
	90: {"N": "E", "E": "S", "S": "W", "W": "N"},
	180: {"N": "S", "E": "W", "S": "N", "W": "E"},
	270: {"N": "W", "E": "N", "S": "E", "W": "S"}
}

# === 坐标变换 ===

# 将板块内局部坐标转换为世界坐标
# local_pos: 板块内坐标 (0-4, 0-4)
# board_pos: 板块在地图中的位置 (板块坐标)
# rotation: 板块旋转角度 (0, 90, 180, 270)
static func local_to_world(local_pos: Vector2i, board_pos: Vector2i, rotation: int) -> Vector2i:
	var world_origin := board_pos * TILE_SIZE
	var center := Vector2i(TILE_SIZE / 2, TILE_SIZE / 2)  # (2, 2) for 5x5
	var relative := local_pos - center
	var rotated := rotate_offset(relative, rotation)
	return world_origin + center + rotated

# 将世界坐标转换为板块坐标和局部坐标
static func world_to_tile(world_pos: Vector2i) -> Dictionary:
	# 注意：world_pos 可能为负数（例如地图扩边/棋盘外组件）。
	var board_x := _floor_div(world_pos.x, TILE_SIZE)
	var board_y := _floor_div(world_pos.y, TILE_SIZE)
	var local_x := world_pos.x - board_x * TILE_SIZE
	var local_y := world_pos.y - board_y * TILE_SIZE
	var board_pos := Vector2i(board_x, board_y)
	var local_pos := Vector2i(local_x, local_y)
	return {
		"board_pos": board_pos,
		"local_pos": local_pos
	}

# 旋转偏移量
static func rotate_offset(offset: Vector2i, rotation: int) -> Vector2i:
	match rotation:
		0:
			return offset
		90:
			return Vector2i(-offset.y, offset.x)
		180:
			return Vector2i(-offset.x, -offset.y)
		270:
			return Vector2i(offset.y, -offset.x)
	return offset

# 逆旋转偏移量 (用于将世界坐标转回局部坐标)
static func unrotate_offset(offset: Vector2i, rotation: int) -> Vector2i:
	# 逆旋转 = 360 - rotation
	var inverse_rotation := (360 - rotation) % 360
	return rotate_offset(offset, inverse_rotation)

# === 方向变换 ===

# 旋转单个方向
static func rotate_dir(dir: String, rotation: int) -> String:
	if not ROTATION_MAP.has(rotation):
		return dir
	return ROTATION_MAP[rotation].get(dir, dir)

# 旋转方向数组
static func rotate_dirs(dirs: Array, rotation: int) -> Array:
	var result := []
	for dir in dirs:
		result.append(rotate_dir(dir, rotation))
	return result

# 旋转道路段
static func rotate_segment(segment: Dictionary, rotation: int) -> Dictionary:
	return {
		"dirs": rotate_dirs(segment.get("dirs", []), rotation),
		"bridge": segment.get("bridge", false)
	}

# 获取对向方向
static func get_opposite_dir(dir: String) -> String:
	return OPPOSITE_DIRS.get(dir, "")

# === 邻居计算 ===

# 获取指定方向的邻居位置
static func get_neighbor_pos(pos: Vector2i, dir: String) -> Vector2i:
	return pos + DIR_OFFSETS.get(dir, Vector2i.ZERO)

# 获取所有邻居位置
static func get_all_neighbors(pos: Vector2i) -> Dictionary:
	var neighbors := {}
	for dir in DIRECTIONS:
		neighbors[dir] = get_neighbor_pos(pos, dir)
	return neighbors

# 检查两个位置是否相邻
static func are_adjacent(pos1: Vector2i, pos2: Vector2i) -> bool:
	var diff := pos2 - pos1
	return diff in DIR_OFFSETS.values()

# 获取两个相邻位置之间的方向 (从 pos1 到 pos2)
static func get_direction_between(pos1: Vector2i, pos2: Vector2i) -> String:
	var diff := pos2 - pos1
	for dir in DIR_OFFSETS:
		if DIR_OFFSETS[dir] == diff:
			return dir
	return ""

# === 边界检查 ===

# 检查位置是否在网格范围内
static func is_valid_pos(pos: Vector2i, grid_size: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < grid_size.x and pos.y >= 0 and pos.y < grid_size.y

# 检查两个位置是否跨越板块边界
static func crosses_tile_boundary(pos1: Vector2i, pos2: Vector2i) -> bool:
	# 注意：world_pos 可能为负数（例如棋盘外板块）。
	# Vector2i(int(pos / TILE_SIZE)) 的截断会导致 -1/5 -> 0，从而错误判定板块索引。
	var tile1 := Vector2i(_floor_div(pos1.x, TILE_SIZE), _floor_div(pos1.y, TILE_SIZE))
	var tile2 := Vector2i(_floor_div(pos2.x, TILE_SIZE), _floor_div(pos2.y, TILE_SIZE))
	return tile1 != tile2

static func _floor_div(a: int, b: int) -> int:
	if b == 0:
		return 0
	return int(floor(float(a) / float(b)))

# === Footprint 计算 ===

# 计算旋转后的占地格子
# footprint_mask: 2D数组，1表示占用
# anchor: 锚点位置 (相对于footprint左上角)
# world_anchor: 世界坐标中的锚点位置
# rotation: 旋转角度
static func get_footprint_cells(footprint_mask: Array, anchor: Vector2i,
								world_anchor: Vector2i, rotation: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []

	for y in footprint_mask.size():
		var row: Array = footprint_mask[y]
		for x in row.size():
			if row[x] == 1:
				var local_offset := Vector2i(x, y) - anchor
				var rotated_offset := rotate_offset(local_offset, rotation)
				cells.append(world_anchor + rotated_offset)

	return cells

# 获取 footprint 的边界框
static func get_footprint_bounds(cells: Array[Vector2i]) -> Dictionary:
	if cells.is_empty():
		return {"min": Vector2i.ZERO, "max": Vector2i.ZERO, "size": Vector2i.ZERO}

	var min_pos := cells[0]
	var max_pos := cells[0]

	for cell in cells:
		min_pos.x = min(min_pos.x, cell.x)
		min_pos.y = min(min_pos.y, cell.y)
		max_pos.x = max(max_pos.x, cell.x)
		max_pos.y = max(max_pos.y, cell.y)

	return {
		"min": min_pos,
		"max": max_pos,
		"size": max_pos - min_pos + Vector2i.ONE
	}

# === 入口点计算 ===

# 获取结构的入口点 (相邻道路的格子)
static func get_entrance_cells(structure_cells: Array[Vector2i],
							   grid_size: Vector2i, cells: Array) -> Array[Vector2i]:
	var entrances: Array[Vector2i] = []
	var structure_set := {}
	for cell in structure_cells:
		structure_set[cell] = true

	for cell in structure_cells:
		for dir in DIRECTIONS:
			var neighbor := get_neighbor_pos(cell, dir)
			if structure_set.has(neighbor):
				continue  # 跳过结构内部
			if not is_valid_pos(neighbor, grid_size):
				continue

			var neighbor_cell = cells[neighbor.y][neighbor.x]
			var road_segments: Array = neighbor_cell.get("road_segments", [])
			if not road_segments.is_empty():
				if not entrances.has(neighbor):
					entrances.append(neighbor)

	return entrances

# === 调试 ===

static func pos_to_string(pos: Vector2i) -> String:
	return "(%d, %d)" % [pos.x, pos.y]

static func direction_to_arrow(dir: String) -> String:
	match dir:
		"N": return "↑"
		"E": return "→"
		"S": return "↓"
		"W": return "←"
	return "?"
