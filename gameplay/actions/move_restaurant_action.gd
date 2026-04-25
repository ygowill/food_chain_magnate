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
const StaffStateClass = preload("res://core/state/staff_state.gd")

var _piece_registry: Dictionary = {}
var _placement_validator = null

func _init(piece_registry: Dictionary = {}, placement_validator = null) -> void:
	action_id = "move_restaurant"
	display_name = "移动餐厅"
	description = "移动一个已有餐厅到新位置"
	requires_actor = true
	is_mandatory = false
	ui_hide_if_not_initiatable = true
	allowed_phases = [DefsClass.PHASE_WORKING]
	allowed_sub_phases = [DefsClass.SUB_PHASE_PLACE_RESTAURANTS]
	_piece_registry = piece_registry
	_placement_validator = placement_validator if placement_validator != null else RestaurantPlacementClass

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

static func _require_restaurant_placement_payload(value, prefix: String) -> Result:
	if not (value is Dictionary):
		return Result.failure("%s: validate_restaurant_placement 返回值类型错误（期望 Dictionary）" % prefix)
	var payload: Dictionary = value
	if not payload.has("footprint_cells"):
		return Result.failure("%s: validate_restaurant_placement 缺少 footprint_cells" % prefix)
	var footprint_read := _require_vector2i_array(payload["footprint_cells"], "%s: validate_restaurant_placement.footprint_cells" % prefix)
	if not footprint_read.ok:
		return footprint_read
	if not payload.has("entrance_pos") or not (payload["entrance_pos"] is Vector2i):
		return Result.failure("%s: validate_restaurant_placement 缺少 entrance_pos" % prefix)
	return Result.success({
		"footprint_cells": footprint_read.value,
		"entrance_pos": payload["entrance_pos"],
	})

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

