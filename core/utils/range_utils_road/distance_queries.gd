extends RefCounted

const CellsClass = preload("res://core/map/map_runtime/cells.gd")
const RoadGraphCacheClass = preload("res://core/map/map_runtime/road_graph_cache.gd")
const AdjacentCellsClass = preload("res://core/utils/range_utils_road/adjacent_cells.gd")

static func is_within_road_range_to_any_road_cells(
	state: GameState,
	actor: int,
	restaurant_ids: Array[String],
	target_road_cells: Array[Vector2i],
	max_distance: int
) -> Result:
	if restaurant_ids.is_empty():
		return Result.failure("restaurant_ids 不能为空")
	if max_distance < 0:
		return Result.failure("max_distance 必须 >= 0")
	if target_road_cells == null:
		return Result.failure("target_road_cells 为空")
	if target_road_cells.is_empty():
		return Result.success(false)

	var min_r: Result = get_min_road_distance_to_any_road_cells(state, actor, restaurant_ids, target_road_cells)
	if not min_r.ok:
		return min_r
	var min_d: int = int(min_r.value)
	return Result.success(min_d >= 0 and min_d <= max_distance)

static func get_min_road_distance_to_any_road_cells(
	state: GameState,
	actor: int,
	restaurant_ids: Array[String],
	target_road_cells: Array[Vector2i]
) -> Result:
	if restaurant_ids.is_empty():
		return Result.failure("restaurant_ids 不能为空")
	if target_road_cells == null:
		return Result.failure("target_road_cells 为空")
	if target_road_cells.is_empty():
		return Result.success(-1)

	var road_graph = RoadGraphCacheClass.get_road_graph(state)
	if road_graph == null:
		return Result.failure("道路图未初始化")

	if not (state.map is Dictionary):
		return Result.failure("state.map 类型错误（期望 Dictionary）")
	if not state.map.has("restaurants") or not (state.map["restaurants"] is Dictionary):
		return Result.failure("state.map.restaurants 缺失或类型错误")
	var restaurants: Dictionary = state.map["restaurants"]

	var targets: Array[Vector2i] = []
	var target_set := {}
	for i in range(target_road_cells.size()):
		var v = target_road_cells[i]
		if not (v is Vector2i):
			return Result.failure("target_road_cells[%d] 类型错误（期望 Vector2i）" % i)
		var p: Vector2i = v
		if target_set.has(p):
			continue
		target_set[p] = true
		if not CellsClass.has_cell_any(state, p):
			continue
		if not CellsClass.has_road_at_any(state, p):
			continue
		targets.append(p)
	if targets.is_empty():
		return Result.success(-1)

	# 免下车：本回合餐厅四角都视为入口（对齐 docs/rules.md 与 DinnertimeDistance）。
	# 若开启，则“起点道路格”取所有入口点邻接道路的并集。
	var drive_thru_active := false
	if state.players is Array and actor >= 0 and actor < (state.players as Array).size():
		var p_val = (state.players as Array)[actor]
		if p_val is Dictionary:
			var dt_val = (p_val as Dictionary).get("drive_thru_active", false)
			if dt_val is bool:
				drive_thru_active = bool(dt_val)
			else:
				return Result.failure("player[%d].drive_thru_active 类型错误（期望 bool）" % actor)
		else:
			return Result.failure("players[%d] 类型错误（期望 Dictionary）" % actor)
	else:
		return Result.failure("state.players 缺失或 actor 越界: %d" % actor)

	var best := -1
	for rest_id in restaurant_ids:
		if not restaurants.has(rest_id):
			return Result.failure("餐厅不存在: %s" % rest_id)
		var rest: Dictionary = restaurants[rest_id]
		if not rest.has("owner") or not (rest["owner"] is int):
			return Result.failure("餐厅 %s 缺少 owner 或类型错误" % rest_id)
		if int(rest["owner"]) != actor:
			return Result.failure("餐厅 %s 不属于玩家 %d" % [rest_id, actor])
		if not rest.has("entrance_pos") or not (rest["entrance_pos"] is Vector2i):
			return Result.failure("餐厅 %s 缺少 entrance_pos 或类型错误" % rest_id)
		var entrance_pos: Vector2i = rest["entrance_pos"]

		var entrance_points: Array[Vector2i] = []
		if drive_thru_active and rest.has("cells") and (rest["cells"] is Array) and not (rest["cells"] as Array).is_empty():
			var cells_any: Array = rest["cells"]
			var cells: Array[Vector2i] = []
			for i in range(cells_any.size()):
				var c = cells_any[i]
				if not (c is Vector2i):
					return Result.failure("餐厅 %s cells[%d] 类型错误（期望 Vector2i）" % [rest_id, i])
				cells.append(c)
			var bounds := MapUtils.get_footprint_bounds(cells)
			if not bounds.has("min") or not (bounds["min"] is Vector2i) or not bounds.has("max") or not (bounds["max"] is Vector2i):
				return Result.failure("餐厅 %s footprint_bounds 计算失败" % rest_id)
			var min_pos: Vector2i = bounds["min"]
			var max_pos: Vector2i = bounds["max"]
			entrance_points = [
				Vector2i(min_pos.x, min_pos.y),
				Vector2i(max_pos.x, min_pos.y),
				Vector2i(min_pos.x, max_pos.y),
				Vector2i(max_pos.x, max_pos.y),
			]
		else:
			entrance_points = [entrance_pos]

		var start_road_set := {}
		for ep in entrance_points:
			var start_cells_result: Result = AdjacentCellsClass.get_adjacent_road_cells(state, ep)
			if not start_cells_result.ok:
				return start_cells_result
			var start_road_cells_one: Array[Vector2i] = start_cells_result.value
			for s2 in start_road_cells_one:
				start_road_set[s2] = true

		var start_road_cells: Array[Vector2i] = []
		for k in start_road_set.keys():
			if k is Vector2i:
				start_road_cells.append(k)
		if start_road_cells.is_empty():
			return Result.failure("餐厅入口未邻接道路: %s" % rest_id)

		for s in start_road_cells:
			for t in targets:
				var d: int = int(road_graph.get_distance(s, t))
				if d < 0:
					continue
				if best < 0 or d < best:
					best = d
					if best == 0:
						return Result.success(0)

	return Result.success(best)

