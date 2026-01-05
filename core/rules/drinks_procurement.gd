# 饮料采购规则（从 ProcureDrinksAction 抽离）
# 负责：起点餐厅解析、默认路线生成、路线校验、沿路线拾取来源等纯规则逻辑。
class_name DrinksProcurement
extends RefCounted

const InputsClass = preload("res://core/rules/drinks_procurement/inputs.gd")
const StartRestaurantResolverClass = preload("res://core/rules/drinks_procurement/start_restaurant_resolver.gd")
const DefaultRouteBuilderClass = preload("res://core/rules/drinks_procurement/default_route_builder.gd")
const RouteValidatorClass = preload("res://core/rules/drinks_procurement/route_validator.gd")
const PickedSourcesFinderClass = preload("res://core/rules/drinks_procurement/picked_sources_finder.gd")
const MapRuntimeClass = preload("res://core/map/map_runtime.gd")
const MilestoneRegistryClass = preload("res://core/data/milestone_registry.gd")

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

	var range_bonus_read := _get_distance_range_bonus_from_milestones(state, command.actor, emp_def.id)
	if not range_bonus_read.ok:
		return range_bonus_read
	var range_bonus: int = int(range_bonus_read.value)
	range_value += range_bonus

	var map_data: Dictionary = state.map

	if not map_data.has("restaurants") or not (map_data["restaurants"] is Dictionary):
		return Result.failure("state.map.restaurants 缺失或类型错误")
	var restaurants: Dictionary = map_data["restaurants"]

	if not map_data.has("drink_sources") or not (map_data["drink_sources"] is Array):
		return Result.failure("state.map.drink_sources 缺失或类型错误")
	var drink_sources: Array = map_data["drink_sources"]
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

	if range_type != "air" and MapRuntimeClass.get_road_graph(state) == null:
		return Result.failure("道路图未初始化")

	var route: Array[Vector2i] = []
	if command.params.has("route"):
		var route_val = command.params["route"]
		var parse_result := InputsClass.parse_route_positions(route_val)
		if not parse_result.ok:
			return parse_result
		route = parse_result.value

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

	# 若未提供 route，则生成一个默认路径（确定性：最近可达来源的最短路）
	if route.is_empty():
		var default_result := DefaultRouteBuilderClass.build_default_route(
			state, restaurant_ids, restaurants, drink_sources, range_type, range_value
		)
		if not default_result.ok:
			return default_result
		var default_info: Dictionary = default_result.value
		if not default_info.has("restaurant_id") or not (default_info["restaurant_id"] is String) or default_info["restaurant_id"].is_empty():
			return Result.failure("内部错误: default_info.restaurant_id 缺失或为空")
		if not default_info.has("entrance_pos") or not (default_info["entrance_pos"] is Vector2i):
			return Result.failure("内部错误: default_info.entrance_pos 缺失或类型错误")
		if not default_info.has("route") or not (default_info["route"] is Array):
			return Result.failure("内部错误: default_info.route 缺失或类型错误")
		restaurant_id = default_info["restaurant_id"]
		entrance_pos = default_info["entrance_pos"]
		route = Array(default_info["route"], TYPE_VECTOR2I, "", null)

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

	return Result.success({
		"restaurant_id": restaurant_id,
		"entrance_pos": entrance_pos,
		"route": route,
		"picked_sources": picked_sources,
	})

static func serialize_route(route: Array) -> Array:
	var out: Array = []
	for p in route:
		assert(p is Vector2i, "route 元素必须为 Vector2i")
		var v: Vector2i = p
		out.append([v.x, v.y])
	return out

