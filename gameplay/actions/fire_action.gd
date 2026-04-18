# 解雇动作（M3 起步）
# 将员工从玩家公司移除并归还到供应池。
class_name FireAction
extends ActionExecutor

const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const MilestoneEffectQueriesClass = preload("res://core/rules/milestone_effect_queries.gd")
const OnlinePhaseInteractionClass = preload("res://core/utils/online_phase_interaction.gd")
const PlayerStateAccessClass = preload("res://core/state/player_state_access.gd")
const SalaryDiscountUsageClass = preload("res://core/rules/employee_rules/payday_salary_discount_usage.gd")
const SalaryTokenPaymentClass = preload("res://modules/base_rules/rules/phase/payday/payday_salary_token_payment.gd")
const StaffStateClass = preload("res://core/state/staff_state.gd")

func _init() -> void:
	action_id = "fire"
	display_name = "解雇"
	description = "将员工从公司移除并归还到员工池"
	requires_actor = true
	is_mandatory = false
	allowed_phases = [DefsClass.PHASE_PAYDAY]

func _validate_specific(state: GameState, command: Command) -> Result:
	var current_player_id := state.get_current_player_id()
	if OnlinePhaseInteractionClass.is_online_parallel_payday(state):
		if command.actor < 0 or command.actor >= state.players.size():
			return Result.failure("无效玩家: %d" % command.actor)
		if OnlinePhaseInteractionClass.is_player_payday_confirmed(state, int(command.actor)):
			return Result.failure("你已经确认结束发薪日")
	elif command.actor != current_player_id:
		return Result.failure("不是你的回合")

	var employee_id_result := require_string_param(command, "employee_id")
	if not employee_id_result.ok:
		return employee_id_result
	var employee_id: String = employee_id_result.value
	var staff_id := -1
	if command.params.has("staff_id"):
		var staff_id_result := require_int_param(command, "staff_id")
		if not staff_id_result.ok:
			return staff_id_result
		staff_id = int(staff_id_result.value)
		if staff_id <= 0:
			return Result.failure("staff_id 必须 > 0，实际: %d" % staff_id)
	if not EmployeeRegistryClass.is_loaded():
		return Result.failure("EmployeeRegistry 未初始化")
	var emp_def = EmployeeRegistryClass.get_def(employee_id)
	if emp_def == null:
		return Result.failure("未知的员工类型: %s" % employee_id)
	if not (emp_def is EmployeeDef):
		return Result.failure("员工定义类型错误（期望 EmployeeDef）: %s" % employee_id)
	var def: EmployeeDef = emp_def
	if not def.can_be_fired:
		return Result.failure("该员工不可解雇: %s" % employee_id)

	var player := state.get_player(command.actor)
	var location := ""
	if command.params.has("location"):
		var location_result := require_string_param(command, "location")
		if not location_result.ok:
			return location_result
		location = location_result.value
	var candidate_read := _resolve_fire_candidate(state, command.actor, employee_id, location, staff_id)
	if not candidate_read.ok:
		return candidate_read
	var candidate: Dictionary = candidate_read.value
	location = str(candidate.get("location", "")).strip_edges()
	staff_id = int(candidate.get("staff_id", -1))

	return Result.success({
		"employee_id": employee_id,
		"location": location,
		"staff_id": staff_id,
	})

