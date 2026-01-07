# 发起营销动作（Working 子阶段：Marketing）
# 放置营销板件并将营销员置为忙碌，创建营销实例，待 Marketing 阶段统一结算产生需求。
class_name InitiateMarketingAction
extends ActionExecutor

const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MarketingRegistryClass = preload("res://core/data/marketing_registry.gd")
const MarketingTypeRegistryClass = preload("res://core/rules/marketing_type_registry.gd")
const MarketingInitiationRegistryClass = preload("res://core/rules/marketing_initiation_registry.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")
const MilestoneRegistryClass = preload("res://core/data/milestone_registry.gd")
const MilestoneDefClass = preload("res://core/data/milestone_def.gd")
const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")
const MapRuntimeClass = preload("res://core/map/map_runtime.gd")
const RangeUtilsClass = preload("res://core/utils/range_utils.gd")
const RoundStateCountersClass = preload("res://core/utils/round_state_counters.gd")

func _init() -> void:
	action_id = "initiate_marketing"
	display_name = "发起营销"
	description = "放置营销板件并创建营销活动"
	requires_actor = true
	is_mandatory = false
	allowed_phases = ["Working"]
	allowed_sub_phases = ["Marketing"]

func can_initiate(state: GameState, player_id: int) -> bool:
	if state == null:
		return true
	if state.get_current_player_id() != player_id:
		return false

	var player := state.get_player(player_id)
	var employees_val = player.get("employees", [])
	if not (employees_val is Array):
		return true
	var employees: Array = employees_val

	var has_marketer := false
	var seen := {}
	for emp_val in employees:
		if not (emp_val is String):
			continue
		var emp_id: String = str(emp_val)
		if emp_id.is_empty():
			continue
		if seen.has(emp_id):
			continue
		seen[emp_id] = true

		var def_val = EmployeeRegistryClass.get_def(emp_id)
		if def_val == null or not (def_val is EmployeeDef):
			continue
		var def: EmployeeDef = def_val
		for t in def.usage_tags:
			var s: String = str(t)
			if s.begins_with("use:marketing:"):
				has_marketer = true
				break
		if has_marketer:
			break

	if not has_marketer:
		return false

	var used := {}
	for inst_val in state.marketing_instances:
		if inst_val is Dictionary:
			var bn = Dictionary(inst_val).get("board_number", null)
			if bn is int:
				used[str(int(bn))] = true
	if state.map is Dictionary and state.map.has("marketing_placements") and (state.map["marketing_placements"] is Dictionary):
		var placements: Dictionary = state.map["marketing_placements"]
		for k in placements.keys():
			used[str(k)] = true

	var player_count := state.players.size()
	for bn2 in MarketingRegistryClass.get_all_board_numbers():
		if used.has(str(bn2)):
			continue
		var def2 = MarketingRegistryClass.get_def(bn2)
		if def2 == null or not def2.has_method("is_available_for_player_count"):
			continue
		if not def2.is_available_for_player_count(player_count):
			continue
		return true

	return false

func _validate_specific(state: GameState, command: Command) -> Result:
	var current_player_id := state.get_current_player_id()
	if command.actor != current_player_id:
		return Result.failure("不是你的回合")

	var employee_type_result := require_string_param(command, "employee_type")
	if not employee_type_result.ok:
		return employee_type_result
	var employee_type: String = employee_type_result.value

	var board_number_result := require_int_param(command, "board_number")
	if not board_number_result.ok:
		return board_number_result
	var board_number: int = board_number_result.value
	if board_number <= 0:
		return Result.failure("board_number 必须 > 0")

	var product_result := require_string_param(command, "product")
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

	var world_pos_result := _require_world_pos(command)
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

	var duration_result := optional_int_param(command, "duration", max_duration)
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
		var axis_result := optional_string_param(command, "axis", "")
		if not axis_result.ok:
			return axis_result
		var axis: String = axis_result.value
		if axis.is_empty():
			axis = _infer_airplane_axis(state, world_pos)
		if axis != "row" and axis != "col":
			return Result.failure("飞机缺少 axis（row/col）")

	return Result.success()

