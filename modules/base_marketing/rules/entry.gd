extends RefCounted

const CellsClass = preload("res://core/map/map_runtime/cells.gd")
const CoordsClass = preload("res://core/map/map_runtime/coords.gd")
const RoadGraphCacheClass = preload("res://core/map/map_runtime/road_graph_cache.gd")
const MapStateAccessClass = preload("res://core/state/map_state_access.gd")

const MODULE_ID := "base_marketing"

func register(registrar) -> Result:
	var types := [
		{"marketing_type": "billboard", "cfg": {"requires_edge": false}, "fn": Callable(self, "_get_billboard_house_ids")},
		{"marketing_type": "mailbox", "cfg": {"requires_edge": false}, "fn": Callable(self, "_get_mailbox_house_ids")},
		{"marketing_type": "radio", "cfg": {"requires_edge": false}, "fn": Callable(self, "_get_radio_house_ids")},
		{"marketing_type": "airplane", "cfg": {"requires_edge": true}, "fn": Callable(self, "_get_airplane_house_ids")},
	]
	for t_val in types:
		assert(t_val is Dictionary, "%s: marketing types 元素类型错误（期望 Dictionary）" % MODULE_ID)
		var t: Dictionary = t_val
		var mt := str(t.get("marketing_type", ""))
		var cfg := Dictionary(t.get("cfg", {}))
		var fn_val = t.get("fn", null)
		assert(fn_val is Callable, "%s: marketing types fn 类型错误（期望 Callable）" % MODULE_ID)
		var fn: Callable = fn_val
		var r: Result = registrar.register_marketing_type(mt, cfg, fn)
		if not r.ok:
			return r
	return Result.success()

func _require_state_map(state: GameState, label: String) -> Result:
	return MapStateAccessClass.require_map(state, "%s: %s" % [MODULE_ID, label])