func _apply_changes(state: GameState, command: Command) -> Result:
	var player_id: int = command.actor
	var employee_id_result := require_string_param(command, "employee_id")
	if not employee_id_result.ok:
		return employee_id_result
	var employee_id: String = employee_id_result.value
	var staff_id := -1
	if command.params.has("staff_id"):
		var staff_id_result := require_int_param(command, "staff_id")
		if not staff_id_result.ok:
			return staff_id_result
		staff_id = int(staff_id_result.value)

	var location := ""
	if command.params.has("location"):
		var location_result := require_string_param(command, "location")
		if not location_result.ok:
			return location_result
		location = location_result.value
	var candidate_read := _resolve_fire_candidate(state, player_id, employee_id, location, staff_id)
	if not candidate_read.ok:
		return candidate_read
	var candidate: Dictionary = candidate_read.value
	location = str(candidate.get("location", "")).strip_edges()
	staff_id = int(candidate.get("staff_id", -1))

	var zone_key := _location_to_key(location)
	if zone_key.is_empty():
		return Result.failure("未知 location: %s" % location)

	var remove_staff := StaffStateClass.remove_staff_from_player(state, player_id, staff_id, zone_key)
	if not remove_staff.ok:
		return remove_staff
	var pool_result := StateUpdater.return_to_pool(state, employee_id, 1)
	if not pool_result.ok:
		return pool_result

	return Result.success({
		"player_id": player_id,
		"employee_id": employee_id,
		"location": location,
		"staff_id": staff_id,
	})

func _generate_specific_events(old_state: GameState, _new_state: GameState, command: Command) -> Array[Dictionary]:
	var employee_id_result := require_string_param(command, "employee_id")
	if not employee_id_result.ok:
		return []
	var employee_id: String = str(employee_id_result.value).strip_edges()
	if employee_id.is_empty():
		return []
	var staff_id := -1
	if command.params.has("staff_id"):
		var staff_id_result := require_int_param(command, "staff_id")
		if not staff_id_result.ok:
			return []
		staff_id = int(staff_id_result.value)

	var location := ""
	if command.params.has("location"):
		var location_result := require_string_param(command, "location")
		if not location_result.ok:
			return []
		location = str(location_result.value).strip_edges()
	var candidate_read := _resolve_fire_candidate(old_state, command.actor, employee_id, location, staff_id)
	if not candidate_read.ok:
		return []
	var candidate: Dictionary = candidate_read.value
	location = str(candidate.get("location", "")).strip_edges()
	staff_id = int(candidate.get("staff_id", -1))

	return [{
		"type": EventBus.EventType.EMPLOYEE_FIRED,
		"data": {
			"player_id": command.actor,
			"employee_id": employee_id,
			"location": location,
			"staff_id": staff_id,
		}
	}]

func _find_employee_location(player: Dictionary, employee_id: String) -> String:
	var active_read := PlayerStateAccessClass.require_employees(player, "player", "fire")
	if not active_read.ok:
		return ""
	var active: Array = active_read.value
	for i in range(active.size()):
		if not (active[i] is String):
			return ""
	if active.find(employee_id) >= 0:
		return "active"
	var reserve_read := PlayerStateAccessClass.require_reserve_employees(player, "player", "fire")
	if not reserve_read.ok:
		return ""
	var reserve: Array = reserve_read.value
	for i in range(reserve.size()):
		if not (reserve[i] is String):
			return ""
	if reserve.find(employee_id) >= 0:
		return "reserve"
	var busy_read := PlayerStateAccessClass.require_busy_marketers(player, "player", "fire")
	if not busy_read.ok:
		return ""
	var busy: Array = busy_read.value
	for i in range(busy.size()):
		if not (busy[i] is String):
			return ""
	if busy.find(employee_id) >= 0:
		return "busy"
	return ""

func _location_to_key(location: String) -> String:
	match location:
		"active":
			return "employees"
		"reserve":
			return "reserve_employees"
		"busy":
			return "busy_marketers"
		_:
			return ""

func _zone_key_to_location(zone_key: String) -> String:
	match zone_key:
		"employees":
			return "active"
		"reserve_employees":
			return "reserve"
		"busy_marketers":
			return "busy"
		_:
			return ""

func _get_staff_ids_for_fire(state: GameState, player_id: int, employee_id: String, zone_key: String) -> Result:
	return StaffStateClass.find_staff_ids_by_employee_type(state, player_id, employee_id, [zone_key])

