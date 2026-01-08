extends RefCounted

static func bake_tile(
	cells: Array,
	tile_def: TileDef,
	board_pos: Vector2i,
	rotation: int,
	piece_registry: Dictionary,
	houses: Dictionary,
	drink_sources: Array
) -> Result:
	var world_origin := board_pos * TileDef.TILE_SIZE
	var max_house_number := 0

	# 烘焙道路段
	for ly in TileDef.TILE_SIZE:
		for lx in TileDef.TILE_SIZE:
			var local_pos := Vector2i(lx, ly)
			var world_pos := MapUtils.local_to_world(local_pos, board_pos, rotation)

			# 获取该位置的道路段
			var segments: Array = tile_def.get_road_segments_at(local_pos)

			# 旋转并添加道路段
			for segment in segments:
				var rotated_segment := MapUtils.rotate_segment(segment, rotation)
				cells[world_pos.y][world_pos.x]["road_segments"].append(rotated_segment)

			# 标记板块来源
			cells[world_pos.y][world_pos.x]["tile_origin"] = board_pos

			# 检查是否阻塞
			if tile_def.is_blocked_at(local_pos):
				cells[world_pos.y][world_pos.x]["blocked"] = true

	# 烘焙印刷建筑
	for struct in tile_def.printed_structures:
		assert(struct is Dictionary, "MapBaker._bake_tile: printed_structures 元素类型错误（期望 Dictionary）")
		assert(struct.has("piece_id") and (struct["piece_id"] is String) and not str(struct["piece_id"]).is_empty(), "MapBaker._bake_tile: printed_structures.piece_id 缺失或为空")
		var piece_id: String = struct["piece_id"]
		assert(struct.has("anchor") and (struct["anchor"] is Vector2i), "MapBaker._bake_tile: printed_structures.anchor 缺失或类型错误（期望 Vector2i）")
		var local_anchor: Vector2i = struct["anchor"]
		assert(struct.has("rotation") and (struct["rotation"] is int), "MapBaker._bake_tile: printed_structures.rotation 缺失或类型错误（期望 int）")
		var struct_rotation: int = int(struct["rotation"])

		var house_id := ""
		if struct.has("house_id"):
			assert(struct["house_id"] is String, "MapBaker._bake_tile: printed_structures.house_id 类型错误（期望 String）")
			house_id = str(struct["house_id"])

		var house_number = 0
		if struct.has("house_number"):
			house_number = struct["house_number"]

		# 计算世界锚点和总旋转
		var world_anchor := MapUtils.local_to_world(local_anchor, board_pos, rotation)
		var total_rotation := (struct_rotation + rotation) % 360

		# 获取建筑件定义
		var piece_def: PieceDef = piece_registry.get(piece_id)
		if piece_def == null:
			return Result.failure("未找到建筑件定义: %s" % piece_id)
		var footprint_mask: Array = piece_def.footprint_mask
		var piece_anchor: Vector2i = piece_def.anchor

		# 计算占地格子
		var footprint_cells := MapUtils.get_footprint_cells(
			footprint_mask, piece_anchor, world_anchor, total_rotation)

		# 写入格子
		for cell_pos in footprint_cells:
			var is_anchor := (cell_pos == world_anchor)
			cells[cell_pos.y][cell_pos.x]["structure"] = {
				"piece_id": piece_id,
				"owner": -1,  # -1 表示印刷建筑
				"anchor_cell": is_anchor,
				"parent_anchor": world_anchor,
				"rotation": total_rotation,
				"house_id": house_id,
				"house_number": house_number,
				"has_garden": piece_id.contains("garden"),
				"dynamic": false
			}

		# 注册房屋
		if not house_id.is_empty():
			var num = house_number
			if num is float or num is int:
				max_house_number = max(max_house_number, int(num))

			var house_entry: Dictionary = {
				"house_id": house_id,
				"house_number": house_number,
				"anchor_pos": world_anchor,
				"cells": footprint_cells,
				"has_garden": piece_id.contains("garden"),
				"is_apartment": false,
				"printed": true,
				"demands": []
			}

			if struct.has("house_props"):
				var props_val = struct.get("house_props", null)
				if not (props_val is Dictionary):
					return Result.failure("MapBaker._bake_tile: printed_structures.house_props 类型错误（期望 Dictionary）")
				var props: Dictionary = props_val
				for k in props.keys():
					house_entry[str(k)] = props[k]

			houses[house_id] = house_entry

	# 烘焙饮品源
	for source in tile_def.drink_sources:
		assert(source is Dictionary, "MapBaker._bake_tile: drink_sources 元素类型错误（期望 Dictionary）")
		assert(source.has("pos") and (source["pos"] is Vector2i), "MapBaker._bake_tile: drink_sources.pos 缺失或类型错误（期望 Vector2i）")
		var local_pos: Vector2i = source["pos"]
		var world_pos := MapUtils.local_to_world(local_pos, board_pos, rotation)
		assert(source.has("type") and (source["type"] is String) and not str(source["type"]).is_empty(), "MapBaker._bake_tile: drink_sources.type 缺失或为空")
		var drink_type: String = source["type"]

		cells[world_pos.y][world_pos.x]["drink_source"] = {
			"type": drink_type
		}

		drink_sources.append({
			"world_pos": world_pos,
			"type": drink_type,
			"tile_id": tile_def.id
		})

	return Result.success({"max_house_number": max_house_number})

