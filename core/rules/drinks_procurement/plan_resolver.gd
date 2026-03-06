extends RefCounted

const InputsClass = preload("res://core/rules/drinks_procurement/inputs.gd")
const StartRestaurantResolverClass = preload("res://core/rules/drinks_procurement/start_restaurant_resolver.gd")
const RouteValidatorClass = preload("res://core/rules/drinks_procurement/route_validator.gd")
const PickedSourcesFinderClass = preload("res://core/rules/drinks_procurement/picked_sources_finder.gd")
const RoadGraphCacheClass = preload("res://core/map/map_runtime/road_graph_cache.gd")
const MilestoneBonusesClass = preload("res://core/rules/drinks_procurement/milestone_bonuses.gd")
const MapStateAccessClass = preload("res://core/state/map_state_access.gd")

static func resolve_procurement_plan(
	state: GameState,
	command: Command,
	restaurant_ids: Array[String],
	emp_def: EmployeeDef
) -> Result:
	if restaurant_ids.is_empty():
		return Result.failure("你没有餐厅，无法采购饮料")

	var range_type: String = emp_def.range_type
	var range_value: int = emp_def.range_value
	if range_type != "air" and range_type != "road":
		return Result.failure("员工 range.type 不支持: %s" % range_type)
	if range_value <= 0:
		return Result.failure("员工 range.value 必须 > 0")

	var range_bonus_read := MilestoneBonusesClass.get_distance_range_bonus_from_milestones(state, command.actor, emp_def.id)
	if not range_bonus_read.ok:
		return range_bonus_read
	var range_bonus: int = int(range_bonus_read.value)
	range_value += range_bonus

	var restaurants_read := MapStateAccessClass.require_restaurants(state, "")
	if not restaurants_read.ok:
		return restaurants_read
	var restaurants: Dictionary = restaurants_read.value

	var drink_sources_read := MapStateAccessClass.require_array_field(state, "drink_sources", "DrinksProcurement")
	if not drink_sources_read.ok:
		return drink_sources_read
	var drink_sources: Array = drink_sources_read.value
	if drink_sources.is_empty():
		return Result.failure("地图上没有饮料源")

	var sources_check := InputsClass.validate_drink_sources(drink_sources)
	if not sources_check.ok:
		return sources_check

	for rest_id in restaurant_ids:
		if not restaurants.has(rest_id):
			return Result.failure("餐厅不存在: %s" % rest_id)
		var rest: Dictionary = restaurants[rest_id]
		var owner_check := InputsClass.require_restaurant_owned_by(rest, rest_id, command.actor)
		if not owner_check.ok:
			return owner_check
		var entrance_check := InputsClass.require_restaurant_entrance_pos(rest, rest_id)
		if not entrance_check.ok:
			return entrance_check

	if range_type != "air" and RoadGraphCacheClass.get_road_graph(state) == null:
		return Result.failure("道路图未初始化")

	var route: Array[Vector2i] = []
	if command.params.has("route"):
		var route_val = command.params["route"]
		var parse_result := InputsClass.parse_route_positions(route_val)
		if not parse_result.ok:
			return parse_result
		route = parse_result.value

	if not command.params.has("selected_sources"):
		return Result.failure("缺少参数: selected_sources", Result.ErrorCode.MISSING_PARAMS)
	var selected_sources_val = command.params["selected_sources"]
	var selected_parse := InputsClass.parse_route_positions(selected_sources_val)
	if not selected_parse.ok:
		return Result.failure("selected_sources 解析失败: %s" % selected_parse.error)
	var selected_sources: Array[Vector2i] = selected_parse.value
	if selected_sources.is_empty():
		return Result.failure("selected_sources 不能为空")

	var selected_sources_set := {}
	for pos in selected_sources:
		selected_sources_set[pos] = true

	var sources_by_pos := {}
	for s_val in drink_sources:
		if not (s_val is Dictionary):
			continue
		var s: Dictionary = s_val
		var wp = s.get("world_pos", null)
		if wp is Vector2i:
			sources_by_pos[Vector2i(wp)] = true

	for pos2 in selected_sources_set.keys():
		if pos2 is Vector2i and not sources_by_pos.has(pos2):
			return Result.failure("选定的饮品来源不存在: %s" % str(pos2))

	# 选择起点餐厅（可能由 restaurant_id 或 route 推导）
	var start_result := StartRestaurantResolverClass.resolve_start_restaurant(
		state, command, restaurant_ids, restaurants, range_type, route
	)
	if not start_result.ok:
		return start_result
	var start_info: Dictionary = start_result.value
	if not start_info.has("restaurant_id") or not (start_info["restaurant_id"] is String) or start_info["restaurant_id"].is_empty():
		return Result.failure("内部错误: start_info.restaurant_id 缺失或为空")
	if not start_info.has("entrance_pos") or not (start_info["entrance_pos"] is Vector2i):
		return Result.failure("内部错误: start_info.entrance_pos 缺失或类型错误")
	var restaurant_id: String = start_info["restaurant_id"]
	var entrance_pos: Vector2i = start_info["entrance_pos"]

	if route.is_empty():
		return Result.failure("route 不能为空（请先手动选择进货点生成路线）")

	# 校验 route（起点、连通性、范围、禁 U 型）
	var route_check := RouteValidatorClass.validate_route(
		state, restaurants, restaurant_id, entrance_pos, route, range_type, range_value
	)
	if not route_check.ok:
		return route_check

	# 计算“沿路线拾取”的饮品来源（同一来源在一次采购中只记一次）
	var picked_result := PickedSourcesFinderClass.find_picked_sources_along_route(
		state, drink_sources, route, range_type
	)
	if not picked_result.ok:
		return picked_result
	var picked_sources: Array[Dictionary] = picked_result.value
	if picked_sources.is_empty():
		return Result.failure("路线未经过任何饮品来源")

	var picked_set := {}
	for s2 in picked_sources:
		if not (s2 is Dictionary):
			continue
		var d2: Dictionary = s2
		var wp2 = d2.get("world_pos", null)
		if wp2 is Vector2i:
			picked_set[Vector2i(wp2)] = true

	for pos3 in selected_sources_set.keys():
		if pos3 is Vector2i and not picked_set.has(pos3):
			return Result.failure("路线未经过选定的饮品来源: %s" % str(pos3))

	var filtered_sources: Array[Dictionary] = []
	for s3 in picked_sources:
		if not (s3 is Dictionary):
			continue
		var d3: Dictionary = s3
		var wp3 = d3.get("world_pos", null)
		if wp3 is Vector2i and selected_sources_set.has(Vector2i(wp3)):
			filtered_sources.append(d3)
	picked_sources = filtered_sources
	if picked_sources.is_empty():
		return Result.failure("路线未经过任何选定的饮品来源")

	return Result.success({
		"restaurant_id": restaurant_id,
		"entrance_pos": entrance_pos,
		"route": route,
		"picked_sources": picked_sources,
	})
