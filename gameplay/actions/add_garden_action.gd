# 添加花园动作（Working 子阶段：PlaceHouses）
# 为一个已有的房屋增加花园（2x1），并将该房屋更新为“带花园房屋”。
class_name AddGardenAction
extends ActionExecutor

const GardenAttachmentClass = preload("res://core/map/placement_validator/garden_attachment.gd")
const MapContextBuilderClass = preload("res://core/map/map_context_builder.gd")
const MapStateAccessClass = preload("res://core/state/map_state_access.gd")
const CellsClass = preload("res://core/map/map_runtime/cells.gd")
const CoordsClass = preload("res://core/map/map_runtime/coords.gd")
const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const RoundStateCountersClass = preload("res://core/utils/round_state_counters.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const EmployeeUsageHelperClass = preload("res://gameplay/actions/employee_usage_helper.gd")

const GARDEN_SUPPLY_KEY := "garden_supply_remaining"
const DEFAULT_GARDEN_SUPPLY := 8

var _piece_registry: Dictionary = {}
var _garden_attachment_validator = null

func _init(piece_registry: Dictionary = {}, garden_attachment_validator = null) -> void:
	action_id = "add_garden"
	display_name = "添加花园"
	description = "为一个已有的房屋添加花园"
	requires_actor = true
	is_mandatory = false
	allowed_phases = [DefsClass.PHASE_WORKING]
	allowed_sub_phases = [DefsClass.SUB_PHASE_PLACE_HOUSES]
	_piece_registry = piece_registry
	_garden_attachment_validator = garden_attachment_validator if garden_attachment_validator != null else GardenAttachmentClass

func can_initiate(state: GameState, player_id: int) -> bool:
	if state == null:
		return true
	if state.get_current_player_id() != player_id:
		return false

	# 全局花园板件耗尽：本动作不可启动
	if _get_garden_supply_remaining(state.map) <= 0:
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

static func _require_vector2i_array(value, path: String) -> Result:
	if not (value is Array):
		return Result.failure("%s 类型错误（期望 Array）" % path)
	var arr: Array = value
	for i in range(arr.size()):
		if not (arr[i] is Vector2i):
			return Result.failure("%s[%d] 类型错误（期望 Vector2i）" % [path, i])
	return Result.success(arr)

static func _require_garden_attachment_payload(value, prefix: String) -> Result:
	if not (value is Dictionary):
		return Result.failure("%s: validate_garden_attachment 返回值类型错误（期望 Dictionary）" % prefix)
	var payload: Dictionary = value
	if not payload.has("garden_cells"):
		return Result.failure("%s: validate_garden_attachment 缺少 garden_cells" % prefix)
	var garden_read := _require_vector2i_array(payload["garden_cells"], "%s: validate_garden_attachment.garden_cells" % prefix)
	if not garden_read.ok:
		return garden_read
	if not payload.has("merged_cells"):
		return Result.failure("%s: validate_garden_attachment 缺少 merged_cells" % prefix)
	var merged_read := _require_vector2i_array(payload["merged_cells"], "%s: validate_garden_attachment.merged_cells" % prefix)
	if not merged_read.ok:
		return merged_read
	return Result.success({
		"garden_cells": garden_read.value,
		"merged_cells": merged_read.value,
	})

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

	var employee_type := ""
	var employee_type_result := optional_string_param(command, "employee_type", "")
	if not employee_type_result.ok:
		return employee_type_result
	employee_type = employee_type_result.value

	# 规则：PlaceHouses 子阶段需要“可添加花园”的在岗员工（数据驱动：员工 usage_tags）
	var player := state.get_player(command.actor)
	var capacity := EmployeeRulesClass.count_active_by_usage_tag_for_working(state, player, command.actor, "use:add_garden")
	if capacity <= 0:
		return Result.failure("需要在岗的可添加花园员工才能添加花园")
	if not employee_type.is_empty():
		if not EmployeeUsageHelperClass.has_active_employee_with_usage_tag(state, command.actor, employee_type, "use:add_garden"):
			return Result.failure("该员工不能添加花园或未在岗: %s" % employee_type)

	# 与 place_house 共享“每子阶段次数=可放置房屋/花园员工数量”的限制
	var used_result := RoundStateCountersClass.get_player_count(
		state.round_state, "house_placement_counts", command.actor
	)
	if not used_result.ok:
		return used_result
	var used := int(used_result.value)
	if used >= capacity:
		return Result.failure("放置房屋/花园本子阶段已用完: %d/%d" % [used, capacity])

	# 全局花园板件数量限制（只限制 add_garden）
	if _get_garden_supply_remaining(state.map) <= 0:
		return Result.failure("花园板件已用完")

	var map_ctx_read := MapContextBuilderClass.build_context_result(state, action_id)
	if not map_ctx_read.ok:
		return map_ctx_read
	var map_ctx: Dictionary = map_ctx_read.value
	var piece_registry := _get_piece_registry()

	var validate_result := _validate_garden_attachment(
		map_ctx, house_id, direction, piece_registry
	)
	if not validate_result.ok:
		return validate_result

	return Result.success()

func _preview_house_placement_increment(state: GameState, player_id: int) -> Result:
	if not (state.round_state is Dictionary):
		return Result.failure("round_state 类型错误（期望 Dictionary）")
	var round_state_preview: Dictionary = state.round_state.duplicate(true)
	return RoundStateCountersClass.increment_player_count(
		round_state_preview, "house_placement_counts", player_id, 1
	)

func _prepare_house_for_apply(state: GameState, house_id: String, player_id: int) -> Result:
	var houses_read := MapStateAccessClass.require_houses(state, action_id)
	if not houses_read.ok:
		return houses_read
	var houses: Dictionary = houses_read.value
	if not houses.has(house_id):
		return Result.failure("房屋不存在: %s" % house_id)
	var house_val = houses.get(house_id, null)
	if not (house_val is Dictionary):
		return Result.failure("add_garden: houses[%s] 类型错误（期望 Dictionary）" % house_id)
	var house: Dictionary = house_val

	if not house.has("anchor_pos") or not (house["anchor_pos"] is Vector2i):
		return Result.failure("add_garden: houses[%s].anchor_pos 缺失或类型错误（期望 Vector2i）" % house_id)
	var old_anchor_pos: Vector2i = house["anchor_pos"]
	if not house.has("house_number"):
		return Result.failure("add_garden: houses[%s] 缺少 house_number" % house_id)
	var house_number = house["house_number"]
	if not (house_number is int or house_number is float or house_number is String):
		return Result.failure("add_garden: houses[%s].house_number 类型错误（期望 int/float/String）" % house_id)

	var anchor_cell: Dictionary = CellsClass.get_cell(state, old_anchor_pos)
	if not anchor_cell.has("structure") or not (anchor_cell["structure"] is Dictionary):
		return Result.failure("add_garden: anchor_cell.structure 缺失或类型错误: %s" % str(old_anchor_pos))
	var structure: Dictionary = anchor_cell["structure"]
	if structure.is_empty():
		return Result.failure("add_garden: 房屋锚点格缺少 structure: %s" % str(old_anchor_pos))
	if not structure.has("owner") or not (structure["owner"] is int):
		return Result.failure("add_garden: 房屋 structure.owner 缺失或类型错误（期望 int）")
	if not structure.has("rotation") or not (structure["rotation"] is int):
		return Result.failure("add_garden: 房屋 structure.rotation 缺失或类型错误（期望 int）")
	if not structure.has("dynamic") or not (structure["dynamic"] is bool):
		return Result.failure("add_garden: 房屋 structure.dynamic 缺失或类型错误（期望 bool）")

	var counter_preview = _preview_house_placement_increment(state, player_id)
	if not counter_preview.ok:
		return counter_preview

	return Result.success({
		"houses": houses,
		"house": house,
		"old_anchor_pos": old_anchor_pos,
		"house_number": house_number,
		"base_owner": int(structure["owner"]),
		"base_dynamic": bool(structure["dynamic"]),
	})

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

	var map_ctx_read := MapContextBuilderClass.build_context_result(state, action_id)
	if not map_ctx_read.ok:
		return map_ctx_read
	var map_ctx: Dictionary = map_ctx_read.value
	var piece_registry := _get_piece_registry()

	var validate_result := _validate_garden_attachment(
		map_ctx, house_id, direction, piece_registry
	)
	if not validate_result.ok:
		return validate_result

	# 再次检查供给（防止并发/重复执行导致负数；正常情况下 validate 已保证）
	var supply_before := _get_garden_supply_remaining(state.map)
	if supply_before <= 0:
		return Result.failure("花园板件已用完")

	var payload_read := _require_garden_attachment_payload(validate_result.value, action_id)
	if not payload_read.ok:
		return payload_read
	var payload: Dictionary = payload_read.value
	var garden_cells: Array = payload["garden_cells"]
	var merged_cells: Array = payload["merged_cells"]

	var house_apply_read := _prepare_house_for_apply(state, house_id, player_id)
	if not house_apply_read.ok:
		return house_apply_read
	var house_apply: Dictionary = house_apply_read.value
	var houses: Dictionary = house_apply["houses"]
	var house: Dictionary = house_apply["house"]
	var old_anchor_pos: Vector2i = house_apply["old_anchor_pos"]
	var house_number = house_apply["house_number"]
	var base_owner: int = int(house_apply["base_owner"])
	var base_dynamic: bool = bool(house_apply["base_dynamic"])

	# house_with_garden 是非对称占地：rotation + anchor_cell 必须与 garden_direction 匹配，
	# 否则在旋转板块上会出现确认位置错乱/可放置性判定错误。
	var new_rotation := _rotation_for_garden_direction(direction)
	var new_anchor_read := _compute_anchor_for_merged_cells(merged_cells, new_rotation)
	if not new_anchor_read.ok:
		return new_anchor_read
	var new_anchor_pos: Vector2i = new_anchor_read.value

	# 更新房屋：cells/has_garden
	house["has_garden"] = true
	house["cells"] = merged_cells
	house["anchor_pos"] = new_anchor_pos
	houses[house_id] = house
	state.map["houses"] = houses

	# 写入结构格（将整栋房屋标记为 house_with_garden，避免后续放置重叠）
	for cell_pos in merged_cells:
		var is_anchor: bool = (cell_pos == new_anchor_pos)
		var idx := CoordsClass.world_to_index(state, cell_pos)
		state.map.cells[idx.y][idx.x]["structure"] = {
			"piece_id": "house_with_garden",
			"owner": base_owner,
			"anchor_cell": is_anchor,
			"parent_anchor": new_anchor_pos,
			"rotation": new_rotation,
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

	state.map[GARDEN_SUPPLY_KEY] = maxi(0, supply_before - 1)

	return Result.success({
		"player_id": player_id,
		"house_id": house_id,
		"direction": direction,
		"garden_cells": garden_cells,
	})

func _generate_specific_events(_old_state: GameState, _new_state: GameState, command: Command) -> Array[Dictionary]:
	var house_id_result := require_string_param(command, "house_id")
	if not house_id_result.ok:
		return []
	var direction_result := require_string_param(command, "direction")
	if not direction_result.ok:
		return []

	var house_id: String = str(house_id_result.value).strip_edges()
	var direction: String = str(direction_result.value).strip_edges()
	if house_id.is_empty() or direction.is_empty():
		return []
	var employee_type := ""
	if command.params.has("employee_type"):
		var employee_type_result := require_string_param(command, "employee_type")
		if not employee_type_result.ok:
			return []
		employee_type = str(employee_type_result.value).strip_edges()
	if employee_type.is_empty():
		var candidates := EmployeeUsageHelperClass.get_active_employee_types_for_usage_tag(
			_old_state, command.actor, "use:add_garden"
		)
		if not candidates.is_empty():
			employee_type = candidates[0]
	var house_number := -1
	var position: Array = []
	if _new_state != null and _new_state.map != null and _new_state.map.houses.has(house_id):
		var house_val = _new_state.map.houses[house_id]
		if house_val is Dictionary:
			var house: Dictionary = house_val
			var num_val = house.get("house_number", null)
			if num_val is int:
				house_number = int(num_val)
			elif num_val is float:
				var f: float = float(num_val)
				if f == floor(f):
					house_number = int(f)
			var pos_val = house.get("anchor_pos", null)
			if pos_val is Vector2i:
				var p: Vector2i = pos_val
				position = [p.x, p.y]

	var data := {
		"player_id": command.actor,
		"house_id": house_id,
		"direction": direction,
		"employee_type": employee_type,
	}
	if house_number > 0:
		data["house_number"] = house_number
	if position.size() >= 2:
		data["position"] = position
	return [{
		"type": EventBus.EventType.GARDEN_ADDED,
		"data": data
	}]

func _validate_garden_attachment(map_ctx: Dictionary, house_id: String, direction: String, piece_registry: Dictionary) -> Result:
	return _garden_attachment_validator.validate_garden_attachment(
		map_ctx,
		house_id,
		direction,
		piece_registry,
		{}
	)

func _get_piece_registry() -> Dictionary:
	if _piece_registry.is_empty():
		const PieceDefClass = preload("res://core/map/piece_def.gd")
		_piece_registry = PieceDefClass.create_default_registry()
	return _piece_registry

static func _rotation_for_garden_direction(direction: String) -> int:
	match str(direction).strip_edges():
		"E":
			return 0
		"S":
			return 90
		"W":
			return 180
		"N":
			return 270
	return 0

static func _compute_anchor_for_merged_cells(merged_cells: Array, rotation: int) -> Result:
	if rotation != 0 and rotation != 90 and rotation != 180 and rotation != 270:
		return Result.failure("add_garden: rotation 非法: %s" % str(rotation))

	var min_x := 2147483647
	var min_y := 2147483647
	var max_x := -2147483648
	var max_y := -2147483648
	var any := false
	for p_val in merged_cells:
		if not (p_val is Vector2i):
			return Result.failure("add_garden: merged_cells 元素类型错误（期望 Vector2i）")
		var p: Vector2i = p_val
		any = true
		min_x = min(min_x, p.x)
		min_y = min(min_y, p.y)
		max_x = max(max_x, p.x)
		max_y = max(max_y, p.y)
	if not any:
		return Result.failure("add_garden: merged_cells 为空")

	# PieceDef.create_house_with_garden() uses anchor at local (0,0). After rotation:
	# - 0: anchor at top-left; 90: top-right; 180: bottom-right; 270: bottom-left (of merged bounds).
	match rotation:
		0:
			return Result.success(Vector2i(min_x, min_y))
		90:
			return Result.success(Vector2i(max_x, min_y))
		180:
			return Result.success(Vector2i(max_x, max_y))
		270:
			return Result.success(Vector2i(min_x, max_y))
	return Result.failure("add_garden: rotation 非法: %s" % str(rotation))

static func _get_garden_supply_remaining(state_map: Dictionary) -> int:
	if state_map == null or not (state_map is Dictionary):
		return int(DEFAULT_GARDEN_SUPPLY)

	var v = state_map.get(GARDEN_SUPPLY_KEY, null)
	if v is int:
		return int(v)
	if v is float:
		var f: float = float(v)
		if f == floor(f):
			return int(f)
	return int(DEFAULT_GARDEN_SUPPLY)
