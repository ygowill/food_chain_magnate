extends RefCounted

const Cells = preload("res://core/map/map_baker/cells.gd")
const TileBaking = preload("res://core/map/map_baker/tile_baking.gd")
const BoundaryIndex = preload("res://core/map/map_baker/boundary_index.gd")

static func bake(map_def: MapDef, tile_registry: Dictionary, piece_registry: Dictionary = {}) -> Result:
	# 验证地图定义
	var validate_result := map_def.validate()
	if not validate_result.ok:
		return Result.failure("地图定义验证失败: %s" % validate_result.error)

	# 计算世界尺寸
	var world_size := map_def.get_world_size()

	# 创建空的格子网格
	var cells := Cells.create_empty_cells(world_size)

	# 追踪数据
	var houses := {}
	var restaurants := {}
	var drink_sources := []
	var tile_placements: Array[Dictionary] = []
	var max_printed_house_number := 0

	# 烘焙每个板块
	for tile_placement in map_def.tiles:
		assert(tile_placement is Dictionary, "MapBaker.bake: tile_placement 类型错误（期望 Dictionary）")
		var tile_id_val = tile_placement["tile_id"]
		assert(tile_id_val is String and not str(tile_id_val).is_empty(), "MapBaker.bake: tile_id 缺失或为空")
		var tile_id: String = tile_id_val
		var board_pos_val = tile_placement["board_pos"]
		assert(board_pos_val is Vector2i, "MapBaker.bake: board_pos 缺失或类型错误（期望 Vector2i）")
		var board_pos: Vector2i = board_pos_val
		var rotation_val = tile_placement["rotation"]
		assert(rotation_val is int, "MapBaker.bake: rotation 缺失或类型错误（期望 int）")
		var rotation: int = int(rotation_val)

		tile_placements.append({
			"tile_id": tile_id,
			"board_pos": board_pos,
			"rotation": rotation,
		})

		# 获取板块定义
		var tile_def: TileDef = tile_registry.get(tile_id)
		if tile_def == null:
			return Result.failure("未找到板块定义: %s" % tile_id)

		# 验证板块
		var tile_validate := tile_def.validate()
		if not tile_validate.ok:
			return Result.failure("板块 %s 验证失败: %s" % [tile_id, tile_validate.error])

		# 烘焙板块
		var bake_result := TileBaking.bake_tile(cells, tile_def, board_pos, rotation,
			piece_registry, houses, drink_sources)
		if not bake_result.ok:
			return bake_result

		assert(bake_result.value is Dictionary, "MapBaker.bake: bake_result.value 类型错误（期望 Dictionary）")
		assert(bake_result.value.has("max_house_number"), "MapBaker.bake: bake_result.value 缺少 max_house_number")
		max_printed_house_number = max(max_printed_house_number, int(bake_result.value["max_house_number"]))

	# 构建板块边界索引 (用于距离计算)
	var boundary_index := BoundaryIndex.build_boundary_index(map_def.grid_size)

	return Result.success({
		"cells": cells,
		"grid_size": world_size,
		"tile_placements": tile_placements,
		"houses": houses,
		"restaurants": restaurants,
		"drink_sources": drink_sources,
		"boundary_index": boundary_index,
		"next_house_number": max_printed_house_number + 1,
		"tile_count": map_def.tiles.size()
	})

