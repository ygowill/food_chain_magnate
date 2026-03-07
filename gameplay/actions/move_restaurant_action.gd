# 移动餐厅动作（Working 子阶段：PlaceRestaurants）
# 将玩家已有餐厅移动到新位置（保留 restaurant_id）。
class_name MoveRestaurantAction
extends ActionExecutor

const RestaurantPlacementClass = preload("res://core/map/placement_validator/restaurant_placement.gd")
const MapContextBuilderClass = preload("res://core/map/map_context_builder.gd")
const CoordsClass = preload("res://core/map/map_runtime/coords.gd")
const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const EmployeeUsageHelperClass = preload("res://gameplay/actions/employee_usage_helper.gd")
const PlayerStateAccessClass = preload("res://core/state/player_state_access.gd")
const MapStateAccessClass = preload("res://core/state/map_state_access.gd")

var _piece_registry: Dictionary = {}

func _init(piece_registry: Dictionary = {}) -> void:
	action_id = "move_restaurant"
	display_name = "移动餐厅"
	description = "移动一个已有餐厅到新位置"
	requires_actor = true
	is_mandatory = false
	allowed_phases = [DefsClass.PHASE_WORKING]
	allowed_sub_phases = [DefsClass.SUB_PHASE_PLACE_RESTAURANTS]
	_piece_registry = piece_registry

func can_initiate(state: GameState, player_id: int) -> bool:
	if state == null:
		return true
	if state.get_current_player_id() != player_id:
		return false

	var player := state.get_player(player_id)
	var restaurants_read := PlayerStateAccessClass.require_restaurants(player, "player[%d]" % player_id, action_id)
	if not restaurants_read.ok:
		return true
	var rest_list: Array = restaurants_read.value
	if rest_list.is_empty():
		return false

	var move_eligible := EmployeeRulesClass.count_active_by_usage_tag_for_working(state, player, player_id, "use:move_restaurant")
	if move_eligible <= 0:
		return false

	var total_eligible := EmployeeRulesClass.count_active_by_usage_tag_for_working(state, player, player_id, "use:place_restaurant")
	if total_eligible <= 0:
		return false

	var used_place_read := EmployeeRulesClass.try_get_action_count(state, player_id, "place_restaurant")
	if not used_place_read.ok:
		return false
	var used_move_read := EmployeeRulesClass.try_get_action_count(state, player_id, "move_restaurant")
	if not used_move_read.ok:
		return false
	var used_place := int(used_place_read.value)
	var used_move := int(used_move_read.value)
	var used_total := used_place + used_move
	if used_total >= total_eligible:
		return false
	if used_move >= move_eligible:
		return false

	return true

static func _require_vector2i_array(value, path: String) -> Result:
	if not (value is Array):
		return Result.failure("%s 类型错误（期望 Array）" % path)
	var arr: Array = value
	for i in range(arr.size()):
		if not (arr[i] is Vector2i):
			return Result.failure("%s[%d] 类型错误（期望 Vector2i）" % [path, i])
	return Result.success(arr)

static func _require_restaurant_record(restaurants: Dictionary, rest_id: String, prefix: String) -> Result:
	if rest_id.is_empty():
		return Result.failure("%srestaurant_id 不能为空" % prefix)
	if not restaurants.has(rest_id):
		return Result.failure("餐厅不存在: %s" % rest_id)
	var rest_val = restaurants[rest_id]
	if not (rest_val is Dictionary):
		return Result.failure("move_restaurant: restaurants[%s] 类型错误（期望 Dictionary）" % rest_id)
	var rest: Dictionary = rest_val
	if not rest.has("owner") or not (rest["owner"] is int):
		return Result.failure("move_restaurant: restaurants[%s].owner 缺失或类型错误（期望 int）" % rest_id)
	if not rest.has("cells") or not (rest["cells"] is Array):
		return Result.failure("move_restaurant: restaurants[%s].cells 缺失或类型错误（期望 Array）" % rest_id)
	var cells_read := _require_vector2i_array(rest["cells"], "move_restaurant: restaurants[%s].cells" % rest_id)
	if not cells_read.ok:
		return cells_read
	return Result.success(rest)

