extends RefCounted

const MapRuntimeClass = preload("res://core/map/map_runtime.gd")

const MODULE_ID := "base_marketing"

func register(registrar) -> Result:
	var r: Result = registrar.register_marketing_type("billboard", {"requires_edge": false}, Callable(self, "_get_billboard_house_ids"))
	if not r.ok:
		return r
	r = registrar.register_marketing_type("mailbox", {"requires_edge": false}, Callable(self, "_get_mailbox_house_ids"))
	if not r.ok:
		return r
	r = registrar.register_marketing_type("radio", {"requires_edge": false}, Callable(self, "_get_radio_house_ids"))
	if not r.ok:
		return r
	r = registrar.register_marketing_type("airplane", {"requires_edge": true}, Callable(self, "_get_airplane_house_ids"))
	if not r.ok:
		return r

	return Result.success()

func _get_billboard_house_ids(state: GameState, marketing_instance: Dictionary) -> Result:
	if state == null:
		return Result.failure("%s: billboard range: state 为空" % MODULE_ID)
	if not (state.map is Dictionary):
		return Result.failure("%s: billboard range: state.map 类型错误（期望 Dictionary）" % MODULE_ID)
	var world_pos_read := _require_world_pos(marketing_instance, "billboard")
	if not world_pos_read.ok:
		return world_pos_read
	var world_pos: Vector2i = world_pos_read.value

	# 等同 core/MarketingRangeCalculator._get_adjacent_house_ids
	if not state.map.has("grid_size") or not (state.map["grid_size"] is Vector2i):
		return Result.failure("%s: billboard range: state.map.grid_size 缺失或类型错误（期望 Vector2i）" % MODULE_ID)
	var grid_size: Vector2i = state.map["grid_size"]
	if grid_size.x <= 0 or grid_size.y <= 0:
		return Result.failure("%s: billboard range: state.map.grid_size 非法: %s" % [MODULE_ID, str(grid_size)])
	if not state.map.has("cells") or not (state.map["cells"] is Array):
		return Result.failure("%s: billboard range: state.map.cells 缺失或类型错误（期望 Array）" % MODULE_ID)

	var set := {}
	for dir in MapUtils.DIRECTIONS:
		var n := MapUtils.get_neighbor_pos(world_pos, dir)
		if not MapRuntimeClass.is_world_pos_in_grid(state, n):
			continue
		var cell := MapRuntimeClass.get_cell(state, n)
		if not cell.has("structure") or not (cell["structure"] is Dictionary):
			return Result.failure("%s: billboard range: cell.structure 缺失或类型错误: %s" % [MODULE_ID, str(n)])
		var structure: Dictionary = cell["structure"]
		if not structure.has("house_id"):
			continue
		if not (structure["house_id"] is String):
			return Result.failure("%s: billboard range: structure.house_id 类型错误（期望 String）: %s" % [MODULE_ID, str(n)])
		var house_id: String = structure["house_id"]
		if not house_id.is_empty():
			set[house_id] = true
	return Result.success(_dict_keys_to_string_array(set))

func _get_mailbox_house_ids(state: GameState, marketing_instance: Dictionary) -> Result:
	if state == null:
		return Result.failure("%s: mailbox range: state 为空" % MODULE_ID)
	if not (state.map is Dictionary):
		return Result.failure("%s: mailbox range: state.map 类型错误（期望 Dictionary）" % MODULE_ID)
	var world_pos_read := _require_world_pos(marketing_instance, "mailbox")
	if not world_pos_read.ok:
		return world_pos_read
	var world_pos: Vector2i = world_pos_read.value

	# 等同 core/MarketingRangeCalculator._get_block_house_ids
	if not state.map.has("cells") or not (state.map["cells"] is Array):
		return Result.failure("%s: mailbox range: state.map.cells 缺失或类型错误（期望 Array）" % MODULE_ID)
	if not state.map.has("grid_size") or not (state.map["grid_size"] is Vector2i):
		return Result.failure("%s: mailbox range: state.map.grid_size 缺失或类型错误（期望 Vector2i）" % MODULE_ID)
	if not state.map.has("boundary_index") or not (state.map["boundary_index"] is Dictionary):
		return Result.failure("%s: mailbox range: state.map.boundary_index 缺失或类型错误（期望 Dictionary）" % MODULE_ID)

	var road_graph = MapRuntimeClass.get_road_graph(state)
	var block_cells: Array[Vector2i] = road_graph.get_block_cells(world_pos)
	if block_cells.is_empty():
		var empty: Array[String] = []
		return Result.success(empty)

	var set := {}
	for c in block_cells:
		var cell := MapRuntimeClass.get_cell(state, c)
		if not cell.has("structure") or not (cell["structure"] is Dictionary):
			return Result.failure("%s: mailbox range: cell.structure 缺失或类型错误: %s" % [MODULE_ID, str(c)])
		var structure: Dictionary = cell["structure"]
		if not structure.has("house_id"):
			continue
		if not (structure["house_id"] is String):
			return Result.failure("%s: mailbox range: structure.house_id 类型错误（期望 String）: %s" % [MODULE_ID, str(c)])
		var house_id: String = structure["house_id"]
		if not house_id.is_empty():
			set[house_id] = true

	return Result.success(_dict_keys_to_string_array(set))

