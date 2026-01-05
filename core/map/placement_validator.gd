# 放置验证器（Fail Fast）
# 提供统一的建筑物放置验证 API（缺字段/类型错直接 assert；规则不满足返回 Result.failure）
class_name PlacementValidator
extends RefCounted

# === 验证结果 ===

# 统一放置验证入口
# map_ctx: 包含 cells, grid_size, houses, restaurants 等的字典
# piece_id: 建筑件 ID
# world_anchor: 世界坐标锚点
# rotation: 旋转角度
# context: 额外上下文 (player_id, phase 等)
static func validate_placement(
	map_ctx: Dictionary,
	piece_id: String,
	world_anchor: Vector2i,
	rotation: int,
	piece_registry: Dictionary,
	context: Dictionary = {}
) -> Result:
	# 获取建筑件定义
	var piece_def: PieceDef = piece_registry.get(piece_id)
	if piece_def == null:
		return Result.failure("未知的建筑件: %s" % piece_id)

	# 验证旋转
	if not piece_def.is_rotation_allowed(rotation):
		return Result.failure("不允许的旋转角度: %d (允许: %s)" % [rotation, str(piece_def.allowed_rotations)])

	# 获取占地格子
	var footprint_cells := piece_def.get_world_cells(world_anchor, rotation)
	if footprint_cells.is_empty():
		return Result.failure("无效的占地定义")

	# 运行验证链
	var validators := [
		_validate_bounds,
		_validate_cells_empty,
		_validate_not_blocked,
		_validate_no_structure_overlap,
		_validate_road_adjacency,
	]

	for validator in validators:
		var result: Result = validator.call(map_ctx, piece_def, footprint_cells, context)
		if not result.ok:
			return result

	return Result.success({
		"piece_id": piece_id,
		"anchor": world_anchor,
		"rotation": rotation,
		"footprint_cells": footprint_cells,
	})

static func _get_map_origin(map_ctx: Dictionary) -> Vector2i:
	if map_ctx.has("map_origin"):
		var v = map_ctx.get("map_origin", null)
		assert(v is Vector2i, "PlacementValidator: map_ctx.map_origin 类型错误（期望 Vector2i）")
		return v
	return Vector2i.ZERO

static func _world_to_index(map_ctx: Dictionary, world_pos: Vector2i) -> Vector2i:
	return world_pos + _get_map_origin(map_ctx)

static func _has_world_cell(map_ctx: Dictionary, world_pos: Vector2i) -> bool:
	assert(map_ctx.has("grid_size") and (map_ctx["grid_size"] is Vector2i), "PlacementValidator: map_ctx.grid_size 缺失或类型错误（期望 Vector2i）")
	var grid_size: Vector2i = map_ctx["grid_size"]
	var idx := _world_to_index(map_ctx, world_pos)
	return idx.x >= 0 and idx.y >= 0 and idx.x < grid_size.x and idx.y < grid_size.y

static func _get_world_cell(map_ctx: Dictionary, world_pos: Vector2i) -> Dictionary:
	assert(map_ctx.has("cells") and (map_ctx["cells"] is Array), "PlacementValidator: map_ctx.cells 缺失或类型错误（期望 Array）")
	var cells: Array = map_ctx["cells"]
	assert(map_ctx.has("grid_size") and (map_ctx["grid_size"] is Vector2i), "PlacementValidator: map_ctx.grid_size 缺失或类型错误（期望 Vector2i）")
	var grid_size: Vector2i = map_ctx["grid_size"]

	var idx := _world_to_index(map_ctx, world_pos)
	assert(idx.x >= 0 and idx.y >= 0 and idx.x < grid_size.x and idx.y < grid_size.y, "PlacementValidator: world_pos 越界: %s (grid=%s origin=%s)" % [str(world_pos), str(grid_size), str(_get_map_origin(map_ctx))])

	var row_val = cells[idx.y]
	assert(row_val is Array, "PlacementValidator: cells[%d] 类型错误（期望 Array）" % idx.y)
	var row: Array = row_val
	var cell_val = row[idx.x]
	assert(cell_val is Dictionary, "PlacementValidator: cells[%d][%d] 类型错误（期望 Dictionary）" % [idx.y, idx.x])
	return cell_val


# === 验证函数 ===