func _parse_params(command: Command) -> Result:
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

	return Result.success({
		"restaurant_id": rest_id,
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

	# 需要至少有一个自己的餐厅（无需 restaurant_id）
	var player0 := state.get_player(command.actor)
	var own_restaurants_read := PlayerStateAccessClass.require_restaurants(player0, "player[%d]" % command.actor, action_id)
	if own_restaurants_read.ok:
		var own_restaurants: Array = own_restaurants_read.value
		if own_restaurants.is_empty():
			return Result.failure("你没有可移动的餐厅")

	# 检查餐厅存在且归属当前玩家
	var restaurants_read := MapStateAccessClass.require_restaurants(state, action_id)
	if not restaurants_read.ok:
		return restaurants_read
	var restaurants: Dictionary = restaurants_read.value

	# 规则：移动餐厅需要在岗的区域经理（data/employees/*.json usage_tags）
	var player := state.get_player(command.actor)
	var move_eligible := EmployeeRulesClass.count_active_by_usage_tag_for_working(state, player, command.actor, "use:move_restaurant")
	if move_eligible <= 0:
		return Result.failure("需要在岗的区域经理才能移动餐厅")
	if not employee_type.is_empty():
		if not EmployeeUsageHelperClass.has_active_employee_with_usage_tag(state, command.actor, employee_type, "use:move_restaurant"):
			return Result.failure("该员工不能移动餐厅或未在岗: %s" % employee_type)

	# PlaceRestaurants 子阶段：place/move 共享次数上限 = 可用的本地/大区经理总数
	var total_eligible := EmployeeRulesClass.count_active_by_usage_tag_for_working(state, player, command.actor, "use:place_restaurant")
	var used_place_read := EmployeeRulesClass.try_get_action_count(state, command.actor, "place_restaurant")
	if not used_place_read.ok:
		return used_place_read
	var used_move_read := EmployeeRulesClass.try_get_action_count(state, command.actor, "move_restaurant")
	if not used_move_read.ok:
		return used_move_read
	var used_place := int(used_place_read.value)
	var used_move := int(used_move_read.value)
	var used_total := used_place + used_move
	if used_total >= total_eligible:
		return Result.failure("本地/大区经理本子阶段已用完: %d/%d" % [used_total, total_eligible])
	if used_move >= move_eligible:
		return Result.failure("区域经理本子阶段已用完: %d/%d" % [used_move, move_eligible])

	var params_result := _parse_params(command)
	if not params_result.ok:
		return params_result
	var params: Dictionary = params_result.value
	var rest_id: String = params["restaurant_id"]
	var world_anchor: Vector2i = params["world_anchor"]
	var rotation: int = int(params["rotation"])

	var rest_read := _require_restaurant_record(restaurants, rest_id, action_id)
	if not rest_read.ok:
		return rest_read
	var rest: Dictionary = rest_read.value
	if int(rest["owner"]) != command.actor:
		return Result.failure("只能移动自己的餐厅")

	var map_ctx_read := MapContextBuilderClass.build_context_result(state, action_id)
	if not map_ctx_read.ok:
		return map_ctx_read
	var map_ctx: Dictionary = map_ctx_read.value
	var piece_registry := _get_piece_registry()

	var ignore_cells: Array = rest["cells"]
	var validate_result := RestaurantPlacementClass.validate_restaurant_placement(
		map_ctx, world_anchor, rotation, piece_registry,
		command.actor, false, {"ignore_structure_cells": ignore_cells}
	)
	if not validate_result.ok:
		return validate_result

	return Result.success()

func _apply_changes(state: GameState, command: Command) -> Result:
	var params_result := _parse_params(command)
	if not params_result.ok:
		return params_result
	var params: Dictionary = params_result.value
	var player_id: int = command.actor
	var used_move_read := EmployeeRulesClass.try_get_action_count(state, player_id, action_id)
	if not used_move_read.ok:
		return used_move_read
	var rest_id: String = params["restaurant_id"]
	var world_anchor: Vector2i = params["world_anchor"]
	var rotation: int = int(params["rotation"])

	var restaurants_read := MapStateAccessClass.require_restaurants(state, action_id)
	if not restaurants_read.ok:
		return restaurants_read
	var restaurants: Dictionary = restaurants_read.value
	var rest_read := _require_restaurant_record(restaurants, rest_id, action_id)
	if not rest_read.ok:
		return rest_read
	var rest: Dictionary = rest_read.value
	if int(rest["owner"]) != player_id:
		return Result.failure("只能移动自己的餐厅")

	var map_ctx_read := MapContextBuilderClass.build_context_result(state, action_id)
	if not map_ctx_read.ok:
		return map_ctx_read
	var map_ctx: Dictionary = map_ctx_read.value
	var piece_registry := _get_piece_registry()

	var ignore_cells: Array = rest["cells"]
	var validate_result := RestaurantPlacementClass.validate_restaurant_placement(
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
		var idx_old := CoordsClass.world_to_index(state, cell_pos)
		state.map.cells[idx_old.y][idx_old.x]["structure"] = {}

	# 写入新格
	for cell_pos in new_cells:
		var is_anchor: bool = (cell_pos == world_anchor)
		var idx_new := CoordsClass.world_to_index(state, cell_pos)
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

	var inc_action := EmployeeRulesClass.try_increment_action_count(state, player_id, action_id)
	if not inc_action.ok:
		return inc_action

	return Result.success({
		"player_id": player_id,
		"restaurant_id": rest_id,
		"position": world_anchor,
		"rotation": rotation,
	})

func _generate_specific_events(_old_state: GameState, _new_state: GameState, command: Command) -> Array[Dictionary]:
	var employee_type := ""
	if command.params.has("employee_type"):
		var employee_type_result := require_string_param(command, "employee_type")
		assert(employee_type_result.ok, "move_restaurant 缺少/错误参数: employee_type")
		employee_type = employee_type_result.value
	if employee_type.is_empty():
		var candidates := EmployeeUsageHelperClass.get_active_employee_types_for_usage_tag(
			_old_state, command.actor, "use:move_restaurant"
		)
		if not candidates.is_empty():
			employee_type = candidates[0]
	var rest_id_result := require_string_param(command, "restaurant_id")
	assert(rest_id_result.ok, "move_restaurant 缺少/错误参数: restaurant_id")
	var rest_id: String = rest_id_result.value
	var restaurants_read := MapStateAccessClass.require_restaurants(_new_state, action_id)
	assert(restaurants_read.ok, "move_restaurant: %s" % str(restaurants_read.error))
	var restaurants: Dictionary = restaurants_read.value
	assert(restaurants.has(rest_id), "move_restaurant 餐厅不存在: %s" % rest_id)
	var rest: Dictionary = restaurants[rest_id]
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
			"employee_type": employee_type,
		}
	}]

func _get_piece_registry() -> Dictionary:
	if _piece_registry.is_empty():
		const PieceDefClass = preload("res://core/map/piece_def.gd")
		_piece_registry = PieceDefClass.create_default_registry()
	return _piece_registry