func _resolve_fire_candidate(
	state: GameState,
	player_id: int,
	employee_id: String,
	location: String,
	explicit_staff_id: int = -1
) -> Result:
	if state == null:
		return Result.failure("state 为空")

	var desired_location := str(location).strip_edges()
	if not desired_location.is_empty() and _location_to_key(desired_location).is_empty():
		return Result.failure("未知 location: %s" % desired_location)

	if explicit_staff_id > 0:
		var emp_read := StaffStateClass.get_staff_employee_type(state, player_id, explicit_staff_id)
		if not emp_read.ok:
			return emp_read
		var actual_employee_id := str(emp_read.value).strip_edges()
		if actual_employee_id != employee_id:
			return Result.failure("staff_id=%d 与 employee_id=%s 不匹配（实际: %s）" % [explicit_staff_id, employee_id, actual_employee_id])
		var zone_read := StaffStateClass.get_staff_zone(state, player_id, explicit_staff_id)
		if not zone_read.ok:
			return zone_read
		var actual_zone_key := str(zone_read.value).strip_edges()
		if actual_zone_key.is_empty():
			return Result.failure("员工不存在: %s" % employee_id)
		var actual_location := _zone_key_to_location(actual_zone_key)
		if actual_location.is_empty():
			return Result.failure("未知 zone_key: %s" % actual_zone_key)
		if not desired_location.is_empty() and desired_location != actual_location:
			return Result.failure("员工不在 %s: %s" % [desired_location, employee_id])
		if state.phase == DefsClass.PHASE_PAYDAY and actual_location == "busy":
			if not _can_fire_busy_marketer(state, player_id, employee_id):
				return Result.failure("通常忙碌的营销员不能解雇")
		return Result.success({
			"employee_id": employee_id,
			"location": actual_location,
			"staff_id": explicit_staff_id,
		})

	if not desired_location.is_empty():
		var zone_key := _location_to_key(desired_location)
		var ids_read := _get_staff_ids_for_fire(state, player_id, employee_id, zone_key)
		if not ids_read.ok:
			return ids_read
		var ids: Array = ids_read.value
		if ids.is_empty():
			return Result.failure("员工不存在: %s" % employee_id)
		if state.phase == DefsClass.PHASE_PAYDAY and desired_location == "busy":
			if not _can_fire_busy_marketer(state, player_id, employee_id):
				return Result.failure("通常忙碌的营销员不能解雇")
		return Result.success({
			"employee_id": employee_id,
			"location": desired_location,
			"staff_id": int(ids[0]),
		})

	var candidates: Array[Dictionary] = []
	for zone_key in ["employees", "reserve_employees"]:
		var ids_read := _get_staff_ids_for_fire(state, player_id, employee_id, zone_key)
		if not ids_read.ok:
			return ids_read
		for staff_id_val in ids_read.value:
			candidates.append({
				"location": _zone_key_to_location(zone_key),
				"staff_id": int(staff_id_val),
			})

	var busy_ids_read := _get_staff_ids_for_fire(state, player_id, employee_id, "busy_marketers")
	if not busy_ids_read.ok:
		return busy_ids_read
	var busy_ids: Array = busy_ids_read.value
	var busy_allowed := true
	if state.phase == DefsClass.PHASE_PAYDAY and not busy_ids.is_empty():
		busy_allowed = _can_fire_busy_marketer(state, player_id, employee_id)
	if busy_allowed:
		for staff_id_val in busy_ids:
			candidates.append({
				"location": "busy",
				"staff_id": int(staff_id_val),
			})

	if candidates.is_empty():
		if not busy_ids.is_empty() and not busy_allowed:
			return Result.failure("通常忙碌的营销员不能解雇")
		return Result.failure("员工不存在: %s" % employee_id)

	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("staff_id", 0)) < int(b.get("staff_id", 0))
	)
	var chosen: Dictionary = candidates[0]
	return Result.success({
		"employee_id": employee_id,
		"location": str(chosen.get("location", "")),
		"staff_id": int(chosen.get("staff_id", -1)),
	})