func _get_billboard_house_ids(state: GameState, marketing_instance: Dictionary) -> Result:
	var map_read := _require_state_map(state, "billboard range")
	if not map_read.ok:
		return map_read
	var world_pos_read := _require_world_pos(marketing_instance, "billboard")
	if not world_pos_read.ok:
		return world_pos_read
	var world_pos: Vector2i = world_pos_read.value

	# 等同 core/MarketingRangeCalculator._get_adjacent_house_ids
	var grid_size_read := MapStateAccessClass.require_grid_size(state, "%s: billboard range" % MODULE_ID)
	if not grid_size_read.ok:
		return grid_size_read
	var grid_size: Vector2i = grid_size_read.value
	if grid_size.x <= 0 or grid_size.y <= 0:
		return Result.failure("%s: billboard range: state.map.grid_size 非法: %s" % [MODULE_ID, str(grid_size)])
	var cells_read := MapStateAccessClass.require_cells(state, "%s: billboard range" % MODULE_ID)
	if not cells_read.ok:
		return cells_read

	var set := {}
	for dir in MapUtils.DIRECTIONS:
		var n := MapUtils.get_neighbor_pos(world_pos, dir)
		if not CoordsClass.is_world_pos_in_grid(state, n):
			continue
		var cell := CellsClass.get_cell(state, n)
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
	var map_read := _require_state_map(state, "mailbox range")
	if not map_read.ok:
		return map_read
	var world_pos_read := _require_world_pos(marketing_instance, "mailbox")
	if not world_pos_read.ok:
		return world_pos_read
	var world_pos: Vector2i = world_pos_read.value

	# 等同 core/MarketingRangeCalculator._get_block_house_ids
	var cells_read := MapStateAccessClass.require_cells(state, "%s: mailbox range" % MODULE_ID)
	if not cells_read.ok:
		return cells_read
	var grid_size_read := MapStateAccessClass.require_grid_size(state, "%s: mailbox range" % MODULE_ID)
	if not grid_size_read.ok:
		return grid_size_read
	var boundary_read := MapStateAccessClass.require_boundary_index(state, "%s: mailbox range" % MODULE_ID)
	if not boundary_read.ok:
		return boundary_read

	var road_graph = RoadGraphCacheClass.get_road_graph(state)
	var block_cells: Array[Vector2i] = road_graph.get_block_cells(world_pos)
	if block_cells.is_empty():
		var empty: Array[String] = []
		return Result.success(empty)

	var set := {}
	for c in block_cells:
		var cell := CellsClass.get_cell(state, c)
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
	var map_read := _require_state_map(state, "radio range")
	if not map_read.ok:
		return map_read
	var world_pos_read := _require_world_pos(marketing_instance, "radio")
	if not world_pos_read.ok:
		return world_pos_read
	var world_pos: Vector2i = world_pos_read.value

	# 等同 core/MarketingRangeCalculator._get_radio_house_ids
	var grid_size_read := MapStateAccessClass.require_grid_size(state, "%s: radio range" % MODULE_ID)
	if not grid_size_read.ok:
		return grid_size_read
	var grid_size: Vector2i = grid_size_read.value
	if grid_size.x <= 0 or grid_size.y <= 0:
		return Result.failure("%s: radio range: state.map.grid_size 非法: %s" % [MODULE_ID, str(grid_size)])

	var tile_grid_size_read := MapStateAccessClass.require_tile_grid_size(state, "%s: radio range" % MODULE_ID)
	if not tile_grid_size_read.ok:
		return tile_grid_size_read
	var tile_grid_size: Vector2i = tile_grid_size_read.value
	if tile_grid_size.x <= 0 or tile_grid_size.y <= 0:
		return Result.failure("%s: radio range: state.map.tile_grid_size 非法: %s" % [MODULE_ID, str(tile_grid_size)])

	var cells_read := MapStateAccessClass.require_cells(state, "%s: radio range" % MODULE_ID)
	if not cells_read.ok:
		return cells_read

	var min_tile: Vector2i = MapUtils.world_to_tile(CoordsClass.get_world_min(state)).board_pos
	var max_tile: Vector2i = MapUtils.world_to_tile(CoordsClass.get_world_max(state)).board_pos
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
					if not CoordsClass.is_world_pos_in_grid(state, p):
						continue
					var cell := CellsClass.get_cell(state, p)
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
	var map_read := _require_state_map(state, "airplane range")
	if not map_read.ok:
		return map_read
	var world_pos_read := _require_world_pos(marketing_instance, "airplane")
	if not world_pos_read.ok:
		return world_pos_read
	var world_pos: Vector2i = world_pos_read.value

	# Airplane range (issue_tracker #42):
	# - Airplanes are placed outside the board.
	# - Their length (1/3/5) indicates how many rows/cols they fly over ON the board.
	# - The affected area is a stripe spanning the entire board width/height.
	var grid_size_read := MapStateAccessClass.require_grid_size(state, "%s: airplane range" % MODULE_ID)
	if not grid_size_read.ok:
		return grid_size_read
	var grid_size: Vector2i = grid_size_read.value
	if grid_size.x <= 0 or grid_size.y <= 0:
		return Result.failure("%s: airplane range: state.map.grid_size 非法: %s" % [MODULE_ID, str(grid_size)])

	var cells_read := MapStateAccessClass.require_cells(state, "%s: airplane range" % MODULE_ID)
	if not cells_read.ok:
		return cells_read

	if not marketing_instance.has("axis") or not (marketing_instance["axis"] is String):
		return Result.failure("%s: airplane range: marketing_instance.axis 缺失或类型错误（期望 String）" % MODULE_ID)
	var axis: String = marketing_instance["axis"]
	if axis != "row" and axis != "col":
		return Result.failure("%s: airplane range: marketing_instance.axis 非法（期望 row/col）: %s" % [MODULE_ID, axis])

	# footprint_size is stored by initiate_marketing.apply; allow fallback to 1x1 for older data.
	var fs := Vector2i.ONE
	var fs_val = marketing_instance.get("footprint_size", null)
	if fs_val is Vector2i:
		fs = Vector2i(fs_val)
	elif fs_val is Array:
		var arr: Array = fs_val
		if arr.size() == 2:
			fs = Vector2i(int(arr[0]), int(arr[1]))
	if fs.x <= 0 or fs.y <= 0:
		fs = Vector2i.ONE

	var thickness := 2
	var length := 0
	if fs.x == 2 and fs.y != 2:
		length = fs.y
	elif fs.y == 2 and fs.x != 2:
		length = fs.x
	else:
		thickness = mini(fs.x, fs.y)
		length = maxi(fs.x, fs.y)

	if length <= 0:
		return Result.failure("%s: airplane range: footprint_size 非法: %s" % [MODULE_ID, str(fs)])

	var minp := CoordsClass.get_world_min(state)
	var maxp := CoordsClass.get_world_max(state)

	# Validate stripe stays inside the board (do not clamp silently; fail fast in strict mode).
	if axis == "row":
		var start_y := world_pos.y
		if start_y < minp.y or (start_y + length - 1) > maxp.y:
			return Result.failure("%s: airplane range: 飞行区越界: start_y=%d len=%d (min=%d max=%d)" % [MODULE_ID, start_y, length, minp.y, maxp.y])
	else:
		var start_x := world_pos.x
		if start_x < minp.x or (start_x + length - 1) > maxp.x:
			return Result.failure("%s: airplane range: 飞行区越界: start_x=%d len=%d (min=%d max=%d)" % [MODULE_ID, start_x, length, minp.x, maxp.x])

	var set := {}
	if axis == "row":
		for dy in range(length):
			var y := world_pos.y + dy
			for x in range(minp.x, maxp.x + 1):
				var p := Vector2i(x, y)
				if not CoordsClass.is_world_pos_in_grid(state, p):
					continue
				var cell := CellsClass.get_cell(state, p)
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

	for dx in range(length):
		var x2 := world_pos.x + dx
		for y2 in range(minp.y, maxp.y + 1):
			var p2 := Vector2i(x2, y2)
			if not CoordsClass.is_world_pos_in_grid(state, p2):
				continue
			var cell2 := CellsClass.get_cell(state, p2)
			if not cell2.has("structure") or not (cell2["structure"] is Dictionary):
				return Result.failure("%s: airplane range: cell.structure 缺失或类型错误: %s" % [MODULE_ID, str(p2)])
			var structure2: Dictionary = cell2["structure"]
			if not structure2.has("house_id"):
				continue
			if not (structure2["house_id"] is String):
				return Result.failure("%s: airplane range: structure.house_id 类型错误（期望 String）: %s" % [MODULE_ID, str(p2)])
			var house_id2: String = structure2["house_id"]
			if not house_id2.is_empty():
				set[house_id2] = true

	return Result.success(_dict_keys_to_string_array(set))

func _collect_houses_in_tile_row(state: GameState, tile_grid_size: Vector2i, min_tile: Vector2i, tile_y: int) -> Result:
	var set := {}
	for tdx in range(tile_grid_size.x):
		var tx := min_tile.x + tdx
		var base := Vector2i(tx * MapUtils.TILE_SIZE, tile_y * MapUtils.TILE_SIZE)
		for y in range(base.y, base.y + MapUtils.TILE_SIZE):
			for x in range(base.x, base.x + MapUtils.TILE_SIZE):
				var p := Vector2i(x, y)
				if not CoordsClass.is_world_pos_in_grid(state, p):
					continue
				var cell := CellsClass.get_cell(state, p)
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
				if not CoordsClass.is_world_pos_in_grid(state, p):
					continue
				var cell := CellsClass.get_cell(state, p)
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