# 验证边界
static func _validate_bounds(
	map_ctx: Dictionary,
	_piece_def: PieceDef,
	footprint_cells: Array[Vector2i],
	_context: Dictionary
) -> Result:
	assert(map_ctx.has("grid_size") and (map_ctx["grid_size"] is Vector2i), "PlacementValidator: map_ctx.grid_size 缺失或类型错误（期望 Vector2i）")
	var grid_size: Vector2i = map_ctx["grid_size"]

	for cell_pos in footprint_cells:
		var idx := _world_to_index(map_ctx, cell_pos)
		if not MapUtils.is_valid_pos(idx, grid_size):
			return Result.failure("放置位置超出边界: %s" % str(cell_pos))

	return Result.success()


# 验证格子为空 (没有道路)
static func _validate_cells_empty(
	map_ctx: Dictionary,
	piece_def: PieceDef,
	footprint_cells: Array[Vector2i],
	_context: Dictionary
) -> Result:
	if not piece_def.must_be_on_empty:
		return Result.success()

	assert(map_ctx.has("cells") and (map_ctx["cells"] is Array), "PlacementValidator: map_ctx.cells 缺失或类型错误（期望 Array）")
	for cell_pos in footprint_cells:
		var cell: Dictionary = _get_world_cell(map_ctx, cell_pos)
		assert(cell.has("road_segments") and (cell["road_segments"] is Array), "PlacementValidator: cell.road_segments 缺失或类型错误（期望 Array）: %s" % str(cell_pos))
		var road_segments: Array = cell["road_segments"]
		if not road_segments.is_empty():
			return Result.failure("位置 %s 有道路，无法放置" % str(cell_pos))

	return Result.success()


# 验证没有被阻塞
static func _validate_not_blocked(
	map_ctx: Dictionary,
	_piece_def: PieceDef,
	footprint_cells: Array[Vector2i],
	_context: Dictionary
) -> Result:
	assert(map_ctx.has("cells") and (map_ctx["cells"] is Array), "PlacementValidator: map_ctx.cells 缺失或类型错误（期望 Array）")
	for cell_pos in footprint_cells:
		var cell: Dictionary = _get_world_cell(map_ctx, cell_pos)
		assert(cell.has("blocked") and (cell["blocked"] is bool), "PlacementValidator: cell.blocked 缺失或类型错误（期望 bool）: %s" % str(cell_pos))
		if bool(cell["blocked"]):
			return Result.failure("位置 %s 被阻塞" % str(cell_pos))

	return Result.success()


# 验证没有建筑重叠
static func _validate_no_structure_overlap(
	map_ctx: Dictionary,
	_piece_def: PieceDef,
	footprint_cells: Array[Vector2i],
	context: Dictionary
) -> Result:
	assert(map_ctx.has("cells") and (map_ctx["cells"] is Array), "PlacementValidator: map_ctx.cells 缺失或类型错误（期望 Array）")
	var ignore_set := {}
	if context.has("ignore_structure_cells"):
		var ignore_cells_val = context["ignore_structure_cells"]
		assert(ignore_cells_val is Array, "PlacementValidator: context.ignore_structure_cells 类型错误（期望 Array[Vector2i]）")
		var ignore_cells: Array = ignore_cells_val
		for v in ignore_cells:
			assert(v is Vector2i, "PlacementValidator: ignore_structure_cells 元素类型错误（期望 Vector2i）")
			ignore_set[v] = true

	for cell_pos in footprint_cells:
		if not ignore_set.is_empty() and ignore_set.has(cell_pos):
			continue

		var cell: Dictionary = _get_world_cell(map_ctx, cell_pos)
		assert(cell.has("structure") and (cell["structure"] is Dictionary), "PlacementValidator: cell.structure 缺失或类型错误（期望 Dictionary）: %s" % str(cell_pos))
		var structure: Dictionary = cell["structure"]

		if not structure.is_empty():
			assert(structure.has("piece_id") and (structure["piece_id"] is String), "PlacementValidator: structure.piece_id 缺失或类型错误（期望 String）: %s" % str(cell_pos))
			var existing_piece: String = str(structure["piece_id"])
			return Result.failure("位置 %s 已有建筑: %s" % [str(cell_pos), existing_piece])

	return Result.success()


