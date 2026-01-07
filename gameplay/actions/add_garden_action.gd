# 添加花园动作（Working 子阶段：PlaceHouses）
# 为一个已有的房屋增加花园（2x1），并将该房屋更新为“带花园房屋”。
class_name AddGardenAction
extends ActionExecutor

const PlacementValidatorClass = preload("res://core/map/placement_validator.gd")
const MapRuntimeClass = preload("res://core/map/map_runtime.gd")
const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const RoundStateCountersClass = preload("res://core/utils/round_state_counters.gd")

var _piece_registry: Dictionary = {}

func _init(piece_registry: Dictionary = {}) -> void:
	action_id = "add_garden"
	display_name = "添加花园"
	description = "为一个已有的房屋添加花园"
	requires_actor = true
	is_mandatory = false
	allowed_phases = ["Working"]
	allowed_sub_phases = ["PlaceHouses"]
	_piece_registry = piece_registry

func can_initiate(state: GameState, player_id: int) -> bool:
	if state == null:
		return true
	if state.get_current_player_id() != player_id:
		return false

	var player := state.get_player(player_id)
	var capacity := EmployeeRulesClass.count_active_by_usage_tag_for_working(state, player, player_id, "use:add_garden")
	if capacity <= 0:
		return false

	var used_result := RoundStateCountersClass.get_player_count(
		state.round_state, "house_placement_counts", player_id
	)
	if not used_result.ok:
		return true
	var used := int(used_result.value)
	return used < capacity

func _validate_specific(state: GameState, command: Command) -> Result:
	var house_id_result := require_string_param(command, "house_id")
	if not house_id_result.ok:
		return house_id_result
	var house_id: String = house_id_result.value

	var direction_result := require_string_param(command, "direction")
	if not direction_result.ok:
		return direction_result
	var direction: String = direction_result.value
	if direction != "N" and direction != "E" and direction != "S" and direction != "W":
		return Result.failure("无效的 direction: %s" % direction)

	# 检查是否是当前玩家的回合
	var current_player_id := state.get_current_player_id()
	if command.actor != current_player_id:
		return Result.failure("不是你的回合")

	# 规则：PlaceHouses 子阶段需要“可添加花园”的在岗员工（数据驱动：员工 usage_tags）
	var player := state.get_player(command.actor)
	var capacity := EmployeeRulesClass.count_active_by_usage_tag_for_working(state, player, command.actor, "use:add_garden")
	if capacity <= 0:
		return Result.failure("需要在岗的可添加花园员工才能添加花园")

	# 与 place_house 共享“每子阶段次数=可放置房屋/花园员工数量”的限制
	var used_result := RoundStateCountersClass.get_player_count(
		state.round_state, "house_placement_counts", command.actor
	)
	if not used_result.ok:
		return used_result
	var used := int(used_result.value)
	if used >= capacity:
		return Result.failure("放置房屋/花园本子阶段已用完: %d/%d" % [used, capacity])

	var map_ctx := _build_map_context(state)
	var piece_registry := _get_piece_registry()

	var validate_result := PlacementValidatorClass.validate_garden_attachment(
		map_ctx, house_id, direction, piece_registry, {}
	)
	if not validate_result.ok:
		return validate_result

	return Result.success()

