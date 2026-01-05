# 营销范围计算器（M4）
# 目标：将“营销板件 -> 受影响房屋集合”的算法从 PhaseManager 抽离，便于后续模块系统插拔。
class_name MarketingRangeCalculator
extends RefCounted

const MapRuntimeClass = preload("res://core/map/map_runtime.gd")
const MarketingTypeRegistryClass = preload("res://core/rules/marketing_type_registry.gd")

func get_affected_house_ids(state: GameState, marketing_instance: Dictionary) -> Result:
	if state == null:
		return Result.failure("MarketingRangeCalculator: state 为空")
	if not (state.map is Dictionary):
		return Result.failure("MarketingRangeCalculator: state.map 类型错误（期望 Dictionary）")
	if not (marketing_instance is Dictionary):
		return Result.failure("MarketingRangeCalculator: marketing_instance 类型错误（期望 Dictionary）")

	if not marketing_instance.has("type") or not (marketing_instance["type"] is String):
		return Result.failure("MarketingRangeCalculator: marketing_instance.type 缺失或类型错误（期望 String）")
	var marketing_type: String = marketing_instance["type"]
	if marketing_type.is_empty():
		return Result.failure("MarketingRangeCalculator: marketing_instance.type 不能为空")

	if not marketing_instance.has("world_pos") or not (marketing_instance["world_pos"] is Vector2i):
		return Result.failure("MarketingRangeCalculator: marketing_instance.world_pos 缺失或类型错误（期望 Vector2i）")
	var world_pos: Vector2i = marketing_instance["world_pos"]

	match marketing_type:
		"billboard":
			return _get_adjacent_house_ids(state, world_pos)
		"mailbox":
			return _get_block_house_ids(state, world_pos)
		"radio":
			return _get_radio_house_ids(state, world_pos)
		"airplane":
			return _get_airplane_house_ids(state, marketing_instance, world_pos)
		_:
			var handler := MarketingTypeRegistryClass.get_range_handler(marketing_type)
			if not handler.is_valid():
				return Result.failure("MarketingRangeCalculator: 未知的 marketing type: %s" % marketing_type)
			var r = handler.call(state, marketing_instance)
			if not (r is Result):
				return Result.failure("MarketingRangeCalculator: marketing type handler 必须返回 Result: %s" % marketing_type)
			return r

func _get_adjacent_house_ids(state: GameState, world_pos: Vector2i) -> Result:
	if not state.map.has("grid_size") or not (state.map["grid_size"] is Vector2i):
		return Result.failure("MarketingRangeCalculator: state.map.grid_size 缺失或类型错误（期望 Vector2i）")
	var grid_size: Vector2i = state.map["grid_size"]
	if grid_size.x <= 0 or grid_size.y <= 0:
		return Result.failure("MarketingRangeCalculator: state.map.grid_size 非法: %s" % str(grid_size))
	if not state.map.has("cells") or not (state.map["cells"] is Array):
		return Result.failure("MarketingRangeCalculator: state.map.cells 缺失或类型错误（期望 Array）")

	var set := {}
	for dir in MapUtils.DIRECTIONS:
		var n := MapUtils.get_neighbor_pos(world_pos, dir)
		if not MapRuntimeClass.is_world_pos_in_grid(state, n):
			continue
		var cell := MapRuntimeClass.get_cell(state, n)
		if not cell.has("structure") or not (cell["structure"] is Dictionary):
			return Result.failure("MarketingRangeCalculator: cell.structure 缺失或类型错误: %s" % str(n))
		var structure: Dictionary = cell["structure"]
		if not structure.has("house_id"):
			continue
		if not (structure["house_id"] is String):
			return Result.failure("MarketingRangeCalculator: structure.house_id 类型错误（期望 String）: %s" % str(n))
		var house_id: String = structure["house_id"]
		if not house_id.is_empty():
			set[house_id] = true
	return Result.success(_dict_keys_to_string_array(set))

func _get_block_house_ids(state: GameState, world_pos: Vector2i) -> Result:
	if not state.map.has("cells") or not (state.map["cells"] is Array):
		return Result.failure("MarketingRangeCalculator: state.map.cells 缺失或类型错误（期望 Array）")
	if not state.map.has("grid_size") or not (state.map["grid_size"] is Vector2i):
		return Result.failure("MarketingRangeCalculator: state.map.grid_size 缺失或类型错误（期望 Vector2i）")
	if not state.map.has("boundary_index") or not (state.map["boundary_index"] is Dictionary):
		return Result.failure("MarketingRangeCalculator: state.map.boundary_index 缺失或类型错误（期望 Dictionary）")

	var road_graph = MapRuntimeClass.get_road_graph(state)
	var block_cells: Array[Vector2i] = road_graph.get_block_cells(world_pos)
	if block_cells.is_empty():
		var empty: Array[String] = []
		return Result.success(empty)
	var set := {}
	for c in block_cells:
		var cell := MapRuntimeClass.get_cell(state, c)
		if not cell.has("structure") or not (cell["structure"] is Dictionary):
			return Result.failure("MarketingRangeCalculator: cell.structure 缺失或类型错误: %s" % str(c))
		var structure: Dictionary = cell["structure"]
		if not structure.has("house_id"):
			continue
		if not (structure["house_id"] is String):
			return Result.failure("MarketingRangeCalculator: structure.house_id 类型错误（期望 String）: %s" % str(c))
		var house_id: String = structure["house_id"]
		if not house_id.is_empty():
			set[house_id] = true
	return Result.success(_dict_keys_to_string_array(set))