static func is_within_road_range(
	state: GameState,
	actor: int,
	restaurant_ids: Array[String],
	target_pos: Vector2i,
	max_distance: int
) -> Result:
	if restaurant_ids.is_empty():
		return Result.failure("restaurant_ids 不能为空")
	if max_distance < 0:
		return Result.failure("max_distance 必须 >= 0")

	var road_graph = RoadGraphCacheClass.get_road_graph(state)
	if road_graph == null:
		return Result.failure("道路图未初始化")

	if not (state.map is Dictionary):
		return Result.failure("state.map 类型错误（期望 Dictionary）")
	if not state.map.has("restaurants") or not (state.map["restaurants"] is Dictionary):
		return Result.failure("state.map.restaurants 缺失或类型错误")
	var restaurants: Dictionary = state.map["restaurants"]

	var target_cells_result: Result = AdjacentCellsClass.get_adjacent_road_cells(state, target_pos)
	if not target_cells_result.ok:
		return target_cells_result
	var target_road_cells: Array[Vector2i] = target_cells_result.value
	if target_road_cells.is_empty():
		return Result.success(false)

	for rest_id in restaurant_ids:
		if not restaurants.has(rest_id):
			return Result.failure("餐厅不存在: %s" % rest_id)
		var rest: Dictionary = restaurants[rest_id]
		if not rest.has("owner") or not (rest["owner"] is int):
			return Result.failure("餐厅 %s 缺少 owner 或类型错误" % rest_id)
		if int(rest["owner"]) != actor:
			return Result.failure("餐厅 %s 不属于玩家 %d" % [rest_id, actor])
		if not rest.has("entrance_pos") or not (rest["entrance_pos"] is Vector2i):
			return Result.failure("餐厅 %s 缺少 entrance_pos 或类型错误" % rest_id)
		var entrance_pos: Vector2i = rest["entrance_pos"]

		var start_cells_result: Result = AdjacentCellsClass.get_adjacent_road_cells(state, entrance_pos)
		if not start_cells_result.ok:
			return start_cells_result
		var start_road_cells: Array[Vector2i] = start_cells_result.value
		if start_road_cells.is_empty():
			return Result.failure("餐厅入口未邻接道路: %s" % rest_id)

		for s in start_road_cells:
			for t in target_road_cells:
				var d: int = int(road_graph.get_distance(s, t))
				if d >= 0 and d <= max_distance:
					return Result.success(true)

	return Result.success(false)