# 验证邻接道路
static func _validate_road_adjacency(
	map_ctx: Dictionary,
	piece_def: PieceDef,
	footprint_cells: Array[Vector2i],
	_context: Dictionary
) -> Result:
	if not piece_def.must_touch_road:
		return Result.success()

	assert(map_ctx.has("cells") and (map_ctx["cells"] is Array), "PlacementValidator: map_ctx.cells 缺失或类型错误（期望 Array）")
	assert(map_ctx.has("grid_size") and (map_ctx["grid_size"] is Vector2i), "PlacementValidator: map_ctx.grid_size 缺失或类型错误（期望 Vector2i）")
	var grid_size: Vector2i = map_ctx["grid_size"]

	# 创建占地集合
	var footprint_set := {}
	for cell in footprint_cells:
		footprint_set[cell] = true

	# 检查是否有任何占地格子邻接道路
	for cell_pos in footprint_cells:
		for dir in MapUtils.DIRECTIONS:
			var neighbor := MapUtils.get_neighbor_pos(cell_pos, dir)

			# 跳过占地内部
			if footprint_set.has(neighbor):
				continue

			# 跳过边界外
			if not _has_world_cell(map_ctx, neighbor):
				continue

			var neighbor_cell: Dictionary = _get_world_cell(map_ctx, neighbor)
			assert(neighbor_cell.has("road_segments") and (neighbor_cell["road_segments"] is Array), "PlacementValidator: cell.road_segments 缺失或类型错误（期望 Array）: %s" % str(neighbor))
			var road_segments: Array = neighbor_cell["road_segments"]
			if not road_segments.is_empty():
				return Result.success()

	return Result.failure("放置位置必须邻接道路")


# === 特定类型验证 ===

# 验证餐厅放置
static func validate_restaurant_placement(
	map_ctx: Dictionary,
	world_anchor: Vector2i,
	rotation: int,
	piece_registry: Dictionary,
	_player_id: int,
	is_initial_placement: bool,
	context: Dictionary = {}
) -> Result:
	# 基础验证
	var base_result := validate_placement(map_ctx, "restaurant", world_anchor, rotation, piece_registry, context)
	if not base_result.ok:
		return base_result

	var footprint_cells: Array = base_result.value.footprint_cells

	# 获取餐厅入口
	var piece_def: PieceDef = piece_registry.get("restaurant")
	assert(piece_def != null, "PlacementValidator: piece_registry 缺少 restaurant PieceDef")
	var entrance_points := piece_def.get_world_entrance_points(world_anchor, rotation)
	assert(not entrance_points.is_empty(), "PlacementValidator: restaurant entrance_points 不能为空")

	# 验证入口邻接道路
	var has_road_access := false
	for entrance in entrance_points:
		for dir in MapUtils.DIRECTIONS:
			var neighbor := MapUtils.get_neighbor_pos(entrance, dir)
			if not _has_world_cell(map_ctx, neighbor):
				continue
			var neighbor_cell: Dictionary = _get_world_cell(map_ctx, neighbor)
			assert(neighbor_cell.has("road_segments") and (neighbor_cell["road_segments"] is Array), "PlacementValidator: cell.road_segments 缺失或类型错误（期望 Array）: %s" % str(neighbor))
			var road_segments: Array = neighbor_cell["road_segments"]
			if not road_segments.is_empty():
				has_road_access = true
				break
		if has_road_access:
			break

	if not has_road_access:
		return Result.failure("餐厅入口必须邻接道路")

	# 初始放置限制: 每个板块只能有一个餐厅入口
	if is_initial_placement:
		var entrance_tile: Vector2i = MapUtils.world_to_tile(entrance_points[0]).board_pos

		assert(map_ctx.has("restaurants") and (map_ctx["restaurants"] is Dictionary), "PlacementValidator: map_ctx.restaurants 缺失或类型错误（期望 Dictionary）")
		var restaurants: Dictionary = map_ctx["restaurants"]
		for rest_id in restaurants:
			var rest_val = restaurants[rest_id]
			assert(rest_val is Dictionary, "PlacementValidator: restaurants[%s] 类型错误（期望 Dictionary）" % str(rest_id))
			var rest: Dictionary = rest_val
			assert(rest.has("entrance_pos") and (rest["entrance_pos"] is Vector2i), "PlacementValidator: restaurants[%s].entrance_pos 缺失或类型错误（期望 Vector2i）" % str(rest_id))
			var rest_entrance: Vector2i = rest["entrance_pos"]
			var rest_tile: Vector2i = MapUtils.world_to_tile(rest_entrance).board_pos
			if rest_tile == entrance_tile:
				return Result.failure("初始放置: 每个板块只能有一个餐厅入口")

	# 添加入口信息到结果
	var result_value: Dictionary = base_result.value
	result_value["entrance_pos"] = entrance_points[0]
	result_value["entrance_points"] = entrance_points

	return Result.success(result_value)