static func bake_tile_into_cells(
	cells: Array,
	grid_size: Vector2i,
	map_origin: Vector2i,
	tile_def: TileDef,
	board_pos: Vector2i,
	rotation: int,
	piece_registry: Dictionary,
	houses: Dictionary,
	drink_sources: Array
) -> Result:
	if not (cells is Array):
		return Result.failure("MapBaker.bake_tile_into_cells: cells 类型错误（期望 Array）")
	if not (grid_size is Vector2i):
		return Result.failure("MapBaker.bake_tile_into_cells: grid_size 类型错误（期望 Vector2i）")
	if not (map_origin is Vector2i):
		return Result.failure("MapBaker.bake_tile_into_cells: map_origin 类型错误（期望 Vector2i）")
	if tile_def == null:
		return Result.failure("MapBaker.bake_tile_into_cells: tile_def 为空")
	if not (piece_registry is Dictionary):
		return Result.failure("MapBaker.bake_tile_into_cells: piece_registry 类型错误（期望 Dictionary）")
	if not (houses is Dictionary):
		return Result.failure("MapBaker.bake_tile_into_cells: houses 类型错误（期望 Dictionary）")
	if not (drink_sources is Array):
		return Result.failure("MapBaker.bake_tile_into_cells: drink_sources 类型错误（期望 Array）")

	var max_house_number := 0

	# 烘焙道路段 + tile_origin/blocked
	for ly in TileDef.TILE_SIZE:
		for lx in TileDef.TILE_SIZE:
			var local_pos := Vector2i(lx, ly)
			var world_pos := MapUtils.local_to_world(local_pos, board_pos, rotation)
			var idx := world_pos + map_origin
			if not MapUtils.is_valid_pos(idx, grid_size):
				return Result.failure("MapBaker.bake_tile_into_cells: tile 写入越界: world=%s idx=%s grid=%s origin=%s" % [str(world_pos), str(idx), str(grid_size), str(map_origin)])

			var segments: Array = tile_def.get_road_segments_at(local_pos)
			cells[idx.y][idx.x]["road_segments"] = []
			for segment in segments:
				var rotated_segment := MapUtils.rotate_segment(segment, rotation)
				cells[idx.y][idx.x]["road_segments"].append(rotated_segment)

			cells[idx.y][idx.x]["tile_origin"] = board_pos

			cells[idx.y][idx.x]["blocked"] = false
			if tile_def.is_blocked_at(local_pos):
				cells[idx.y][idx.x]["blocked"] = true

	# 烘焙印刷建筑
	for struct in tile_def.printed_structures:
		assert(struct is Dictionary, "MapBaker.bake_tile_into_cells: printed_structures 元素类型错误（期望 Dictionary）")
		assert(struct.has("piece_id") and (struct["piece_id"] is String) and not str(struct["piece_id"]).is_empty(), "MapBaker.bake_tile_into_cells: printed_structures.piece_id 缺失或为空")
		var piece_id: String = struct["piece_id"]
		assert(struct.has("anchor") and (struct["anchor"] is Vector2i), "MapBaker.bake_tile_into_cells: printed_structures.anchor 缺失或类型错误（期望 Vector2i）")
		var local_anchor: Vector2i = struct["anchor"]
		assert(struct.has("rotation") and (struct["rotation"] is int), "MapBaker.bake_tile_into_cells: printed_structures.rotation 缺失或类型错误（期望 int）")
		var struct_rotation: int = int(struct["rotation"])

		var house_id := ""
		if struct.has("house_id"):
			assert(struct["house_id"] is String, "MapBaker.bake_tile_into_cells: printed_structures.house_id 类型错误（期望 String）")
			house_id = str(struct["house_id"])

		var house_number = 0
		if struct.has("house_number"):
			house_number = struct["house_number"]

		var world_anchor := MapUtils.local_to_world(local_anchor, board_pos, rotation)
		var total_rotation := (struct_rotation + rotation) % 360

		var piece_def: PieceDef = piece_registry.get(piece_id)
		if piece_def == null:
			return Result.failure("未找到建筑件定义: %s" % piece_id)
		var footprint_mask: Array = piece_def.footprint_mask
		var piece_anchor: Vector2i = piece_def.anchor

		var footprint_cells := MapUtils.get_footprint_cells(
			footprint_mask, piece_anchor, world_anchor, total_rotation)

		for cell_pos in footprint_cells:
			var idx2 := cell_pos + map_origin
			if not MapUtils.is_valid_pos(idx2, grid_size):
				return Result.failure("MapBaker.bake_tile_into_cells: structure 写入越界: %s" % str(cell_pos))
			var is_anchor := (cell_pos == world_anchor)
			cells[idx2.y][idx2.x]["structure"] = {
				"piece_id": piece_id,
				"owner": -1,
				"anchor_cell": is_anchor,
				"parent_anchor": world_anchor,
				"rotation": total_rotation,
				"house_id": house_id,
				"house_number": house_number,
				"has_garden": piece_id.contains("garden"),
				"dynamic": false
			}

		if not house_id.is_empty():
			var num = house_number
			if num is float or num is int:
				max_house_number = max(max_house_number, int(num))

			var house_entry: Dictionary = {
				"house_id": house_id,
				"house_number": house_number,
				"anchor_pos": world_anchor,
				"cells": footprint_cells,
				"has_garden": piece_id.contains("garden"),
				"is_apartment": false,
				"printed": true,
				"demands": []
			}

			if struct.has("house_props"):
				var props_val = struct.get("house_props", null)
				if not (props_val is Dictionary):
					return Result.failure("MapBaker.bake_tile_into_cells: printed_structures.house_props 类型错误（期望 Dictionary）")
				var props: Dictionary = props_val
				for k in props.keys():
					house_entry[str(k)] = props[k]

			houses[house_id] = house_entry

	# 烘焙饮品源
	for source in tile_def.drink_sources:
		assert(source is Dictionary, "MapBaker.bake_tile_into_cells: drink_sources 元素类型错误（期望 Dictionary）")
		assert(source.has("pos") and (source["pos"] is Vector2i), "MapBaker.bake_tile_into_cells: drink_sources.pos 缺失或类型错误（期望 Vector2i）")
		var local_pos: Vector2i = source["pos"]
		var world_pos2 := MapUtils.local_to_world(local_pos, board_pos, rotation)
		var idx3 := world_pos2 + map_origin
		if not MapUtils.is_valid_pos(idx3, grid_size):
			return Result.failure("MapBaker.bake_tile_into_cells: drink_source 写入越界: %s" % str(world_pos2))
		assert(source.has("type") and (source["type"] is String) and not str(source["type"]).is_empty(), "MapBaker.bake_tile_into_cells: drink_sources.type 缺失或为空")
		var drink_type: String = source["type"]

		cells[idx3.y][idx3.x]["drink_source"] = {
			"type": drink_type
		}

		drink_sources.append({
			"world_pos": world_pos2,
			"type": drink_type,
			"tile_id": tile_def.id
		})

	return Result.success({"max_house_number": max_house_number})