func _read_optional_staff_id(command: Command) -> Result:
	if command == null:
		return Result.failure("command 为空")
	if not command.params.has("staff_id"):
		return Result.success(-1)
	var staff_id_result := require_int_param(command, "staff_id")
	if not staff_id_result.ok:
		return staff_id_result
	var staff_id := int(staff_id_result.value)
	if staff_id <= 0:
		return Result.failure("staff_id 必须 > 0，实际: %d" % staff_id)
	return Result.success(staff_id)

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
	var requested_staff_read := _read_optional_staff_id(command)
	if not requested_staff_read.ok:
		return requested_staff_read
	var requested_staff_id := int(requested_staff_read.value)

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

	var provider_read := EmployeeRulesClass.try_resolve_restaurant_placer(
		state,
		command.actor,
		action_id,
		employee_type,
		requested_staff_id
	)
	if not provider_read.ok:
		return provider_read

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
	var validate_result := _validate_restaurant_placement(
		map_ctx, world_anchor, rotation, piece_registry,
		command.actor, ignore_cells
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
	var employee_type := ""
	var employee_type_result := optional_string_param(command, "employee_type", "")
	if not employee_type_result.ok:
		return employee_type_result
	employee_type = employee_type_result.value
	var requested_staff_read := _read_optional_staff_id(command)
	if not requested_staff_read.ok:
		return requested_staff_read
	var requested_staff_id := int(requested_staff_read.value)
	var provider_read := EmployeeRulesClass.try_resolve_restaurant_placer(
		state,
		player_id,
		action_id,
		employee_type,
		requested_staff_id
	)
	if not provider_read.ok:
		return provider_read
	var provider: Dictionary = provider_read.value
	var mover_staff_id := int(provider.get("staff_id", -1))
	if employee_type.is_empty():
		employee_type = str(provider.get("employee_type", provider.get("id", ""))).strip_edges()
	if mover_staff_id <= 0 or employee_type.is_empty():
		return Result.failure("move_restaurant: 餐厅员工解析结果无效: %s" % str(provider))
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
	var validate_result := _validate_restaurant_placement(
		map_ctx, world_anchor, rotation, piece_registry,
		player_id, ignore_cells
	)
	if not validate_result.ok:
		return validate_result

	var placement_read := _require_restaurant_placement_payload(validate_result.value, action_id)
	if not placement_read.ok:
		return placement_read
	var placement: Dictionary = placement_read.value
	var new_cells: Array = placement["footprint_cells"]
	var entrance_pos: Vector2i = placement["entrance_pos"]

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
	var use_staff := StaffStateClass.increment_staff_track_usage(state, mover_staff_id, "place_or_move_restaurant", 1)
	if not use_staff.ok:
		return use_staff

	return Result.success({
		"player_id": player_id,
		"restaurant_id": rest_id,
		"position": world_anchor,
		"rotation": rotation,
		"staff_id": mover_staff_id,
		"employee_type": employee_type,
	})

func _generate_specific_events(_old_state: GameState, _new_state: GameState, command: Command) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var employee_type := ""
	var staff_id := -1
	if command.params.has("employee_type"):
		var employee_type_result := require_string_param(command, "employee_type")
		if not employee_type_result.ok:
			return events
		employee_type = str(employee_type_result.value).strip_edges()
	if command.params.has("staff_id"):
		var staff_id_result := require_int_param(command, "staff_id")
		if staff_id_result.ok:
			staff_id = int(staff_id_result.value)
	if _old_state != null:
		var provider_read := EmployeeRulesClass.try_resolve_restaurant_placer(
			_old_state,
			command.actor,
			action_id,
			employee_type,
			staff_id
		)
		if provider_read.ok and provider_read.value is Dictionary:
			var provider: Dictionary = provider_read.value
			staff_id = int(provider.get("staff_id", staff_id))
			if employee_type.is_empty():
				employee_type = str(provider.get("employee_type", provider.get("id", ""))).strip_edges()
	if employee_type.is_empty():
		var candidates := EmployeeUsageHelperClass.get_active_employee_types_for_usage_tag(
			_old_state, command.actor, "use:move_restaurant"
		)
		if not candidates.is_empty():
			employee_type = candidates[0]
	var rest_id_result := require_string_param(command, "restaurant_id")
	if not rest_id_result.ok:
		return events
	var rest_id: String = str(rest_id_result.value).strip_edges()
	if rest_id.is_empty():
		return events
	var restaurants_read := MapStateAccessClass.require_restaurants(_new_state, action_id)
	if not restaurants_read.ok:
		return events
	var restaurants: Dictionary = restaurants_read.value
	if not restaurants.has(rest_id):
		return events
	var old_rest: Dictionary = {}
	if _old_state != null:
		var old_restaurants_read := MapStateAccessClass.require_restaurants(_old_state, action_id)
		if old_restaurants_read.ok and old_restaurants_read.value is Dictionary:
			var old_restaurants: Dictionary = old_restaurants_read.value
			var old_rest_val = old_restaurants.get(rest_id, null)
			if old_rest_val is Dictionary:
				old_rest = old_rest_val
	var rest_val = restaurants[rest_id]
	if not (rest_val is Dictionary):
		return events
	var rest: Dictionary = rest_val
	if not rest.has("anchor_pos") or not (rest["anchor_pos"] is Vector2i):
		return events
	var anchor_pos: Vector2i = rest["anchor_pos"]
	if not rest.has("rotation") or not (rest["rotation"] is int or rest["rotation"] is float):
		return events
	var rotation: int = int(rest["rotation"])
	var p := [anchor_pos.x, anchor_pos.y]
	var data := {
		"player_id": command.actor,
		"restaurant_id": rest_id,
		"position": p,
		"to_position": p,
		"rotation": rotation,
		"to_rotation": rotation,
		"employee_type": employee_type,
	}
	var cells_val = rest.get("cells", null)
	if cells_val is Array:
		data["to_cells"] = _serialize_vector2i_array(Array(cells_val))
	if not old_rest.is_empty():
		var old_anchor_val = old_rest.get("anchor_pos", null)
		if old_anchor_val is Vector2i:
			var old_anchor: Vector2i = old_anchor_val
			data["from_position"] = [old_anchor.x, old_anchor.y]
		var old_rotation_val = old_rest.get("rotation", null)
		if old_rotation_val is int or old_rotation_val is float:
			data["from_rotation"] = int(old_rotation_val)
		var old_cells_val = old_rest.get("cells", null)
		if old_cells_val is Array:
			data["from_cells"] = _serialize_vector2i_array(Array(old_cells_val))
	events.append({
		"type": EventBus.EventType.RESTAURANT_MOVED,
		"data": data,
	})
	if staff_id > 0:
		var event_data: Dictionary = events[0].get("data", {})
		event_data["staff_id"] = staff_id
		events[0]["data"] = event_data
	return events

func _serialize_vector2i_array(cells: Array) -> Array:
	var out: Array = []
	for cell_val in cells:
		if cell_val is Vector2i:
			var p: Vector2i = cell_val
			out.append([p.x, p.y])
	return out

func _validate_restaurant_placement(map_ctx: Dictionary, world_anchor: Vector2i, rotation: int, piece_registry: Dictionary, player_id: int, ignore_cells: Array) -> Result:
	return _placement_validator.validate_restaurant_placement(
		map_ctx,
		world_anchor,
		rotation,
		piece_registry,
		player_id,
		false,
		{"ignore_structure_cells": ignore_cells}
	)

func _get_piece_registry() -> Dictionary:
	if _piece_registry.is_empty():
		const PieceDefClass = preload("res://core/map/piece_def.gd")
		_piece_registry = PieceDefClass.create_default_registry()
	return _piece_registry
