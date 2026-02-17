# Game scene：Working/Drinks Procurement（road procure）帮助函数
# 拆分自：`game_panel_working_drinks_procurement_controller.gd`
extends RefCounted

const StructuresClass = preload("res://core/map/map_runtime/structures.gd")
const DrinksProcurementClass = preload("res://core/rules/drinks_procurement.gd")
const RoadGraphCacheClass = preload("res://core/map/map_runtime/road_graph_cache.gd")
const RangeUtilsClass = preload("res://core/utils/range_utils.gd")

static func build_road_route(state: GameState, entrance_pos: Vector2i, sources: Array[Vector2i]) -> Result:
	var road_graph = RoadGraphCacheClass.get_road_graph(state)
	if road_graph == null:
		return Result.failure("道路图未初始化")

	var start_candidates_r := RangeUtilsClass.get_adjacent_road_cells(state, entrance_pos)
	if not start_candidates_r.ok:
		return start_candidates_r
	var start_candidates: Array[Vector2i] = start_candidates_r.value
	if start_candidates.is_empty():
		return Result.failure("餐厅入口未邻接道路")

	var route: Array[Vector2i] = []
	var current_pos: Vector2i = Vector2i.ZERO

	for src in sources:
		var end_candidates_r := RangeUtilsClass.get_adjacent_road_cells(state, src)
		if not end_candidates_r.ok:
			return end_candidates_r
		var end_candidates: Array[Vector2i] = end_candidates_r.value
		if end_candidates.is_empty():
			return Result.failure("饮料源未邻接道路: %s" % str(src))

		var best_path: Array[Vector2i] = []
		var best_dist := INF
		var best_steps := INF

		if route.is_empty():
			for from_cell in start_candidates:
				for to_cell in end_candidates:
					var sp_r = road_graph.find_shortest_path(from_cell, to_cell)
					if not sp_r.ok:
						continue
					var sp: Dictionary = sp_r.value
					var d: int = int(sp.get("distance", INF))
					var steps: int = int(sp.get("steps", INF))
					var path_val = sp.get("path", null)
					if not (path_val is Array):
						continue
					var path: Array = path_val
					if d < best_dist or (d == best_dist and steps < best_steps):
						best_dist = d
						best_steps = steps
						best_path = []
						for p in path:
							if p is Vector2i:
								best_path.append(p)

			if best_path.is_empty():
				return Result.failure("找不到到饮料源的道路路径: %s" % str(src))
			route = best_path
			current_pos = route[route.size() - 1]
			continue

		for to_cell2 in end_candidates:
			var sp_r2 = road_graph.find_shortest_path(current_pos, to_cell2)
			if not sp_r2.ok:
				continue
			var sp2: Dictionary = sp_r2.value
			var d2: int = int(sp2.get("distance", INF))
			var steps2: int = int(sp2.get("steps", INF))
			var path_val2 = sp2.get("path", null)
			if not (path_val2 is Array):
				continue
			var path2: Array = path_val2
			if d2 < best_dist or (d2 == best_dist and steps2 < best_steps):
				best_dist = d2
				best_steps = steps2
				best_path = []
				for p in path2:
					if p is Vector2i:
						best_path.append(p)

		if best_path.is_empty():
			return Result.failure("找不到到饮料源的道路路径: %s" % str(src))

		# 拼接（避免重复 current_pos）
		for j in range(1, best_path.size()):
			route.append(best_path[j])
		current_pos = route[route.size() - 1]

	return Result.success(route)

static func get_road_procure_max_distance(state: GameState, emp_def: EmployeeDef) -> int:
	if emp_def == null:
		return 0
	var max_dist := int(emp_def.range_value)
	if state == null:
		return max_dist
	var bonus_read := DrinksProcurementClass._get_distance_range_bonus_from_milestones(
		state, state.get_current_player_id(), str(emp_def.id)
	)
	if bonus_read.ok:
		max_dist += int(bonus_read.value)
	return max_dist

static func count_road_boundary_crossings(route: Array[Vector2i]) -> int:
	var count := 0
	for i in range(1, route.size()):
		if MapUtils.crosses_tile_boundary(route[i - 1], route[i]):
			count += 1
	return count

static func build_road_procure_preview_plan(
	state: GameState,
	emp_def: EmployeeDef,
	employee_type: String,
	restaurant_id: String,
	selected_sources: Array[Vector2i]
) -> Result:
	if state == null:
		return Result.failure("state 为空")
	if emp_def == null:
		return Result.failure("员工缺失")
	var emp_id := str(employee_type).strip_edges()
	if emp_id.is_empty() or emp_id == "errand_boy":
		return Result.failure("员工未选择")

	var player_id := state.get_current_player_id()
	var restaurant_ids := StructuresClass.get_player_restaurants(state, player_id)
	if restaurant_ids.is_empty() or not restaurant_ids.has(restaurant_id):
		return Result.failure("餐厅不存在或不属于当前玩家: %s" % restaurant_id)

	var restaurants_val = state.map.get("restaurants", null)
	if not (restaurants_val is Dictionary):
		return Result.failure("state.map.restaurants 缺失或类型错误")
	var restaurants: Dictionary = restaurants_val
	if not restaurants.has(restaurant_id) or not (restaurants[restaurant_id] is Dictionary):
		return Result.failure("餐厅不存在: %s" % restaurant_id)
	var rest: Dictionary = restaurants[restaurant_id]
	var ep = rest.get("entrance_pos", null)
	if not (ep is Vector2i):
		return Result.failure("无法解析餐厅入口位置: %s" % restaurant_id)
	var entrance_pos: Vector2i = Vector2i(ep)

	var road_r := build_road_route(state, entrance_pos, selected_sources)
	if not road_r.ok:
		return road_r
	var route: Array[Vector2i] = road_r.value

	var cmd := Command.create("procure_drinks", player_id, {
		"employee_type": emp_id,
		"restaurant_id": restaurant_id,
		"route": DrinksProcurementClass.serialize_route(route),
		"selected_sources": DrinksProcurementClass.serialize_route(selected_sources)
	})
	return DrinksProcurementClass.resolve_procurement_plan(state, cmd, restaurant_ids, emp_def)

