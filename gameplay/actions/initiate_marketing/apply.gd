# InitiateMarketingAction 应用逻辑（抽离自 gameplay/actions/initiate_marketing_action.gd）
extends RefCounted

const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MarketingRegistryClass = preload("res://core/data/marketing_registry.gd")
const MarketingInitiationRegistryClass = preload("res://core/rules/marketing_initiation_registry.gd")
const MilestoneRegistryClass = preload("res://core/data/milestone_registry.gd")
const MilestoneDefClass = preload("res://core/data/milestone_def.gd")
const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")
const MapRuntimeClass = preload("res://core/map/map_runtime.gd")
const RoundStateCountersClass = preload("res://core/utils/round_state_counters.gd")

static func apply(action: ActionExecutor, state: GameState, command: Command) -> Result:
	var player_id: int = command.actor
	var employee_type_result := action.require_string_param(command, "employee_type")
	if not employee_type_result.ok:
		return employee_type_result
	var employee_type: String = employee_type_result.value

	var board_number_result := action.require_int_param(command, "board_number")
	if not board_number_result.ok:
		return board_number_result
	var board_number: int = board_number_result.value

	var product_result := action.require_string_param(command, "product")
	if not product_result.ok:
		return product_result
	var product: String = product_result.value

	var world_pos_result := action.require_vector2i_param(command, "position")
	if not world_pos_result.ok:
		return world_pos_result
	var world_pos: Vector2i = world_pos_result.value

	var def = MarketingRegistryClass.get_def(board_number)
	if def == null:
		return Result.failure("未知的营销板件编号: %d" % board_number)
	var marketing_type := str(def.type)

	var emp_def = EmployeeRegistryClass.get_def(employee_type)
	if emp_def == null:
		return Result.failure("未知的员工类型: %s" % employee_type)
	var max_duration := int(emp_def.marketing_max_duration)
	var duration_result := action.optional_int_param(command, "duration", max_duration)
	if not duration_result.ok:
		return duration_result
	var duration: int = duration_result.value
	if duration <= 0:
		return Result.failure("duration 必须 > 0")
	if duration > max_duration:
		return Result.failure("持续时间超出上限: %d > %d" % [duration, max_duration])

	var effective_duration := duration
	var player := state.get_player(player_id)
	if not player.is_empty() and player.has("milestones"):
		var milestones_val = player.get("milestones", null)
		if not (milestones_val is Array):
			return Result.failure("initiate_marketing: player.milestones 类型错误（期望 Array）")
		var milestones: Array = milestones_val

		# 里程碑效果：marketing_permanent -> 之后放置的营销活动永久生效（duration=-1）
		for i in range(milestones.size()):
			var mid_val = milestones[i]
			if not (mid_val is String):
				return Result.failure("initiate_marketing: player.milestones[%d] 类型错误（期望 String）" % i)
			var mid: String = str(mid_val)
			if mid.is_empty():
				return Result.failure("initiate_marketing: player.milestones 不应包含空字符串")

			var def_val = MilestoneRegistryClass.get_def(mid)
			if def_val == null:
				return Result.failure("initiate_marketing: 未知里程碑定义: %s" % mid)
			if not (def_val is MilestoneDefClass):
				return Result.failure("initiate_marketing: 里程碑定义类型错误（期望 MilestoneDef）: %s" % mid)
			var ms_def = def_val

			for e_i in range(ms_def.effects.size()):
				var eff_val = ms_def.effects[e_i]
				if not (eff_val is Dictionary):
					return Result.failure("initiate_marketing: %s.effects[%d] 类型错误（期望 Dictionary）" % [mid, e_i])
				var eff: Dictionary = eff_val
				var type_val = eff.get("type", null)
				if not (type_val is String):
					return Result.failure("initiate_marketing: %s.effects[%d].type 类型错误（期望 String）" % [mid, e_i])
				var t: String = str(type_val)
				if t == "marketing_permanent":
					effective_duration = -1
					break

			if effective_duration == -1:
				break

	# 将营销员从在岗移到忙碌（不占卡槽）
	var removed := StateUpdater.remove_from_array(state.players[player_id], "employees", employee_type)
	if not removed:
		return Result.failure("你没有激活的 %s" % employee_type)
	StateUpdater.append_to_array(state.players[player_id], "busy_marketers", employee_type)

	var inc_result := RoundStateCountersClass.increment_player_key_count(
		state.round_state, "marketing_used", player_id, employee_type, 1
	)
	if not inc_result.ok:
		return inc_result
	var warnings: Array[String] = []

	# 使用员工：用于“first_marketeer_used”等里程碑
	var ms_use := MilestoneSystemClass.process_event(state, "UseEmployee", {"player_id": player_id, "id": employee_type})
	if not ms_use.ok:
		warnings.append("里程碑触发失败(UseEmployee/%s): %s" % [employee_type, ms_use.error])

	# 飞机轴与 tile 索引
	var axis := ""
	var tile_index := -1
	if marketing_type == "airplane":
		var axis_result := action.optional_string_param(command, "axis", "")
		if not axis_result.ok:
			return axis_result
		axis = axis_result.value
		if axis.is_empty():
			axis = _infer_airplane_axis(state, world_pos)
		if axis != "row" and axis != "col":
			return Result.failure("飞机缺少 axis（row/col）")
		var tile_pos: Vector2i = MapUtils.world_to_tile(world_pos).board_pos
		tile_index = tile_pos.y if axis == "row" else tile_pos.x

	# 创建营销实例（按 board_number 唯一）
	var instance := {
		"board_number": board_number,
		"type": marketing_type,
		"owner": player_id,
		"employee_type": employee_type,
		"product": product,
		"world_pos": world_pos,
		"remaining_duration": effective_duration,
		"axis": axis,
		"tile_index": tile_index,
		"created_round": state.round_number,
	}
	state.marketing_instances.append(instance)

	# 记录放置信息（供 UI/调试）
	if not state.map.has("marketing_placements") or not (state.map["marketing_placements"] is Dictionary):
		return Result.failure("state.map.marketing_placements 缺失或类型错误")
	state.map["marketing_placements"][str(board_number)] = {
		"board_number": board_number,
		"type": marketing_type,
		"owner": player_id,
		"product": product,
		"world_pos": world_pos,
		"remaining_duration": effective_duration,
		"axis": axis,
		"tile_index": tile_index,
	}

	var ms := MilestoneSystemClass.process_event(state, "InitiateMarketing", {
		"player_id": player_id,
		"type": marketing_type,
		"employee_type": employee_type,
		"employee_is_marketeer": _is_employee_marketeer(emp_def),
	})

	var ext_apply := MarketingInitiationRegistryClass.apply(state, command, instance)
	if not ext_apply.ok:
		return ext_apply

	var result := Result.success({
		"player_id": player_id,
		"employee_type": employee_type,
		"board_number": board_number,
		"type": marketing_type,
		"product": product,
		"duration": duration,
		"remaining_duration": effective_duration,
		"world_pos": world_pos
	})
	if not ms.ok:
		result.with_warning("里程碑触发失败(InitiateMarketing): %s" % ms.error)
	result.with_warnings(ext_apply.warnings)
	result.with_warnings(warnings)
	return result

static func _infer_airplane_axis(state: GameState, pos: Vector2i) -> String:
	# 默认：左右边缘 -> row（横飞），上下边缘 -> col（竖飞）
	var minp := MapRuntimeClass.get_world_min(state)
	var maxp := MapRuntimeClass.get_world_max(state)
	if pos.x == minp.x or pos.x == maxp.x:
		return "row"
	if pos.y == minp.y or pos.y == maxp.y:
		return "col"
	return ""

static func _is_employee_marketeer(emp_def: EmployeeDef) -> bool:
	if emp_def == null:
		return false
	if not (emp_def.usage_tags is Array):
		return false
	for t in emp_def.usage_tags:
		if t is String and str(t).begins_with("use:marketing:"):
			return true
	return false
