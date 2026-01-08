# 发起营销动作（Working 子阶段：Marketing）
# 放置营销板件并将营销员置为忙碌，创建营销实例，待 Marketing 阶段统一结算产生需求。
class_name InitiateMarketingAction
extends ActionExecutor

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MarketingRegistryClass = preload("res://core/data/marketing_registry.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")
const MapRuntimeClass = preload("res://core/map/map_runtime.gd")

const ValidationClass = preload("res://gameplay/actions/initiate_marketing/validation.gd")
const ApplyClass = preload("res://gameplay/actions/initiate_marketing/apply.gd")

func _init() -> void:
	action_id = "initiate_marketing"
	display_name = "发起营销"
	description = "放置营销板件并创建营销活动"
	requires_actor = true
	is_mandatory = false
	allowed_phases = ["Working"]
	allowed_sub_phases = ["Marketing"]

func can_initiate(state: GameState, player_id: int) -> bool:
	if state == null:
		return true
	if state.get_current_player_id() != player_id:
		return false

	var player := state.get_player(player_id)
	var employees_val = player.get("employees", [])
	if not (employees_val is Array):
		return true
	var employees: Array = employees_val

	var has_marketer := false
	var seen := {}
	for emp_val in employees:
		if not (emp_val is String):
			continue
		var emp_id: String = str(emp_val)
		if emp_id.is_empty():
			continue
		if seen.has(emp_id):
			continue
		seen[emp_id] = true

		var def_val = EmployeeRegistryClass.get_def(emp_id)
		if def_val == null or not (def_val is EmployeeDef):
			continue
		var def: EmployeeDef = def_val
		for t in def.usage_tags:
			var s: String = str(t)
			if s.begins_with("use:marketing:"):
				has_marketer = true
				break
		if has_marketer:
			break

	if not has_marketer:
		return false

	var used := {}
	for inst_val in state.marketing_instances:
		if inst_val is Dictionary:
			var bn = Dictionary(inst_val).get("board_number", null)
			if bn is int:
				used[str(int(bn))] = true
	if state.map is Dictionary and state.map.has("marketing_placements") and (state.map["marketing_placements"] is Dictionary):
		var placements: Dictionary = state.map["marketing_placements"]
		for k in placements.keys():
			used[str(k)] = true

	var player_count := state.players.size()
	for bn2 in MarketingRegistryClass.get_all_board_numbers():
		if used.has(str(bn2)):
			continue
		var def2 = MarketingRegistryClass.get_def(bn2)
		if def2 == null or not def2.has_method("is_available_for_player_count"):
			continue
		if not def2.is_available_for_player_count(player_count):
			continue
		return true

	return false

func _validate_specific(state: GameState, command: Command) -> Result:
	return ValidationClass.validate(self, state, command)

func _apply_changes(state: GameState, command: Command) -> Result:
	return ApplyClass.apply(self, state, command)

func _is_employee_marketeer(emp_def: EmployeeDef) -> bool:
	if emp_def == null:
		return false
	if not (emp_def.usage_tags is Array):
		return false
	for t in emp_def.usage_tags:
		if t is String and str(t).begins_with("use:marketing:"):
			return true
	return false

func _generate_specific_events(_old_state: GameState, _new_state: GameState, command: Command) -> Array[Dictionary]:
	var employee_type_result := require_string_param(command, "employee_type")
	assert(employee_type_result.ok, "initiate_marketing 缺少/错误参数: employee_type")
	var employee_type: String = employee_type_result.value

	var board_number_result := require_int_param(command, "board_number")
	assert(board_number_result.ok, "initiate_marketing 缺少/错误参数: board_number")
	var board_number: int = board_number_result.value

	var product_result := require_string_param(command, "product")
	assert(product_result.ok, "initiate_marketing 缺少/错误参数: product")
	var product: String = product_result.value
	assert(ProductRegistryClass.has(product), "initiate_marketing 未知的产品: %s" % product)

	var world_pos_result := require_vector2i_param(command, "position")
	assert(world_pos_result.ok, "initiate_marketing 缺少/错误参数: position")
	var world_pos: Vector2i = world_pos_result.value
	var p := [world_pos.x, world_pos.y]

	var def = MarketingRegistryClass.get_def(board_number)
	assert(def != null, "initiate_marketing 未知的营销板件编号: %d" % board_number)
	var marketing_type := str(def.type)

	var emp_def = EmployeeRegistryClass.get_def(employee_type)
	assert(emp_def != null, "initiate_marketing 未知的员工类型: %s" % employee_type)
	var max_duration: int = int(emp_def.marketing_max_duration)
	assert(max_duration > 0, "initiate_marketing 该员工无法发起营销")

	var duration_result := optional_int_param(command, "duration", max_duration)
	assert(duration_result.ok, "initiate_marketing 参数 duration 类型错误")
	var duration: int = duration_result.value
	assert(duration > 0, "initiate_marketing duration 必须 > 0")
	assert(duration <= max_duration, "initiate_marketing 持续时间超出上限: %d > %d" % [duration, max_duration])

	var axis := ""
	if marketing_type == "airplane":
		var axis_result := optional_string_param(command, "axis", "")
		assert(axis_result.ok, "initiate_marketing 参数 axis 类型错误")
		axis = axis_result.value
		if axis.is_empty():
			axis = _infer_airplane_axis(_new_state, world_pos)
		assert(axis == "row" or axis == "col", "initiate_marketing 飞机缺少 axis（row/col）")

	return [{
		"type": EventBus.EventType.MARKETING_PLACED,
		"data": {
			"player_id": command.actor,
			"employee_type": employee_type,
			"board_number": board_number,
			"product": product,
			"duration": duration,
			"axis": axis,
			"position": p,
		}
	}]

# === 内部：放置/距离校验 ===

func _infer_airplane_axis(state: GameState, pos: Vector2i) -> String:
	# 默认：左右边缘 -> row（横飞），上下边缘 -> col（竖飞）
	var minp := MapRuntimeClass.get_world_min(state)
	var maxp := MapRuntimeClass.get_world_max(state)
	if pos.x == minp.x or pos.x == maxp.x:
		return "row"
	if pos.y == minp.y or pos.y == maxp.y:
		return "col"
	return ""

func _require_world_pos(command: Command) -> Result:
	return require_vector2i_param(command, "position")
