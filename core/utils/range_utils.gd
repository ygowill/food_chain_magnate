# 距离/范围工具（去重模块）
# 负责：road/air range 判断、道路邻接格计算等可复用逻辑。
class_name RangeUtils
extends RefCounted

const MapRuntimeClass = preload("res://core/map/map_runtime.gd")

static func get_adjacent_road_cells(state: GameState, anchor: Vector2i) -> Result:
	if not (state.map is Dictionary):
		return Result.failure("state.map 类型错误（期望 Dictionary）")
	if not MapRuntimeClass.is_world_pos_in_grid(state, anchor):
		return Result.failure("anchor 越界: %s" % str(anchor))

	var cells: Array[Vector2i] = []
	if MapRuntimeClass.has_road_at(state, anchor):
		cells.append(anchor)

	for dir in MapUtils.DIRECTIONS:
		var neighbor := MapUtils.get_neighbor_pos(anchor, dir)
		if not MapRuntimeClass.is_world_pos_in_grid(state, neighbor):
			continue
		if MapRuntimeClass.has_road_at(state, neighbor) and not cells.has(neighbor):
			cells.append(neighbor)

	return Result.success(cells)

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

	var road_graph = MapRuntimeClass.get_road_graph(state)
	if road_graph == null:
		return Result.failure("道路图未初始化")

	if not (state.map is Dictionary):
		return Result.failure("state.map 类型错误（期望 Dictionary）")
	if not state.map.has("restaurants") or not (state.map["restaurants"] is Dictionary):
		return Result.failure("state.map.restaurants 缺失或类型错误")
	var restaurants: Dictionary = state.map["restaurants"]

	var target_cells_result := get_adjacent_road_cells(state, target_pos)
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

		var start_cells_result := get_adjacent_road_cells(state, entrance_pos)
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

static func is_within_air_range(
	state: GameState,
	actor: int,
	restaurant_ids: Array[String],
	target_pos: Vector2i,
	max_steps: int
) -> Result:
	if restaurant_ids.is_empty():
		return Result.failure("restaurant_ids 不能为空")
	if max_steps < 0:
		return Result.failure("max_steps 必须 >= 0")

	if not (state.map is Dictionary):
		return Result.failure("state.map 类型错误（期望 Dictionary）")
	if not state.map.has("restaurants") or not (state.map["restaurants"] is Dictionary):
		return Result.failure("state.map.restaurants 缺失或类型错误")
	var restaurants: Dictionary = state.map["restaurants"]

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

		var d: int = abs(entrance_pos.x - target_pos.x) + abs(entrance_pos.y - target_pos.y)
		if d <= max_steps:
			return Result.success(true)

	return Result.success(false)
