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
const PlayerStateAccessClass = preload("res://core/state/player_state_access.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const StaffStateClass = preload("res://core/state/staff_state.gd")

const ROUND_STATE_OPENING_SOON_RESTAURANTS_KEY := "opening_soon_restaurants"

var _piece_registry: Dictionary = {}
var _placement_validator = null

func _init(piece_registry: Dictionary = {}, placement_validator = null) -> void:
	action_id = "place_restaurant"
	display_name = "放置餐厅"
	description = "在地图上放置餐厅"
	requires_actor = true
	is_mandatory = false
	ui_hide_if_not_initiatable = true
	allowed_phases = [DefsClass.PHASE_SETUP, DefsClass.PHASE_WORKING]
	allowed_sub_phases = [DefsClass.SUB_PHASE_PLACE_RESTAURANTS]
	_piece_registry = piece_registry
	_placement_validator = placement_validator if placement_validator != null else RestaurantPlacementClass

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
	var used_place_read := EmployeeRulesClass.try_get_action_count(state, player_id, "place_restaurant")
	if not used_place_read.ok:
		return false
	var used_move_read := EmployeeRulesClass.try_get_action_count(state, player_id, "move_restaurant")
	if not used_move_read.ok:
		return false
	var used_place := int(used_place_read.value)
	var used_move := int(used_move_read.value)
	return (used_place + used_move) < eligible

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
		var used_place_read := EmployeeRulesClass.try_get_action_count(state, command.actor, "place_restaurant")
		if not used_place_read.ok:
			return used_place_read
		var used_move_read := EmployeeRulesClass.try_get_action_count(state, command.actor, "move_restaurant")
		if not used_move_read.ok:
			return used_move_read
		var used_place := int(used_place_read.value)
		var used_move := int(used_move_read.value)
		var used_total := used_place + used_move
		if used_total >= eligible:
			return Result.failure("本地/大区经理本子阶段已用完: %d/%d" % [used_total, eligible])

		var provider_read := EmployeeRulesClass.try_resolve_restaurant_placer(
			state,
			command.actor,
			action_id,
			employee_type,
			requested_staff_id
		)
		if not provider_read.ok:
			return provider_read

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

func _prepare_opening_soon_restaurants(state: GameState) -> Result:
	if not (state.round_state is Dictionary):
		return Result.failure("place_restaurant: state.round_state 类型错误（期望 Dictionary）")
	if not state.round_state.has(ROUND_STATE_OPENING_SOON_RESTAURANTS_KEY):
		return Result.success([])
	var pending_val = state.round_state.get(ROUND_STATE_OPENING_SOON_RESTAURANTS_KEY, null)
	if not (pending_val is Array):
		return Result.failure("place_restaurant: state.round_state.%s 类型错误（期望 Array）" % ROUND_STATE_OPENING_SOON_RESTAURANTS_KEY)
	return Result.success(Array(pending_val))

func _apply_changes(state: GameState, command: Command) -> Result:
	var employee_type := ""
	var employee_type_result := optional_string_param(command, "employee_type", "")
	if not employee_type_result.ok:
		return employee_type_result
	employee_type = employee_type_result.value
	var requested_staff_read := _read_optional_staff_id(command)
	if not requested_staff_read.ok:
		return requested_staff_read
	var requested_staff_id := int(requested_staff_read.value)
	var placer_staff_id := -1
	if state.phase == DefsClass.PHASE_WORKING:
		var provider_read := EmployeeRulesClass.try_resolve_restaurant_placer(
			state,
			command.actor,
			action_id,
			employee_type,
			requested_staff_id
		)
		if not provider_read.ok:
			return provider_read
		var provider: Dictionary = provider_read.value
		placer_staff_id = int(provider.get("staff_id", -1))
		if employee_type.is_empty():
			employee_type = str(provider.get("employee_type", provider.get("id", ""))).strip_edges()
		if placer_staff_id <= 0 or employee_type.is_empty():
			return Result.failure("place_restaurant: 餐厅员工解析结果无效: %s" % str(provider))
	elif employee_type.is_empty():
		var candidates := EmployeeUsageHelperClass.get_active_employee_types_for_usage_tag(
			state, command.actor, "use:place_restaurant"
		)
		if not candidates.is_empty():
			employee_type = candidates[0]
	var opening_soon := (state.phase == DefsClass.PHASE_WORKING and employee_type == "local_manager")
	if state.phase == DefsClass.PHASE_WORKING:
		var used_place_read := EmployeeRulesClass.try_get_action_count(state, command.actor, action_id)
		if not used_place_read.ok:
			return used_place_read
	var opening_soon_pending: Array = []
	if opening_soon:
		var pending_read = _prepare_opening_soon_restaurants(state)
		if not pending_read.ok:
			return pending_read
		opening_soon_pending = pending_read.value

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
	var validate_result := _validate_restaurant_placement(
		map_ctx, world_anchor, rotation, piece_registry,
		player_id, is_initial
	)

	if not validate_result.ok:
		return validate_result

	var placement_read := _require_restaurant_placement_payload(validate_result.value, action_id)
	if not placement_read.ok:
		return placement_read
	var placement: Dictionary = placement_read.value
	var footprint_cells: Array = placement["footprint_cells"]
	var entrance_pos: Vector2i = placement["entrance_pos"]

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
		opening_soon_pending.append(restaurant_data.duplicate(true))
		state.round_state[ROUND_STATE_OPENING_SOON_RESTAURANTS_KEY] = opening_soon_pending
	else:
		# 注册餐厅（立即开业）
		state.map.restaurants[restaurant_id] = restaurant_data

		# 添加到玩家餐厅列表
		var restaurants_read := PlayerStateAccessClass.require_player_restaurants(state, player_id, action_id)
		if not restaurants_read.ok:
			return restaurants_read
		var restaurants: Array = restaurants_read.value
		restaurants.append(restaurant_id)
		state.players[player_id]["restaurants"] = restaurants

	# 使道路图缓存失效
	RoadGraphCacheClass.invalidate_road_graph(state)

	if state.phase == DefsClass.PHASE_WORKING:
		var inc_action := EmployeeRulesClass.try_increment_action_count(state, player_id, action_id)
		if not inc_action.ok:
			return inc_action
		var use_staff := StaffStateClass.increment_staff_track_usage(state, placer_staff_id, "place_or_move_restaurant", 1)
		if not use_staff.ok:
			return use_staff

	var result_payload := {
		"restaurant_id": restaurant_id,
		"player_id": player_id,
		"position": world_anchor,
		"rotation": rotation,
		"opening_soon": opening_soon,
		"employee_type": employee_type,
	}
	if placer_staff_id > 0:
		result_payload["staff_id"] = placer_staff_id
	var result := Result.success(result_payload)

	# 里程碑触发（模块化）：首次在 Working 阶段放置新餐厅
	if state.phase == DefsClass.PHASE_WORKING:
		var ms := MilestoneSystemClass.process_event(state, "RestaurantPlaced", {
			"player_id": player_id,
			"phase": state.phase,
		})
		if not ms.ok:
			return Result.failure("里程碑触发失败(RestaurantPlaced): %s" % ms.error).with_warnings(ms.warnings)
		result.with_warnings(ms.warnings)

	return result

func _generate_specific_events(old_state: GameState, new_state: GameState, command: Command) -> Array[Dictionary]:
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
	if old_state != null and old_state.phase == DefsClass.PHASE_WORKING:
		var provider_read := EmployeeRulesClass.try_resolve_restaurant_placer(
			old_state,
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
	if employee_type.is_empty() and old_state != null and old_state.phase == DefsClass.PHASE_WORKING:
		var candidates := EmployeeUsageHelperClass.get_active_employee_types_for_usage_tag(
			old_state, command.actor, "use:place_restaurant"
		)
		if not candidates.is_empty():
			employee_type = candidates[0]

	var old_restaurants: Dictionary = {}
	if old_state != null and old_state.map is Dictionary and old_state.map.has("restaurants") and old_state.map["restaurants"] is Dictionary:
		old_restaurants = old_state.map["restaurants"]
	var new_restaurants: Dictionary = {}
	if new_state != null and new_state.map is Dictionary and new_state.map.has("restaurants") and new_state.map["restaurants"] is Dictionary:
		new_restaurants = new_state.map["restaurants"]

	var restaurant_id := ""
	var opening_soon := false
	var world_anchor: Vector2i = Vector2i(-1, -1)

	for rest_id in new_restaurants.keys():
		if rest_id in old_restaurants:
			continue
		restaurant_id = str(rest_id).strip_edges()
		if restaurant_id.is_empty():
			return events
		var rest_val = new_restaurants[rest_id]
		if not (rest_val is Dictionary):
			return events
		var rest: Dictionary = rest_val
		if not rest.has("anchor_pos") or not (rest["anchor_pos"] is Vector2i):
			return events
		world_anchor = rest["anchor_pos"]
		break
	if restaurant_id.is_empty():
		# opening_soon: restaurant 不会立即加入 map.restaurants，改从 round_state 中推导
		var old_pending: Array = []
		var new_pending: Array = []
		if old_state != null and old_state.round_state is Dictionary:
			var ov = (old_state.round_state as Dictionary).get(ROUND_STATE_OPENING_SOON_RESTAURANTS_KEY, null)
			if ov is Array:
				old_pending = ov
		if new_state != null and new_state.round_state is Dictionary:
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
			var ap = e2.get("anchor_pos", null)
			if not (ap is Vector2i):
				return events
			restaurant_id = rid2
			world_anchor = Vector2i(ap)
			opening_soon = true
			break
	if restaurant_id.is_empty():
		return events

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
	if staff_id > 0:
		var data: Dictionary = events[0].get("data", {})
		data["staff_id"] = staff_id
		events[0]["data"] = data

	return events

# 辅助方法：获取建筑件注册表（优先使用注入的 modules/*/content/pieces）
func _validate_restaurant_placement(map_ctx: Dictionary, world_anchor: Vector2i, rotation: int, piece_registry: Dictionary, player_id: int, is_initial: bool) -> Result:
	return _placement_validator.validate_restaurant_placement(
		map_ctx,
		world_anchor,
		rotation,
		piece_registry,
		player_id,
		is_initial,
		{}
	)

func _get_piece_registry() -> Dictionary:
	if _piece_registry.is_empty():
		const PieceDefClass = preload("res://core/map/piece_def.gd")
		_piece_registry = PieceDefClass.create_default_registry()
	return _piece_registry