func _apply_changes(state: GameState, command: Command) -> Result:
	var player_id: int = command.actor
	var employee_type_result := require_string_param(command, "employee_type")
	if not employee_type_result.ok:
		return employee_type_result
	var employee_type: String = employee_type_result.value

	var board_number_result := require_int_param(command, "board_number")
	if not board_number_result.ok:
		return board_number_result
	var board_number: int = board_number_result.value

	var product_result := require_string_param(command, "product")
	if not product_result.ok:
		return product_result
	var product: String = product_result.value

	var world_pos_result := _require_world_pos(command)
	if not world_pos_result.ok:
		return world_pos_result
	var world_pos: Vector2i = world_pos_result.value

	var def = MarketingRegistryClass.get_def(board_number)
	if def == null:
		return Result.failure("未知的营销板件编号: %d" % board_number)
	var marketing_type := str(def.type)

	var emp_def = EmployeeRegistryClass.get_def(employee_type)
	if emp_def == null:
		return Result.failure("未知的员工类型: %s" % employee_type)
	var max_duration := int(emp_def.marketing_max_duration)
	var duration_result := optional_int_param(command, "duration", max_duration)
	if not duration_result.ok:
		return duration_result
	var duration: int = duration_result.value
	if duration <= 0:
		return Result.failure("duration 必须 > 0")
	if duration > max_duration:
		return Result.failure("持续时间超出上限: %d > %d" % [duration, max_duration])

	var effective_duration := duration
	var player := state.get_player(player_id)
	if not player.is_empty() and player.has("milestones"):
		var milestones_val = player.get("milestones", null)
		if not (milestones_val is Array):
			return Result.failure("initiate_marketing: player.milestones 类型错误（期望 Array）")
		var milestones: Array = milestones_val

		# 里程碑效果：marketing_permanent -> 之后放置的营销活动永久生效（duration=-1）
		for i in range(milestones.size()):
			var mid_val = milestones[i]
			if not (mid_val is String):
				return Result.failure("initiate_marketing: player.milestones[%d] 类型错误（期望 String）" % i)
			var mid: String = str(mid_val)
			if mid.is_empty():
				return Result.failure("initiate_marketing: player.milestones 不应包含空字符串")

			var def_val = MilestoneRegistryClass.get_def(mid)
			if def_val == null:
				return Result.failure("initiate_marketing: 未知里程碑定义: %s" % mid)
			if not (def_val is MilestoneDefClass):
				return Result.failure("initiate_marketing: 里程碑定义类型错误（期望 MilestoneDef）: %s" % mid)
			var ms_def = def_val

			for e_i in range(ms_def.effects.size()):
				var eff_val = ms_def.effects[e_i]
				if not (eff_val is Dictionary):
					return Result.failure("initiate_marketing: %s.effects[%d] 类型错误（期望 Dictionary）" % [mid, e_i])
				var eff: Dictionary = eff_val
				var type_val = eff.get("type", null)
				if not (type_val is String):
					return Result.failure("initiate_marketing: %s.effects[%d].type 类型错误（期望 String）" % [mid, e_i])
				var t: String = str(type_val)
				if t == "marketing_permanent":
					effective_duration = -1
					break

			if effective_duration == -1:
				break

	# 将营销员从在岗移到忙碌（不占卡槽）
	var removed := StateUpdater.remove_from_array(state.players[player_id], "employees", employee_type)
	if not removed:
		return Result.failure("你没有激活的 %s" % employee_type)
	StateUpdater.append_to_array(state.players[player_id], "busy_marketers", employee_type)

	var inc_result := RoundStateCountersClass.increment_player_key_count(
		state.round_state, "marketing_used", player_id, employee_type, 1
	)
	if not inc_result.ok:
		return inc_result
	var warnings: Array[String] = []

	# 使用员工：用于“first_marketeer_used”等里程碑
	var ms_use := MilestoneSystemClass.process_event(state, "UseEmployee", {"player_id": player_id, "id": employee_type})
	if not ms_use.ok:
		warnings.append("里程碑触发失败(UseEmployee/%s): %s" % [employee_type, ms_use.error])

	# 飞机轴与 tile 索引
	var axis := ""
	var tile_index := -1
	if marketing_type == "airplane":
		var axis_result := optional_string_param(command, "axis", "")
		if not axis_result.ok:
			return axis_result
		axis = axis_result.value
		if axis.is_empty():
			axis = _infer_airplane_axis(state, world_pos)
		if axis != "row" and axis != "col":
			return Result.failure("飞机缺少 axis（row/col）")
		var tile_pos: Vector2i = MapUtils.world_to_tile(world_pos).board_pos
		tile_index = tile_pos.y if axis == "row" else tile_pos.x

	# 创建营销实例（按 board_number 唯一）
	var instance := {
		"board_number": board_number,
		"type": marketing_type,
		"owner": player_id,
		"employee_type": employee_type,
		"product": product,
		"world_pos": world_pos,
		"remaining_duration": effective_duration,
		"axis": axis,
		"tile_index": tile_index,
		"created_round": state.round_number,
	}
	state.marketing_instances.append(instance)

	# 记录放置信息（供 UI/调试）
	if not state.map.has("marketing_placements") or not (state.map["marketing_placements"] is Dictionary):
		return Result.failure("state.map.marketing_placements 缺失或类型错误")
	state.map["marketing_placements"][str(board_number)] = {
		"board_number": board_number,
		"type": marketing_type,
		"owner": player_id,
		"product": product,
		"world_pos": world_pos,
		"remaining_duration": effective_duration,
		"axis": axis,
		"tile_index": tile_index,
	}

	var ms := MilestoneSystemClass.process_event(state, "InitiateMarketing", {
		"player_id": player_id,
		"type": marketing_type,
		"employee_type": employee_type,
		"employee_is_marketeer": _is_employee_marketeer(emp_def),
	})

	var ext_apply := MarketingInitiationRegistryClass.apply(state, command, instance)
	if not ext_apply.ok:
		return ext_apply

	var result := Result.success({
		"player_id": player_id,
		"employee_type": employee_type,
		"board_number": board_number,
		"type": marketing_type,
		"product": product,
		"duration": duration,
		"remaining_duration": effective_duration,
		"world_pos": world_pos
	})
	if not ms.ok:
		result.with_warning("里程碑触发失败(InitiateMarketing): %s" % ms.error)
	result.with_warnings(ext_apply.warnings)
	result.with_warnings(warnings)
	return result

