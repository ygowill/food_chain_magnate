# InitiateMarketingAction 验证逻辑（抽离自 gameplay/actions/initiate_marketing_action.gd）
extends RefCounted

const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MarketingTypeRegistryClass = preload("res://core/rules/marketing_type_registry.gd")
const MarketingRulesClass = preload("res://core/rules/marketing_rules.gd")
const CellsClass = preload("res://core/map/map_runtime/cells.gd")
const CoordsClass = preload("res://core/map/map_runtime/coords.gd")
const StructuresClass = preload("res://core/map/map_runtime/structures.gd")
const MapUtilsClass = preload("res://core/map/map_utils.gd")
const RangeUtilsClass = preload("res://core/utils/range_utils.gd")
const RoundStateCountersClass = preload("res://core/utils/round_state_counters.gd")
const MarketingPlacementQueryClass = preload("res://core/map/marketing_placement_query.gd")
const MapStateAccessClass = preload("res://core/state/map_state_access.gd")

static func validate(action: ActionExecutor, state: GameState, command: Command) -> Result:
	var current_player_id := state.get_current_player_id()
	if command.actor != current_player_id:
		return Result.failure("不是你的回合")

	var employee_type_result := action.require_string_param(command, "employee_type")
	if not employee_type_result.ok:
		return employee_type_result
	var employee_type: String = employee_type_result.value
	var requested_staff_id := -1
	if command.params.has("staff_id"):
		var staff_id_result := action.require_int_param(command, "staff_id")
		if not staff_id_result.ok:
			return staff_id_result
		requested_staff_id = int(staff_id_result.value)
		if requested_staff_id <= 0:
			return Result.failure("staff_id 必须 > 0，实际: %d" % requested_staff_id)

	var board_number_result := action.require_int_param(command, "board_number")
	if not board_number_result.ok:
		return board_number_result
	var board_number: int = board_number_result.value
	if board_number <= 0:
		return Result.failure("board_number 必须 > 0")

	var product_result := action.require_string_param(command, "product")
	if not product_result.ok:
		return product_result
	var product: String = product_result.value
	var product_read := MarketingRulesClass.require_marketable_product(product)
	if not product_read.ok:
		return product_read

	var world_pos_result := action.require_vector2i_param(command, "position")
	if not world_pos_result.ok:
		return world_pos_result
	var world_pos: Vector2i = world_pos_result.value

	var rotation_result := action.optional_int_param(command, "rotation", 0)
	if not rotation_result.ok:
		return rotation_result
	var rotation: int = int(rotation_result.value)
	var rotation_read := MarketingRulesClass.require_rotation(rotation)
	if not rotation_read.ok:
		return rotation_read

	var board_spec_read := MarketingRulesClass.require_board_spec(state, board_number)
	if not board_spec_read.ok:
		return board_spec_read
	var board_spec: Dictionary = board_spec_read.value
	var marketing_type := str(board_spec.get("marketing_type", ""))
	if not MarketingTypeRegistryClass.has_type(marketing_type):
		return Result.failure("未知的营销类型: %s" % marketing_type)

	# 检查是否已被占用（同一编号唯一）
	for inst_val in state.marketing_instances:
		if not (inst_val is Dictionary):
			return Result.failure("marketing_instances 元素类型错误（期望 Dictionary）")
		var inst: Dictionary = inst_val
		if not inst.has("board_number") or not (inst["board_number"] is int):
			return Result.failure("marketing_instances.board_number 缺失或类型错误（期望 int）")
		if int(inst["board_number"]) == board_number:
			return Result.failure("营销板件已在使用中: #%d" % board_number)
	var placements_read := MapStateAccessClass.require_marketing_placements(state, "")
	if not placements_read.ok:
		return placements_read
	var placements: Dictionary = placements_read.value
	if placements.has(str(board_number)):
		return Result.failure("营销板件已在使用中: #%d" % board_number)

	# 员工能力校验
	var employee_read := MarketingRulesClass.require_marketing_employee(employee_type, marketing_type)
	if not employee_read.ok:
		return employee_read
	var employee_meta: Dictionary = employee_read.value
	var emp_def = employee_meta.get("definition", null)
	var max_duration := int(employee_meta.get("max_duration", 0))

	var duration_read := MarketingRulesClass.require_marketing_duration(action, command, max_duration)
	if not duration_read.ok:
		return duration_read
	var duration: int = int(duration_read.value)

	# 玩家必须有餐厅
	var restaurant_ids := StructuresClass.get_player_restaurants(state, command.actor)
	if restaurant_ids.is_empty():
		return Result.failure("你没有餐厅，无法发起营销")

	# 检查玩家是否拥有可用的营销员：
	# - 默认：需要在岗营销员
	# - 扩展：允许通过 working_employee_multiplier 让“本回合刚变忙碌”的营销员额外发起营销（例如夜班经理）。
	var player := state.get_player(command.actor)
	var active_count := EmployeeRulesClass.count_active(player, employee_type)
	var mult := maxi(1, EmployeeRulesClass.get_working_employee_multiplier(state, command.actor, employee_type))
	var extra_busy_uses := _count_reusable_marketing_uses_from_busy_groups_this_round(state, command.actor, employee_type, mult)
	if active_count <= 0 and extra_busy_uses <= 0:
		return Result.failure("你没有可用的 %s" % employee_type)

	var provider_read := EmployeeRulesClass.try_resolve_marketer(state, command.actor, employee_type, requested_staff_id)
	if not provider_read.ok:
		return provider_read

	# === 放置校验：占地/边界/阻塞/道路/边缘/重叠 ===
	var base_size_val = board_spec.get("footprint_size", null)
	if not (base_size_val is Vector2i):
		return Result.failure("board_spec.footprint_size 缺失或类型错误（期望 Vector2i）")
	var base_size: Vector2i = base_size_val

	# Airplane is placed outside the board:
	# - It is NOT blocked by structures/roads/drink_sources.
	# - It is NOT affected by employee range.
	# - The only constraint is that its length (1/3/5) flies over that many rows/cols ON the board.
	# (issue_tracker #42)
	if marketing_type == "airplane":
		# length is the dimension that isn't the outward thickness(=2)
		var thickness := 2
		var length := 0
		if base_size.x == 2 and base_size.y != 2:
			length = base_size.y
		elif base_size.y == 2 and base_size.x != 2:
			length = base_size.x
		else:
			thickness = mini(base_size.x, base_size.y)
			length = maxi(base_size.x, base_size.y)

		if length <= 0:
			return Result.failure("飞机营销板件长度非法: %s" % str(base_size))

		# World pos must be a valid edge cell.
		if not CoordsClass.is_world_pos_in_grid(state, world_pos):
			return Result.failure("position 越界: %s" % str(world_pos))
		if not CoordsClass.is_on_map_edge(state, world_pos):
			return Result.failure("飞机必须放置在地图边缘格子: %s" % str(world_pos))

		var axis_read := MarketingRulesClass.require_airplane_axis(
			action,
			command,
			_infer_airplane_axis(state, world_pos, Vector2i.ONE)
		)
		if not axis_read.ok:
			return axis_read
		var axis: String = axis_read.value

		var minp2 := CoordsClass.get_world_min(state)
		var maxp2 := CoordsClass.get_world_max(state)

		# Axis must match the attached edge: left/right -> row (flies horizontally), top/bottom -> col (flies vertically).
		if axis == "row":
			if world_pos.x != minp2.x and world_pos.x != maxp2.x and world_pos.x != (maxp2.x - (thickness - 1)):
				return Result.failure("飞机 axis=row 时必须贴左右边缘: %s" % str(world_pos))
			var start_y := world_pos.y
			if start_y < minp2.y or (start_y + length - 1) > maxp2.y:
				return Result.failure("飞机不能飞出棋盘：长度=%d start_y=%d (min=%d max=%d)" % [length, start_y, minp2.y, maxp2.y])
		else:
			if world_pos.y != minp2.y and world_pos.y != maxp2.y and world_pos.y != (maxp2.y - (thickness - 1)):
				return Result.failure("飞机 axis=col 时必须贴上下边缘: %s" % str(world_pos))
			var start_x := world_pos.x
			if start_x < minp2.x or (start_x + length - 1) > maxp2.x:
				return Result.failure("飞机不能飞出棋盘：长度=%d start_x=%d (min=%d max=%d)" % [length, start_x, minp2.x, maxp2.x])

		# Prevent airplane vs airplane overlap on the same side (outside area).
		var airplane_overlap := _validate_airplane_overlap(state, world_pos, axis, thickness, length)
		if not airplane_overlap.ok:
			return airplane_overlap

		return Result.success()

	var size_read := MarketingRulesClass.get_rotated_footprint_size(base_size, rotation)
	if not size_read.ok:
		return size_read
	var size: Vector2i = size_read.value

	var footprint_cells: Array[Vector2i] = MarketingRulesClass.build_footprint_cells(world_pos, size)

	# 饮品进货点集合（用于“禁止覆盖 drink_source”校验，issue_tracker #35）。
	var drink_source_pos_set_read := _build_drink_source_pos_set(state)
	if not drink_source_pos_set_read.ok:
		return drink_source_pos_set_read
	var drink_source_pos_set: Dictionary = drink_source_pos_set_read.value

	# 1) 越界/建筑占用检查（所有占地格）
	for p in footprint_cells:
		if not CoordsClass.is_world_pos_in_grid(state, p):
			return Result.failure("position 越界: %s" % str(p))
		var cell := CellsClass.get_cell(state, p)
		if cell.is_empty():
			return Result.failure("position 无效: %s" % str(p))
		if not cell.has("structure") or not (cell["structure"] is Dictionary):
			return Result.failure("cell.structure 缺失或类型错误: %s" % str(p))
		var structure: Dictionary = cell["structure"]
		if not structure.is_empty():
			return Result.failure("该位置已有建筑，无法放置营销: %s" % str(p))
		# 禁止覆盖饮品进货点
		if not drink_source_pos_set.is_empty() and drink_source_pos_set.has(p):
			return Result.failure("该位置是饮品进货点，无法放置营销: %s" % str(p))
		var ds = cell.get("drink_source", null)
		if ds != null:
			if ds is Dictionary and (ds as Dictionary).is_empty():
				pass
			else:
				return Result.failure("该位置是饮品进货点，无法放置营销: %s" % str(p))

	var requires_edge := MarketingTypeRegistryClass.requires_edge(marketing_type)

	# 2) 边缘营销：要求“整条边贴边”（不能超出）
	if requires_edge:
		var minp := CoordsClass.get_world_min(state)
		var maxp := CoordsClass.get_world_max(state)
		var left := world_pos.x
		var right := world_pos.x + size.x - 1
		var top := world_pos.y
		var bottom := world_pos.y + size.y - 1
		var flush := (left == minp.x) or (right == maxp.x) or (top == minp.y) or (bottom == maxp.y)
		if not flush:
			return Result.failure("该营销必须有一条边完全贴地图边缘: %s" % str(world_pos))
	else:
		# 3) 非边缘营销：所有占地格必须在空地（非道路/非阻塞），且占地整体需邻接道路
		for p2 in footprint_cells:
			var cell2 := CellsClass.get_cell(state, p2)
			if not cell2.has("blocked") or not (cell2["blocked"] is bool):
				return Result.failure("cell.blocked 缺失或类型错误: %s" % str(p2))
			if bool(cell2["blocked"]):
				return Result.failure("该位置被阻塞: %s" % str(p2))
			if not cell2.has("road_segments") or not (cell2["road_segments"] is Array):
				return Result.failure("cell.road_segments 缺失或类型错误: %s" % str(p2))
			var road_segments: Array = cell2["road_segments"]
			if not road_segments.is_empty():
				return Result.failure("营销必须放置在空格（非道路）上: %s (anchor=%s board=#%d)" % [str(p2), str(world_pos), board_number])

		var footprint_set := {}
		for p3 in footprint_cells:
			footprint_set[p3] = true
		var has_adjacent_road := false
		for p4 in footprint_cells:
			for dir in MapUtilsClass.DIRECTIONS:
				var n := MapUtilsClass.get_neighbor_pos(p4, dir)
				if footprint_set.has(n):
					continue
				if not CoordsClass.is_world_pos_in_grid(state, n):
					continue
				if CellsClass.has_road_at(state, n):
					has_adjacent_road = true
					break
			if has_adjacent_road:
				break
		if not has_adjacent_road:
			return Result.failure("营销必须邻接道路: %s" % str(world_pos))

	# 4) 不允许与其他营销板件占地重叠
	var occupied_read := _has_marketing_overlap_excluding_airplane(state, footprint_cells)
	if not occupied_read.ok:
		return occupied_read
	if bool(occupied_read.value):
		return Result.failure("营销占地与其他营销板件重叠: %s" % str(world_pos))

	# === 距离校验（对齐员工卡 range）===
	var range_type := str(emp_def.range_type)
	var range_value := int(emp_def.range_value)
	if range_value >= 0 and not range_type.is_empty():
		# Airplane is NOT affected by range (validated above).
		if marketing_type == "airplane":
			return Result.success()
		if range_type == "road":
			# 对多格营销板件：距离应基于“占地邻接的道路格”，而不是仅用 anchor。
			var target_roads_r := RangeUtilsClass.get_adjacent_road_cells_for_positions(state, footprint_cells)
			if not target_roads_r.ok:
				return target_roads_r
			var target_road_cells: Array[Vector2i] = target_roads_r.value
			var min_r := RangeUtilsClass.get_min_road_distance_to_any_road_cells(
				state, command.actor, restaurant_ids, target_road_cells
			)
			if not min_r.ok:
				return min_r
			var min_d: int = int(min_r.value)
			if min_d < 0:
				return Result.failure("无法通过道路到达目标附近的道路（距离限制：%s %d）" % [range_type, range_value])
			if min_d > range_value:
				return Result.failure("超出距离范围: %s %d (min=%d)" % [range_type, range_value, min_d])
		elif range_type == "air":
			var range_ok_result := RangeUtilsClass.is_within_air_range_to_any_cells(
				state, command.actor, restaurant_ids, footprint_cells, range_value
			)
			if not range_ok_result.ok:
				return range_ok_result
			if not bool(range_ok_result.value):
				return Result.failure("超出距离范围: %s %d" % [range_type, range_value])
		else:
			return Result.failure("未知的 range_type: %s" % range_type)

	# 飞机营销需要选择飞行轴（row/col）；若未指定则按“贴边方向”推断
	if marketing_type == "airplane":
		var axis_result := action.optional_string_param(command, "axis", "")
		if not axis_result.ok:
			return axis_result
		var axis: String = axis_result.value
		if axis.is_empty():
			axis = _infer_airplane_axis(state, world_pos, size)
		if axis != "row" and axis != "col":
			return Result.failure("飞机缺少 axis（row/col）")

	return Result.success()