static func get_drinks_per_source_bonus_from_milestones(state: GameState, player_id: int) -> Result:
	if state == null:
		return Result.failure("DrinksProcurement: state 为空")
	if not (state.players is Array):
		return Result.failure("DrinksProcurement: state.players 类型错误（期望 Array）")
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("DrinksProcurement: player_id 越界: %d" % player_id)

	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return Result.failure("DrinksProcurement: players[%d] 类型错误（期望 Dictionary）" % player_id)
	var player: Dictionary = player_val
	if not player.has("milestones") or not (player["milestones"] is Array):
		return Result.failure("DrinksProcurement: player[%d].milestones 缺失或类型错误（期望 Array）" % player_id)
	var milestones: Array = player["milestones"]

	var bonus := 0
	for i in range(milestones.size()):
		var mid_val = milestones[i]
		if not (mid_val is String):
			return Result.failure("DrinksProcurement: milestones[%d] 类型错误（期望 String）" % i)
		var mid: String = str(mid_val)
		if mid.is_empty():
			return Result.failure("DrinksProcurement: milestones 不应包含空字符串")

		var def_val = MilestoneRegistryClass.get_def(mid)
		if def_val == null:
			return Result.failure("DrinksProcurement: 未知里程碑定义: %s" % mid)
		if not (def_val is MilestoneDef):
			return Result.failure("DrinksProcurement: 里程碑定义类型错误（期望 MilestoneDef）: %s" % mid)
		var def: MilestoneDef = def_val

		for e_i in range(def.effects.size()):
			var eff_val = def.effects[e_i]
			if not (eff_val is Dictionary):
				return Result.failure("DrinksProcurement: %s.effects[%d] 类型错误（期望 Dictionary）" % [mid, e_i])
			var eff: Dictionary = eff_val
			var type_val = eff.get("type", null)
			if not (type_val is String):
				return Result.failure("DrinksProcurement: %s.effects[%d].type 类型错误（期望 String）" % [mid, e_i])
			var t: String = str(type_val)
			if t != "procure_plus_one":
				continue

			var value_val = eff.get("value", null)
			var v_read := _parse_positive_int_value(value_val, "%s.effects[%d].value" % [mid, e_i])
			if not v_read.ok:
				return Result.failure("DrinksProcurement: %s" % v_read.error)
			bonus += int(v_read.value)

	return Result.success(bonus)

static func get_drinks_per_source_delta_for_employee_from_milestones(state: GameState, player_id: int, employee_id: String) -> Result:
	if state == null:
		return Result.failure("DrinksProcurement: state 为空")
	if not (state.players is Array):
		return Result.failure("DrinksProcurement: state.players 类型错误（期望 Array）")
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("DrinksProcurement: player_id 越界: %d" % player_id)
	if employee_id.is_empty():
		return Result.failure("DrinksProcurement: employee_id 不能为空")

	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return Result.failure("DrinksProcurement: players[%d] 类型错误（期望 Dictionary）" % player_id)
	var player: Dictionary = player_val
	if not player.has("milestones") or not (player["milestones"] is Array):
		return Result.failure("DrinksProcurement: player[%d].milestones 缺失或类型错误（期望 Array）" % player_id)
	var milestones: Array = player["milestones"]

	var bonus := 0
	for i in range(milestones.size()):
		var mid_val = milestones[i]
		if not (mid_val is String):
			return Result.failure("DrinksProcurement: milestones[%d] 类型错误（期望 String）" % i)
		var mid: String = str(mid_val)
		if mid.is_empty():
			return Result.failure("DrinksProcurement: milestones 不应包含空字符串")

		var def_val = MilestoneRegistryClass.get_def(mid)
		if def_val == null:
			return Result.failure("DrinksProcurement: 未知里程碑定义: %s" % mid)
		if not (def_val is MilestoneDef):
			return Result.failure("DrinksProcurement: 里程碑定义类型错误（期望 MilestoneDef）: %s" % mid)
		var def: MilestoneDef = def_val

		for e_i in range(def.effects.size()):
			var eff_val = def.effects[e_i]
			if not (eff_val is Dictionary):
				return Result.failure("DrinksProcurement: %s.effects[%d] 类型错误（期望 Dictionary）" % [mid, e_i])
			var eff: Dictionary = eff_val
			var type_val = eff.get("type", null)
			if not (type_val is String):
				return Result.failure("DrinksProcurement: %s.effects[%d].type 类型错误（期望 String）" % [mid, e_i])
			var t: String = str(type_val)
			if t != "drinks_per_source_delta":
				continue

			if not eff.has("targets") or not (eff["targets"] is Array):
				return Result.failure("DrinksProcurement: %s.effects[%d].targets 缺失或类型错误（期望 Array）" % [mid, e_i])
			var targets: Array = eff["targets"]
			var hit := false
			for j in range(targets.size()):
				var target_val = targets[j]
				if not (target_val is String):
					return Result.failure("DrinksProcurement: %s.effects[%d].targets[%d] 类型错误（期望 String）" % [mid, e_i, j])
				if str(target_val) == employee_id:
					hit = true
					break
			if not hit:
				continue

			var value_val = eff.get("value", null)
			var v_read := _parse_positive_int_value(value_val, "%s.effects[%d].value" % [mid, e_i])
			if not v_read.ok:
				return Result.failure("DrinksProcurement: %s" % v_read.error)
			bonus += int(v_read.value)

	return Result.success(bonus)