func _get_radio_house_ids(state: GameState, world_pos: Vector2i) -> Result:
	if not state.map.has("grid_size") or not (state.map["grid_size"] is Vector2i):
		return Result.failure("MarketingRangeCalculator: state.map.grid_size 缺失或类型错误（期望 Vector2i）")
	var grid_size: Vector2i = state.map["grid_size"]
	if grid_size.x <= 0 or grid_size.y <= 0:
		return Result.failure("MarketingRangeCalculator: state.map.grid_size 非法: %s" % str(grid_size))

	if not state.map.has("tile_grid_size") or not (state.map["tile_grid_size"] is Vector2i):
		return Result.failure("MarketingRangeCalculator: state.map.tile_grid_size 缺失或类型错误（期望 Vector2i）")
	var tile_grid_size: Vector2i = state.map["tile_grid_size"]
	if tile_grid_size.x <= 0 or tile_grid_size.y <= 0:
		return Result.failure("MarketingRangeCalculator: state.map.tile_grid_size 非法: %s" % str(tile_grid_size))

	if not state.map.has("cells") or not (state.map["cells"] is Array):
		return Result.failure("MarketingRangeCalculator: state.map.cells 缺失或类型错误（期望 Array）")

	var min_tile: Vector2i = MapUtils.world_to_tile(MapRuntimeClass.get_world_min(state)).board_pos
	var max_tile: Vector2i = MapUtils.world_to_tile(MapRuntimeClass.get_world_max(state)).board_pos
	var tile_pos: Vector2i = MapUtils.world_to_tile(world_pos).board_pos

	var min_tx := maxi(min_tile.x, tile_pos.x - 1)
	var max_tx := mini(max_tile.x, tile_pos.x + 1)
	var min_ty := maxi(min_tile.y, tile_pos.y - 1)
	var max_ty := mini(max_tile.y, tile_pos.y + 1)

	var set := {}
	for ty in range(min_ty, max_ty + 1):
		for tx in range(min_tx, max_tx + 1):
			var base := Vector2i(tx * MapUtils.TILE_SIZE, ty * MapUtils.TILE_SIZE)
			for y in range(base.y, base.y + MapUtils.TILE_SIZE):
				for x in range(base.x, base.x + MapUtils.TILE_SIZE):
					var p := Vector2i(x, y)
					if not MapRuntimeClass.is_world_pos_in_grid(state, p):
						continue
					var cell := MapRuntimeClass.get_cell(state, p)
					if not cell.has("structure") or not (cell["structure"] is Dictionary):
						return Result.failure("MarketingRangeCalculator: cell.structure 缺失或类型错误: %s" % str(p))
					var structure: Dictionary = cell["structure"]
					if not structure.has("house_id"):
						continue
					if not (structure["house_id"] is String):
						return Result.failure("MarketingRangeCalculator: structure.house_id 类型错误（期望 String）: %s" % str(p))
					var house_id: String = structure["house_id"]
					if not house_id.is_empty():
						set[house_id] = true

	return Result.success(_dict_keys_to_string_array(set))

