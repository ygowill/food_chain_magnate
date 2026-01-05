class_name PlaceNewRestaurantMailboxAction
extends ActionExecutor

const MapRuntimeClass = preload("res://core/map/map_runtime.gd")
const RangeUtilsClass = preload("res://core/utils/range_utils.gd")
const MarketingRegistryClass = preload("res://core/data/marketing_registry.gd")
const MarketingTypeRegistryClass = preload("res://core/rules/marketing_type_registry.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")

const MILESTONE_ID := "first_new_restaurant"
const USED_KEY := "new_milestones_first_new_restaurant_mailbox_used"
const EMPLOYEE_TYPE_SENTINEL := "__milestone_mailbox__"

func _init() -> void:
	action_id = "place_new_restaurant_mailbox"
	display_name = "放置永久邮箱（首个新餐厅）"
	description = "占用一个 mailbox(#5-#10)，在自家餐厅所在街区免费放置一个永久邮箱营销（不绑定营销员）"
	requires_actor = true
	is_mandatory = false
	allowed_phases = ["Working"]
	allowed_sub_phases = ["PlaceRestaurants"]

func _validate_specific(state: GameState, command: Command) -> Result:
	var current_player_id := state.get_current_player_id()
	if command.actor != current_player_id:
		return Result.failure("不是你的回合")

	if not (state.players is Array):
		return Result.failure("state.players 类型错误（期望 Array）")
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

	if player.has(USED_KEY):
		var used_val = player.get(USED_KEY, false)
		if not (used_val is bool):
			return Result.failure("%s 类型错误（期望 bool）" % USED_KEY)
		if bool(used_val):
			return Result.failure("本局已放置过该永久邮箱")

	var board_number_result := require_int_param(command, "board_number")
	if not board_number_result.ok:
		return board_number_result
	var board_number: int = board_number_result.value
	if board_number < 5 or board_number > 10:
		return Result.failure("board_number 必须在 5..10（mailbox）范围内")

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

	var world_pos_result := require_vector2i_param(command, "position")
	if not world_pos_result.ok:
		return world_pos_result
	var world_pos: Vector2i = world_pos_result.value

	var def = MarketingRegistryClass.get_def(board_number)
	if def == null:
		return Result.failure("未知的营销板件编号: %d" % board_number)
	var marketing_type := str(def.type)
	if marketing_type != "mailbox":
		return Result.failure("该板件不是 mailbox: #%d (%s)" % [board_number, marketing_type])
	if not MarketingTypeRegistryClass.has_type(marketing_type):
		return Result.failure("未知的营销类型: %s" % marketing_type)
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

	# 放置校验：位置/空格/邻路/边缘等（复用 initiate_marketing 的规则子集）
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

	# 同街区约束：必须与自家任意餐厅在同一 mailbox block（RoadGraph block）
	var same_block_ok := _has_own_restaurant_in_same_block(state, command.actor, world_pos)
	if not same_block_ok.ok:
		return same_block_ok
	if not bool(same_block_ok.value):
		return Result.failure("永久邮箱必须放置在自家餐厅所在街区（mailbox block）内: %s" % str(world_pos))

	return Result.success({
		"board_number": board_number,
		"type": marketing_type,
		"product": product,
		"world_pos": world_pos,
	})

func _apply_changes(state: GameState, command: Command) -> Result:
	var validate := _validate_specific(state, command)
	if not validate.ok:
		return validate
	var info: Dictionary = validate.value

	var player_id: int = command.actor
	var board_number: int = int(info["board_number"])
	var marketing_type: String = str(info["type"])
	var product: String = str(info["product"])
	var world_pos: Vector2i = info["world_pos"]

	var instance := {
		"board_number": board_number,
		"type": marketing_type,
		"owner": player_id,
		"employee_type": EMPLOYEE_TYPE_SENTINEL,
		"product": product,
		"world_pos": world_pos,
		"remaining_duration": -1,
		"axis": "",
		"tile_index": -1,
		"created_round": state.round_number,
	}
	state.marketing_instances.append(instance)

	if not (state.map is Dictionary) or not state.map.has("marketing_placements") or not (state.map["marketing_placements"] is Dictionary):
		return Result.failure("state.map.marketing_placements 缺失或类型错误")
	state.map["marketing_placements"][str(board_number)] = {
		"board_number": board_number,
		"type": marketing_type,
		"owner": player_id,
		"product": product,
		"world_pos": world_pos,
		"remaining_duration": -1,
		"axis": "",
		"tile_index": -1,
	}

	var player_val = state.players[player_id]
	assert(player_val is Dictionary, "place_new_restaurant_mailbox: player 类型错误")
	var player: Dictionary = player_val
	player[USED_KEY] = true
	state.players[player_id] = player

	return Result.success({
		"player_id": player_id,
		"board_number": board_number,
		"type": marketing_type,
		"product": product,
		"world_pos": world_pos,
	})

func _has_own_restaurant_in_same_block(state: GameState, player_id: int, world_pos: Vector2i) -> Result:
	if state == null:
		return Result.failure("state 为空")
	if not (state.map is Dictionary):
		return Result.failure("state.map 类型错误（期望 Dictionary）")

	var road_graph = MapRuntimeClass.get_road_graph(state)
	if road_graph == null:
		return Result.failure("RoadGraph 未初始化")
	var block_cells: Array[Vector2i] = road_graph.get_block_cells(world_pos)
	if block_cells.is_empty():
		return Result.success(false)

	for c in block_cells:
		if not MapRuntimeClass.is_world_pos_in_grid(state, c):
			continue
		var cell := MapRuntimeClass.get_cell(state, c)
		if not cell.has("structure") or not (cell["structure"] is Dictionary):
			return Result.failure("cell.structure 缺失或类型错误: %s" % str(c))
		var structure: Dictionary = cell["structure"]
		if not structure.has("restaurant_id"):
			continue
		if not structure.has("owner") or not (structure["owner"] is int):
			return Result.failure("restaurant structure.owner 缺失或类型错误: %s" % str(c))
		if int(structure["owner"]) == player_id:
			return Result.success(true)

	return Result.success(false)