func _can_fire_busy_marketer(state: GameState, player_id: int, employee_id: String) -> bool:
	var player := state.get_player(player_id)
	if player.is_empty():
		return false

	var busy_read := PlayerStateAccessClass.require_busy_marketers(player, "player", "FireAction._can_fire_busy_marketer")
	if not busy_read.ok:
		return false
	var busy: Array = busy_read.value
	for i in range(busy.size()):
		if not (busy[i] is String):
			return false
	if busy.find(employee_id) < 0:
		return false

	# 特殊例外仅适用于“需要薪水”的忙碌营销员
	if not EmployeeRulesClass.requires_salary(employee_id, player):
		return false

	# 必须已解雇所有其他需要薪水的员工（在岗/待命）
	var active_read := PlayerStateAccessClass.require_employees(player, "player", "FireAction._can_fire_busy_marketer")
	if not active_read.ok:
		return false
	var active: Array = active_read.value
	for i in range(active.size()):
		if not (active[i] is String):
			return false
		var emp_id: String = active[i]
		if emp_id.is_empty():
			return false
		if EmployeeRulesClass.requires_salary(emp_id, player):
			return false

	var reserve_read := PlayerStateAccessClass.require_reserve_employees(player, "player", "FireAction._can_fire_busy_marketer")
	if not reserve_read.ok:
		return false
	var reserve: Array = reserve_read.value
	for i in range(reserve.size()):
		if not (reserve[i] is String):
			return false
		var emp_id2: String = reserve[i]
		if emp_id2.is_empty():
			return false
		if EmployeeRulesClass.requires_salary(emp_id2, player):
			return false

	# 仍无力支付薪资时，允许解雇其中一名忙碌营销员（按 PaydaySettlement 的计算口径，含折扣/里程碑/token）。
	var cash_read := PlayerStateAccessClass.require_int_field(player, "cash", "player", "FireAction._can_fire_busy_marketer")
	if not cash_read.ok:
		return false
	var cash: int = int(cash_read.value)

	var base_salary_cost: int = state.get_rule_int("salary_cost")
	var salary_cost := base_salary_cost
	if player.has("salary_cost_override"):
		var override_val = player.get("salary_cost_override", null)
		if not (override_val is int):
			return false
		var v := int(override_val)
		if v < 0:
			return false
		salary_cost = v

	var milestones_read := PlayerStateAccessClass.require_milestones(player, "player", "FireAction._can_fire_busy_marketer: ")
	if not milestones_read.ok:
		return false
	var milestones: Array = milestones_read.value

	var delta_read := MilestoneEffectQueriesClass.sum_int_values(
		milestones,
		"salary_total_delta",
		"FireAction._can_fire_busy_marketer: ",
		"player.milestones"
	)
	if not delta_read.ok:
		return false
	var milestone_delta_amount: int = int(delta_read.value)

	var discount_usage_read := SalaryDiscountUsageClass.collect_for_player(state, player_id, player)
	if not discount_usage_read.ok:
		return false
	var discount_usage: Dictionary = discount_usage_read.value
	var unused_discount_actions: int = int(discount_usage.get("salary_discount_unused_actions", 0))
	var discount_amount: int = unused_discount_actions * base_salary_cost

	var paid_employee_count := EmployeeRulesClass.count_paid_employees(player)

	var pay_with_tokens := bool(player.get("salary_pay_with_tokens", false))
	var inventory_read := PlayerStateAccessClass.require_inventory(player, "player", "FireAction._can_fire_busy_marketer: ")
	if not inventory_read.ok:
		return false
	var inventory: Dictionary = inventory_read.value

	var tokens_available := 0
	if pay_with_tokens:
		tokens_available = SalaryTokenPaymentClass.count_food_drink_tokens(inventory)

	var tokens_used := 0
	if pay_with_tokens and tokens_available > 0 and paid_employee_count > 0:
		var need := SalaryTokenPaymentClass.compute_min_tokens_needed(
			paid_employee_count, salary_cost, milestone_delta_amount, discount_amount, cash
		)
		tokens_used = mini(tokens_available, need)

	var due_cash_amount := maxi(0, (paid_employee_count - tokens_used) * salary_cost + milestone_delta_amount - discount_amount)
	return cash < due_cash_amount