# 验证房屋放置
static func validate_house_placement(
	map_ctx: Dictionary,
	world_anchor: Vector2i,
	rotation: int,
	piece_registry: Dictionary,
	_player_id: int,
	context: Dictionary = {}
) -> Result:
	# 基础验证
	return validate_placement(map_ctx, "house", world_anchor, rotation, piece_registry, context)


# 验证花园添加
static func validate_garden_attachment(
	map_ctx: Dictionary,
	house_id: String,
	garden_direction: String,  # 花园相对于房屋的方向 (N/E/S/W)
	_piece_registry: Dictionary,
	_context: Dictionary = {}
) -> Result:
	assert(map_ctx.has("houses") and (map_ctx["houses"] is Dictionary), "PlacementValidator: map_ctx.houses 缺失或类型错误（期望 Dictionary）")
	var houses: Dictionary = map_ctx["houses"]
	assert(map_ctx.has("cells") and (map_ctx["cells"] is Array), "PlacementValidator: map_ctx.cells 缺失或类型错误（期望 Array）")
	var cells: Array = map_ctx["cells"]
	assert(map_ctx.has("grid_size") and (map_ctx["grid_size"] is Vector2i), "PlacementValidator: map_ctx.grid_size 缺失或类型错误（期望 Vector2i）")
	var grid_size: Vector2i = map_ctx["grid_size"]

	# 检查房屋存在
	if not houses.has(house_id):
		return Result.failure("房屋不存在: %s" % house_id)

	var house_val = houses[house_id]
	assert(house_val is Dictionary, "PlacementValidator: houses[%s] 类型错误（期望 Dictionary）" % house_id)
	var house: Dictionary = house_val

	# 检查房屋是否已有花园
	assert(house.has("has_garden") and (house["has_garden"] is bool), "PlacementValidator: houses[%s].has_garden 缺失或类型错误（期望 bool）" % house_id)
	if bool(house["has_garden"]):
		return Result.failure("房屋已有花园")

	assert(house.has("anchor_pos") and (house["anchor_pos"] is Vector2i), "PlacementValidator: houses[%s].anchor_pos 缺失或类型错误（期望 Vector2i）" % house_id)
	var anchor_pos: Vector2i = house["anchor_pos"]
	assert(house.has("cells") and (house["cells"] is Array), "PlacementValidator: houses[%s].cells 缺失或类型错误（期望 Array）" % house_id)
	var house_cells: Array = house["cells"]

	# 根据方向计算花园位置 (2x1 区域)
	assert(MapUtils.DIR_OFFSETS.has(garden_direction), "PlacementValidator: 无效的花园方向: %s" % garden_direction)
	var garden_cells: Array[Vector2i] = []
	match garden_direction:
		"N":
			garden_cells.append(Vector2i(anchor_pos.x, anchor_pos.y - 1))
			garden_cells.append(Vector2i(anchor_pos.x + 1, anchor_pos.y - 1))
		"S":
			garden_cells.append(Vector2i(anchor_pos.x, anchor_pos.y + 2))
			garden_cells.append(Vector2i(anchor_pos.x + 1, anchor_pos.y + 2))
		"W":
			garden_cells.append(Vector2i(anchor_pos.x - 1, anchor_pos.y))
			garden_cells.append(Vector2i(anchor_pos.x - 1, anchor_pos.y + 1))
		"E":
			garden_cells.append(Vector2i(anchor_pos.x + 2, anchor_pos.y))
			garden_cells.append(Vector2i(anchor_pos.x + 2, anchor_pos.y + 1))

	# 验证花园格子
	for cell_pos in garden_cells:
		# 检查边界
		var idx := _world_to_index(map_ctx, cell_pos)
		if not MapUtils.is_valid_pos(idx, grid_size):
			return Result.failure("花园位置超出边界: %s" % str(cell_pos))

		var cell: Dictionary = _get_world_cell(map_ctx, cell_pos)

		# 检查是否有道路
		assert(cell.has("road_segments") and (cell["road_segments"] is Array), "PlacementValidator: cell.road_segments 缺失或类型错误（期望 Array）: %s" % str(cell_pos))
		var road_segments: Array = cell["road_segments"]
		if not road_segments.is_empty():
			return Result.failure("花园位置有道路: %s" % str(cell_pos))

		# 检查是否有建筑
		assert(cell.has("structure") and (cell["structure"] is Dictionary), "PlacementValidator: cell.structure 缺失或类型错误（期望 Dictionary）: %s" % str(cell_pos))
		var structure: Dictionary = cell["structure"]
		if not structure.is_empty():
			return Result.failure("花园位置有建筑: %s" % str(cell_pos))

		# 检查是否阻塞
		assert(cell.has("blocked") and (cell["blocked"] is bool), "PlacementValidator: cell.blocked 缺失或类型错误（期望 bool）: %s" % str(cell_pos))
		if bool(cell["blocked"]):
			return Result.failure("花园位置被阻塞: %s" % str(cell_pos))

	return Result.success({
		"house_id": house_id,
		"garden_direction": garden_direction,
		"garden_cells": garden_cells,
		"merged_cells": house_cells + garden_cells,
	})


