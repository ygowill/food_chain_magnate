class_name PlaceNewRestaurantMailboxAction
extends ActionExecutor

const CellsClass = preload("res://core/map/map_runtime/cells.gd")
const CoordsClass = preload("res://core/map/map_runtime/coords.gd")
const RoadGraphCacheClass = preload("res://core/map/map_runtime/road_graph_cache.gd")
const RangeUtilsClass = preload("res://core/utils/range_utils.gd")
const MarketingTypeRegistryClass = preload("res://core/rules/marketing_type_registry.gd")
const MarketingRulesClass = preload("res://core/rules/marketing_rules.gd")
const MarketingPlacementQueryClass = preload("res://core/map/marketing_placement_query.gd")
const MapStateAccessClass = preload("res://core/state/map_state_access.gd")

const MILESTONE_ID := "first_new_restaurant"
const USED_KEY := "new_milestones_first_new_restaurant_mailbox_used"
const EMPLOYEE_TYPE_SENTINEL := "__milestone_mailbox__"

func _init() -> void:
	action_id = "place_new_restaurant_mailbox"
	display_name = "放置永久邮箱（首个新餐厅）"
	description = "占用一个 mailbox(#7-#10)，在自家餐厅所在街区免费放置一个永久邮箱营销（不绑定营销员）"
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
	var placements_read := MapStateAccessClass.require_marketing_placements(state, action_id)
	if not placements_read.ok:
		return placements_read
	var placements: Dictionary = placements_read.value

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
	if board_number < 7 or board_number > 10:
		return Result.failure("board_number 必须在 7..10（mailbox）范围内")

	var product_result := require_string_param(command, "product")
	if not product_result.ok:
		return product_result
	var product: String = product_result.value
	var product_read := MarketingRulesClass.require_marketable_product(product)
	if not product_read.ok:
		return product_read

	var world_pos_result := require_vector2i_param(command, "position")
	if not world_pos_result.ok:
		return world_pos_result
	var world_pos: Vector2i = world_pos_result.value

	var rotation_result := optional_int_param(command, "rotation", 0)
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
	if marketing_type != "mailbox":
		return Result.failure("该板件不是 mailbox: #%d (%s)" % [board_number, marketing_type])
	if not MarketingTypeRegistryClass.has_type(marketing_type):
		return Result.failure("未知的营销类型: %s" % marketing_type)

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

	# === 放置校验：占地/边界/阻塞/道路/边缘/重叠（对齐 initiate_marketing）===
	var base_size: Vector2i = board_spec.get("footprint_size", Vector2i.ONE)
	var size_read := MarketingRulesClass.get_rotated_footprint_size(base_size, rotation)
	if not size_read.ok:
		return size_read
	var size: Vector2i = size_read.value

	var footprint_cells: Array[Vector2i] = MarketingRulesClass.build_footprint_cells(world_pos, size)

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

		var adjacent_roads_result := RangeUtilsClass.get_adjacent_road_cells_for_positions(state, footprint_cells)
		if not adjacent_roads_result.ok:
			return adjacent_roads_result
		var adjacent_roads: Array[Vector2i] = adjacent_roads_result.value
		if adjacent_roads.is_empty():
			return Result.failure("营销必须邻接道路: %s" % str(world_pos))

	# 4) 不允许与其他营销板件占地重叠
	var occupied_read := MarketingPlacementQueryClass.has_any_in_world_positions(state, footprint_cells)
	if not occupied_read.ok:
		return occupied_read
	if bool(occupied_read.value):
		return Result.failure("营销占地与其他营销板件重叠: %s" % str(world_pos))

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
		"rotation": rotation,
		"footprint_size": base_size,
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
	var rotation: int = int(info.get("rotation", 0))
	var footprint_size: Vector2i = info.get("footprint_size", Vector2i.ONE)

	var placements_read := MapStateAccessClass.require_marketing_placements(state, action_id)
	if not placements_read.ok:
		return placements_read
	var placements: Dictionary = placements_read.value

	var instance := {
		"board_number": board_number,
		"type": marketing_type,
		"owner": player_id,
		"employee_type": EMPLOYEE_TYPE_SENTINEL,
		"product": product,
		"world_pos": world_pos,
		"rotation": rotation,
		"footprint_size": footprint_size,
		"remaining_duration": -1,
		"axis": "",
		"tile_index": -1,
		"created_round": state.round_number,
	}
	state.marketing_instances.append(instance)

	placements[str(board_number)] = {
		"board_number": board_number,
		"type": marketing_type,
		"owner": player_id,
		"product": product,
		"world_pos": world_pos,
		"rotation": rotation,
		"footprint_size": footprint_size,
		"remaining_duration": -1,
		"axis": "",
		"tile_index": -1,
	}
	state.map["marketing_placements"] = placements

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

	var road_graph = RoadGraphCacheClass.get_road_graph(state)
	if road_graph == null:
		return Result.failure("RoadGraph 未初始化")
	var block_cells: Array[Vector2i] = road_graph.get_block_cells(world_pos)
	if block_cells.is_empty():
		return Result.success(false)

	for c in block_cells:
		if not CoordsClass.is_world_pos_in_grid(state, c):
			continue
		var cell := CellsClass.get_cell(state, c)
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