static func _get_distance_range_bonus_from_milestones(state: GameState, player_id: int, employee_id: String) -> Result:
	if state == null:
		return Result.failure("DrinksProcurement: state 为空")
	if not (state.players is Array):
		return Result.failure("DrinksProcurement: state.players 类型错误（期望 Array）")
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("DrinksProcurement: player_id 越界: %d" % player_id)
	if employee_id.is_empty():
		return Result.failure("DrinksProcurement: employee_id 不能为空")

	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return Result.failure("DrinksProcurement: players[%d] 类型错误（期望 Dictionary）" % player_id)
	var player: Dictionary = player_val
	if not player.has("milestones") or not (player["milestones"] is Array):
		return Result.failure("DrinksProcurement: player[%d].milestones 缺失或类型错误（期望 Array）" % player_id)
	var milestones: Array = player["milestones"]

	var bonus := 0
	for i in range(milestones.size()):
		var mid_val = milestones[i]
		if not (mid_val is String):
			return Result.failure("DrinksProcurement: milestones[%d] 类型错误（期望 String）" % i)
		var mid: String = str(mid_val)
		if mid.is_empty():
			return Result.failure("DrinksProcurement: milestones 不应包含空字符串")

		var def_val = MilestoneRegistryClass.get_def(mid)
		if def_val == null:
			return Result.failure("DrinksProcurement: 未知里程碑定义: %s" % mid)
		if not (def_val is MilestoneDef):
			return Result.failure("DrinksProcurement: 里程碑定义类型错误（期望 MilestoneDef）: %s" % mid)
		var def: MilestoneDef = def_val

		for e_i in range(def.effects.size()):
			var eff_val = def.effects[e_i]
			if not (eff_val is Dictionary):
				return Result.failure("DrinksProcurement: %s.effects[%d] 类型错误（期望 Dictionary）" % [mid, e_i])
			var eff: Dictionary = eff_val
			var type_val = eff.get("type", null)
			if not (type_val is String):
				return Result.failure("DrinksProcurement: %s.effects[%d].type 类型错误（期望 String）" % [mid, e_i])
			var t: String = str(type_val)
			if t != "distance_plus_one":
				continue

			if not eff.has("targets") or not (eff["targets"] is Array):
				return Result.failure("DrinksProcurement: %s.effects[%d].targets 缺失或类型错误（期望 Array）" % [mid, e_i])
			var targets: Array = eff["targets"]
			for j in range(targets.size()):
				var target_val = targets[j]
				if not (target_val is String):
					return Result.failure("DrinksProcurement: %s.effects[%d].targets[%d] 类型错误（期望 String）" % [mid, e_i, j])
				var target: String = str(target_val)
				if target.is_empty():
					return Result.failure("DrinksProcurement: %s.effects[%d].targets[%d] 不能为空" % [mid, e_i, j])
				if target == employee_id:
					bonus += 1
					break

	return Result.success(bonus)

static func _parse_positive_int_value(value, path: String) -> Result:
	if value is int:
		if int(value) <= 0:
			return Result.failure("%s 必须 > 0，实际: %d" % [path, int(value)])
		return Result.success(int(value))
	if value is float:
		var f: float = float(value)
		if f == int(f):
			var i: int = int(f)
			if i <= 0:
				return Result.failure("%s 必须 > 0，实际: %d" % [path, i])
			return Result.success(i)
		return Result.failure("%s 必须为整数（不允许小数）" % path)
	return Result.failure("%s 必须为正整数" % path)