func _is_employee_marketeer(emp_def: EmployeeDef) -> bool:
	if emp_def == null:
		return false
	if not (emp_def.usage_tags is Array):
		return false
	for t in emp_def.usage_tags:
		if t is String and str(t).begins_with("use:marketing:"):
			return true
	return false

func _generate_specific_events(_old_state: GameState, _new_state: GameState, command: Command) -> Array[Dictionary]:
	var employee_type_result := require_string_param(command, "employee_type")
	assert(employee_type_result.ok, "initiate_marketing 缺少/错误参数: employee_type")
	var employee_type: String = employee_type_result.value

	var board_number_result := require_int_param(command, "board_number")
	assert(board_number_result.ok, "initiate_marketing 缺少/错误参数: board_number")
	var board_number: int = board_number_result.value

	var product_result := require_string_param(command, "product")
	assert(product_result.ok, "initiate_marketing 缺少/错误参数: product")
	var product: String = product_result.value
	assert(ProductRegistryClass.has(product), "initiate_marketing 未知的产品: %s" % product)

	var world_pos_result := require_vector2i_param(command, "position")
	assert(world_pos_result.ok, "initiate_marketing 缺少/错误参数: position")
	var world_pos: Vector2i = world_pos_result.value
	var p := [world_pos.x, world_pos.y]

	var def = MarketingRegistryClass.get_def(board_number)
	assert(def != null, "initiate_marketing 未知的营销板件编号: %d" % board_number)
	var marketing_type := str(def.type)

	var emp_def = EmployeeRegistryClass.get_def(employee_type)
	assert(emp_def != null, "initiate_marketing 未知的员工类型: %s" % employee_type)
	var max_duration: int = int(emp_def.marketing_max_duration)
	assert(max_duration > 0, "initiate_marketing 该员工无法发起营销")

	var duration_result := optional_int_param(command, "duration", max_duration)
	assert(duration_result.ok, "initiate_marketing 参数 duration 类型错误")
	var duration: int = duration_result.value
	assert(duration > 0, "initiate_marketing duration 必须 > 0")
	assert(duration <= max_duration, "initiate_marketing 持续时间超出上限: %d > %d" % [duration, max_duration])

	var axis := ""
	if marketing_type == "airplane":
		var axis_result := optional_string_param(command, "axis", "")
		assert(axis_result.ok, "initiate_marketing 参数 axis 类型错误")
		axis = axis_result.value
		if axis.is_empty():
			axis = _infer_airplane_axis(_new_state, world_pos)
		assert(axis == "row" or axis == "col", "initiate_marketing 飞机缺少 axis（row/col）")

	return [{
		"type": EventBus.EventType.MARKETING_PLACED,
		"data": {
			"player_id": command.actor,
			"employee_type": employee_type,
			"board_number": board_number,
			"product": product,
			"duration": duration,
			"axis": axis,
			"position": p,
		}
	}]

# === 内部：放置/距离校验 ===

func _infer_airplane_axis(state: GameState, pos: Vector2i) -> String:
	# 默认：左右边缘 -> row（横飞），上下边缘 -> col（竖飞）
	var minp := MapRuntimeClass.get_world_min(state)
	var maxp := MapRuntimeClass.get_world_max(state)
	if pos.x == minp.x or pos.x == maxp.x:
		return "row"
	if pos.y == minp.y or pos.y == maxp.y:
		return "col"
	return ""

func _require_world_pos(command: Command) -> Result:
	return require_vector2i_param(command, "position")
