class_name PlaceCampaignManagerSecondTileAction
extends ActionExecutor

const RangeUtilsClass = preload("res://core/utils/range_utils.gd")
const MapRuntimeClass = preload("res://core/map/map_runtime.gd")
const MarketingRegistryClass = preload("res://core/data/marketing_registry.gd")
const MarketingTypeRegistryClass = preload("res://core/rules/marketing_type_registry.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")

const MILESTONE_ID := "first_campaign_manager_used"
const PENDING_KEY := "new_milestones_campaign_manager_pending"

func _init() -> void:
	action_id = "place_campaign_manager_second_tile"
	display_name = "追加放置第二张营销板件（营销经理）"
	description = "同回合内追加放置同类型营销板件（billboard/mailbox），与第一次相同商品/持续时间；不绑定额外营销员"
	requires_actor = true
	is_mandatory = false
	allowed_phases = ["Working"]
	allowed_sub_phases = ["Marketing"]

func _validate_specific(state: GameState, command: Command) -> Result:
	var current_player_id := state.get_current_player_id()
	if command.actor != current_player_id:
		return Result.failure("不是你的回合")

	if not (state.players is Array):
		return Result.failure("state.players 类型错误（期望 Array）")
	if not (state.round_state is Dictionary):
		return Result.failure("state.round_state 类型错误（期望 Dictionary）")
	if not (state.map is Dictionary):
		return Result.failure("state.map 类型错误（期望 Dictionary）")
	if not state.map.has("marketing_placements") or not (state.map["marketing_placements"] is Dictionary):
		return Result.failure("state.map.marketing_placements 缺失或类型错误")
	var placements: Dictionary = state.map["marketing_placements"]

	var player_val = state.players[command.actor]
	if not (player_val is Dictionary):
		return Result.failure("player 类型错误（期望 Dictionary）")
	var player: Dictionary = player_val
	if not player.has("milestones") or not (player["milestones"] is Array):
		return Result.failure("player.milestones 缺失或类型错误（期望 Array）")
	var milestones: Array = player["milestones"]
	if not milestones.has(MILESTONE_ID):
		return Result.failure("未获得里程碑：%s" % MILESTONE_ID)

	if not state.round_state.has(PENDING_KEY):
		return Result.failure("当前没有可追加放置的第二张营销板件")
	var pending_val = state.round_state.get(PENDING_KEY, null)
	if not (pending_val is Dictionary):
		return Result.failure("round_state.%s 类型错误（期望 Dictionary）" % PENDING_KEY)
	var pending: Dictionary = pending_val
	if not pending.has(command.actor):
		return Result.failure("当前没有可追加放置的第二张营销板件")
	var info_val = pending.get(command.actor, null)
	if not (info_val is Dictionary):
		return Result.failure("round_state.%s[%d] 类型错误（期望 Dictionary）" % [PENDING_KEY, int(command.actor)])
	var info: Dictionary = info_val

	var mk_type: String = str(info.get("type", ""))
	if mk_type != "billboard" and mk_type != "mailbox":
		return Result.failure("pending.type 非法: %s" % mk_type)
	var product: String = str(info.get("product", ""))
	if product.is_empty():
		return Result.failure("pending.product 不能为空")
	var duration_val = info.get("remaining_duration", null)
	if not (duration_val is int):
		return Result.failure("pending.remaining_duration 缺失或类型错误（期望 int）")
	var duration: int = int(duration_val)
	if duration == 0:
		return Result.failure("pending.remaining_duration 不应为 0")
	var link_id: String = str(info.get("link_id", ""))
	if link_id.is_empty():
		return Result.failure("pending.link_id 不能为空")
	var employee_type: String = str(info.get("employee_type", ""))
	if employee_type != "campaign_manager":
		return Result.failure("pending.employee_type 非法: %s" % employee_type)

	var board_number_result := require_int_param(command, "board_number")
	if not board_number_result.ok:
		return board_number_result
	var board_number: int = board_number_result.value
	if board_number <= 0:
		return Result.failure("board_number 必须 > 0")

	var world_pos_result := require_vector2i_param(command, "position")
	if not world_pos_result.ok:
		return world_pos_result
	var world_pos: Vector2i = world_pos_result.value

	var def = MarketingRegistryClass.get_def(board_number)
	if def == null:
		return Result.failure("未知的营销板件编号: %d" % board_number)
	var def_type := str(def.type)
	if def_type != mk_type:
		return Result.failure("第二张板件类型必须为 %s，实际: %s" % [mk_type, def_type])
	if not MarketingTypeRegistryClass.has_type(def_type):
		return Result.failure("未知的营销类型: %s" % def_type)
	if not def.has_method("is_available_for_player_count") or not def.is_available_for_player_count(state.players.size()):
		return Result.failure("该营销板件在当前玩家数下已移除: #%d" % board_number)

	# 检查编号唯一占用
	for inst_val in state.marketing_instances:
		if not (inst_val is Dictionary):
			return Result.failure("marketing_instances 元素类型错误（期望 Dictionary）")
		var inst: Dictionary = inst_val
		if not inst.has("board_number") or not (inst["board_number"] is int):
			return Result.failure("marketing_instances.board_number 缺失或类型错误（期望 int）")
		if int(inst["board_number"]) == board_number:
			return Result.failure("营销板件已在使用中: #%d" % board_number)
	if placements.has(str(board_number)):
		return Result.failure("营销板件已在使用中: #%d" % board_number)

	# 放置校验（对齐 initiate_marketing 的规则）
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

	if MarketingTypeRegistryClass.requires_edge(def_type):
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

	# 距离校验：使用 campaign_manager 的 range
	var emp_def = EmployeeRegistryClass.get_def(employee_type)
	if emp_def == null:
		return Result.failure("未知的员工类型: %s" % employee_type)
	var range_type := str(emp_def.range_type)
	var range_value := int(emp_def.range_value)
	if range_value >= 0 and not range_type.is_empty():
		var restaurant_ids: Array[String] = MapRuntimeClass.get_player_restaurants(state, command.actor)
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

	return Result.success({
		"link_id": link_id,
		"type": mk_type,
		"product": product,
		"remaining_duration": duration,
		"board_number": board_number,
		"world_pos": world_pos,
	})

