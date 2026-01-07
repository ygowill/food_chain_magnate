# 放置餐厅动作
# 玩家在地图上放置餐厅
class_name PlaceRestaurantAction
extends ActionExecutor

const PlacementValidatorClass = preload("res://core/map/placement_validator.gd")
const MapRuntimeClass = preload("res://core/map/map_runtime.gd")
const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")

var _piece_registry: Dictionary = {}

func _init(piece_registry: Dictionary = {}) -> void:
	action_id = "place_restaurant"
	display_name = "放置餐厅"
	description = "在地图上放置餐厅"
	requires_actor = true
	is_mandatory = false
	allowed_phases = ["Setup", "Working"]
	allowed_sub_phases = ["PlaceRestaurants"]
	_piece_registry = piece_registry

func can_initiate(state: GameState, player_id: int) -> bool:
	if state == null:
		return true
	if state.get_current_player_id() != player_id:
		return false

	if state.phase == "Setup":
		var player_restaurants := MapRuntimeClass.get_player_restaurants(state, player_id)
		return player_restaurants.size() < 1

	if state.phase != "Working":
		return true

	var player := state.get_player(player_id)
	var eligible := EmployeeRulesClass.count_active_by_usage_tag_for_working(state, player, player_id, "use:place_restaurant")
	if eligible <= 0:
		return false
	var used_place := EmployeeRulesClass.get_action_count(state, player_id, "place_restaurant")
	var used_move := EmployeeRulesClass.get_action_count(state, player_id, "move_restaurant")
	return (used_place + used_move) < eligible

func _validate_specific(state: GameState, command: Command) -> Result:
	# 检查是否是当前玩家的回合
	var current_player_id := state.get_current_player_id()
	if command.actor != current_player_id:
		return Result.failure("不是你的回合")

	# 规则：Working/PlaceRestaurants 需要在岗的本地经理或区域经理（docs/rules.md 子阶段 6）
	var is_initial := state.phase == "Setup"

	# Setup 阶段：每位玩家只能放置一个餐厅（无需 position/rotation）
	if is_initial:
		var player_restaurants := MapRuntimeClass.get_player_restaurants(state, command.actor)
		if player_restaurants.size() >= 1:
			return Result.failure("设置阶段每位玩家只能放置一个餐厅")

	if state.phase == "Working":
		var player := state.get_player(command.actor)
		var eligible := EmployeeRulesClass.count_active_by_usage_tag_for_working(state, player, command.actor, "use:place_restaurant")
		if eligible <= 0:
			return Result.failure("需要在岗的本地经理或区域经理才能放置餐厅")
		var used_place := EmployeeRulesClass.get_action_count(state, command.actor, "place_restaurant")
		var used_move := EmployeeRulesClass.get_action_count(state, command.actor, "move_restaurant")
		var used_total := used_place + used_move
		if used_total >= eligible:
			return Result.failure("本地/大区经理本子阶段已用完: %d/%d" % [used_total, eligible])

	# 检查必需参数
	var pos_result := require_vector2i_param(command, "position")
	if not pos_result.ok:
		return pos_result
	var world_anchor: Vector2i = pos_result.value

	var rotation_result := require_int_param(command, "rotation")
	if not rotation_result.ok:
		return rotation_result
	var rotation: int = rotation_result.value

	# 构建地图上下文
	var map_ctx := _build_map_context(state)

	# 构建建筑件注册表
	var piece_registry := _get_piece_registry()

	# 验证放置
	var validate_result := PlacementValidatorClass.validate_restaurant_placement(
		map_ctx, world_anchor, rotation, piece_registry,
		command.actor, is_initial, {}
	)

	if not validate_result.ok:
		return validate_result

	return Result.success()

