# InitiateMarketingAction 验证逻辑（抽离自 gameplay/actions/initiate_marketing_action.gd）
extends RefCounted

const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MarketingRegistryClass = preload("res://core/data/marketing_registry.gd")
const MarketingTypeRegistryClass = preload("res://core/rules/marketing_type_registry.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")
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
	if not ProductRegistryClass.has(product):
		return Result.failure("未知的产品: %s" % product)
	var p_def = ProductRegistryClass.get_def(product)
	if p_def == null:
		return Result.failure("未知的产品: %s" % product)
	if p_def is ProductDef and (p_def as ProductDef).has_tag("no_marketing"):
		return Result.failure("该产品不能被营销: %s" % product)

	var world_pos_result := action.require_vector2i_param(command, "position")
	if not world_pos_result.ok:
		return world_pos_result
	var world_pos: Vector2i = world_pos_result.value

	var rotation_result := action.optional_int_param(command, "rotation", 0)
	if not rotation_result.ok:
		return rotation_result
	var rotation: int = int(rotation_result.value)
	if not MapUtilsClass.VALID_ROTATIONS.has(rotation):
		return Result.failure("rotation 非法（期望 0/90/180/270），实际: %d" % rotation)

	var def = MarketingRegistryClass.get_def(board_number)
	if def == null:
		return Result.failure("未知的营销板件编号: %d" % board_number)
	var marketing_type := str(def.type)
	if not MarketingTypeRegistryClass.has_type(marketing_type):
		return Result.failure("未知的营销类型: %s" % marketing_type)

	if not def.has_method("is_available_for_player_count") or not def.is_available_for_player_count(state.players.size()):
		return Result.failure("该营销板件在当前玩家数下已移除: #%d" % board_number)

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
	var emp_def = EmployeeRegistryClass.get_def(employee_type)
	if emp_def == null:
		return Result.failure("未知的员工类型: %s" % employee_type)
	var required_usage := "use:marketing:%s" % marketing_type
	if not emp_def.has_usage_tag(required_usage):
		return Result.failure("该员工无法发起 %s 营销" % marketing_type)

	var max_duration := int(emp_def.marketing_max_duration)
	if max_duration <= 0:
		return Result.failure("该员工无法发起营销")

	var duration_result := action.optional_int_param(command, "duration", max_duration)
	if not duration_result.ok:
		return duration_result
	var duration: int = duration_result.value
	if duration <= 0:
		return Result.failure("duration 必须 > 0")
	if duration > max_duration:
		return Result.failure("持续时间超出上限: %d > %d" % [duration, max_duration])

	# 玩家必须有餐厅
	var restaurant_ids := StructuresClass.get_player_restaurants(state, command.actor)
	if restaurant_ids.is_empty():
		return Result.failure("你没有餐厅，无法发起营销")

	# 检查玩家是否拥有可用的营销员（每张卡每回合一次）
	var player := state.get_player(command.actor)
	var active_count := EmployeeRulesClass.count_active(player, employee_type)
	if active_count <= 0:
		return Result.failure("你没有激活的 %s" % employee_type)
	var used_result := RoundStateCountersClass.get_player_key_count(
		state.round_state, "marketing_used", command.actor, employee_type
	)
	if not used_result.ok:
		return used_result
	var used := int(used_result.value)
	if used >= active_count:
		return Result.failure("所有 %s 本子阶段已发起营销: %d/%d" % [employee_type, used, active_count])

	# === 放置校验：占地/边界/阻塞/道路/边缘/重叠 ===
	var base_size := Vector2i.ONE
	if def is MarketingDef:
		base_size = (def as MarketingDef).footprint_size
	elif def.has_method("get"):
		var fs = def.get("footprint_size")
		if fs is Vector2i:
			base_size = fs
	if base_size.x <= 0 or base_size.y <= 0:
		return Result.failure("营销板件占地非法: %s" % str(base_size))

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

		var axis_result := action.optional_string_param(command, "axis", "")
		if not axis_result.ok:
			return axis_result
		var axis: String = axis_result.value
		if axis.is_empty():
			axis = _infer_airplane_axis(state, world_pos, Vector2i.ONE)

		if axis != "row" and axis != "col":
			return Result.failure("飞机缺少 axis（row/col）")

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
		var placements2: Dictionary = state.map.get("marketing_placements", {})
		if placements2 is Dictionary and not placements2.is_empty():
			var side := ""
			var seg_start := 0
			var seg_end := 0
			if axis == "row":
				side = "W" if world_pos.x == minp2.x else "E"
				seg_start = world_pos.y
				seg_end = world_pos.y + length - 1
			else:
				side = "N" if world_pos.y == minp2.y else "S"
				seg_start = world_pos.x
				seg_end = world_pos.x + length - 1

			for k2 in placements2.keys():
				var pv = placements2[k2]
				if not (pv is Dictionary):
					continue
				var p2: Dictionary = pv
				if str(p2.get("type", "")) != "airplane":
					continue
				var wp2_val = p2.get("world_pos", null)
				if not (wp2_val is Vector2i):
					continue
				var wp2: Vector2i = wp2_val
				var axis2 := str(p2.get("axis", "")).strip_edges()
				if axis2 != "row" and axis2 != "col":
					axis2 = _infer_airplane_axis(state, wp2, Vector2i.ONE)
				if axis2 != axis:
					continue

				var fs2_val = p2.get("footprint_size", null)
				var fs2 := Vector2i.ONE
				if fs2_val is Vector2i:
					fs2 = Vector2i(fs2_val)
				elif fs2_val is Array:
					var a2: Array = fs2_val
					if a2.size() == 2:
						fs2 = Vector2i(int(a2[0]), int(a2[1]))
				var len2 := 0
				if fs2.x == 2 and fs2.y != 2:
					len2 = fs2.y
				elif fs2.y == 2 and fs2.x != 2:
					len2 = fs2.x
				else:
					len2 = maxi(fs2.x, fs2.y)
				if len2 <= 0:
					continue

				var side2 := ""
				var start2 := 0
				var end2 := 0
				if axis2 == "row":
					if wp2.x == minp2.x:
						side2 = "W"
					elif wp2.x == maxp2.x or wp2.x == (maxp2.x - (thickness - 1)):
						side2 = "E"
					else:
						continue
					start2 = wp2.y
					end2 = wp2.y + len2 - 1
				else:
					if wp2.y == minp2.y:
						side2 = "N"
					elif wp2.y == maxp2.y or wp2.y == (maxp2.y - (thickness - 1)):
						side2 = "S"
					else:
						continue
					start2 = wp2.x
					end2 = wp2.x + len2 - 1

				if side2 != side:
					continue
				var overlaps := not (seg_end < start2 or seg_start > end2)
				if overlaps:
					return Result.failure("飞机与已有飞机占用同一边并重叠: %s" % side)

		return Result.success()

	var size := base_size
	if rotation == 90 or rotation == 270:
		size = Vector2i(base_size.y, base_size.x)

	var footprint_cells: Array[Vector2i] = []
	for dy in range(size.y):
		for dx in range(size.x):
			footprint_cells.append(world_pos + Vector2i(dx, dy))

	# 饮品进货点集合（用于“禁止覆盖 drink_source”校验，issue_tracker #35）。
	var drink_source_pos_set := {}
	var sources_val = state.map.get("drink_sources", null)
	if sources_val is Array:
		var sources: Array = sources_val
		for s_val in sources:
			if not (s_val is Dictionary):
				continue
			var s: Dictionary = s_val
			var wp_val = s.get("world_pos", null)
			if wp_val is Vector2i:
				drink_source_pos_set[Vector2i(wp_val)] = true

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
	if state == null or not (state.map is Dictionary):
		return Result.failure("marketing overlap: state.map 类型错误")
	var placements_val = state.map.get("marketing_placements", null)
	if placements_val == null:
		return Result.success(false)
	if not (placements_val is Dictionary):
		return Result.failure("marketing overlap: state.map.marketing_placements 类型错误（期望 Dictionary）")
	var placements: Dictionary = placements_val
	if placements.is_empty():
		return Result.success(false)

	for k in placements.keys():
		var p_val = placements[k]
		if not (p_val is Dictionary):
			return Result.failure("marketing overlap: marketing_placements[%s] 类型错误（期望 Dictionary）" % str(k))
		var p: Dictionary = p_val
		if str(p.get("type", "")) == "airplane":
			continue

		var wp_val = p.get("world_pos", null)
		if not (wp_val is Vector2i):
			return Result.failure("marketing overlap: marketing_placements[%s].world_pos 缺失或类型错误（期望 Vector2i）" % str(k))
		var anchor: Vector2i = wp_val

		var base_size := Vector2i.ONE
		var fs_val = p.get("footprint_size", null)
		if fs_val is Vector2i:
			base_size = Vector2i(fs_val)
		elif fs_val is Array:
			var arr: Array = fs_val
			if arr.size() == 2:
				base_size = Vector2i(int(arr[0]), int(arr[1]))
		if base_size.x <= 0 or base_size.y <= 0:
			base_size = Vector2i.ONE

		var rotation := 0
		var rot_val = p.get("rotation", null)
		if rot_val is int:
			rotation = int(rot_val)
		elif rot_val is float:
			var f: float = float(rot_val)
			if f == floor(f):
				rotation = int(f)
		if not rotation in [0, 90, 180, 270]:
			rotation = 0

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
