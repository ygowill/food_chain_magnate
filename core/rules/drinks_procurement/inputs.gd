# 饮料采购：输入解析与基础校验（Fail Fast）
extends RefCounted

static func validate_drink_sources(drink_sources: Array) -> Result:
	for i in range(drink_sources.size()):
		var source = drink_sources[i]
		if not (source is Dictionary):
			return Result.failure("drink_sources[%d] 必须为字典" % i)
		var src: Dictionary = source
		if not src.has("world_pos") or not (src["world_pos"] is Vector2i):
			return Result.failure("drink_sources[%d].world_pos 缺失或类型错误" % i)
		if not src.has("type") or not (src["type"] is String):
			return Result.failure("drink_sources[%d].type 缺失或为空" % i)
		var type: String = src["type"]
		if type.is_empty():
			return Result.failure("drink_sources[%d].type 缺失或为空" % i)

		if not src.has("tile_id") or not (src["tile_id"] is String):
			return Result.failure("drink_sources[%d].tile_id 缺失或为空" % i)
		var tile_id: String = src["tile_id"]
		if tile_id.is_empty():
			return Result.failure("drink_sources[%d].tile_id 缺失或为空" % i)
	return Result.success()

static func parse_route_positions(value) -> Result:
	if not (value is Array):
		return Result.failure("route 必须为数组")
	var route: Array[Vector2i] = []
	var arr: Array = value
	for i in range(arr.size()):
		var item = arr[i]
		if not (item is Array):
			return Result.failure("route[%d] 必须为 [x,y] 数组" % i)
		var coord: Array = item
		if coord.size() != 2:
			return Result.failure("route[%d] 必须为 [x,y]，实际长度=%d" % [i, coord.size()])
		var x_read := _parse_int(coord[0], "route[%d][0]" % i)
		if not x_read.ok:
			return x_read
		var y_read := _parse_int(coord[1], "route[%d][1]" % i)
		if not y_read.ok:
			return y_read
		route.append(Vector2i(int(x_read.value), int(y_read.value)))
	return Result.success(route)

static func _parse_int(value, path: String) -> Result:
	if value is int:
		return Result.success(int(value))
	if value is float:
		var f: float = float(value)
		if f != floor(f):
			return Result.failure("%s 必须为整数（不允许小数），实际: %s" % [path, str(value)])
		return Result.success(int(f))
	return Result.failure("%s 必须为整数，实际类型: %s" % [path, typeof(value)])

static func require_restaurant_entrance_pos(rest: Dictionary, rest_id: String) -> Result:
	if not rest.has("entrance_pos") or not (rest["entrance_pos"] is Vector2i):
		return Result.failure("餐厅 %s 缺少 entrance_pos 或类型错误" % rest_id)
	return Result.success(rest["entrance_pos"])

static func require_restaurant_owned_by(rest: Dictionary, rest_id: String, actor: int) -> Result:
	if not rest.has("owner") or not (rest["owner"] is int):
		return Result.failure("餐厅 %s 缺少 owner 或类型错误" % rest_id)
	if rest["owner"] != actor:
		return Result.failure("餐厅 %s 不属于玩家 %d" % [rest_id, actor])
	return Result.success()
