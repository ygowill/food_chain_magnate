extends RefCounted

const MapAccess = preload("res://core/map/placement_validator/map_access.gd")

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
		var idx := MapAccess.world_to_index(map_ctx, cell_pos)
		if not MapUtils.is_valid_pos(idx, grid_size):
			return Result.failure("花园位置超出边界: %s" % str(cell_pos))

		var cell: Dictionary = MapAccess.get_world_cell(map_ctx, cell_pos)

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