func _apply_changes(state: GameState, command: Command) -> Result:
	var pos_result := require_vector2i_param(command, "position")
	if not pos_result.ok:
		return pos_result
	var world_anchor: Vector2i = pos_result.value

	var rotation_result := require_int_param(command, "rotation")
	if not rotation_result.ok:
		return rotation_result
	var rotation: int = rotation_result.value
	var player_id: int = command.actor

	# 构建地图上下文和建筑件注册表
	var map_ctx := _build_map_context(state)
	var piece_registry := _get_piece_registry()
	var is_initial := state.phase == "Setup"

	# 获取验证结果 (包含 footprint_cells)
	var validate_result := PlacementValidatorClass.validate_restaurant_placement(
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
		var idx := MapRuntimeClass.world_to_index(state, cell_pos)
		state.map.cells[idx.y][idx.x]["structure"] = {
			"piece_id": "restaurant",
			"owner": player_id,
			"anchor_cell": is_anchor,
			"parent_anchor": world_anchor,
			"rotation": rotation,
			"restaurant_id": restaurant_id,
			"dynamic": true
		}

	# 注册餐厅
	state.map.restaurants[restaurant_id] = {
		"restaurant_id": restaurant_id,
		"owner": player_id,
		"anchor_pos": world_anchor,
		"entrance_pos": entrance_pos,
		"cells": footprint_cells,
		"rotation": rotation
	}

	# 添加到玩家餐厅列表
	var player := state.get_player(player_id)
	assert(not player.is_empty(), "place_restaurant: player 不存在: %d" % player_id)
	assert(player.has("restaurants") and (player["restaurants"] is Array), "place_restaurant: player.restaurants 缺失或类型错误（期望 Array）")
	var restaurants: Array = player["restaurants"]
	restaurants.append(restaurant_id)
	state.players[player_id]["restaurants"] = restaurants

	# 使道路图缓存失效
	MapRuntimeClass.invalidate_road_graph(state)

	# Working 阶段：使用本地/大区经理放置餐厅会启用本回合的免下车能力
	if state.phase == "Working":
		state.players[player_id]["drive_thru_active"] = true
		EmployeeRulesClass.increment_action_count(state, player_id, action_id)

	var result := Result.success({
		"restaurant_id": restaurant_id,
		"player_id": player_id,
		"position": world_anchor,
		"rotation": rotation
	})

	# 里程碑触发（模块化）：首次在 Working 阶段放置新餐厅
	if state.phase == "Working":
		var ms := MilestoneSystemClass.process_event(state, "RestaurantPlaced", {
			"player_id": player_id,
			"phase": state.phase,
		})
		if not ms.ok:
			result.with_warning("里程碑触发失败(RestaurantPlaced): %s" % ms.error)

	return result

func _generate_specific_events(old_state: GameState, new_state: GameState, command: Command) -> Array[Dictionary]:
	var events: Array[Dictionary] = []

	# 找到新创建的餐厅
	var new_restaurants = new_state.map.restaurants.keys()
	var old_restaurants = old_state.map.restaurants.keys()
	var restaurant_id := ""

	for rest_id in new_restaurants:
		if rest_id not in old_restaurants:
			restaurant_id = rest_id
			break
	assert(not restaurant_id.is_empty(), "place_restaurant 未找到新创建的餐厅")
	assert(new_state.map.restaurants.has(restaurant_id), "place_restaurant 新餐厅缺失: %s" % restaurant_id)
	var rest: Dictionary = new_state.map.restaurants[restaurant_id]
	assert(rest.has("anchor_pos") and rest["anchor_pos"] is Vector2i, "place_restaurant anchor_pos 缺失或类型错误")
	var world_anchor: Vector2i = rest["anchor_pos"]

	events.append({
		"type": EventBus.EventType.RESTAURANT_PLACED,
		"data": {
			"player_id": command.actor,
			"restaurant_id": restaurant_id,
			"position": [world_anchor.x, world_anchor.y]
		}
	})

	return events

# 辅助方法：构建地图上下文
func _build_map_context(state: GameState) -> Dictionary:
	return {
		"cells": state.map.cells,
		"grid_size": state.map.grid_size,
		"map_origin": MapRuntimeClass.get_map_origin(state),
		"houses": state.map.houses,
		"restaurants": state.map.restaurants,
		"drink_sources": state.map.get("drink_sources", []),
	}

# 辅助方法：获取建筑件注册表（优先使用注入的 modules/*/content/pieces）
func _get_piece_registry() -> Dictionary:
	if _piece_registry.is_empty():
		_piece_registry = _build_default_piece_registry()
	return _piece_registry

func _build_default_piece_registry() -> Dictionary:
	# 从 PieceDef 类创建默认定义
	const PieceDefClass = preload("res://core/map/piece_def.gd")
	return {
		"restaurant": PieceDefClass.create_restaurant(),
		"house": PieceDefClass.create_house(),
		"house_with_garden": PieceDefClass.create_house_with_garden()
	}
