# InitiateMarketingAction 应用逻辑（抽离自 gameplay/actions/initiate_marketing_action.gd）
extends RefCounted

const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const MarketingRulesClass = preload("res://core/rules/marketing_rules.gd")
const MarketingInitiationRegistryClass = preload("res://core/rules/marketing_initiation_registry.gd")
const MilestoneRegistryClass = preload("res://core/data/milestone_registry.gd")
const MilestoneDefClass = preload("res://core/data/milestone_def.gd")
const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")
const EmployeeUsageHelperClass = preload("res://gameplay/actions/employee_usage_helper.gd")
const CoordsClass = preload("res://core/map/map_runtime/coords.gd")
const RoundStateCountersClass = preload("res://core/utils/round_state_counters.gd")
const MapStateAccessClass = preload("res://core/state/map_state_access.gd")

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

	var rotation_result := action.optional_int_param(command, "rotation", 0)
	if not rotation_result.ok:
		return rotation_result
	var rotation: int = int(rotation_result.value)
	var rotation_read := MarketingRulesClass.require_rotation(rotation)
	if not rotation_read.ok:
		return rotation_read

	var board_spec_read := MarketingRulesClass.require_board_spec(state, board_number)
	if not board_spec_read.ok:
		return board_spec_read
	var board_spec: Dictionary = board_spec_read.value
	var marketing_type := str(board_spec.get("marketing_type", ""))
	# Airplane rotation has no meaning; orientation is determined by the attached edge (issue_tracker #40).
	if marketing_type == "airplane":
		rotation = 0

	var footprint_size: Vector2i = board_spec.get("footprint_size", Vector2i.ONE)

	var employee_read := MarketingRulesClass.require_marketing_employee(employee_type, marketing_type)
	if not employee_read.ok:
		return employee_read
	var employee_meta: Dictionary = employee_read.value
	var emp_def = employee_meta.get("definition", null)
	var max_duration := int(employee_meta.get("max_duration", 0))
	var duration_read := MarketingRulesClass.require_marketing_duration(action, command, max_duration)
	if not duration_read.ok:
		return duration_read
	var duration: int = int(duration_read.value)

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
	var mult := maxi(1, EmployeeRulesClass.get_working_employee_multiplier(state, player_id, employee_type))

	var consume_active := true
	var link_id := ""
	if mult > 1:
		link_id = _choose_reusable_marketing_link_id_this_round(state, player_id, employee_type, mult)
		if not link_id.is_empty():
			consume_active = false
		else:
			# 新建一组“同一张营销员卡”的 link_id（用于到期释放判定；避免多个活动提前释放营销员）。
			link_id = "working_multiplier:marketing:%d:%d:%s:%d" % [state.round_number, player_id, employee_type, board_number]

	if consume_active:
		var removed := StateUpdater.remove_from_array(state.players[player_id], "employees", employee_type)
		if not removed:
			return Result.failure("你没有激活的 %s" % employee_type)
		StateUpdater.append_to_array(state.players[player_id], "busy_marketers", employee_type)
	else:
		# 使用“本回合刚变忙碌”的营销员的额外次数（例如夜班经理带来的第二次工作）。
		var busy_val = state.players[player_id].get("busy_marketers", [])
		var busy_now: Array = busy_val if busy_val is Array else []
		if not busy_now.has(employee_type):
			return Result.failure("该营销员不在忙碌区，无法追加发起营销: %s" % employee_type)

	var inc_result := RoundStateCountersClass.increment_player_key_count(
		state.round_state, "marketing_used", player_id, employee_type, 1
	)
	if not inc_result.ok:
		return inc_result
	var warnings: Array[String] = []

	# 使用员工：用于“first_marketeer_used”等里程碑
	EmployeeUsageHelperClass.append_use_employee_warning(warnings, state, player_id, employee_type)

	# 飞机轴与 tile 索引
	var axis := ""
	var tile_index := -1
	if marketing_type == "airplane":
		var axis_read := MarketingRulesClass.require_airplane_axis(
			action,
			command,
			_infer_airplane_axis(state, world_pos, Vector2i.ONE)
		)
		if not axis_read.ok:
			return axis_read
		axis = axis_read.value
		# Keep a stable index for debugging/replays. Semantics: start row/col index (cell-level, not tile-level).
		var idx := CoordsClass.world_to_index(state, world_pos)
		tile_index = idx.y if axis == "row" else idx.x

	# 创建营销实例（按 board_number 唯一）
	var instance := {
		"board_number": board_number,
		"type": marketing_type,
		"owner": player_id,
		"employee_type": employee_type,
		"product": product,
		"world_pos": world_pos,
		"rotation": rotation,
		"footprint_size": footprint_size,
		"remaining_duration": effective_duration,
		"axis": axis,
		"tile_index": tile_index,
		"created_round": state.round_number,
	}
	if not link_id.is_empty():
		instance["link_id"] = link_id
	state.marketing_instances.append(instance)

	# 记录放置信息（供 UI/调试）
	var placements_read := MapStateAccessClass.require_marketing_placements(state, "")
	if not placements_read.ok:
		return placements_read
	var placements: Dictionary = placements_read.value
	placements[str(board_number)] = {
		"board_number": board_number,
		"type": marketing_type,
		"owner": player_id,
		"product": product,
		"world_pos": world_pos,
		"rotation": rotation,
		"footprint_size": footprint_size,
		"remaining_duration": effective_duration,
		"axis": axis,
		"tile_index": tile_index,
	}
	if not link_id.is_empty():
		placements[str(board_number)]["link_id"] = link_id
	state.map[MapStateAccessClass.KEY_MARKETING_PLACEMENTS] = placements

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
		"world_pos": world_pos,
		"rotation": rotation,
	})
	if not ms.ok:
		result.with_warning("里程碑触发失败(InitiateMarketing): %s" % ms.error)
	result.with_warnings(ext_apply.warnings)
	result.with_warnings(warnings)
	return result