static func _validate_airplane_overlap(
	state: GameState,
	world_pos: Vector2i,
	axis: String,
	thickness: int,
	length: int
) -> Result:
	var placements_read := MapStateAccessClass.require_marketing_placements(state, "airplane overlap")
	if not placements_read.ok:
		return placements_read
	var placements: Dictionary = placements_read.value
	if placements.is_empty():
		return Result.success()

	var minp := CoordsClass.get_world_min(state)
	var maxp := CoordsClass.get_world_max(state)
	var side := ""
	var seg_start := 0
	var seg_end := 0
	if axis == "row":
		side = "W" if world_pos.x == minp.x else "E"
		seg_start = world_pos.y
		seg_end = world_pos.y + length - 1
	else:
		side = "N" if world_pos.y == minp.y else "S"
		seg_start = world_pos.x
		seg_end = world_pos.x + length - 1

	for key in placements.keys():
		var p_val = placements[key]
		if not (p_val is Dictionary):
			return Result.failure("airplane overlap: marketing_placements[%s] 类型错误（期望 Dictionary）" % str(key))
		var placement: Dictionary = p_val
		var type_val = placement.get("type", null)
		if not (type_val is String):
			return Result.failure("airplane overlap: marketing_placements[%s].type 缺失或类型错误（期望 String）" % str(key))
		var placement_type := str(type_val).strip_edges()
		if placement_type.is_empty():
			return Result.failure("airplane overlap: marketing_placements[%s].type 不能为空" % str(key))
		if placement_type != "airplane":
			continue
		var wp_val = placement.get("world_pos", null)
		if not (wp_val is Vector2i):
			return Result.failure("airplane overlap: marketing_placements[%s].world_pos 缺失或类型错误（期望 Vector2i）" % str(key))
		var existing_world_pos: Vector2i = wp_val
		var existing_axis := str(placement.get("axis", "")).strip_edges()
		if existing_axis != "row" and existing_axis != "col":
			return Result.failure("airplane overlap: marketing_placements[%s].axis 缺失或非法（期望 row/col）" % str(key))
		if existing_axis != axis:
			continue

		var footprint_read := _require_marketing_footprint_size(placement, "airplane overlap: marketing_placements[%s].footprint_size" % str(key))
		if not footprint_read.ok:
			return footprint_read
		var footprint: Vector2i = footprint_read.value
		var existing_length := 0
		if footprint.x == 2 and footprint.y != 2:
			existing_length = footprint.y
		elif footprint.y == 2 and footprint.x != 2:
			existing_length = footprint.x
		else:
			existing_length = maxi(footprint.x, footprint.y)
		if existing_length <= 0:
			continue

		var existing_side := ""
		var existing_start := 0
		var existing_end := 0
		if existing_axis == "row":
			if existing_world_pos.x == minp.x:
				existing_side = "W"
			elif existing_world_pos.x == maxp.x or existing_world_pos.x == (maxp.x - (thickness - 1)):
				existing_side = "E"
			else:
				return Result.failure("airplane overlap: marketing_placements[%s].world_pos 不在对应左右边缘: %s" % [str(key), str(existing_world_pos)])
			existing_start = existing_world_pos.y
			existing_end = existing_world_pos.y + existing_length - 1
		else:
			if existing_world_pos.y == minp.y:
				existing_side = "N"
			elif existing_world_pos.y == maxp.y or existing_world_pos.y == (maxp.y - (thickness - 1)):
				existing_side = "S"
			else:
				return Result.failure("airplane overlap: marketing_placements[%s].world_pos 不在对应上下边缘: %s" % [str(key), str(existing_world_pos)])
			existing_start = existing_world_pos.x
			existing_end = existing_world_pos.x + existing_length - 1

		if existing_side != side:
			continue
		var overlaps := not (seg_end < existing_start or seg_start > existing_end)
		if overlaps:
			return Result.failure("飞机与已有飞机占用同一边并重叠: %s" % side)

	return Result.success()

