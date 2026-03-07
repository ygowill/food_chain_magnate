# 解雇动作（M3 起步）
# 将员工从玩家公司移除并归还到供应池。
class_name FireAction
extends ActionExecutor

const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const MilestoneEffectQueriesClass = preload("res://core/rules/milestone_effect_queries.gd")
const PlayerStateAccessClass = preload("res://core/state/player_state_access.gd")
const RoundStateCountersClass = preload("res://core/utils/round_state_counters.gd")
const SalaryTokenPaymentClass = preload("res://modules/base_rules/rules/phase/payday/payday_salary_token_payment.gd")

func _init() -> void:
	action_id = "fire"
	display_name = "解雇"
	description = "将员工从公司移除并归还到员工池"
	requires_actor = true
	is_mandatory = false
	allowed_phases = [DefsClass.PHASE_PAYDAY]

func _validate_specific(state: GameState, command: Command) -> Result:
	var current_player_id := state.get_current_player_id()
	if command.actor != current_player_id:
		return Result.failure("不是你的回合")

	var employee_id_result := require_string_param(command, "employee_id")
	if not employee_id_result.ok:
		return employee_id_result
	var employee_id: String = employee_id_result.value
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
	if location.is_empty():
		location = _find_employee_location(player, employee_id)
	if location.is_empty():
		return Result.failure("员工不存在: %s" % employee_id)
	if location != "active" and location != "reserve" and location != "busy":
		return Result.failure("未知 location: %s" % location)

	# Payday 规则：通常忙碌营销员不能解雇；特殊例外（对齐 rules.md）见 _can_fire_busy_marketer。
	if state.phase == DefsClass.PHASE_PAYDAY and location == "busy":
		if not _can_fire_busy_marketer(state, command.actor, employee_id):
			return Result.failure("通常忙碌的营销员不能解雇")

	return Result.success({
		"employee_id": employee_id,
		"location": location
	})

func _apply_changes(state: GameState, command: Command) -> Result:
	var player_id: int = command.actor
	var employee_id_result := require_string_param(command, "employee_id")
	if not employee_id_result.ok:
		return employee_id_result
	var employee_id: String = employee_id_result.value
	var player := state.get_player(player_id)

	var location := ""
	if command.params.has("location"):
		var location_result := require_string_param(command, "location")
		if not location_result.ok:
			return location_result
		location = location_result.value
	if location.is_empty():
		location = _find_employee_location(player, employee_id)
	if location.is_empty():
		return Result.failure("员工不存在: %s" % employee_id)

	var key := _location_to_key(location)
	if key.is_empty():
		return Result.failure("未知 location: %s" % location)

	var removed := StateUpdater.remove_from_array(state.players[player_id], key, employee_id)
	if not removed:
		return Result.failure("员工不在 %s: %s" % [location, employee_id])

	StateUpdater.return_to_pool(state, employee_id, 1)

	return Result.success({
		"player_id": player_id,
		"employee_id": employee_id,
		"location": location
	})

func _generate_specific_events(old_state: GameState, _new_state: GameState, command: Command) -> Array[Dictionary]:
	var employee_id_result := require_string_param(command, "employee_id")
	assert(employee_id_result.ok, "fire 缺少/错误参数: employee_id")
	var employee_id: String = employee_id_result.value

	var location := ""
	if command.params.has("location"):
		var location_result := require_string_param(command, "location")
		assert(location_result.ok, "fire 参数 location 类型错误")
		location = location_result.value
	if location.is_empty():
		location = _find_employee_location(old_state.get_player(command.actor), employee_id)
	assert(not location.is_empty(), "fire 无法推断 location: %s" % employee_id)

	return [{
		"type": EventBus.EventType.EMPLOYEE_FIRED,
		"data": {
			"player_id": command.actor,
			"employee_id": employee_id,
			"location": location
		}
	}]

