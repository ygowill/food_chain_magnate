# 移动餐厅动作（Working 子阶段：PlaceRestaurants）
# 将玩家已有餐厅移动到新位置（保留 restaurant_id）。
class_name MoveRestaurantAction
extends ActionExecutor

const PlacementValidatorClass = preload("res://core/map/placement_validator.gd")
const MapRuntimeClass = preload("res://core/map/map_runtime.gd")
const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")

var _piece_registry: Dictionary = {}

func _init(piece_registry: Dictionary = {}) -> void:
	action_id = "move_restaurant"
	display_name = "移动餐厅"
	description = "移动一个已有餐厅到新位置"
	requires_actor = true
	is_mandatory = false
	allowed_phases = ["Working"]
	allowed_sub_phases = ["PlaceRestaurants"]
	_piece_registry = piece_registry

func can_initiate(state: GameState, player_id: int) -> bool:
	if state == null:
		return true
	if state.get_current_player_id() != player_id:
		return false

	var player := state.get_player(player_id)
	if not player.has("restaurants") or not (player["restaurants"] is Array):
		return true
	var rest_list: Array = player["restaurants"]
	if rest_list.is_empty():
		return false

	var move_eligible := EmployeeRulesClass.count_active_by_usage_tag_for_working(state, player, player_id, "use:move_restaurant")
	if move_eligible <= 0:
		return false

	var total_eligible := EmployeeRulesClass.count_active_by_usage_tag_for_working(state, player, player_id, "use:place_restaurant")
	if total_eligible <= 0:
		return false

	var used_place := EmployeeRulesClass.get_action_count(state, player_id, "place_restaurant")
	var used_move := EmployeeRulesClass.get_action_count(state, player_id, "move_restaurant")
	var used_total := used_place + used_move
	if used_total >= total_eligible:
		return false
	if used_move >= move_eligible:
		return false

	return true

func _validate_specific(state: GameState, command: Command) -> Result:
	# 检查是否是当前玩家的回合
	var current_player_id := state.get_current_player_id()
	if command.actor != current_player_id:
		return Result.failure("不是你的回合")

	# 需要至少有一个自己的餐厅（无需 restaurant_id）
	var player0 := state.get_player(command.actor)
	if player0.has("restaurants") and (player0["restaurants"] is Array):
		if (player0["restaurants"] as Array).is_empty():
			return Result.failure("你没有可移动的餐厅")

	# 检查餐厅存在且归属当前玩家
	assert(state.map is Dictionary, "move_restaurant: state.map 类型错误（期望 Dictionary）")
	assert(state.map.has("restaurants") and (state.map["restaurants"] is Dictionary), "move_restaurant: state.map.restaurants 缺失或类型错误（期望 Dictionary）")
	var restaurants: Dictionary = state.map["restaurants"]

	# 规则：移动餐厅需要在岗的区域经理（data/employees/*.json usage_tags）
	var player := state.get_player(command.actor)
	var move_eligible := EmployeeRulesClass.count_active_by_usage_tag_for_working(state, player, command.actor, "use:move_restaurant")
	if move_eligible <= 0:
		return Result.failure("需要在岗的区域经理才能移动餐厅")

	# PlaceRestaurants 子阶段：place/move 共享次数上限 = 可用的本地/大区经理总数
	var total_eligible := EmployeeRulesClass.count_active_by_usage_tag_for_working(state, player, command.actor, "use:place_restaurant")
	var used_place := EmployeeRulesClass.get_action_count(state, command.actor, "place_restaurant")
	var used_move := EmployeeRulesClass.get_action_count(state, command.actor, "move_restaurant")
	var used_total := used_place + used_move
	if used_total >= total_eligible:
		return Result.failure("本地/大区经理本子阶段已用完: %d/%d" % [used_total, total_eligible])
	if used_move >= move_eligible:
		return Result.failure("区域经理本子阶段已用完: %d/%d" % [used_move, move_eligible])

	var rest_id_result := require_string_param(command, "restaurant_id")
	if not rest_id_result.ok:
		return rest_id_result
	var rest_id: String = rest_id_result.value

	if not restaurants.has(rest_id):
		return Result.failure("餐厅不存在: %s" % rest_id)
	var rest_val = restaurants[rest_id]
	assert(rest_val is Dictionary, "move_restaurant: restaurants[%s] 类型错误（期望 Dictionary）" % rest_id)
	var rest: Dictionary = rest_val
	assert(rest.has("owner") and (rest["owner"] is int), "move_restaurant: restaurants[%s].owner 缺失或类型错误（期望 int）" % rest_id)
	if int(rest["owner"]) != command.actor:
		return Result.failure("只能移动自己的餐厅")

	var pos_result := require_vector2i_param(command, "position")
	if not pos_result.ok:
		return pos_result
	var world_anchor: Vector2i = pos_result.value

	var rotation_result := require_int_param(command, "rotation")
	if not rotation_result.ok:
		return rotation_result
	var rotation: int = rotation_result.value

	var map_ctx := _build_map_context(state)
	var piece_registry := _get_piece_registry()

	assert(rest.has("cells") and (rest["cells"] is Array), "move_restaurant: restaurants[%s].cells 缺失或类型错误（期望 Array）" % rest_id)
	var ignore_cells: Array = rest["cells"]
	var validate_result := PlacementValidatorClass.validate_restaurant_placement(
		map_ctx, world_anchor, rotation, piece_registry,
		command.actor, false, {"ignore_structure_cells": ignore_cells}
	)
	if not validate_result.ok:
		return validate_result

	return Result.success()