static func _build_drink_source_pos_set(state: GameState) -> Result:
	var sources_read := MapStateAccessClass.require_drink_sources(state, "initiate_marketing")
	if not sources_read.ok:
		return sources_read
	var sources: Array = sources_read.value
	var out := {}
	for i in range(sources.size()):
		var src_val = sources[i]
		if not (src_val is Dictionary):
			return Result.failure("initiate_marketing: state.map.drink_sources[%d] 类型错误（期望 Dictionary）" % i)
		var src: Dictionary = src_val
		var wp_val = src.get("world_pos", null)
		if not (wp_val is Vector2i):
			return Result.failure("initiate_marketing: state.map.drink_sources[%d].world_pos 缺失或类型错误（期望 Vector2i）" % i)
		var type_val = src.get("type", null)
		if not (type_val is String) or str(type_val).strip_edges().is_empty():
			return Result.failure("initiate_marketing: state.map.drink_sources[%d].type 缺失或为空" % i)
		out[Vector2i(wp_val)] = true
	return Result.success(out)

static func _require_marketing_footprint_size(placement: Dictionary, path: String) -> Result:
	if not placement.has("footprint_size"):
		return Result.failure("%s 缺失" % path)
	var read := _parse_vector2i_value(placement.get("footprint_size", null), path)
	if not read.ok:
		return read
	var size: Vector2i = read.value
	if size.x <= 0 or size.y <= 0:
		return Result.failure("%s 非法: %s" % [path, str(size)])
	return Result.success(size)

