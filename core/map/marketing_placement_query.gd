# MarketingPlacementQuery：营销板件放置（state.map.marketing_placements）查询封装
# 用途：避免模块/规则层手工遍历 + 字段解析，减少对底层结构的扩散依赖。
class_name MarketingPlacementQuery
extends RefCounted

const MarketingRegistryClass = preload("res://core/data/marketing_registry.gd")
const MapStateAccessClass = preload("res://core/state/map_state_access.gd")

const KEY := "marketing_placements"

static func has_any_at_world_pos(state: GameState, world_pos: Vector2i) -> Result:
	var read := _read_placements(state)
	if not read.ok:
		return read
	var placements: Dictionary = read.value

	for k in placements.keys():
		var p_val = placements[k]
		if not (p_val is Dictionary):
			return Result.failure("state.map.%s[%s] 类型错误（期望 Dictionary）" % [KEY, str(k)])
		var p: Dictionary = p_val
		var contains_read := _placement_contains_world_pos(state, p, world_pos, "state.map.%s[%s]" % [KEY, str(k)])
		if not contains_read.ok:
			return contains_read
		if bool(contains_read.value):
			return Result.success(true)

	return Result.success(false)

static func has_any_in_world_positions(state: GameState, world_positions: Array) -> Result:
	if world_positions == null:
		return Result.failure("MarketingPlacementQuery.has_any_in_world_positions: world_positions 为空")

	var positions: Array[Vector2i] = []
	var pos_set := {}
	for i in range(world_positions.size()):
		var v = world_positions[i]
		if not (v is Vector2i):
			return Result.failure("MarketingPlacementQuery.has_any_in_world_positions: world_positions[%d] 类型错误（期望 Vector2i）" % i)
		var p: Vector2i = v
		if not pos_set.has(p):
			pos_set[p] = true
			positions.append(p)

	var read := _read_placements(state)
	if not read.ok:
		return read
	var placements: Dictionary = read.value

	for k in placements.keys():
		var p_val = placements[k]
		if not (p_val is Dictionary):
			return Result.failure("state.map.%s[%s] 类型错误（期望 Dictionary）" % [KEY, str(k)])
		var placement: Dictionary = p_val

		var path := "state.map.%s[%s]" % [KEY, str(k)]
		var bounds_read := _read_placement_bounds(state, placement, path)
		if not bounds_read.ok:
			return bounds_read
		var b: Dictionary = bounds_read.value
		var anchor: Vector2i = b.anchor
		var size: Vector2i = b.size

		for pos in positions:
			if _rect_contains(anchor, size, pos):
				return Result.success(true)

	return Result.success(false)

static func has_type_at_world_pos(state: GameState, marketing_type: String, world_pos: Vector2i) -> Result:
	if marketing_type.is_empty():
		return Result.failure("MarketingPlacementQuery.has_type_at_world_pos: marketing_type 不能为空")

	var read := _read_placements(state)
	if not read.ok:
		return read
	var placements: Dictionary = read.value

	for k in placements.keys():
		var p_val = placements[k]
		if not (p_val is Dictionary):
			return Result.failure("state.map.%s[%s] 类型错误（期望 Dictionary）" % [KEY, str(k)])
		var p: Dictionary = p_val

		var t_val = p.get("type", null)
		if not (t_val is String):
			return Result.failure("state.map.%s[%s].type 缺失或类型错误（期望 String）" % [KEY, str(k)])
		if str(t_val) != marketing_type:
			continue

		var contains_read := _placement_contains_world_pos(state, p, world_pos, "state.map.%s[%s]" % [KEY, str(k)])
		if not contains_read.ok:
			return contains_read
		if bool(contains_read.value):
			return Result.success(true)

	return Result.success(false)

static func has_type_in_world_positions(state: GameState, marketing_type: String, world_positions: Array) -> Result:
	if marketing_type.is_empty():
		return Result.failure("MarketingPlacementQuery.has_type_in_world_positions: marketing_type 不能为空")
	if world_positions == null:
		return Result.failure("MarketingPlacementQuery.has_type_in_world_positions: world_positions 为空")

	var positions: Array[Vector2i] = []
	var pos_set := {}
	for i in range(world_positions.size()):
		var v = world_positions[i]
		if not (v is Vector2i):
			return Result.failure("MarketingPlacementQuery.has_type_in_world_positions: world_positions[%d] 类型错误（期望 Vector2i）" % i)
		var p: Vector2i = v
		if not pos_set.has(p):
			pos_set[p] = true
			positions.append(p)

	var read := _read_placements(state)
	if not read.ok:
		return read
	var placements: Dictionary = read.value

	for k in placements.keys():
		var p_val = placements[k]
		if not (p_val is Dictionary):
			return Result.failure("state.map.%s[%s] 类型错误（期望 Dictionary）" % [KEY, str(k)])
		var placement: Dictionary = p_val

		var t_val = placement.get("type", null)
		if not (t_val is String):
			return Result.failure("state.map.%s[%s].type 缺失或类型错误（期望 String）" % [KEY, str(k)])
		if str(t_val) != marketing_type:
			continue

		var path := "state.map.%s[%s]" % [KEY, str(k)]
		var bounds_read := _read_placement_bounds(state, placement, path)
		if not bounds_read.ok:
			return bounds_read
		var b: Dictionary = bounds_read.value
		var anchor: Vector2i = b.anchor
		var size: Vector2i = b.size

		for pos in positions:
			if _rect_contains(anchor, size, pos):
				return Result.success(true)

	return Result.success(false)