func _apply_changes(state: GameState, command: Command) -> Result:
	var player_id: int = command.actor
	var house_id_result := require_string_param(command, "house_id")
	if not house_id_result.ok:
		return house_id_result
	var house_id: String = house_id_result.value

	var direction_result := require_string_param(command, "direction")
	if not direction_result.ok:
		return direction_result
	var direction: String = direction_result.value

	var map_ctx := _build_map_context(state)
	var piece_registry := _get_piece_registry()

	var validate_result := PlacementValidatorClass.validate_garden_attachment(
		map_ctx, house_id, direction, piece_registry, {}
	)
	if not validate_result.ok:
		return validate_result

	assert(validate_result.value is Dictionary, "add_garden: validate_garden_attachment 返回值类型错误（期望 Dictionary）")
	var validate_value: Dictionary = validate_result.value
	assert(validate_value.has("garden_cells") and (validate_value["garden_cells"] is Array), "add_garden: validate_garden_attachment 缺少 garden_cells")
	assert(validate_value.has("merged_cells") and (validate_value["merged_cells"] is Array), "add_garden: validate_garden_attachment 缺少 merged_cells")
	var garden_cells: Array = validate_value["garden_cells"]
	var merged_cells: Array = validate_value["merged_cells"]

	assert(state.map.has("houses") and (state.map["houses"] is Dictionary), "add_garden: state.map.houses 缺失或类型错误（期望 Dictionary）")
	var houses: Dictionary = state.map["houses"]
	if not houses.has(house_id):
		return Result.failure("房屋不存在: %s" % house_id)
	var house_val = houses[house_id]
	assert(house_val is Dictionary, "add_garden: houses[%s] 类型错误（期望 Dictionary）" % house_id)
	var house: Dictionary = house_val

	assert(house.has("anchor_pos") and (house["anchor_pos"] is Vector2i), "add_garden: houses[%s].anchor_pos 缺失或类型错误（期望 Vector2i）" % house_id)
	var anchor_pos: Vector2i = house["anchor_pos"]
	assert(house.has("house_number"), "add_garden: houses[%s] 缺少 house_number" % house_id)
	var house_number = house["house_number"]
	assert(house_number is int or house_number is float or house_number is String, "add_garden: houses[%s].house_number 类型错误（期望 int/float/String）" % house_id)

	# 尽量继承房屋原有结构字段（owner/rotation/dynamic）
	var base_owner: int = -1
	var base_rotation: int = 0
	var base_dynamic: bool = false
	var anchor_cell: Dictionary = MapRuntimeClass.get_cell(state, anchor_pos)
	assert(anchor_cell.has("structure") and (anchor_cell["structure"] is Dictionary), "add_garden: anchor_cell.structure 缺失或类型错误: %s" % str(anchor_pos))
	var s: Dictionary = anchor_cell["structure"]
	assert(not s.is_empty(), "add_garden: 房屋锚点格缺少 structure: %s" % str(anchor_pos))
	assert(s.has("owner") and (s["owner"] is int), "add_garden: 房屋 structure.owner 缺失或类型错误（期望 int）")
	assert(s.has("rotation") and (s["rotation"] is int), "add_garden: 房屋 structure.rotation 缺失或类型错误（期望 int）")
	assert(s.has("dynamic") and (s["dynamic"] is bool), "add_garden: 房屋 structure.dynamic 缺失或类型错误（期望 bool）")
	base_owner = int(s["owner"])
	base_rotation = int(s["rotation"])
	base_dynamic = bool(s["dynamic"])

	# 更新房屋：cells/has_garden
	house["has_garden"] = true
	house["cells"] = merged_cells
	houses[house_id] = house
	state.map["houses"] = houses

	# 写入结构格（将整栋房屋标记为 house_with_garden，避免后续放置重叠）
	for cell_pos in merged_cells:
		var is_anchor: bool = (cell_pos == anchor_pos)
		var idx := MapRuntimeClass.world_to_index(state, cell_pos)
		state.map.cells[idx.y][idx.x]["structure"] = {
			"piece_id": "house_with_garden",
			"owner": base_owner,
			"anchor_cell": is_anchor,
			"parent_anchor": anchor_pos,
			"rotation": base_rotation,
			"house_id": house_id,
			"house_number": house_number,
			"has_garden": true,
			"dynamic": base_dynamic
		}

	var inc_result := RoundStateCountersClass.increment_player_count(
		state.round_state, "house_placement_counts", player_id, 1
	)
	if not inc_result.ok:
		return inc_result

	return Result.success({
		"player_id": player_id,
		"house_id": house_id,
		"direction": direction,
		"garden_cells": garden_cells,
	})

func _generate_specific_events(_old_state: GameState, _new_state: GameState, command: Command) -> Array[Dictionary]:
	var house_id_result := require_string_param(command, "house_id")
	assert(house_id_result.ok, "add_garden 缺少/错误参数: house_id")
	var direction_result := require_string_param(command, "direction")
	assert(direction_result.ok, "add_garden 缺少/错误参数: direction")
	return [{
		"type": EventBus.EventType.GARDEN_ADDED,
		"data": {
			"player_id": command.actor,
			"house_id": house_id_result.value,
			"direction": direction_result.value,
		}
	}]

func _build_map_context(state: GameState) -> Dictionary:
	return {
		"cells": state.map.cells,
		"grid_size": state.map.grid_size,
		"map_origin": MapRuntimeClass.get_map_origin(state),
		"houses": state.map.houses,
		"restaurants": state.map.restaurants
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
