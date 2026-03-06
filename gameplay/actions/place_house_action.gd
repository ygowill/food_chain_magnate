# 放置房屋动作
# 玩家在地图上放置房屋
class_name PlaceHouseAction
extends ActionExecutor

const PlacementClass = preload("res://core/map/placement_validator/placement.gd")
const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const MapContextBuilderClass = preload("res://core/map/map_context_builder.gd")
const CoordsClass = preload("res://core/map/map_runtime/coords.gd")
const RoadGraphCacheClass = preload("res://core/map/map_runtime/road_graph_cache.gd")
const RoundStateCountersClass = preload("res://core/utils/round_state_counters.gd")
const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const EmployeeUsageHelperClass = preload("res://gameplay/actions/employee_usage_helper.gd")

const HOUSE_PIECE_ID := "house_with_garden"
const HOUSE_NUMBER_SUPPLY_KEY := "house_number_supply_remaining"
const DEFAULT_HOUSE_NUMBER_SUPPLY := [1, 3, 6, 9, 11, 14, 17, 19]

var _piece_registry: Dictionary = {}

func _init(piece_registry: Dictionary = {}) -> void:
	action_id = "place_house"
	display_name = "放置房屋"
	description = "在地图上放置房屋"
	requires_actor = true
	is_mandatory = false
	allowed_phases = [DefsClass.PHASE_WORKING]
	allowed_sub_phases = [DefsClass.SUB_PHASE_PLACE_HOUSES]
	_piece_registry = piece_registry

func can_initiate(state: GameState, player_id: int) -> bool:
	if state == null:
		return true
	if state.get_current_player_id() != player_id:
		return false

	# 全局可放置房屋编号已耗尽：本动作不可启动
	if _get_remaining_house_numbers(state.map).is_empty():
		return false

	var player := state.get_player(player_id)
	var capacity := EmployeeRulesClass.count_active_by_usage_tag_for_working(state, player, player_id, "use:place_house")
	if capacity <= 0:
		return false

	var used_result := RoundStateCountersClass.get_player_count(
		state.round_state, "house_placement_counts", player_id
	)
	if not used_result.ok:
		return true
	var used := int(used_result.value)
	return used < capacity

func _parse_params(command: Command) -> Result:
	var pos_result := require_vector2i_param(command, "position")
	if not pos_result.ok:
		return pos_result
	var world_anchor: Vector2i = pos_result.value

	var rotation_result := require_int_param(command, "rotation")
	if not rotation_result.ok:
		return rotation_result
	var rotation: int = rotation_result.value

	var house_number_result := require_int_param(command, "house_number")
	if not house_number_result.ok:
		return house_number_result
	var house_number: int = int(house_number_result.value)
	if house_number <= 0:
		return Result.failure("请选择房屋编号")

	return Result.success({
		"world_anchor": world_anchor,
		"rotation": rotation,
		"house_number": house_number,
	})

func _validate_specific(state: GameState, command: Command) -> Result:
	# 检查必需参数
	var params_result := _parse_params(command)
	if not params_result.ok:
		return params_result
	var params: Dictionary = params_result.value
	var world_anchor: Vector2i = params["world_anchor"]
	var rotation: int = int(params["rotation"])
	var house_number: int = int(params["house_number"])

	# 检查是否是当前玩家的回合
	var current_player_id := state.get_current_player_id()
	if command.actor != current_player_id:
		return Result.failure("不是你的回合")

	var employee_type := ""
	var employee_type_result := optional_string_param(command, "employee_type", "")
	if not employee_type_result.ok:
		return employee_type_result
	employee_type = employee_type_result.value

	# 规则：仅允许从“剩余编号池”中选择（用完即无）
	var remaining_numbers := _get_remaining_house_numbers(state.map)
	if remaining_numbers.is_empty():
		return Result.failure("可放置房屋编号已用完")
	if not remaining_numbers.has(house_number):
		return Result.failure("不可用的房屋编号: %d" % house_number)

	# 规则：PlaceHouses 子阶段需要“可放置房屋”的在岗员工（数据驱动：员工 usage_tags）
	var player := state.get_player(command.actor)
	var capacity := EmployeeRulesClass.count_active_by_usage_tag_for_working(state, player, command.actor, "use:place_house")
	if capacity <= 0:
		return Result.failure("需要在岗的可放置房屋员工才能放置房屋")
	if not employee_type.is_empty():
		if not EmployeeUsageHelperClass.has_active_employee_with_usage_tag(state, command.actor, employee_type, "use:place_house"):
			return Result.failure("该员工不能放置房屋或未在岗: %s" % employee_type)
	var used_result := RoundStateCountersClass.get_player_count(
		state.round_state, "house_placement_counts", command.actor
	)
	if not used_result.ok:
		return used_result
	var used := int(used_result.value)
	if used >= capacity:
		return Result.failure("放置房屋/花园本子阶段已用完: %d/%d" % [used, capacity])

	# 构建地图上下文
	var map_ctx_read := MapContextBuilderClass.build_context_result(state, action_id)
	if not map_ctx_read.ok:
		return map_ctx_read
	var map_ctx: Dictionary = map_ctx_read.value

	# 构建建筑件注册表
	var piece_registry := _get_piece_registry()

	# 验证放置
	var validate_result := PlacementClass.validate_placement(
		map_ctx, HOUSE_PIECE_ID, world_anchor, rotation, piece_registry, {}
	)

	if not validate_result.ok:
		return validate_result

	return Result.success()

