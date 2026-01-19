extends RefCounted

const MapAccess = preload("res://core/map/placement_validator/map_access.gd")
const Validators = preload("res://core/map/placement_validator/validators.gd")

# 验证花园添加
static func validate_garden_attachment(
	map_ctx: Dictionary,
	house_id: String,
	garden_direction: String,  # 花园相对于房屋的方向 (N/E/S/W)
	_piece_registry: Dictionary,
	_context: Dictionary = {}
) -> Result:
	if not map_ctx.has("houses") or not (map_ctx["houses"] is Dictionary):
		return Result.failure("PlacementValidator: map_ctx.houses 缺失或类型错误（期望 Dictionary）")
	var houses: Dictionary = map_ctx["houses"]
	if not map_ctx.has("cells") or not (map_ctx["cells"] is Array):
		return Result.failure("PlacementValidator: map_ctx.cells 缺失或类型错误（期望 Array）")
	var cells: Array = map_ctx["cells"]
	if not map_ctx.has("grid_size") or not (map_ctx["grid_size"] is Vector2i):
		return Result.failure("PlacementValidator: map_ctx.grid_size 缺失或类型错误（期望 Vector2i）")
	var grid_size: Vector2i = map_ctx["grid_size"]

	# 检查房屋存在
	if not houses.has(house_id):
		return Result.failure("房屋不存在: %s" % house_id)

	var house_val = houses[house_id]
	if not (house_val is Dictionary):
		return Result.failure("PlacementValidator: houses[%s] 类型错误（期望 Dictionary）" % house_id)
	var house: Dictionary = house_val

	# 检查房屋是否已有花园
	if not house.has("has_garden") or not (house["has_garden"] is bool):
		return Result.failure("PlacementValidator: houses[%s].has_garden 缺失或类型错误（期望 bool）" % house_id)
	if bool(house["has_garden"]):
		return Result.failure("房屋已有花园")

	if not house.has("cells") or not (house["cells"] is Array):
		return Result.failure("PlacementValidator: houses[%s].cells 缺失或类型错误（期望 Array）" % house_id)
	var house_cells: Array = house["cells"]

	# 根据方向计算花园位置 (2x1 区域)
	if not MapUtils.DIR_OFFSETS.has(garden_direction):
		return Result.failure("PlacementValidator: 无效的花园方向: %s" % garden_direction)
	var house_cells_world: Array[Vector2i] = []
	var min_x := 2147483647
	var min_y := 2147483647
	var max_x := -2147483648
	var max_y := -2147483648
	for p_val in house_cells:
		if not (p_val is Vector2i):
			return Result.failure("PlacementValidator: houses[%s].cells 元素类型错误（期望 Vector2i）" % house_id)
		var p: Vector2i = p_val
		house_cells_world.append(p)
		min_x = min(min_x, p.x)
		min_y = min(min_y, p.y)
		max_x = max(max_x, p.x)
		max_y = max(max_y, p.y)

	if house_cells_world.is_empty():
		return Result.failure("房屋占地为空: %s" % house_id)

	# 花园放置方向为世界方向（N/E/S/W）。房屋在 tile 旋转后，其 anchor_pos 可能不再是左上角；
	# 因此以房屋占地 bounding box 计算花园位置，避免旋转板块下的错位判定。
	var garden_cells: Array[Vector2i] = []
	match garden_direction:
		"N":
			for x in range(min_x, max_x + 1):
				garden_cells.append(Vector2i(x, min_y - 1))
		"S":
			for x in range(min_x, max_x + 1):
				garden_cells.append(Vector2i(x, max_y + 1))
		"W":
			for y in range(min_y, max_y + 1):
				garden_cells.append(Vector2i(min_x - 1, y))
		"E":
			for y in range(min_y, max_y + 1):
				garden_cells.append(Vector2i(max_x + 1, y))

	# 验证花园格子
	for cell_pos in garden_cells:
		# 检查边界
		var idx := MapAccess.world_to_index(map_ctx, cell_pos)
		if not MapUtils.is_valid_pos(idx, grid_size):
			return Result.failure("花园位置超出边界: %s" % str(cell_pos))

		var cell: Dictionary = MapAccess.get_world_cell(map_ctx, cell_pos)

		# 检查是否有道路
		var road_segments_val = cell.get("road_segments", null)
		if not (road_segments_val is Array):
			return Result.failure("PlacementValidator: cell.road_segments 缺失或类型错误（期望 Array）: %s" % str(cell_pos))
		var road_segments: Array = road_segments_val
		if not road_segments.is_empty():
			return Result.failure("花园位置有道路: %s" % str(cell_pos))

		# 检查是否有建筑
		var structure_val = cell.get("structure", null)
		if not (structure_val is Dictionary):
			return Result.failure("PlacementValidator: cell.structure 缺失或类型错误（期望 Dictionary）: %s" % str(cell_pos))
		var structure: Dictionary = structure_val
		if not structure.is_empty():
			return Result.failure("花园位置有建筑: %s" % str(cell_pos))

		# 检查是否阻塞
		var blocked_val = cell.get("blocked", null)
		if not (blocked_val is bool):
			return Result.failure("PlacementValidator: cell.blocked 缺失或类型错误（期望 bool）: %s" % str(cell_pos))
		if bool(blocked_val):
			return Result.failure("花园位置被阻塞: %s" % str(cell_pos))

	# 花园扩建也不能与营销板件重叠（营销板件为阻挡物）
	var mk_r := Validators.validate_no_marketing_overlap(map_ctx, null, garden_cells, _context)
	if not mk_r.ok:
		return mk_r

	return Result.success({
		"house_id": house_id,
		"garden_direction": garden_direction,
		"garden_cells": garden_cells,
		"merged_cells": house_cells_world + garden_cells,
	})