func _apply_changes(state: GameState, command: Command) -> Result:
	var validate := _validate_specific(state, command)
	if not validate.ok:
		return validate
	var info: Dictionary = validate.value

	var player_id: int = command.actor
	var link_id: String = str(info["link_id"])
	var mk_type: String = str(info["type"])
	var product: String = str(info["product"])
	var remaining_duration: int = int(info["remaining_duration"])
	var board_number: int = int(info["board_number"])
	var world_pos: Vector2i = info["world_pos"]

	var instance := {
		"board_number": board_number,
		"type": mk_type,
		"owner": player_id,
		"employee_type": "campaign_manager",
		"product": product,
		"world_pos": world_pos,
		"remaining_duration": remaining_duration,
		"axis": "",
		"tile_index": -1,
		"created_round": state.round_number,
		"link_id": link_id,
	}
	state.marketing_instances.append(instance)

	state.map["marketing_placements"][str(board_number)] = {
		"board_number": board_number,
		"type": mk_type,
		"owner": player_id,
		"product": product,
		"world_pos": world_pos,
		"remaining_duration": remaining_duration,
		"axis": "",
		"tile_index": -1,
	}

	# 消耗本回合能力
	var pending: Dictionary = state.round_state[PENDING_KEY]
	pending.erase(player_id)
	state.round_state[PENDING_KEY] = pending

	return Result.success({
		"player_id": player_id,
		"board_number": board_number,
		"type": mk_type,
		"product": product,
		"remaining_duration": remaining_duration,
		"world_pos": world_pos,
	})

