# 地图烘焙器
# 将 TileDef/MapDef 转换为运行时的 map.cells 网格结构
class_name MapBaker
extends RefCounted

# === 烘焙主入口 ===

# 烘焙地图定义为运行时数据
# map_def: 地图定义
# tile_registry: 板块注册表 { tile_id -> TileDef }
# piece_registry: 建筑件注册表 { piece_id -> PieceDef }
static func bake(map_def: MapDef, tile_registry: Dictionary,
				 piece_registry: Dictionary = {}) -> Result:
	# 验证地图定义
	var validate_result := map_def.validate()
	if not validate_result.ok:
		return Result.failure("地图定义验证失败: %s" % validate_result.error)

	# 计算世界尺寸
	var world_size := map_def.get_world_size()

	# 创建空的格子网格
	var cells := _create_empty_cells(world_size)

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
		var bake_result := _bake_tile(cells, tile_def, board_pos, rotation,
									  piece_registry, houses, drink_sources)
		if not bake_result.ok:
			return bake_result

		assert(bake_result.value is Dictionary, "MapBaker.bake: bake_result.value 类型错误（期望 Dictionary）")
		assert(bake_result.value.has("max_house_number"), "MapBaker.bake: bake_result.value 缺少 max_house_number")
		max_printed_house_number = max(max_printed_house_number, int(bake_result.value["max_house_number"]))

	# 构建板块边界索引 (用于距离计算)
	var boundary_index := _build_boundary_index(map_def.grid_size)

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

# === 格子网格创建 ===

static func _create_empty_cells(grid_size: Vector2i) -> Array:
	var cells := []
	for y in grid_size.y:
		var row := []
		for x in grid_size.x:
			row.append(_create_empty_cell())
		cells.append(row)
	return cells

static func _create_empty_cell() -> Dictionary:
	return {
		"road_segments": [],     # 道路段数组
		"structure": {},         # 建筑物信息
		"terrain_type": null,    # 地形类型
		"drink_source": null,    # 饮品源
		"tile_origin": Vector2i(-1, -1),  # 所属板块
		"blocked": false         # 是否被阻塞
	}

# === 板块烘焙 ===

static func _bake_tile(cells: Array, tile_def: TileDef, board_pos: Vector2i,
					   rotation: int, piece_registry: Dictionary,
					   houses: Dictionary, drink_sources: Array) -> Result:
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

# === 边界索引构建 ===

static func _build_boundary_index(tile_grid_size: Vector2i) -> Dictionary:
	# 构建板块边界的快速查找索引
	# 用于在路径计算时快速判断是否跨越边界

	var horizontal_boundaries := []  # y 坐标为板块边界
	var vertical_boundaries := []    # x 坐标为板块边界

	for i in range(1, tile_grid_size.y):
		horizontal_boundaries.append(i * TileDef.TILE_SIZE)

	for i in range(1, tile_grid_size.x):
		vertical_boundaries.append(i * TileDef.TILE_SIZE)

	return {
		"horizontal": horizontal_boundaries,
		"vertical": vertical_boundaries,
		"tile_size": TileDef.TILE_SIZE
	}

# === 工具方法 ===

# 获取指定世界坐标的格子
static func get_cell(cells: Array, pos: Vector2i, grid_size: Vector2i) -> Dictionary:
	assert(MapUtils.is_valid_pos(pos, grid_size), "MapBaker.get_cell: pos 越界: %s (grid=%s)" % [str(pos), str(grid_size)])
	var cell_val = cells[pos.y][pos.x]
	assert(cell_val is Dictionary, "MapBaker.get_cell: cells[%d][%d] 类型错误（期望 Dictionary）" % [pos.y, pos.x])
	return cell_val

# 获取指定位置的道路段
static func get_road_segments_at(cells: Array, pos: Vector2i, grid_size: Vector2i) -> Array:
	var cell := get_cell(cells, pos, grid_size)
	assert(cell.has("road_segments") and (cell["road_segments"] is Array), "MapBaker.get_road_segments_at: cell.road_segments 缺失或类型错误: %s" % str(pos))
	return cell["road_segments"]

# 检查位置是否有道路
static func has_road_at(cells: Array, pos: Vector2i, grid_size: Vector2i) -> bool:
	return not get_road_segments_at(cells, pos, grid_size).is_empty()

# 检查位置是否有建筑
static func has_structure_at(cells: Array, pos: Vector2i, grid_size: Vector2i) -> bool:
	var cell := get_cell(cells, pos, grid_size)
	assert(cell.has("structure") and (cell["structure"] is Dictionary), "MapBaker.has_structure_at: cell.structure 缺失或类型错误: %s" % str(pos))
	var structure: Dictionary = cell["structure"]
	return not structure.is_empty()

# 检查位置是否被阻塞
static func is_blocked_at(cells: Array, pos: Vector2i, grid_size: Vector2i) -> bool:
	var cell := get_cell(cells, pos, grid_size)
	assert(cell.has("blocked") and (cell["blocked"] is bool), "MapBaker.is_blocked_at: cell.blocked 缺失或类型错误: %s" % str(pos))
	return bool(cell["blocked"])

# 获取位置的饮品源
static func get_drink_source_at(cells: Array, pos: Vector2i, grid_size: Vector2i) -> Dictionary:
	var cell := get_cell(cells, pos, grid_size)
	assert(cell.has("drink_source"), "MapBaker.get_drink_source_at: cell.drink_source 缺失: %s" % str(pos))
	var source_val = cell["drink_source"]
	if source_val == null:
		return {}
	assert(source_val is Dictionary, "MapBaker.get_drink_source_at: cell.drink_source 类型错误（期望 Dictionary）: %s" % str(pos))
	return source_val

# === 调试 ===

static func dump_cells(cells: Array, grid_size: Vector2i) -> String:
	var output := "=== Map Cells (%dx%d) ===\n" % [grid_size.x, grid_size.y]

	# 道路层
	output += "Roads:\n"
	for y in grid_size.y:
			var row_str := ""
			for x in grid_size.x:
				var cell: Dictionary = cells[y][x]
				assert(cell.has("road_segments") and (cell["road_segments"] is Array), "MapBaker.dump_cells: cell.road_segments 缺失或类型错误 (%d,%d)" % [x, y])
				var segments: Array = cell["road_segments"]
				if segments.is_empty():
					row_str += "."
				else:
					# 显示第一个段的方向数
					var seg0 = segments[0]
					assert(seg0 is Dictionary and seg0.has("dirs") and (seg0["dirs"] is Array), "MapBaker.dump_cells: road_segments[0].dirs 缺失或类型错误 (%d,%d)" % [x, y])
					var dirs: Array = seg0["dirs"]
					row_str += str(dirs.size())
			output += "  %s\n" % row_str

	# 建筑层
	output += "Structures:\n"
	for y in grid_size.y:
			var row_str := ""
			for x in grid_size.x:
				var cell: Dictionary = cells[y][x]
				assert(cell.has("structure") and (cell["structure"] is Dictionary), "MapBaker.dump_cells: cell.structure 缺失或类型错误 (%d,%d)" % [x, y])
				var structure: Dictionary = cell["structure"]
				if structure.is_empty():
					row_str += "."
				else:
					assert(structure.has("anchor_cell") and (structure["anchor_cell"] is bool), "MapBaker.dump_cells: structure.anchor_cell 缺失或类型错误 (%d,%d)" % [x, y])
					row_str += "A" if bool(structure["anchor_cell"]) else "#"
			output += "  %s\n" % row_str

	return output