static func _read_placements(state: GameState) -> Result:
	return MapStateAccessClass.require_marketing_placements(state, "MarketingPlacementQuery")

static func _placement_contains_world_pos(state: GameState, placement: Dictionary, world_pos: Vector2i, path: String) -> Result:
	var bounds_read := _read_placement_bounds(state, placement, path)
	if not bounds_read.ok:
		return bounds_read
	var b: Dictionary = bounds_read.value
	var anchor: Vector2i = b.anchor
	var size: Vector2i = b.size
	return Result.success(_rect_contains(anchor, size, world_pos))

static func _read_placement_bounds(state: GameState, placement: Dictionary, path: String) -> Result:
	var wp_val = placement.get("world_pos", null)
	if not (wp_val is Vector2i):
		return Result.failure("%s.world_pos 缺失或类型错误（期望 Vector2i）" % path)
	var anchor: Vector2i = wp_val

	# rotation: optional (backward compatible)
	var rotation := 0
	var rot_val = placement.get("rotation", null)
	if rot_val != null:
		if rot_val is int:
			rotation = int(rot_val)
		elif rot_val is float:
			var f: float = float(rot_val)
			if f != floor(f):
				return Result.failure("%s.rotation 必须为整数，实际: %s" % [path, str(rot_val)])
			rotation = int(f)
		else:
			return Result.failure("%s.rotation 类型错误（期望 int）" % path)
	if not rotation in [0, 90, 180, 270]:
		return Result.failure("%s.rotation 非法（期望 0/90/180/270），实际: %d" % [path, rotation])

	var size_read := _read_placement_base_size(state, placement, path)
	if not size_read.ok:
		return size_read
	var base_size: Vector2i = size_read.value
	var size := base_size
	if rotation == 90 or rotation == 270:
		size = Vector2i(base_size.y, base_size.x)

	return Result.success({"anchor": anchor, "size": size})

static func _read_placement_base_size(state: GameState, placement: Dictionary, path: String) -> Result:
	# Preferred: explicit footprint_size in placement (UI-friendly, avoids registry dependency)
	if placement.has("footprint_size"):
		var fs_val = placement.get("footprint_size", null)
		if fs_val is Vector2i:
			var v: Vector2i = fs_val
			return Result.success(v)
		if fs_val is Array:
			var arr: Array = fs_val
			if arr.size() != 2:
				return Result.failure("%s.footprint_size 长度错误（期望 2），实际: %d" % [path, arr.size()])
			var w_val = arr[0]
			var h_val = arr[1]
			if not (w_val is int or w_val is float) or not (h_val is int or h_val is float):
				return Result.failure("%s.footprint_size 类型错误（期望 [int,int]）" % path)
			var w := int(w_val)
			var h := int(h_val)
			if float(w_val) != float(w) or float(h_val) != float(h):
				return Result.failure("%s.footprint_size 必须为整数，实际: %s" % [path, str(fs_val)])
			return Result.success(Vector2i(w, h))
		return Result.failure("%s.footprint_size 类型错误（期望 Vector2i 或 [w,h] Array）" % path)

	# Fallback: derive from MarketingRegistry if available
	var bn_val = placement.get("board_number", null)
	var board_number := -1
	if bn_val is int:
		board_number = int(bn_val)
	elif bn_val is float:
		var f2: float = float(bn_val)
		if f2 == floor(f2):
			board_number = int(f2)

	if board_number > 0 and MarketingRegistryClass.is_loaded():
		var def_val = MarketingRegistryClass.get_def(board_number)
		if def_val != null and def_val.has_method("to_dict"):
			# MarketingDef has footprint_size field (Vector2i)
			var fs = def_val.get("footprint_size") if def_val is Object else null
			if fs is Vector2i:
				return Result.success(fs)
			if def_val is MarketingDef and (def_val as MarketingDef).footprint_size is Vector2i:
				return Result.success((def_val as MarketingDef).footprint_size)

	# Last resort: backward compatible 1x1
	return Result.success(Vector2i.ONE)

static func _rect_contains(anchor: Vector2i, size: Vector2i, pos: Vector2i) -> bool:
	if size.x <= 0 or size.y <= 0:
		return false
	return (
		pos.x >= anchor.x
		and pos.y >= anchor.y
		and pos.x < anchor.x + size.x
		and pos.y < anchor.y + size.y
	)
