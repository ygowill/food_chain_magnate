class_name PlacePizzaRadioAction
extends ActionExecutor

const RangeUtilsClass = preload("res://core/utils/range_utils.gd")
const MapRuntimeClass = preload("res://core/map/map_runtime.gd")
const MarketingRegistryClass = preload("res://core/data/marketing_registry.gd")
const MarketingTypeRegistryClass = preload("res://core/rules/marketing_type_registry.gd")

const PENDING_KEY := "new_milestones_pizza_radios_pending"

func _init() -> void:
	action_id = "place_pizza_radio"
	display_name = "放置披萨电波广告（里程碑）"
	description = "当触发“首个卖出披萨”里程碑后，本回合前3个买披萨的房屋，卖家需在该房屋所在 tile 内放置一个持续2回合的 radio(pizza)（若有空间）"
	requires_actor = true
	is_mandatory = true
	allowed_phases = ["Dinnertime"]
	allowed_sub_phases = []  # 任何子阶段都可以执行

func _validate_specific(state: GameState, command: Command) -> Result:
	if state == null:
		return Result.failure("state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("state.round_state 类型错误（期望 Dictionary）")
	if not (state.map is Dictionary):
		return Result.failure("state.map 类型错误（期望 Dictionary）")
	if not state.map.has("marketing_placements") or not (state.map["marketing_placements"] is Dictionary):
		return Result.failure("state.map.marketing_placements 缺失或类型错误")
	var placements: Dictionary = state.map["marketing_placements"]

	if not state.round_state.has(PENDING_KEY):
		return Result.failure("当前没有待放置的披萨 radio")
	var pending_val = state.round_state.get(PENDING_KEY, null)
	if not (pending_val is Array):
		return Result.failure("round_state.%s 类型错误（期望 Array）" % PENDING_KEY)
	var pending: Array = pending_val
	if pending.is_empty():
		return Result.failure("当前没有待放置的披萨 radio")

	var first_val = pending[0]
	if not (first_val is Dictionary):
		return Result.failure("round_state.%s[0] 类型错误（期望 Dictionary）" % PENDING_KEY)
	var first: Dictionary = first_val

	var seller_val = first.get("seller", null)
	if not (seller_val is int):
		return Result.failure("pending.seller 缺失或类型错误（期望 int）")
	var seller: int = int(seller_val)
	if command.actor != seller:
		return Result.failure("请等待玩家 %d 放置披萨 radio" % seller)

	var board_number_val = first.get("board_number", null)
	if not (board_number_val is int):
		return Result.failure("pending.board_number 缺失或类型错误（期望 int）")
	var board_number: int = int(board_number_val)
	var def = MarketingRegistryClass.get_def(board_number)
	if def == null:
		return Result.failure("未知的营销板件编号: %d" % board_number)
	if str(def.type) != "radio":
		return Result.failure("该板件不是 radio: #%d" % board_number)
	if not def.has_method("is_available_for_player_count") or not def.is_available_for_player_count(state.players.size()):
		return Result.failure("该营销板件在当前玩家数下已移除: #%d" % board_number)

	# board_number 唯一占用
	for inst_val in state.marketing_instances:
		if not (inst_val is Dictionary):
			continue
		var inst: Dictionary = inst_val
		if int(inst.get("board_number", -1)) == board_number:
			return Result.failure("营销板件已被占用: #%d" % board_number)
	if placements.has(str(board_number)):
		return Result.failure("营销板件已被占用: #%d" % board_number)

	var tile_min_val = first.get("tile_min", null)
	var tile_max_val = first.get("tile_max", null)
	if not (tile_min_val is Vector2i) or not (tile_max_val is Vector2i):
		return Result.failure("pending.tile_min/tile_max 缺失或类型错误（期望 Vector2i）")
	var tile_min: Vector2i = tile_min_val
	var tile_max: Vector2i = tile_max_val

	var pos_read := require_vector2i_param(command, "position")
	if not pos_read.ok:
		return pos_read
	var world_pos: Vector2i = pos_read.value
	if world_pos.x < tile_min.x or world_pos.x > tile_max.x or world_pos.y < tile_min.y or world_pos.y > tile_max.y:
		return Result.failure("position 必须在目标 tile 内: %s" % str(world_pos))

	# 放置校验：位置/空格/邻路
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

	if MarketingTypeRegistryClass.requires_edge("radio"):
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
		var adjacent_roads: Array = adjacent_roads_result.value
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

	return Result.success({
		"board_number": board_number,
		"world_pos": world_pos,
		"product": str(first.get("product", "pizza")),
		"duration": int(first.get("duration", 2)),
	})

func _apply_changes(state: GameState, command: Command) -> Result:
	var validate := _validate_specific(state, command)
	if not validate.ok:
		return validate
	var info: Dictionary = validate.value

	var board_number: int = int(info["board_number"])
	var world_pos: Vector2i = info["world_pos"]
	var product: String = str(info["product"])
	var duration: int = int(info["duration"])

	var instance := {
		"board_number": board_number,
		"type": "radio",
		"owner": command.actor,
		"employee_type": "__milestone__",
		"product": product,
		"world_pos": world_pos,
		"remaining_duration": duration,
		"axis": "",
		"tile_index": -1,
		"created_round": state.round_number,
	}
	state.marketing_instances.append(instance)

	state.map["marketing_placements"][str(board_number)] = {
		"board_number": board_number,
		"type": "radio",
		"owner": command.actor,
		"product": product,
		"world_pos": world_pos,
		"remaining_duration": duration,
		"axis": "",
		"tile_index": -1,
	}

	# 消耗一个 pending
	var pending: Array = state.round_state[PENDING_KEY]
	pending.remove_at(0)
	state.round_state[PENDING_KEY] = pending

	# 更新推进阻塞器
	if state.round_state.has("pending_phase_actions"):
		var ppa_val = state.round_state.get("pending_phase_actions", null)
		if ppa_val is Dictionary:
			var ppa: Dictionary = ppa_val
			if pending.is_empty():
				ppa.erase("Dinnertime")
			else:
				ppa["Dinnertime"] = pending.duplicate(true)
			state.round_state["pending_phase_actions"] = ppa

	return Result.success({
		"board_number": board_number,
		"position": [world_pos.x, world_pos.y],
		"product": product,
		"duration": duration,
	})