static func _require_marketing_rotation(placement: Dictionary, path: String) -> Result:
	if not placement.has("rotation"):
		return Result.failure("%s 缺失" % path)
	return _parse_int_value(placement.get("rotation", null), path)

static func _parse_vector2i_value(value, path: String) -> Result:
	if value is Vector2i:
		return Result.success(Vector2i(value))
	if value is Array:
		var arr: Array = value
		if arr.size() != 2:
			return Result.failure("%s 长度错误（期望 2）" % path)
		var x_read := _parse_int_value(arr[0], "%s[0]" % path)
		if not x_read.ok:
			return x_read
		var y_read := _parse_int_value(arr[1], "%s[1]" % path)
		if not y_read.ok:
			return y_read
		return Result.success(Vector2i(int(x_read.value), int(y_read.value)))
	return Result.failure("%s 类型错误（期望 Vector2i 或 [x,y] Array）" % path)

static func _parse_int_value(value, path: String) -> Result:
	if value is int:
		return Result.success(int(value))
	if value is float:
		var f: float = float(value)
		if f != floor(f):
			return Result.failure("%s 必须为整数" % path)
		return Result.success(int(f))
	return Result.failure("%s 类型错误（期望 int）" % path)

static func _count_reusable_marketing_uses_from_busy_groups_this_round(
	state: GameState,
	player_id: int,
	employee_type: String,
	mult: int
) -> int:
	if state == null:
		return 0
	if mult <= 1:
		return 0
	if not (state.marketing_instances is Array):
		return 0

	var by_link: Dictionary = {}
	for inst_val in state.marketing_instances:
		if not (inst_val is Dictionary):
			continue
		var inst: Dictionary = inst_val
		if int(inst.get("owner", -1)) != player_id:
			continue
		if str(inst.get("employee_type", "")).strip_edges() != employee_type:
			continue
		if int(inst.get("created_round", -1)) != state.round_number:
			continue
		var link_id := str(inst.get("link_id", "")).strip_edges()
		if link_id.is_empty():
			continue
		by_link[link_id] = int(by_link.get(link_id, 0)) + 1

	var remaining := 0
	for k in by_link.keys():
		var used := int(by_link.get(k, 0))
		remaining += maxi(0, mult - used)
	return remaining