func _apply_changes(state: GameState, command: Command) -> Result:
	var params_result := _parse_params(command)
	if not params_result.ok:
		return params_result
	var params: Dictionary = params_result.value
	var world_anchor: Vector2i = params["world_anchor"]
	var rotation: int = int(params["rotation"])
	var house_number: int = int(params["house_number"])
	var player_id: int = command.actor

	# 构建地图上下文和建筑件注册表
	var map_ctx_read := MapContextBuilderClass.build_context_result(state, action_id)
	if not map_ctx_read.ok:
		return map_ctx_read
	var map_ctx: Dictionary = map_ctx_read.value
	var piece_registry := _get_piece_registry()

	# 获取验证结果 (包含 footprint_cells)
	var validate_result := PlacementClass.validate_placement(
		map_ctx, HOUSE_PIECE_ID, world_anchor, rotation, piece_registry, {}
	)

	if not validate_result.ok:
		return validate_result

	var footprint_cells: Array = validate_result.value.footprint_cells

	# 规则：玩家选择房屋编号，house_id 与编号保持一致（与印刷房屋一致，便于范围/日志/调试对齐）。
	var house_id := str(house_number)
	if state.map.has("houses") and (state.map["houses"] is Dictionary):
		var houses: Dictionary = state.map["houses"]
		if houses.has(house_id):
			return Result.failure("房屋编号已被占用: %d" % house_number)

	var consume_r := _consume_house_number(state.map, house_number)
	if not consume_r.ok:
		return consume_r

	# 写入格子
	for cell_pos in footprint_cells:
		var is_anchor = (cell_pos == world_anchor)
		var idx := CoordsClass.world_to_index(state, cell_pos)
		state.map.cells[idx.y][idx.x]["structure"] = {
			"piece_id": HOUSE_PIECE_ID,
			"owner": player_id,
			"anchor_cell": is_anchor,
			"parent_anchor": world_anchor,
			"rotation": rotation,
			"house_id": house_id,
			"house_number": house_number,
			"has_garden": true,
			"dynamic": true
		}

	# 注册房屋
	state.map.houses[house_id] = {
		"house_id": house_id,
		"house_number": house_number,
		"anchor_pos": world_anchor,
		"cells": footprint_cells,
		"has_garden": true,
		"is_apartment": false,
		"printed": false,
		"owner": player_id,
		"demands": []
	}

	# 使道路图缓存失效
	RoadGraphCacheClass.invalidate_road_graph(state)

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
	var employee_type := ""
	if command.params.has("employee_type"):
		var employee_type_result := require_string_param(command, "employee_type")
		assert(employee_type_result.ok, "place_house 缺少/错误参数: employee_type")
		employee_type = employee_type_result.value
	if employee_type.is_empty():
		var candidates := EmployeeUsageHelperClass.get_active_employee_types_for_usage_tag(
			old_state, command.actor, "use:place_house"
		)
		if not candidates.is_empty():
			employee_type = candidates[0]

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
			"has_garden": true,
			"employee_type": employee_type,
		}
	})

	return events

# 辅助方法：获取建筑件注册表（优先使用注入的 modules/*/content/pieces）
func _get_piece_registry() -> Dictionary:
	if _piece_registry.is_empty():
		const PieceDefClass = preload("res://core/map/piece_def.gd")
		_piece_registry = PieceDefClass.create_default_registry()
	return _piece_registry

static func _get_remaining_house_numbers(state_map: Dictionary) -> Array[int]:
	if state_map == null or not (state_map is Dictionary):
		return Array(DEFAULT_HOUSE_NUMBER_SUPPLY, TYPE_INT, "", null)

	var list_val = state_map.get(HOUSE_NUMBER_SUPPLY_KEY, null)
	if list_val is Array:
		var out: Array[int] = []
		for v in Array(list_val):
			if v is int:
				out.append(int(v))
			elif v is float:
				var f: float = float(v)
				if f == floor(f):
					out.append(int(f))
		# 去重 + 排序，保证稳定
		out.sort()
		var dedup: Array[int] = []
		for n in out:
			if dedup.has(n):
				continue
			dedup.append(n)
		return dedup

	# 兼容旧存档：没有 supply 字段时，按默认列表扣掉已存在的 house_number。
	var used: Dictionary = {}
	var houses_val = state_map.get("houses", null)
	if houses_val is Dictionary:
		var houses: Dictionary = houses_val
		for hid in houses.keys():
			var h_val = houses.get(hid, null)
			if not (h_val is Dictionary):
				continue
			var h: Dictionary = h_val
			var hn_val = h.get("house_number", null)
			if hn_val is int:
				used[int(hn_val)] = true
			elif hn_val is float:
				var f2: float = float(hn_val)
				if f2 == floor(f2):
					used[int(f2)] = true

	var remaining: Array[int] = []
	for n in DEFAULT_HOUSE_NUMBER_SUPPLY:
		var nn := int(n)
		if used.has(nn):
			continue
		remaining.append(nn)
	return remaining

static func _consume_house_number(state_map: Dictionary, house_number: int) -> Result:
	if state_map == null or not (state_map is Dictionary):
		return Result.failure("state.map 类型错误（期望 Dictionary）")

	var remaining := _get_remaining_house_numbers(state_map)
	if remaining.is_empty():
		return Result.failure("可放置房屋编号已用完")
	if not remaining.has(house_number):
		return Result.failure("不可用的房屋编号: %d" % house_number)

	var new_list: Array[int] = []
	for n in remaining:
		if int(n) == int(house_number):
			continue
		new_list.append(int(n))
	state_map[HOUSE_NUMBER_SUPPLY_KEY] = Array(new_list, TYPE_INT, "", null)
	return Result.success()