func _get_airplane_house_ids(state: GameState, marketing_instance: Dictionary, _world_pos: Vector2i) -> Result:
	if not state.map.has("grid_size") or not (state.map["grid_size"] is Vector2i):
		return Result.failure("MarketingRangeCalculator: state.map.grid_size 缺失或类型错误（期望 Vector2i）")
	var grid_size: Vector2i = state.map["grid_size"]
	if grid_size.x <= 0 or grid_size.y <= 0:
		return Result.failure("MarketingRangeCalculator: state.map.grid_size 非法: %s" % str(grid_size))

	if not state.map.has("tile_grid_size") or not (state.map["tile_grid_size"] is Vector2i):
		return Result.failure("MarketingRangeCalculator: state.map.tile_grid_size 缺失或类型错误（期望 Vector2i）")
	var tile_grid_size: Vector2i = state.map["tile_grid_size"]
	if tile_grid_size.x <= 0 or tile_grid_size.y <= 0:
		return Result.failure("MarketingRangeCalculator: state.map.tile_grid_size 非法: %s" % str(tile_grid_size))

	if not state.map.has("cells") or not (state.map["cells"] is Array):
		return Result.failure("MarketingRangeCalculator: state.map.cells 缺失或类型错误（期望 Array）")

	if not marketing_instance.has("axis") or not (marketing_instance["axis"] is String):
		return Result.failure("MarketingRangeCalculator: marketing_instance.axis 缺失或类型错误（期望 String）")
	var axis: String = marketing_instance["axis"]
	if axis != "row" and axis != "col":
		return Result.failure("MarketingRangeCalculator: marketing_instance.axis 非法（期望 row/col）: %s" % axis)

	if not marketing_instance.has("tile_index") or not (marketing_instance["tile_index"] is int):
		return Result.failure("MarketingRangeCalculator: marketing_instance.tile_index 缺失或类型错误（期望 int）")
	var tile_index: int = marketing_instance["tile_index"]

	var min_tile: Vector2i = MapUtils.world_to_tile(MapRuntimeClass.get_world_min(state)).board_pos
	var max_tile: Vector2i = MapUtils.world_to_tile(MapRuntimeClass.get_world_max(state)).board_pos

	if axis == "row":
		if tile_index < min_tile.y or tile_index > max_tile.y:
			return Result.failure("MarketingRangeCalculator: marketing_instance.tile_index 越界: %d (min=%d max=%d)" % [tile_index, min_tile.y, max_tile.y])
		return _collect_houses_in_tile_row(state, tile_grid_size, min_tile, tile_index)

	if tile_index < min_tile.x or tile_index > max_tile.x:
		return Result.failure("MarketingRangeCalculator: marketing_instance.tile_index 越界: %d (min=%d max=%d)" % [tile_index, min_tile.x, max_tile.x])
	return _collect_houses_in_tile_col(state, tile_grid_size, min_tile, tile_index)

func _collect_houses_in_tile_row(state: GameState, tile_grid_size: Vector2i, min_tile: Vector2i, tile_y: int) -> Result:
	if not state.map.has("grid_size") or not (state.map["grid_size"] is Vector2i):
		return Result.failure("MarketingRangeCalculator: state.map.grid_size 缺失或类型错误（期望 Vector2i）")
	var grid_size: Vector2i = state.map["grid_size"]
	var set := {}
	for tdx in range(tile_grid_size.x):
		var tx := min_tile.x + tdx
		var base := Vector2i(tx * MapUtils.TILE_SIZE, tile_y * MapUtils.TILE_SIZE)
		for y in range(base.y, base.y + MapUtils.TILE_SIZE):
			for x in range(base.x, base.x + MapUtils.TILE_SIZE):
				var p := Vector2i(x, y)
				if not MapRuntimeClass.is_world_pos_in_grid(state, p):
					continue
				var cell := MapRuntimeClass.get_cell(state, p)
				if not cell.has("structure") or not (cell["structure"] is Dictionary):
					return Result.failure("MarketingRangeCalculator: cell.structure 缺失或类型错误: %s" % str(p))
				var structure: Dictionary = cell["structure"]
				if not structure.has("house_id"):
					continue
				if not (structure["house_id"] is String):
					return Result.failure("MarketingRangeCalculator: structure.house_id 类型错误（期望 String）: %s" % str(p))
				var house_id: String = structure["house_id"]
				if not house_id.is_empty():
					set[house_id] = true
	return Result.success(_dict_keys_to_string_array(set))

func _collect_houses_in_tile_col(state: GameState, tile_grid_size: Vector2i, min_tile: Vector2i, tile_x: int) -> Result:
	if not state.map.has("grid_size") or not (state.map["grid_size"] is Vector2i):
		return Result.failure("MarketingRangeCalculator: state.map.grid_size 缺失或类型错误（期望 Vector2i）")
	var grid_size: Vector2i = state.map["grid_size"]
	var set := {}
	for tdy in range(tile_grid_size.y):
		var ty := min_tile.y + tdy
		var base := Vector2i(tile_x * MapUtils.TILE_SIZE, ty * MapUtils.TILE_SIZE)
		for y in range(base.y, base.y + MapUtils.TILE_SIZE):
			for x in range(base.x, base.x + MapUtils.TILE_SIZE):
				var p := Vector2i(x, y)
				if not MapRuntimeClass.is_world_pos_in_grid(state, p):
					continue
				var cell := MapRuntimeClass.get_cell(state, p)
				if not cell.has("structure") or not (cell["structure"] is Dictionary):
					return Result.failure("MarketingRangeCalculator: cell.structure 缺失或类型错误: %s" % str(p))
				var structure: Dictionary = cell["structure"]
				if not structure.has("house_id"):
					continue
				if not (structure["house_id"] is String):
					return Result.failure("MarketingRangeCalculator: structure.house_id 类型错误（期望 String）: %s" % str(p))
				var house_id: String = structure["house_id"]
				if not house_id.is_empty():
					set[house_id] = true
	return Result.success(_dict_keys_to_string_array(set))

func _dict_keys_to_string_array(dict: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for k in dict.keys():
		result.append(str(k))
	return result
