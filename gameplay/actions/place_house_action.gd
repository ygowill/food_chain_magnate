# 放置房屋动作
# 玩家在地图上放置房屋
class_name PlaceHouseAction
extends ActionExecutor

const PlacementValidatorClass = preload("res://core/map/placement_validator.gd")
const HouseNumberManagerClass = preload("res://core/map/house_number_manager.gd")
const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const MapRuntimeClass = preload("res://core/map/map_runtime.gd")
const RoundStateCountersClass = preload("res://core/utils/round_state_counters.gd")
const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")

var _piece_registry: Dictionary = {}

func _init(piece_registry: Dictionary = {}) -> void:
	action_id = "place_house"
	display_name = "放置房屋"
	description = "在地图上放置房屋"
	requires_actor = true
	is_mandatory = false
	allowed_phases = ["Working"]
	allowed_sub_phases = ["PlaceHouses"]
	_piece_registry = piece_registry

func _validate_specific(state: GameState, command: Command) -> Result:
	# 检查必需参数
	var pos_result := require_vector2i_param(command, "position")
	if not pos_result.ok:
		return pos_result
	var world_anchor: Vector2i = pos_result.value

	var rotation_result := require_int_param(command, "rotation")
	if not rotation_result.ok:
		return rotation_result
	var rotation: int = rotation_result.value

	# 检查是否是当前玩家的回合
	var current_player_id := state.get_current_player_id()
	if command.actor != current_player_id:
		return Result.failure("不是你的回合")

	# 规则：PlaceHouses 子阶段需要“可放置房屋”的在岗员工（数据驱动：员工 usage_tags）
	var player := state.get_player(command.actor)
	var capacity := EmployeeRulesClass.count_active_by_usage_tag_for_working(state, player, command.actor, "use:place_house")
	if capacity <= 0:
		return Result.failure("需要在岗的可放置房屋员工才能放置房屋")
	var used_result := RoundStateCountersClass.get_player_count(
		state.round_state, "house_placement_counts", command.actor
	)
	if not used_result.ok:
		return used_result
	var used := int(used_result.value)
	if used >= capacity:
		return Result.failure("放置房屋/花园本子阶段已用完: %d/%d" % [used, capacity])

	# 构建地图上下文
	var map_ctx := _build_map_context(state)

	# 构建建筑件注册表
	var piece_registry := _get_piece_registry()

	# 验证放置
	var validate_result := PlacementValidatorClass.validate_house_placement(
		map_ctx, world_anchor, rotation, piece_registry,
		command.actor, {}
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

	# 获取验证结果 (包含 footprint_cells)
	var validate_result := PlacementValidatorClass.validate_house_placement(
		map_ctx, world_anchor, rotation, piece_registry,
		player_id, {}
	)

	if not validate_result.ok:
		return validate_result

	var footprint_cells: Array = validate_result.value.footprint_cells

	# 生成房屋 ID 和编号
	var house_id := HouseNumberManagerClass.generate_house_id(state.map)
	var house_number := HouseNumberManagerClass.assign_house_number(state.map)

	# 写入格子
	for cell_pos in footprint_cells:
		var is_anchor = (cell_pos == world_anchor)
		var idx := MapRuntimeClass.world_to_index(state, cell_pos)
		state.map.cells[idx.y][idx.x]["structure"] = {
			"piece_id": "house",
			"owner": player_id,
			"anchor_cell": is_anchor,
			"parent_anchor": world_anchor,
			"rotation": rotation,
			"house_id": house_id,
			"house_number": house_number,
			"has_garden": false,
			"dynamic": true
		}

	# 注册房屋
	state.map.houses[house_id] = {
		"house_id": house_id,
		"house_number": house_number,
		"anchor_pos": world_anchor,
		"cells": footprint_cells,
		"has_garden": false,
		"is_apartment": false,
		"printed": false,
		"owner": player_id,
		"demands": []
	}

	# 使道路图缓存失效
	MapRuntimeClass.invalidate_road_graph(state)

	var inc_result := RoundStateCountersClass.increment_player_count(
		state.round_state, "house_placement_counts", player_id, 1
	)
	if not inc_result.ok:
		return inc_result

	var ms := MilestoneSystemClass.process_event(state, "HouseBuilt", {"player_id": player_id})

	var result := Result.success({
		"house_id": house_id,
		"house_number": house_number,
		"player_id": player_id,
		"position": world_anchor,
		"rotation": rotation
	})
	if not ms.ok:
		result.with_warning("里程碑触发失败(HouseBuilt): %s" % ms.error)
	return result

func _generate_specific_events(old_state: GameState, new_state: GameState, command: Command) -> Array[Dictionary]:
	var events: Array[Dictionary] = []

	# 找到新创建的房屋
	var new_houses = new_state.map.houses.keys()
	var old_houses = old_state.map.houses.keys()
	var house_id := ""
	var house_number = 0

	for h_id in new_houses:
		if h_id not in old_houses:
			house_id = h_id
			assert(new_state.map.houses.has(h_id), "place_house 新房屋缺失: %s" % str(h_id))
			var new_house_val = new_state.map.houses[h_id]
			assert(new_house_val is Dictionary, "place_house 新房屋类型错误（期望 Dictionary）: %s" % str(h_id))
			var new_house: Dictionary = new_house_val
			assert(new_house.has("house_number") and (new_house["house_number"] is int), "place_house 新房屋 house_number 缺失或类型错误（期望 int）: %s" % str(h_id))
			house_number = int(new_house["house_number"])
			break
	assert(not house_id.is_empty(), "place_house 未找到新创建的房屋")
	assert(new_state.map.houses.has(house_id), "place_house 新房屋缺失: %s" % house_id)
	var house: Dictionary = new_state.map.houses[house_id]
	assert(house.has("anchor_pos") and house["anchor_pos"] is Vector2i, "place_house 房屋 anchor_pos 缺失或类型错误")
	var world_anchor: Vector2i = house["anchor_pos"]

	events.append({
		"type": EventBus.EventType.HOUSE_PLACED,
		"data": {
			"player_id": command.actor,
			"house_id": house_id,
			"house_number": house_number,
			"position": [world_anchor.x, world_anchor.y],
			"has_garden": false
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
		"restaurants": state.map.restaurants
	}

# 辅助方法：获取建筑件注册表（优先使用注入的 modules/*/content/pieces）
func _get_piece_registry() -> Dictionary:
	if _piece_registry.is_empty():
		_piece_registry = _build_default_piece_registry()
	return _piece_registry

func _build_default_piece_registry() -> Dictionary:
	const PieceDefClass = preload("res://core/map/piece_def.gd")
	return {
		"restaurant": PieceDefClass.create_restaurant(),
		"house": PieceDefClass.create_house(),
		"house_with_garden": PieceDefClass.create_house_with_garden()
	}
