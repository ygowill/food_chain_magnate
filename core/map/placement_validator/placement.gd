extends RefCounted

const Validators = preload("res://core/map/placement_validator/validators.gd")

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
	var result := Validators.validate_bounds(map_ctx, piece_def, footprint_cells, context)
	if not result.ok:
		return result
	result = Validators.validate_cells_empty(map_ctx, piece_def, footprint_cells, context)
	if not result.ok:
		return result
	result = Validators.validate_not_blocked(map_ctx, piece_def, footprint_cells, context)
	if not result.ok:
		return result
	result = Validators.validate_no_drink_source(map_ctx, piece_def, footprint_cells, context)
	if not result.ok:
		return result
	result = Validators.validate_no_structure_overlap(map_ctx, piece_def, footprint_cells, context)
	if not result.ok:
		return result
	result = Validators.validate_road_adjacency(map_ctx, piece_def, footprint_cells, context)
	if not result.ok:
		return result

	return Result.success({
		"piece_id": piece_id,
		"anchor": world_anchor,
		"rotation": rotation,
		"footprint_cells": footprint_cells,
	})

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

