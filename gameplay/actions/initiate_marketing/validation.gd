# InitiateMarketingAction 验证逻辑（抽离自 gameplay/actions/initiate_marketing_action.gd）
extends RefCounted

const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MarketingRegistryClass = preload("res://core/data/marketing_registry.gd")
const MarketingTypeRegistryClass = preload("res://core/rules/marketing_type_registry.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")
const MapRuntimeClass = preload("res://core/map/map_runtime.gd")
const RangeUtilsClass = preload("res://core/utils/range_utils.gd")
const RoundStateCountersClass = preload("res://core/utils/round_state_counters.gd")

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
	if not state.map.has("marketing_placements") or not (state.map["marketing_placements"] is Dictionary):
		return Result.failure("state.map.marketing_placements 缺失或类型错误")
	var placements: Dictionary = state.map["marketing_placements"]
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
	var restaurant_ids := MapRuntimeClass.get_player_restaurants(state, command.actor)
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

	# 放置校验：位置/空格/邻路/边缘等
	if not MapRuntimeClass.is_world_pos_in_grid(state, world_pos):
		return Result.failure("position 越界: %s" % str(world_pos))

	var cell := MapRuntimeClass.get_cell(state, world_pos)
	if cell.is_empty():
		return Result.failure("position 无效: %s" % str(world_pos))
	if not cell.has("structure") or not (cell["structure"] is Dictionary):
		return Result.failure("cell.structure 缺失或类型错误: %s" % str(world_pos))
	var structure: Dictionary = cell["structure"]
	if not structure.is_empty():
		return Result.failure("该位置已有建筑，无法放置营销: %s" % str(world_pos))

	if MarketingTypeRegistryClass.requires_edge(marketing_type):
		if not MapRuntimeClass.is_on_map_edge(state, world_pos):
			return Result.failure("该营销必须放置在地图边缘: %s" % str(world_pos))
	else:
		if not cell.has("blocked") or not (cell["blocked"] is bool):
			return Result.failure("cell.blocked 缺失或类型错误: %s" % str(world_pos))
		if bool(cell["blocked"]):
			return Result.failure("该位置被阻塞: %s" % str(world_pos))
		if not cell.has("road_segments") or not (cell["road_segments"] is Array):
			return Result.failure("cell.road_segments 缺失或类型错误: %s" % str(world_pos))
		var road_segments: Array = cell["road_segments"]
		if not road_segments.is_empty():
			return Result.failure("营销必须放置在空格（非道路）上: %s" % str(world_pos))
		var adjacent_roads_result := RangeUtilsClass.get_adjacent_road_cells(state, world_pos)
		if not adjacent_roads_result.ok:
			return adjacent_roads_result
		var adjacent_roads: Array[Vector2i] = adjacent_roads_result.value
		if adjacent_roads.is_empty():
			return Result.failure("营销必须邻接道路: %s" % str(world_pos))

	# 同一位置不能放多个营销板件
	for key in placements.keys():
		var p_val = placements[key]
		if not (p_val is Dictionary):
			return Result.failure("marketing_placements[%s] 类型错误（期望 Dictionary）" % str(key))
		var p: Dictionary = p_val
		if not p.has("world_pos") or not (p["world_pos"] is Vector2i):
			return Result.failure("marketing_placements[%s].world_pos 缺失或类型错误" % str(key))
		if p["world_pos"] == world_pos:
			return Result.failure("该位置已放置其他营销板件: %s" % str(world_pos))

	# 距离校验（对齐员工卡 range）
	var range_type := str(emp_def.range_type)
	var range_value := int(emp_def.range_value)
	if range_value >= 0 and not range_type.is_empty():
		if range_type == "road":
			var range_ok_result := RangeUtilsClass.is_within_road_range(
				state, command.actor, restaurant_ids, world_pos, range_value
			)
			if not range_ok_result.ok:
				return range_ok_result
			if not bool(range_ok_result.value):
				return Result.failure("超出距离范围: %s %d" % [range_type, range_value])
		elif range_type == "air":
			var range_ok_result := RangeUtilsClass.is_within_air_range(
				state, command.actor, restaurant_ids, world_pos, range_value
			)
			if not range_ok_result.ok:
				return range_ok_result
			if not bool(range_ok_result.value):
				return Result.failure("超出距离范围: %s %d" % [range_type, range_value])
		else:
			return Result.failure("未知的 range_type: %s" % range_type)

	# 飞机营销需要选择飞行轴（row/col）；若未指定则按边缘推断
	if marketing_type == "airplane":
		var axis_result := action.optional_string_param(command, "axis", "")
		if not axis_result.ok:
			return axis_result
		var axis: String = axis_result.value
		if axis.is_empty():
			axis = _infer_airplane_axis(state, world_pos)
		if axis != "row" and axis != "col":
			return Result.failure("飞机缺少 axis（row/col）")

	return Result.success()

static func _infer_airplane_axis(state: GameState, pos: Vector2i) -> String:
	# 默认：左右边缘 -> row（横飞），上下边缘 -> col（竖飞）
	var minp := MapRuntimeClass.get_world_min(state)
	var maxp := MapRuntimeClass.get_world_max(state)
	if pos.x == minp.x or pos.x == maxp.x:
		return "row"
	if pos.y == minp.y or pos.y == maxp.y:
		return "col"
	return ""