func _get_radio_house_ids(state: GameState, marketing_instance: Dictionary) -> Result:
	if state == null:
		return Result.failure("%s: radio range: state 为空" % MODULE_ID)
	if not (state.map is Dictionary):
		return Result.failure("%s: radio range: state.map 类型错误（期望 Dictionary）" % MODULE_ID)
	var world_pos_read := _require_world_pos(marketing_instance, "radio")
	if not world_pos_read.ok:
		return world_pos_read
	var world_pos: Vector2i = world_pos_read.value

	# 等同 core/MarketingRangeCalculator._get_radio_house_ids
	if not state.map.has("grid_size") or not (state.map["grid_size"] is Vector2i):
		return Result.failure("%s: radio range: state.map.grid_size 缺失或类型错误（期望 Vector2i）" % MODULE_ID)
	var grid_size: Vector2i = state.map["grid_size"]
	if grid_size.x <= 0 or grid_size.y <= 0:
		return Result.failure("%s: radio range: state.map.grid_size 非法: %s" % [MODULE_ID, str(grid_size)])

	if not state.map.has("tile_grid_size") or not (state.map["tile_grid_size"] is Vector2i):
		return Result.failure("%s: radio range: state.map.tile_grid_size 缺失或类型错误（期望 Vector2i）" % MODULE_ID)
	var tile_grid_size: Vector2i = state.map["tile_grid_size"]
	if tile_grid_size.x <= 0 or tile_grid_size.y <= 0:
		return Result.failure("%s: radio range: state.map.tile_grid_size 非法: %s" % [MODULE_ID, str(tile_grid_size)])

	if not state.map.has("cells") or not (state.map["cells"] is Array):
		return Result.failure("%s: radio range: state.map.cells 缺失或类型错误（期望 Array）" % MODULE_ID)

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
						return Result.failure("%s: radio range: cell.structure 缺失或类型错误: %s" % [MODULE_ID, str(p)])
					var structure: Dictionary = cell["structure"]
					if not structure.has("house_id"):
						continue
					if not (structure["house_id"] is String):
						return Result.failure("%s: radio range: structure.house_id 类型错误（期望 String）: %s" % [MODULE_ID, str(p)])
					var house_id: String = structure["house_id"]
					if not house_id.is_empty():
						set[house_id] = true

	return Result.success(_dict_keys_to_string_array(set))