# === 工具方法 ===

# 获取有效的放置位置
static func get_valid_placements(
	map_ctx: Dictionary,
	piece_id: String,
	piece_registry: Dictionary,
	context: Dictionary = {}
) -> Array[Dictionary]:
	var valid_placements: Array[Dictionary] = []
	var piece_def: PieceDef = piece_registry.get(piece_id)
	if piece_def == null:
		return valid_placements

	assert(map_ctx.has("grid_size") and (map_ctx["grid_size"] is Vector2i), "PlacementValidator: map_ctx.grid_size 缺失或类型错误（期望 Vector2i）")
	var grid_size: Vector2i = map_ctx["grid_size"]

	# 遍历所有可能的位置和旋转
	for y in grid_size.y:
		for x in grid_size.x:
			var anchor := Vector2i(x, y)
			for rot in piece_def.allowed_rotations:
				var result := validate_placement(map_ctx, piece_id, anchor, rot, piece_registry, context)
				if result.ok:
					valid_placements.append({
						"anchor": anchor,
						"rotation": rot,
						"footprint_cells": result.value.footprint_cells,
					})

	return valid_placements


# 检查位置是否邻接道路
static func is_adjacent_to_road(cells: Array, pos: Vector2i, grid_size: Vector2i) -> bool:
	for dir in MapUtils.DIRECTIONS:
		var neighbor := MapUtils.get_neighbor_pos(pos, dir)
		if not MapUtils.is_valid_pos(neighbor, grid_size):
			continue

		var cell_val = cells[neighbor.y][neighbor.x]
		assert(cell_val is Dictionary, "PlacementValidator: cells[%d][%d] 类型错误（期望 Dictionary）" % [neighbor.y, neighbor.x])
		var cell: Dictionary = cell_val
		assert(cell.has("road_segments") and (cell["road_segments"] is Array), "PlacementValidator: cell.road_segments 缺失或类型错误（期望 Array）: %s" % str(neighbor))
		var road_segments: Array = cell["road_segments"]
		if not road_segments.is_empty():
			return true

	return false


# 获取邻接的道路格子
static func get_adjacent_road_cells(cells: Array, positions: Array[Vector2i], grid_size: Vector2i) -> Array[Vector2i]:
	var road_cells: Array[Vector2i] = []
	var pos_set := {}
	for pos in positions:
		pos_set[pos] = true

	for pos in positions:
		for dir in MapUtils.DIRECTIONS:
			var neighbor := MapUtils.get_neighbor_pos(pos, dir)
			if pos_set.has(neighbor):
				continue
			if not MapUtils.is_valid_pos(neighbor, grid_size):
				continue

			var cell_val = cells[neighbor.y][neighbor.x]
			assert(cell_val is Dictionary, "PlacementValidator: cells[%d][%d] 类型错误（期望 Dictionary）" % [neighbor.y, neighbor.x])
			var cell: Dictionary = cell_val
			assert(cell.has("road_segments") and (cell["road_segments"] is Array), "PlacementValidator: cell.road_segments 缺失或类型错误（期望 Array）: %s" % str(neighbor))
			var road_segments: Array = cell["road_segments"]

			if not road_segments.is_empty() and not road_cells.has(neighbor):
				road_cells.append(neighbor)

	return road_cells
