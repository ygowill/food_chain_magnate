# 发起营销动作（Working 子阶段：Marketing）
# 放置营销板件并将营销员置为忙碌，创建营销实例，待 Marketing 阶段统一结算产生需求。
class_name InitiateMarketingAction
extends ActionExecutor

const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MarketingRegistryClass = preload("res://core/data/marketing_registry.gd")
const CoordsClass = preload("res://core/map/map_runtime/coords.gd")
const MarketingRulesClass = preload("res://core/rules/marketing_rules.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const PlayerStateAccessClass = preload("res://core/state/player_state_access.gd")
const MapStateAccessClass = preload("res://core/state/map_state_access.gd")

const ValidationClass = preload("res://gameplay/actions/initiate_marketing/validation.gd")
const ApplyClass = preload("res://gameplay/actions/initiate_marketing/apply.gd")

func _init() -> void:
	action_id = "initiate_marketing"
	display_name = "发起营销"
	description = "放置营销板件并创建营销活动"
	requires_actor = true
	is_mandatory = false
	allowed_phases = [DefsClass.PHASE_WORKING]
	allowed_sub_phases = [DefsClass.SUB_PHASE_MARKETING]

func can_initiate(state: GameState, player_id: int) -> bool:
	if state == null:
		return true
	if state.get_current_player_id() != player_id:
		return false

	var player := state.get_player(player_id)
	var employees_read := PlayerStateAccessClass.require_employees(player, "player[%d]" % player_id, action_id)
	if not employees_read.ok:
		return true
	var employees: Array = employees_read.value

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
		# 扩展：某些模块允许“本回合刚变忙碌”的营销员额外发起营销（例如夜班经理）。
		has_marketer = _has_reusable_busy_marketer_for_working(state, player_id)
	if not has_marketer:
		return false

	var used := {}
	for inst_val in state.marketing_instances:
		if inst_val is Dictionary:
			var bn = Dictionary(inst_val).get("board_number", null)
			if bn is int:
				used[str(int(bn))] = true
	var placements_read := MapStateAccessClass.require_marketing_placements(state, action_id)
	if placements_read.ok:
		var placements: Dictionary = placements_read.value
		for k in placements.keys():
			used[str(k)] = true

	for bn2 in MarketingRegistryClass.get_all_board_numbers():
		if used.has(str(bn2)):
			continue
		var board_spec_read := MarketingRulesClass.require_board_spec(state, bn2)
		if not board_spec_read.ok:
			continue
		return true

	return false

func _has_reusable_busy_marketer_for_working(state: GameState, player_id: int) -> bool:
	if state == null:
		return false
	if not (state.marketing_instances is Array):
		return false
	var player := state.get_player(player_id)
	if player.is_empty():
		return false

	var busy_read := PlayerStateAccessClass.require_busy_marketers(player, "player[%d]" % player_id, action_id)
	if not busy_read.ok:
		return false
	var busy: Array = busy_read.value
	if busy.is_empty():
		return false

	var counts_by_link: Dictionary = {}  # link_id -> {employee_type, count}
	for inst_val in state.marketing_instances:
		if not (inst_val is Dictionary):
			continue
		var inst: Dictionary = inst_val
		if int(inst.get("owner", -1)) != player_id:
			continue
		if int(inst.get("created_round", -1)) != state.round_number:
			continue
		var employee_type := str(inst.get("employee_type", "")).strip_edges()
		if employee_type.is_empty():
			continue
		var link_id := str(inst.get("link_id", "")).strip_edges()
		if link_id.is_empty():
			continue
		if not counts_by_link.has(link_id):
			counts_by_link[link_id] = {"employee_type": employee_type, "count": 0}
		var meta: Dictionary = counts_by_link[link_id]
		meta["count"] = int(meta.get("count", 0)) + 1
		counts_by_link[link_id] = meta

	for lid in counts_by_link.keys():
		var meta2_val = counts_by_link.get(lid, null)
		if not (meta2_val is Dictionary):
			continue
		var meta2: Dictionary = meta2_val
		var employee_type2 := str(meta2.get("employee_type", "")).strip_edges()
		if employee_type2.is_empty():
			continue
		if not busy.has(employee_type2):
			continue
		var used := int(meta2.get("count", 0))
		var mult := maxi(1, EmployeeRulesClass.get_working_employee_multiplier(state, player_id, employee_type2))
		if used < mult:
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
	var events: Array[Dictionary] = []
	var employee_type_result := require_string_param(command, "employee_type")
	if not employee_type_result.ok:
		return events
	var employee_type: String = str(employee_type_result.value).strip_edges()
	if employee_type.is_empty():
		return events
	var staff_id := -1
	if command.params.has("staff_id"):
		var staff_id_result := require_int_param(command, "staff_id")
		if staff_id_result.ok:
			staff_id = int(staff_id_result.value)
	if _old_state != null:
		var provider_read := EmployeeRulesClass.try_resolve_marketer(_old_state, command.actor, employee_type, staff_id)
		if provider_read.ok and provider_read.value is Dictionary:
			staff_id = int(Dictionary(provider_read.value).get("staff_id", staff_id))

	var board_number_result := require_int_param(command, "board_number")
	if not board_number_result.ok:
		return events
	var board_number: int = int(board_number_result.value)

	var product_result := require_string_param(command, "product")
	if not product_result.ok:
		return events
	var product: String = str(product_result.value).strip_edges()
	var product_read := MarketingRulesClass.require_marketable_product(product)
	if not product_read.ok:
		return events

	var world_pos_result := require_vector2i_param(command, "position")
	if not world_pos_result.ok:
		return events
	var world_pos: Vector2i = world_pos_result.value
	var p := [world_pos.x, world_pos.y]

	var board_spec_read := MarketingRulesClass.require_board_spec(_new_state, board_number)
	if not board_spec_read.ok:
		return events
	var board_spec: Dictionary = board_spec_read.value
	var marketing_type := str(board_spec.get("marketing_type", "")).strip_edges()
	if marketing_type.is_empty():
		return events

	var employee_read := MarketingRulesClass.require_marketing_employee(employee_type, marketing_type)
	if not employee_read.ok:
		return events
	var employee_meta: Dictionary = employee_read.value
	var max_duration: int = int(employee_meta.get("max_duration", 0))

	var duration_read := MarketingRulesClass.require_marketing_duration(self, command, max_duration)
	if not duration_read.ok:
		return events
	var duration: int = int(duration_read.value)

	var axis := ""
	if marketing_type == "airplane":
		var axis_read := MarketingRulesClass.require_airplane_axis(self, command, _infer_airplane_axis(_new_state, world_pos))
		if not axis_read.ok:
			return events
		axis = axis_read.value

	# 真实持续时间：可能被里程碑效果改为永久（remaining_duration=-1）。
	var remaining_duration := duration
	if _new_state != null and (_new_state.marketing_instances is Array):
		for inst_val in _new_state.marketing_instances:
			if not (inst_val is Dictionary):
				continue
			var inst: Dictionary = inst_val
			if int(inst.get("board_number", 0)) != board_number:
				continue
			var rd_val = inst.get("remaining_duration", null)
			if rd_val is int:
				remaining_duration = int(rd_val)
			elif rd_val is float:
				var f: float = float(rd_val)
				if f == floor(f):
					remaining_duration = int(f)
			break

	events.append({
		"type": EventBus.EventType.MARKETING_PLACED,
		"data": {
			"player_id": command.actor,
			"employee_type": employee_type,
			"board_number": board_number,
			"marketing_type": marketing_type,
			"product": product,
			"duration": duration,
			"remaining_duration": remaining_duration,
			"axis": axis,
			"position": p,
		}
	})
	if staff_id > 0:
		var data: Dictionary = events[0].get("data", {})
		data["staff_id"] = staff_id
		events[0]["data"] = data
	return events

# === 内部：放置/距离校验 ===

func _infer_airplane_axis(state: GameState, pos: Vector2i) -> String:
	# 默认：左右边缘 -> row（横飞），上下边缘 -> col（竖飞）
	var minp := CoordsClass.get_world_min(state)
	var maxp := CoordsClass.get_world_max(state)
	if pos.x == minp.x or pos.x == maxp.x:
		return "row"
	if pos.y == minp.y or pos.y == maxp.y:
		return "col"
	return ""

func _require_world_pos(command: Command) -> Result:
	return require_vector2i_param(command, "position")