func _find_employee_location(player: Dictionary, employee_id: String) -> String:
	var active_read := PlayerStateAccessClass.require_employees(player, "player", "fire")
	assert(active_read.ok, active_read.error)
	var active: Array = active_read.value
	for i in range(active.size()):
		assert(active[i] is String, "fire: player.employees[%d] 类型错误（期望 String）" % i)
	if active.find(employee_id) >= 0:
		return "active"
	var reserve_read := PlayerStateAccessClass.require_reserve_employees(player, "player", "fire")
	assert(reserve_read.ok, reserve_read.error)
	var reserve: Array = reserve_read.value
	for i in range(reserve.size()):
		assert(reserve[i] is String, "fire: player.reserve_employees[%d] 类型错误（期望 String）" % i)
	if reserve.find(employee_id) >= 0:
		return "reserve"
	var busy_read := PlayerStateAccessClass.require_busy_marketers(player, "player", "fire")
	assert(busy_read.ok, busy_read.error)
	var busy: Array = busy_read.value
	for i in range(busy.size()):
		assert(busy[i] is String, "fire: player.busy_marketers[%d] 类型错误（期望 String）" % i)
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

func _can_fire_busy_marketer(state: GameState, player_id: int, employee_id: String) -> bool:
	var player := state.get_player(player_id)
	if player.is_empty():
		return false

	var busy_read := PlayerStateAccessClass.require_busy_marketers(player, "player", "FireAction._can_fire_busy_marketer")
	if not busy_read.ok:
		return false
	var busy: Array = busy_read.value
	for i in range(busy.size()):
		assert(busy[i] is String, "fire: player.busy_marketers[%d] 类型错误（期望 String）" % i)
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
		assert(active[i] is String, "fire: player.employees[%d] 类型错误（期望 String）" % i)
		var emp_id: String = active[i]
		assert(not emp_id.is_empty(), "fire: player.employees[%d] 不应为空字符串" % i)
		if EmployeeRulesClass.requires_salary(emp_id, player):
			return false

	var reserve_read := PlayerStateAccessClass.require_reserve_employees(player, "player", "FireAction._can_fire_busy_marketer")
	if not reserve_read.ok:
		return false
	var reserve: Array = reserve_read.value
	for i in range(reserve.size()):
		assert(reserve[i] is String, "fire: player.reserve_employees[%d] 类型错误（期望 String）" % i)
		var emp_id2: String = reserve[i]
		assert(not emp_id2.is_empty(), "fire: player.reserve_employees[%d] 不应为空字符串" % i)
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

	var used_recruit := 0
	if state.round_state is Dictionary:
		var used_recruit_read := RoundStateCountersClass.get_player_count(state.round_state, "recruit_used", player_id)
		if not used_recruit_read.ok:
			return false
		used_recruit = int(used_recruit_read.value)

	var discount_info := _collect_payday_salary_discount_capacity_from_active(player)
	var discount_recruit_capacity: int = int(discount_info.get("total", 0))
	var total_recruit_capacity: int = EmployeeRulesClass.get_recruit_limit(player)
	var non_discount_recruit_capacity: int = total_recruit_capacity - discount_recruit_capacity
	if non_discount_recruit_capacity < 0:
		non_discount_recruit_capacity = 0
	var used_from_discount: int = maxi(0, used_recruit - non_discount_recruit_capacity)
	used_from_discount = mini(used_from_discount, discount_recruit_capacity)
	var unused_discount_actions: int = maxi(0, discount_recruit_capacity - used_from_discount)
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

static func _collect_payday_salary_discount_capacity_from_active(player: Dictionary) -> Dictionary:
	# 等价于 PaydaySalaryDiscount.get_salary_discount_recruit_capacity（但这里不依赖 EffectRegistry，避免在 Action 中持有 phase_manager）。
	var emp_val = player.get("employees", null)
	if not (emp_val is Array):
		return {"total": 0, "sources": {}}
	var employees: Array = emp_val

	var sources: Dictionary = {}
	var total := 0
	for v in employees:
		if not (v is String):
			continue
		var emp_id: String = str(v)
		if emp_id.is_empty():
			continue
		var def_val = EmployeeRegistryClass.get_def(emp_id)
		if def_val == null or not (def_val is EmployeeDef):
			continue
		var def: EmployeeDef = def_val

		var has_discount := false
		for eff_id in def.effect_ids:
			var s: String = str(eff_id)
			if s.find(":payday:salary_discount:") >= 0:
				has_discount = true
				break
		if not has_discount:
			continue

		var cap := int(def.recruit_capacity)
		if cap <= 0:
			continue
		total += cap
		sources[emp_id] = int(sources.get(emp_id, 0)) + cap

	return {"total": total, "sources": sources}