func _get_airplane_house_ids(state: GameState, marketing_instance: Dictionary) -> Result:
	if state == null:
		return Result.failure("%s: airplane range: state 为空" % MODULE_ID)
	if not (state.map is Dictionary):
		return Result.failure("%s: airplane range: state.map 类型错误（期望 Dictionary）" % MODULE_ID)
	var world_pos_read := _require_world_pos(marketing_instance, "airplane")
	if not world_pos_read.ok:
		return world_pos_read

	# 等同 core/MarketingRangeCalculator._get_airplane_house_ids
	if not state.map.has("grid_size") or not (state.map["grid_size"] is Vector2i):
		return Result.failure("%s: airplane range: state.map.grid_size 缺失或类型错误（期望 Vector2i）" % MODULE_ID)
	var grid_size: Vector2i = state.map["grid_size"]
	if grid_size.x <= 0 or grid_size.y <= 0:
		return Result.failure("%s: airplane range: state.map.grid_size 非法: %s" % [MODULE_ID, str(grid_size)])

	if not state.map.has("tile_grid_size") or not (state.map["tile_grid_size"] is Vector2i):
		return Result.failure("%s: airplane range: state.map.tile_grid_size 缺失或类型错误（期望 Vector2i）" % MODULE_ID)
	var tile_grid_size: Vector2i = state.map["tile_grid_size"]
	if tile_grid_size.x <= 0 or tile_grid_size.y <= 0:
		return Result.failure("%s: airplane range: state.map.tile_grid_size 非法: %s" % [MODULE_ID, str(tile_grid_size)])

	if not state.map.has("cells") or not (state.map["cells"] is Array):
		return Result.failure("%s: airplane range: state.map.cells 缺失或类型错误（期望 Array）" % MODULE_ID)

	if not marketing_instance.has("axis") or not (marketing_instance["axis"] is String):
		return Result.failure("%s: airplane range: marketing_instance.axis 缺失或类型错误（期望 String）" % MODULE_ID)
	var axis: String = marketing_instance["axis"]
	if axis != "row" and axis != "col":
		return Result.failure("%s: airplane range: marketing_instance.axis 非法（期望 row/col）: %s" % [MODULE_ID, axis])

	if not marketing_instance.has("tile_index") or not (marketing_instance["tile_index"] is int):
		return Result.failure("%s: airplane range: marketing_instance.tile_index 缺失或类型错误（期望 int）" % MODULE_ID)
	var tile_index: int = marketing_instance["tile_index"]

	var min_tile: Vector2i = MapUtils.world_to_tile(MapRuntimeClass.get_world_min(state)).board_pos
	var max_tile: Vector2i = MapUtils.world_to_tile(MapRuntimeClass.get_world_max(state)).board_pos

	if axis == "row":
		if tile_index < min_tile.y or tile_index > max_tile.y:
			return Result.failure("%s: airplane range: marketing_instance.tile_index 越界: %d (min=%d max=%d)" % [MODULE_ID, tile_index, min_tile.y, max_tile.y])
		return _collect_houses_in_tile_row(state, tile_grid_size, min_tile, tile_index)

	if tile_index < min_tile.x or tile_index > max_tile.x:
		return Result.failure("%s: airplane range: marketing_instance.tile_index 越界: %d (min=%d max=%d)" % [MODULE_ID, tile_index, min_tile.x, max_tile.x])
	return _collect_houses_in_tile_col(state, tile_grid_size, min_tile, tile_index)

func _collect_houses_in_tile_row(state: GameState, tile_grid_size: Vector2i, min_tile: Vector2i, tile_y: int) -> Result:
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
					return Result.failure("%s: airplane range: cell.structure 缺失或类型错误: %s" % [MODULE_ID, str(p)])
				var structure: Dictionary = cell["structure"]
				if not structure.has("house_id"):
					continue
				if not (structure["house_id"] is String):
					return Result.failure("%s: airplane range: structure.house_id 类型错误（期望 String）: %s" % [MODULE_ID, str(p)])
				var house_id: String = structure["house_id"]
				if not house_id.is_empty():
					set[house_id] = true
	return Result.success(_dict_keys_to_string_array(set))

func _collect_houses_in_tile_col(state: GameState, tile_grid_size: Vector2i, min_tile: Vector2i, tile_x: int) -> Result:
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
					return Result.failure("%s: airplane range: cell.structure 缺失或类型错误: %s" % [MODULE_ID, str(p)])
				var structure: Dictionary = cell["structure"]
				if not structure.has("house_id"):
					continue
				if not (structure["house_id"] is String):
					return Result.failure("%s: airplane range: structure.house_id 类型错误（期望 String）: %s" % [MODULE_ID, str(p)])
				var house_id: String = structure["house_id"]
				if not house_id.is_empty():
					set[house_id] = true
	return Result.success(_dict_keys_to_string_array(set))

static func _dict_keys_to_string_array(dict: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for k in dict.keys():
		result.append(str(k))
	return result

static func _require_world_pos(marketing_instance: Dictionary, type_id: String) -> Result:
	if marketing_instance == null or not (marketing_instance is Dictionary):
		return Result.failure("%s: %s range: marketing_instance 类型错误（期望 Dictionary）" % [MODULE_ID, type_id])
	if not marketing_instance.has("world_pos") or not (marketing_instance["world_pos"] is Vector2i):
		return Result.failure("%s: %s range: marketing_instance.world_pos 缺失或类型错误（期望 Vector2i）" % [MODULE_ID, type_id])
	return Result.success(marketing_instance["world_pos"])