static func _choose_reusable_marketing_link_id_this_round(state: GameState, player_id: int, employee_type: String, mult: int) -> String:
	if state == null:
		return ""
	if mult <= 1:
		return ""
	if not (state.marketing_instances is Array):
		return ""

	var counts_by_link: Dictionary = {}
	for inst_val in state.marketing_instances:
		if not (inst_val is Dictionary):
			continue
		var inst: Dictionary = inst_val
		if int(inst.get("owner", -1)) != player_id:
			continue
		if str(inst.get("employee_type", "")).strip_edges() != employee_type:
			continue
		if int(inst.get("created_round", -1)) != state.round_number:
			continue
		var link_id := str(inst.get("link_id", "")).strip_edges()
		if link_id.is_empty():
			continue
		counts_by_link[link_id] = int(counts_by_link.get(link_id, 0)) + 1

	var best_link := ""
	var best_used := 0
	for k in counts_by_link.keys():
		var link_id2 := str(k)
		if link_id2.is_empty():
			continue
		var used := int(counts_by_link.get(k, 0))
		if used >= mult:
			continue
		if best_link.is_empty():
			best_link = link_id2
			best_used = used
			continue
		if used < best_used or (used == best_used and link_id2 < best_link):
			best_link = link_id2
			best_used = used

	return best_link

static func _infer_airplane_axis(state: GameState, pos: Vector2i, size: Vector2i) -> String:
	# 默认：左右边缘 -> row（横飞），上下边缘 -> col（竖飞）
	# 语义：基于“整条边贴边”判断；若同时贴两条边（角落），保持旧优先级：先 row 后 col。
	var minp := CoordsClass.get_world_min(state)
	var maxp := CoordsClass.get_world_max(state)
	var left := pos.x
	var right := pos.x + size.x - 1
	var top := pos.y
	var bottom := pos.y + size.y - 1
	if left == minp.x or right == maxp.x:
		return "row"
	if top == minp.y or bottom == maxp.y:
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