func _apply_changes(state: GameState, command: Command) -> Result:
	var player_id: int = command.actor
	var rest_id_result := require_string_param(command, "restaurant_id")
	if not rest_id_result.ok:
		return rest_id_result
	var rest_id: String = rest_id_result.value

	var pos_result := require_vector2i_param(command, "position")
	if not pos_result.ok:
		return pos_result
	var world_anchor: Vector2i = pos_result.value

	var rotation_result := require_int_param(command, "rotation")
	if not rotation_result.ok:
		return rotation_result
	var rotation: int = rotation_result.value

	assert(state.map is Dictionary, "move_restaurant: state.map 类型错误（期望 Dictionary）")
	assert(state.map.has("restaurants") and (state.map["restaurants"] is Dictionary), "move_restaurant: state.map.restaurants 缺失或类型错误（期望 Dictionary）")
	var restaurants: Dictionary = state.map["restaurants"]
	if not restaurants.has(rest_id):
		return Result.failure("餐厅不存在: %s" % rest_id)
	var rest_val = restaurants[rest_id]
	assert(rest_val is Dictionary, "move_restaurant: restaurants[%s] 类型错误（期望 Dictionary）" % rest_id)
	var rest: Dictionary = rest_val

	var map_ctx := _build_map_context(state)
	var piece_registry := _get_piece_registry()

	assert(rest.has("cells") and (rest["cells"] is Array), "move_restaurant: restaurants[%s].cells 缺失或类型错误（期望 Array）" % rest_id)
	var ignore_cells: Array = rest["cells"]
	var validate_result := PlacementValidatorClass.validate_restaurant_placement(
		map_ctx, world_anchor, rotation, piece_registry,
		player_id, false, {"ignore_structure_cells": ignore_cells}
	)
	if not validate_result.ok:
		return validate_result

	assert(validate_result.value is Dictionary, "move_restaurant: validate_restaurant_placement 返回值类型错误（期望 Dictionary）")
	var validate_value: Dictionary = validate_result.value
	assert(validate_value.has("footprint_cells") and (validate_value["footprint_cells"] is Array), "move_restaurant: validate_restaurant_placement 缺少 footprint_cells")
	assert(validate_value.has("entrance_pos") and (validate_value["entrance_pos"] is Vector2i), "move_restaurant: validate_restaurant_placement 缺少 entrance_pos")
	var new_cells: Array = validate_value["footprint_cells"]
	var entrance_pos: Vector2i = validate_value["entrance_pos"]

	# 清空旧格
	for cell_pos in ignore_cells:
		assert(cell_pos is Vector2i, "move_restaurant: ignore_cells 元素类型错误（期望 Vector2i）")
		var idx_old := MapRuntimeClass.world_to_index(state, cell_pos)
		state.map.cells[idx_old.y][idx_old.x]["structure"] = {}

	# 写入新格
	for cell_pos in new_cells:
		var is_anchor: bool = (cell_pos == world_anchor)
		var idx_new := MapRuntimeClass.world_to_index(state, cell_pos)
		state.map.cells[idx_new.y][idx_new.x]["structure"] = {
			"piece_id": "restaurant",
			"owner": player_id,
			"anchor_cell": is_anchor,
			"parent_anchor": world_anchor,
			"rotation": rotation,
			"restaurant_id": rest_id,
			"dynamic": true
		}

	# 更新餐厅记录（保留 restaurant_id）
	rest["anchor_pos"] = world_anchor
	rest["entrance_pos"] = entrance_pos
	rest["cells"] = new_cells
	rest["rotation"] = rotation
	restaurants[rest_id] = rest
	state.map["restaurants"] = restaurants

	# 使用区域经理会启用本回合的免下车能力
	state.players[player_id]["drive_thru_active"] = true
	EmployeeRulesClass.increment_action_count(state, player_id, action_id)

	return Result.success({
		"player_id": player_id,
		"restaurant_id": rest_id,
		"position": world_anchor,
		"rotation": rotation,
	})

func _generate_specific_events(_old_state: GameState, _new_state: GameState, command: Command) -> Array[Dictionary]:
	var rest_id_result := require_string_param(command, "restaurant_id")
	assert(rest_id_result.ok, "move_restaurant 缺少/错误参数: restaurant_id")
	var rest_id: String = rest_id_result.value
	assert(_new_state.map.restaurants.has(rest_id), "move_restaurant 餐厅不存在: %s" % rest_id)
	var rest: Dictionary = _new_state.map.restaurants[rest_id]
	assert(rest.has("anchor_pos") and rest["anchor_pos"] is Vector2i, "move_restaurant anchor_pos 缺失或类型错误")
	var anchor_pos: Vector2i = rest["anchor_pos"]
	assert(rest.has("rotation") and (rest["rotation"] is int or rest["rotation"] is float), "move_restaurant rotation 缺失或类型错误")
	var rotation: int = int(rest["rotation"])
	var p := [anchor_pos.x, anchor_pos.y]
	return [{
		"type": EventBus.EventType.RESTAURANT_MOVED,
		"data": {
			"player_id": command.actor,
			"restaurant_id": rest_id,
			"position": p,
			"rotation": rotation,
		}
	}]

func _build_map_context(state: GameState) -> Dictionary:
	return {
		"cells": state.map.cells,
		"grid_size": state.map.grid_size,
		"map_origin": MapRuntimeClass.get_map_origin(state),
		"houses": state.map.houses,
		"restaurants": state.map.restaurants,
		"drink_sources": state.map.get("drink_sources", []),
	}

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