static func _infer_airplane_axis(state: GameState, pos: Vector2i, size: Vector2i) -> String:
	# 默认：左右边缘 -> row（横飞），上下边缘 -> col（竖飞）
	# 语义：基于“整条边贴边”判断；若同时贴两条边（角落），保持旧优先级：先 row 后 col。
	var minp := CoordsClass.get_world_min(state)
	var maxp := CoordsClass.get_world_max(state)
	var left := pos.x
	var right := pos.x + size.x - 1
	var top := pos.y
	var bottom := pos.y + size.y - 1
	if left == minp.x or right == maxp.x:
		return "row"
	if top == minp.y or bottom == maxp.y:
		return "col"
	return ""

static func _has_marketing_overlap_excluding_airplane(state: GameState, footprint_cells: Array[Vector2i]) -> Result:
	# Keep UI/core rules consistent: airplane marketing is outside the board and should not block on-board marketing.
	var placements_read := MapStateAccessClass.require_marketing_placements(state, "marketing overlap")
	if not placements_read.ok:
		return placements_read
	var placements: Dictionary = placements_read.value
	if placements.is_empty():
		return Result.success(false)

	for k in placements.keys():
		var p_val = placements[k]
		if not (p_val is Dictionary):
			return Result.failure("marketing overlap: marketing_placements[%s] 类型错误（期望 Dictionary）" % str(k))
		var p: Dictionary = p_val
		var type_val = p.get("type", null)
		if not (type_val is String):
			return Result.failure("marketing overlap: marketing_placements[%s].type 缺失或类型错误（期望 String）" % str(k))
		var placement_type := str(type_val).strip_edges()
		if placement_type.is_empty():
			return Result.failure("marketing overlap: marketing_placements[%s].type 不能为空" % str(k))
		if placement_type == "airplane":
			continue

		var wp_val = p.get("world_pos", null)
		if not (wp_val is Vector2i):
			return Result.failure("marketing overlap: marketing_placements[%s].world_pos 缺失或类型错误（期望 Vector2i）" % str(k))
		var anchor: Vector2i = wp_val

		var base_size_read := _require_marketing_footprint_size(p, "marketing overlap: marketing_placements[%s].footprint_size" % str(k))
		if not base_size_read.ok:
			return base_size_read
		var base_size: Vector2i = base_size_read.value

		var rotation_read := _require_marketing_rotation(p, "marketing overlap: marketing_placements[%s].rotation" % str(k))
		if not rotation_read.ok:
			return rotation_read
		var rotation: int = int(rotation_read.value)
		var rotation_valid := MarketingRulesClass.require_rotation(rotation)
		if not rotation_valid.ok:
			return Result.failure("marketing overlap: marketing_placements[%s].rotation 非法: %s" % [str(k), str(rotation)])

		var size := base_size
		if rotation == 90 or rotation == 270:
			size = Vector2i(base_size.y, base_size.x)

		var left := anchor.x
		var right := anchor.x + size.x - 1
		var top := anchor.y
		var bottom := anchor.y + size.y - 1

		for c in footprint_cells:
			if c.x < left or c.x > right or c.y < top or c.y > bottom:
				continue
			return Result.success(true)

	return Result.success(false)
