# 放置餐厅动作
# 玩家在地图上放置餐厅
class_name PlaceRestaurantAction
extends ActionExecutor

const RestaurantPlacementClass = preload("res://core/map/placement_validator/restaurant_placement.gd")
const MapContextBuilderClass = preload("res://core/map/map_context_builder.gd")
const CoordsClass = preload("res://core/map/map_runtime/coords.gd")
const RoadGraphCacheClass = preload("res://core/map/map_runtime/road_graph_cache.gd")
const StructuresClass = preload("res://core/map/map_runtime/structures.gd")
const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")
const EmployeeUsageHelperClass = preload("res://gameplay/actions/employee_usage_helper.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

const ROUND_STATE_OPENING_SOON_RESTAURANTS_KEY := "opening_soon_restaurants"

var _piece_registry: Dictionary = {}

func _init(piece_registry: Dictionary = {}) -> void:
	action_id = "place_restaurant"
	display_name = "放置餐厅"
	description = "在地图上放置餐厅"
	requires_actor = true
	is_mandatory = false
	allowed_phases = [DefsClass.PHASE_SETUP, DefsClass.PHASE_WORKING]
	allowed_sub_phases = [DefsClass.SUB_PHASE_PLACE_RESTAURANTS]
	_piece_registry = piece_registry

func can_initiate(state: GameState, player_id: int) -> bool:
	if state == null:
		return true
	if state.get_current_player_id() != player_id:
		return false

	if state.phase == DefsClass.PHASE_SETUP:
		if str(state.sub_phase) == DefsClass.SUB_PHASE_RESERVE_CARDS:
			return false
		var player_restaurants := StructuresClass.get_player_restaurants(state, player_id)
		return player_restaurants.size() < 1

	if state.phase != DefsClass.PHASE_WORKING:
		return true

	var player := state.get_player(player_id)
	var eligible := EmployeeRulesClass.count_active_by_usage_tag_for_working(state, player, player_id, "use:place_restaurant")
	if eligible <= 0:
		return false
	var used_place := EmployeeRulesClass.get_action_count(state, player_id, "place_restaurant")
	var used_move := EmployeeRulesClass.get_action_count(state, player_id, "move_restaurant")
	return (used_place + used_move) < eligible

func _parse_params(command: Command) -> Result:
	var pos_result := require_vector2i_param(command, "position")
	if not pos_result.ok:
		return pos_result
	var world_anchor: Vector2i = pos_result.value

	var rotation_result := require_int_param(command, "rotation")
	if not rotation_result.ok:
		return rotation_result
	var rotation: int = rotation_result.value

	return Result.success({
		"world_anchor": world_anchor,
		"rotation": rotation,
	})

func _validate_specific(state: GameState, command: Command) -> Result:
	# 检查是否是当前玩家的回合
	var current_player_id := state.get_current_player_id()
	if command.actor != current_player_id:
		return Result.failure("不是你的回合")

	var employee_type := ""
	var employee_type_result := optional_string_param(command, "employee_type", "")
	if not employee_type_result.ok:
		return employee_type_result
	employee_type = employee_type_result.value

	# 规则：Working/PlaceRestaurants 需要在岗的本地经理或区域经理（docs/rules.md 子阶段 6）
	var is_initial := state.phase == DefsClass.PHASE_SETUP
	if is_initial and str(state.sub_phase) == DefsClass.SUB_PHASE_RESERVE_CARDS:
		return Result.failure("请先选择银行储备卡（所有玩家选择后才能放置餐厅）")

	# Setup 阶段：每位玩家只能放置一个餐厅（无需 position/rotation）
	if is_initial:
		var player_restaurants := StructuresClass.get_player_restaurants(state, command.actor)
		if player_restaurants.size() >= 1:
			return Result.failure("设置阶段每位玩家只能放置一个餐厅")

	if state.phase == DefsClass.PHASE_WORKING:
		var player := state.get_player(command.actor)
		var eligible := EmployeeRulesClass.count_active_by_usage_tag_for_working(state, player, command.actor, "use:place_restaurant")
		if eligible <= 0:
			return Result.failure("需要在岗的本地经理或区域经理才能放置餐厅")
		if not employee_type.is_empty():
			if not EmployeeUsageHelperClass.has_active_employee_with_usage_tag(state, command.actor, employee_type, "use:place_restaurant"):
				return Result.failure("该员工不能放置餐厅或未在岗: %s" % employee_type)
		var used_place := EmployeeRulesClass.get_action_count(state, command.actor, "place_restaurant")
		var used_move := EmployeeRulesClass.get_action_count(state, command.actor, "move_restaurant")
		var used_total := used_place + used_move
		if used_total >= eligible:
			return Result.failure("本地/大区经理本子阶段已用完: %d/%d" % [used_total, eligible])

	# 检查必需参数
	var params_result := _parse_params(command)
	if not params_result.ok:
		return params_result
	var params: Dictionary = params_result.value
	var world_anchor: Vector2i = params["world_anchor"]
	var rotation: int = int(params["rotation"])

	# 构建地图上下文
	var map_ctx_read := MapContextBuilderClass.build_context_result(state, action_id)
	if not map_ctx_read.ok:
		return map_ctx_read
	var map_ctx: Dictionary = map_ctx_read.value

	# 构建建筑件注册表
	var piece_registry := _get_piece_registry()

	# 验证放置
	var validate_result := RestaurantPlacementClass.validate_restaurant_placement(
		map_ctx, world_anchor, rotation, piece_registry,
		command.actor, is_initial, {}
	)

	if not validate_result.ok:
		return validate_result

	return Result.success()

func _apply_changes(state: GameState, command: Command) -> Result:
	var employee_type := ""
	var employee_type_result := optional_string_param(command, "employee_type", "")
	if not employee_type_result.ok:
		return employee_type_result
	employee_type = employee_type_result.value
	if employee_type.is_empty() and state.phase == DefsClass.PHASE_WORKING:
		var candidates := EmployeeUsageHelperClass.get_active_employee_types_for_usage_tag(
			state, command.actor, "use:place_restaurant"
		)
		if not candidates.is_empty():
			employee_type = candidates[0]
	var opening_soon := (state.phase == DefsClass.PHASE_WORKING and employee_type == "local_manager")

	var params_result := _parse_params(command)
	if not params_result.ok:
		return params_result
	var params: Dictionary = params_result.value
	var world_anchor: Vector2i = params["world_anchor"]
	var rotation: int = int(params["rotation"])
	var player_id: int = command.actor

	# 构建地图上下文和建筑件注册表
	var map_ctx_read := MapContextBuilderClass.build_context_result(state, action_id)
	if not map_ctx_read.ok:
		return map_ctx_read
	var map_ctx: Dictionary = map_ctx_read.value
	var piece_registry := _get_piece_registry()
	var is_initial := state.phase == DefsClass.PHASE_SETUP

	# 获取验证结果 (包含 footprint_cells)
	var validate_result := RestaurantPlacementClass.validate_restaurant_placement(
		map_ctx, world_anchor, rotation, piece_registry,
		player_id, is_initial, {}
	)

	if not validate_result.ok:
		return validate_result

	assert(validate_result.value is Dictionary, "place_restaurant: validate_restaurant_placement 返回值类型错误（期望 Dictionary）")
	var validate_value: Dictionary = validate_result.value
	assert(validate_value.has("footprint_cells") and (validate_value["footprint_cells"] is Array), "place_restaurant: validate_restaurant_placement 缺少 footprint_cells")
	assert(validate_value.has("entrance_pos") and (validate_value["entrance_pos"] is Vector2i), "place_restaurant: validate_restaurant_placement 缺少 entrance_pos")
	var footprint_cells: Array = validate_value["footprint_cells"]
	var entrance_pos: Vector2i = validate_value["entrance_pos"]

	# 生成餐厅 ID
	var restaurant_id := "rest_%d" % state.map.next_restaurant_id
	state.map.next_restaurant_id += 1

	# 写入格子
	for cell_pos in footprint_cells:
		var is_anchor = (cell_pos == world_anchor)
		var idx := CoordsClass.world_to_index(state, cell_pos)
		var structure := {
			"piece_id": "restaurant",
			"owner": player_id,
			"anchor_cell": is_anchor,
			"parent_anchor": world_anchor,
			"rotation": rotation,
			"restaurant_id": restaurant_id,
			"dynamic": true
		}
		if opening_soon:
			structure["opening_soon"] = true
		state.map.cells[idx.y][idx.x]["structure"] = structure

	var restaurant_data := {
		"restaurant_id": restaurant_id,
		"owner": player_id,
		"anchor_pos": world_anchor,
		"entrance_pos": entrance_pos,
		"cells": footprint_cells,
		"rotation": rotation
	}

	if opening_soon:
		if not (state.round_state is Dictionary):
			return Result.failure("place_restaurant: state.round_state 类型错误（期望 Dictionary）")
		if not state.round_state.has(ROUND_STATE_OPENING_SOON_RESTAURANTS_KEY) or not (state.round_state[ROUND_STATE_OPENING_SOON_RESTAURANTS_KEY] is Array):
			state.round_state[ROUND_STATE_OPENING_SOON_RESTAURANTS_KEY] = []
		var pending: Array = state.round_state[ROUND_STATE_OPENING_SOON_RESTAURANTS_KEY]
		pending.append(restaurant_data.duplicate(true))
		state.round_state[ROUND_STATE_OPENING_SOON_RESTAURANTS_KEY] = pending
	else:
		# 注册餐厅（立即开业）
		state.map.restaurants[restaurant_id] = restaurant_data

		# 添加到玩家餐厅列表
		var player := state.get_player(player_id)
		assert(not player.is_empty(), "place_restaurant: player 不存在: %d" % player_id)
		assert(player.has("restaurants") and (player["restaurants"] is Array), "place_restaurant: player.restaurants 缺失或类型错误（期望 Array）")
		var restaurants: Array = player["restaurants"]
		restaurants.append(restaurant_id)
		state.players[player_id]["restaurants"] = restaurants

	# 使道路图缓存失效
	RoadGraphCacheClass.invalidate_road_graph(state)

	if state.phase == DefsClass.PHASE_WORKING:
		EmployeeRulesClass.increment_action_count(state, player_id, action_id)

	var result := Result.success({
		"restaurant_id": restaurant_id,
		"player_id": player_id,
		"position": world_anchor,
		"rotation": rotation,
		"opening_soon": opening_soon,
	})

	# 里程碑触发（模块化）：首次在 Working 阶段放置新餐厅
	if state.phase == DefsClass.PHASE_WORKING:
		var ms := MilestoneSystemClass.process_event(state, "RestaurantPlaced", {
			"player_id": player_id,
			"phase": state.phase,
		})
		if not ms.ok:
			result.with_warning("里程碑触发失败(RestaurantPlaced): %s" % ms.error)

	return result

func _generate_specific_events(old_state: GameState, new_state: GameState, command: Command) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var employee_type := ""
	if command.params.has("employee_type"):
		var employee_type_result := require_string_param(command, "employee_type")
		assert(employee_type_result.ok, "place_restaurant 缺少/错误参数: employee_type")
		employee_type = employee_type_result.value
	if employee_type.is_empty() and old_state.phase == DefsClass.PHASE_WORKING:
		var candidates := EmployeeUsageHelperClass.get_active_employee_types_for_usage_tag(
			old_state, command.actor, "use:place_restaurant"
		)
		if not candidates.is_empty():
			employee_type = candidates[0]

	# 找到新创建的餐厅
	var new_restaurants = new_state.map.restaurants.keys()
	var old_restaurants = old_state.map.restaurants.keys()
	var restaurant_id := ""
	var opening_soon := false
	var world_anchor: Vector2i = Vector2i(-1, -1)

	for rest_id in new_restaurants:
		if rest_id not in old_restaurants:
			restaurant_id = rest_id
			break
	if not restaurant_id.is_empty():
		assert(new_state.map.restaurants.has(restaurant_id), "place_restaurant 新餐厅缺失: %s" % restaurant_id)
		var rest: Dictionary = new_state.map.restaurants[restaurant_id]
		assert(rest.has("anchor_pos") and rest["anchor_pos"] is Vector2i, "place_restaurant anchor_pos 缺失或类型错误")
		world_anchor = rest["anchor_pos"]
	else:
		# opening_soon: restaurant 不会立即加入 map.restaurants，改从 round_state 中推导
		var old_pending: Array = []
		var new_pending: Array = []
		if old_state.round_state is Dictionary:
			var ov = (old_state.round_state as Dictionary).get(ROUND_STATE_OPENING_SOON_RESTAURANTS_KEY, null)
			if ov is Array:
				old_pending = ov
		if new_state.round_state is Dictionary:
			var nv = (new_state.round_state as Dictionary).get(ROUND_STATE_OPENING_SOON_RESTAURANTS_KEY, null)
			if nv is Array:
				new_pending = nv

		var old_ids := {}
		for e_val in old_pending:
			if not (e_val is Dictionary):
				continue
			var e: Dictionary = e_val
			var rid := str(e.get("restaurant_id", "")).strip_edges()
			if not rid.is_empty():
				old_ids[rid] = true
		for e_val2 in new_pending:
			if not (e_val2 is Dictionary):
				continue
			var e2: Dictionary = e_val2
			var rid2 := str(e2.get("restaurant_id", "")).strip_edges()
			if rid2.is_empty() or old_ids.has(rid2):
				continue
			restaurant_id = rid2
			var ap = e2.get("anchor_pos", null)
			if ap is Vector2i:
				world_anchor = Vector2i(ap)
			opening_soon = true
			break

	assert(not restaurant_id.is_empty(), "place_restaurant 未找到新创建的餐厅")

	events.append({
		"type": EventBus.EventType.RESTAURANT_PLACED,
		"data": {
			"player_id": command.actor,
			"restaurant_id": restaurant_id,
			"position": [world_anchor.x, world_anchor.y],
			"employee_type": employee_type,
			"opening_soon": opening_soon,
		}
	})

	return events

# 辅助方法：获取建筑件注册表（优先使用注入的 modules/*/content/pieces）
func _get_piece_registry() -> Dictionary:
	if _piece_registry.is_empty():
		const PieceDefClass = preload("res://core/map/piece_def.gd")
		_piece_registry = PieceDefClass.create_default_registry()
	return _piece_registry
