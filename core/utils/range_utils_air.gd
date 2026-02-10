# RangeUtils：空中距离/范围实现
# 目的：拆分 RangeUtils 的职责，避免单文件过大；本文件专注于 air range。
extends RefCounted

const MapStateAccessClass = preload("res://core/state/map_state_access.gd")
const RangeOriginRegistryClass = preload("res://core/rules/range_origin_registry.gd")

static func is_within_air_range_to_any_cells(
	state: GameState,
	actor: int,
	restaurant_ids: Array[String],
	target_cells: Array[Vector2i],
	max_steps: int
) -> Result:
	if restaurant_ids == null:
		return Result.failure("restaurant_ids 为空")
	if max_steps < 0:
		return Result.failure("max_steps 必须 >= 0")
	if target_cells == null:
		return Result.failure("target_cells 为空")
	if target_cells.is_empty():
		return Result.success(false)

	var restaurants_read := MapStateAccessClass.require_restaurants(state, "")
	if not restaurants_read.ok:
		return restaurants_read
	var restaurants: Dictionary = restaurants_read.value

	var targets: Array[Vector2i] = []
	var target_set := {}
	for i in range(target_cells.size()):
		var v = target_cells[i]
		if not (v is Vector2i):
			return Result.failure("target_cells[%d] 类型错误（期望 Vector2i）" % i)
		var p: Vector2i = v
		if target_set.has(p):
			continue
		target_set[p] = true
		targets.append(p)
	if targets.is_empty():
		return Result.success(false)

	# 起点：餐厅入口
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

		for t in targets:
			var d: int = abs(entrance_pos.x - t.x) + abs(entrance_pos.y - t.y)
			if d <= max_steps:
				return Result.success(true)

	# 模块可扩展起点（例如 coffee_shop）
	var extra_read := RangeOriginRegistryClass.get_extra_origin_positions(state, actor, restaurant_ids, "air")
	if not extra_read.ok:
		return extra_read
	var extra: Array[Vector2i] = extra_read.value
	for origin in extra:
		for t2 in targets:
			var d2: int = abs(origin.x - t2.x) + abs(origin.y - t2.y)
			if d2 <= max_steps:
				return Result.success(true)

	return Result.success(false)

static func is_within_air_range(
	state: GameState,
	actor: int,
	restaurant_ids: Array[String],
	target_pos: Vector2i,
	max_steps: int
) -> Result:
	if restaurant_ids == null:
		return Result.failure("restaurant_ids 为空")
	if max_steps < 0:
		return Result.failure("max_steps 必须 >= 0")

	var restaurants_read := MapStateAccessClass.require_restaurants(state, "")
	if not restaurants_read.ok:
		return restaurants_read
	var restaurants: Dictionary = restaurants_read.value

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

	# 模块可扩展起点（例如 coffee_shop）
	var extra_read := RangeOriginRegistryClass.get_extra_origin_positions(state, actor, restaurant_ids, "air")
	if not extra_read.ok:
		return extra_read
	var extra: Array[Vector2i] = extra_read.value
	for origin in extra:
		var d2: int = abs(origin.x - target_pos.x) + abs(origin.y - target_pos.y)
		if d2 <= max_steps:
			return Result.success(true)

	return Result.success(false)
