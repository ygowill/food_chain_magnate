# Payday 结算（从 PhaseManager 抽离）
# 目标：聚合 Payday 阶段“发薪/折扣/里程碑修正/round_state.payday 记录”逻辑，便于测试与复用。
class_name PaydaySettlement
extends RefCounted

const StateUpdaterClass = preload("res://core/state/state_updater.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MilestoneRegistryClass = preload("res://core/data/milestone_registry.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")
const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")

const EFFECT_SEG_PAYDAY_SALARY_DISCOUNT := ":payday:salary_discount:"

static func apply(state: GameState, phase_manager = null) -> Result:
	if state == null:
		return Result.failure("PaydaySettlement: state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("PaydaySettlement: state.round_state 类型错误（期望 Dictionary）")
	if not (state.players is Array):
		return Result.failure("PaydaySettlement: state.players 类型错误（期望 Array）")

	var base_salary_cost: int = state.get_rule_int("salary_cost")
	var effect_registry = null
	if phase_manager != null and phase_manager.has_method("get_effect_registry"):
		effect_registry = phase_manager.get_effect_registry()
	if effect_registry == null:
		return Result.failure("PaydaySettlement: EffectRegistry 未设置")

	var base_due: Array[int] = []
	var discount: Array[int] = []
	var milestone_delta: Array[int] = []
	var due: Array[int] = []
	var paid: Array[int] = []
	var unpaid: Array[int] = []
	var details: Array[Dictionary] = []
	var warnings: Array[String] = []

	# 记录在 Recruit 子阶段累计的招聘次数（用于薪资折扣推导）
	var recruit_used: Dictionary = {}
	if state.round_state.has("recruit_used"):
		if not (state.round_state["recruit_used"] is Dictionary):
			return Result.failure("PaydaySettlement: round_state.recruit_used 类型错误（期望 Dictionary）")
		recruit_used = state.round_state["recruit_used"]

	for i in range(state.players.size()):
		assert(not recruit_used.has(str(i)), "round_state.recruit_used 不应包含字符串玩家 key: %s" % str(i))
		var player_val = state.players[i]
		if not (player_val is Dictionary):
			return Result.failure("PaydaySettlement: players[%d] 类型错误（期望 Dictionary）" % i)
		var player: Dictionary = player_val

		var paid_employee_count := EmployeeRulesClass.count_paid_employees(player)
		# FIRST WAITRESS USED：薪水变为每人 $3（仅影响持有者）
		var salary_cost := base_salary_cost
		if player.has("salary_cost_override"):
			var override_val = player.get("salary_cost_override", null)
			if not (override_val is int):
				return Result.failure("PaydaySettlement: player[%d].salary_cost_override 类型错误（期望 int）" % i)
			var v := int(override_val)
			if v < 0:
				return Result.failure("PaydaySettlement: player[%d].salary_cost_override 不能为负数: %d" % [i, v])
			salary_cost = v

		var base_due_amount: int = paid_employee_count * salary_cost

		# 折扣：招聘经理/HR 总监未使用的招聘次数（每次 $5，强制使用）
		var used_recruit := 0
		if recruit_used.has(i):
			if not (recruit_used[i] is int):
				return Result.failure("PaydaySettlement: round_state.recruit_used[%d] 类型错误（期望 int）" % i)
			used_recruit = int(recruit_used[i])

		var cap_read := _get_salary_discount_recruit_capacity(state, i, player, effect_registry)
		if not cap_read.ok:
			return cap_read
		warnings.append_array(cap_read.warnings)
		var discount_recruit_capacity: int = int(cap_read.value)
		var total_recruit_capacity: int = EmployeeRulesClass.get_recruit_limit(player)
		var non_discount_recruit_capacity: int = total_recruit_capacity - discount_recruit_capacity
		if non_discount_recruit_capacity < 0:
			return Result.failure("PaydaySettlement: 招聘次数计算不一致：total=%d < discount=%d" % [total_recruit_capacity, discount_recruit_capacity])

		var used_from_discount: int = maxi(0, used_recruit - non_discount_recruit_capacity)
		used_from_discount = mini(used_from_discount, discount_recruit_capacity)
		var unused_discount_actions: int = maxi(0, discount_recruit_capacity - used_from_discount)
		# 注：即使薪水变为 $3，recruiting_manager/hr_director 的折扣仍为每次 $5（更高效）
		var discount_amount: int = unused_discount_actions * base_salary_cost

		# 里程碑：首个培训员工（总薪资永久 -$15）
		var delta_read := _get_salary_total_delta(state, player)
		if not delta_read.ok:
			return delta_read
		var milestone_delta_amount: int = int(delta_read.value)

		# 最低支付额为 $0
		var due_amount: int = maxi(0, base_due_amount + milestone_delta_amount - discount_amount)

		if not player.has("cash") or not (player["cash"] is int):
			return Result.failure("PaydaySettlement: player[%d].cash 缺失或类型错误（期望 int）" % i)
		var cash_before: int = int(player["cash"])
		var pay_with_tokens := bool(player.get("salary_pay_with_tokens", false))
		var allow_unpaid := bool(player.get("salary_allow_unpaid", false))

		var inventory: Dictionary = {}
		if player.has("inventory") and (player["inventory"] is Dictionary):
			inventory = player["inventory"]
		else:
			# 容错：测试/旧存档可能缺失 inventory；视为无 token。
			warnings.append("PaydaySettlement: player[%d].inventory 缺失或类型错误（期望 Dictionary），已视为 {}" % i)
			player["inventory"] = {}
			state.players[i] = player
			inventory = player["inventory"]

		var tokens_available := 0
		if pay_with_tokens:
			tokens_available = _count_food_drink_tokens(inventory)

		var tokens_used := 0
		if pay_with_tokens and tokens_available > 0 and paid_employee_count > 0:
			var need := _compute_min_tokens_needed(
				paid_employee_count, salary_cost, milestone_delta_amount, discount_amount, cash_before
			)
			tokens_used = mini(tokens_available, need)

		var due_cash_amount := maxi(0, (paid_employee_count - tokens_used) * salary_cost + milestone_delta_amount - discount_amount)

		var pay_amount: int = mini(cash_before, due_cash_amount)
		if pay_amount > 0:
			var pay_result := StateUpdaterClass.player_pay_to_bank(state, i, pay_amount)
			if not pay_result.ok:
				return Result.failure("发薪失败: 玩家 %d: %s" % [i, pay_result.error])

		var token_payment: Dictionary = {}
		if tokens_used > 0:
			var token_pay := _pay_with_tokens(state, i, tokens_used)
			if not token_pay.ok:
				return token_pay
			token_payment = token_pay.value

		var unpaid_amount: int = due_cash_amount - pay_amount
		if unpaid_amount > 0 and not allow_unpaid:
			return Result.failure("玩家 %d 薪水不足：仍欠 $%d（需在 Payday 解雇员工以支付薪水；或获得相关里程碑允许欠薪）" % [i, unpaid_amount])

		var ms := MilestoneSystemClass.process_event(state, "PaySalaries", {
			"player_id": i,
			"paid": pay_amount,
		})
		if not ms.ok:
			warnings.append("里程碑触发失败(PaySalaries): 玩家 %d: %s" % [i, ms.error])

		base_due.append(base_due_amount)
		discount.append(discount_amount)
		milestone_delta.append(milestone_delta_amount)
		due.append(due_amount)
		paid.append(pay_amount)
		unpaid.append(unpaid_amount)

		details.append({
			"player_id": i,
			"paid_employee_count": paid_employee_count,
			"base_due": base_due_amount,
			"recruit_used": used_recruit,
			"salary_discount_recruit_capacity": discount_recruit_capacity,
			"salary_discount_unused_actions": unused_discount_actions,
			"salary_discount": discount_amount,
			"milestone_delta": milestone_delta_amount,
			"due": due_amount,
			"paid": pay_amount,
			"paid_with_tokens": token_payment,
			"unpaid": unpaid_amount,
			"cash_before": cash_before,
			"cash_after": int(state.players[i]["cash"])
		})

		if unpaid_amount > 0:
			warnings.append("玩家 %d 薪水不足：应付 $%d（现金部分 $%d），实付 $%d" % [i, due_amount, due_cash_amount, pay_amount])

	state.round_state["payday"] = {
		"base_due": base_due,
		"discount": discount,
		"milestone_delta": milestone_delta,
		"due": due,
		"paid": paid,
		"unpaid": unpaid,
		"details": details
	}

	return Result.success().with_warnings(warnings)

static func _count_food_drink_tokens(inventory: Dictionary) -> int:
	var total := 0
	for k in inventory.keys():
		var product_id: String = str(k)
		if product_id == "coffee":
			continue
		var def = ProductRegistryClass.get_def(product_id)
		if def == null or not (def is ProductDef):
			continue
		var p: ProductDef = def
		if not (p.has_tag("food") or p.has_tag("drink")):
			continue
		var v = inventory.get(k, 0)
		if v is int and int(v) > 0:
			total += int(v)
	return total

static func _compute_min_tokens_needed(paid_employee_count: int, salary_cost: int, milestone_delta: int, discount_amount: int, cash_available: int) -> int:
	if paid_employee_count <= 0:
		return 0
	for t in range(paid_employee_count + 1):
		var due_cash := maxi(0, (paid_employee_count - t) * salary_cost + milestone_delta - discount_amount)
		if cash_available >= due_cash:
			return t
	return paid_employee_count

static func _pay_with_tokens(state: GameState, player_id: int, tokens_needed: int) -> Result:
	if state == null:
		return Result.failure("PaydaySettlement: state 为空")
	if player_id < 0 or player_id >= state.players.size():
		return Result.failure("PaydaySettlement: player_id 越界: %d" % player_id)
	if tokens_needed <= 0:
		return Result.success({})

	var player_val = state.players[player_id]
	if not (player_val is Dictionary):
		return Result.failure("PaydaySettlement: players[%d] 类型错误（期望 Dictionary）" % player_id)
	var player: Dictionary = player_val

	var inventory_val = player.get("inventory", null)
	if not (inventory_val is Dictionary):
		return Result.failure("PaydaySettlement: player[%d].inventory 类型错误（期望 Dictionary）" % player_id)
	var inventory: Dictionary = inventory_val

	var paid: Dictionary = {}
	var remaining := tokens_needed

	var ids := []
	for k in inventory.keys():
		ids.append(str(k))
	ids.sort()

	for pid in ids:
		if remaining <= 0:
			break
		if pid == "coffee":
			continue
		var def = ProductRegistryClass.get_def(pid)
		if def == null or not (def is ProductDef):
			continue
		var p: ProductDef = def
		if not (p.has_tag("food") or p.has_tag("drink")):
			continue
		var cur_val = inventory.get(pid, 0)
		if not (cur_val is int):
			continue
		var cur: int = int(cur_val)
		if cur <= 0:
			continue
		var use := mini(cur, remaining)
		inventory[pid] = cur - use
		paid[pid] = use
		remaining -= use

	if remaining > 0:
		return Result.failure("PaydaySettlement: food/drink tokens 不足（need=%d remain=%d）" % [tokens_needed, remaining])

	player["inventory"] = inventory
	state.players[player_id] = player
	return Result.success(paid)

static func _get_salary_discount_recruit_capacity(state: GameState, player_id: int, player: Dictionary, effect_registry) -> Result:
	assert(state != null, "PaydaySettlement: state 为空")
	assert(player.has("employees") and (player["employees"] is Array), "PaydaySettlement: player.employees 缺失或类型错误（期望 Array）")
	var employees: Array = player["employees"]

	if effect_registry == null:
		return Result.failure("PaydaySettlement: EffectRegistry 未设置")

	var warnings: Array[String] = []
	var ctx := {"salary_discount_recruit_capacity": 0}

	# Q3：折扣仅由“在岗员工”提供（reserve 不计入）
	for i in range(employees.size()):
		var emp_val = employees[i]
		if not (emp_val is String):
			return Result.failure("PaydaySettlement: employees[%d] 类型错误（期望 String）" % i)
		var emp_id: String = str(emp_val)
		if emp_id.is_empty():
			return Result.failure("PaydaySettlement: employees 不应包含空字符串")

		var def_val = EmployeeRegistryClass.get_def(emp_id)
		if def_val == null:
			return Result.failure("PaydaySettlement: 未知员工定义: %s" % emp_id)
		if not (def_val is EmployeeDef):
			return Result.failure("PaydaySettlement: 员工定义类型错误（期望 EmployeeDef）: %s" % emp_id)
		var def: EmployeeDef = def_val

		for eid in def.effect_ids:
			var effect_id: String = eid
			if effect_id.find(EFFECT_SEG_PAYDAY_SALARY_DISCOUNT) == -1:
				continue
			var r = effect_registry.invoke(effect_id, [state, player_id, ctx, emp_id])
			if not r.ok:
				return r
			warnings.append_array(r.warnings)

	var cap_val = ctx.get("salary_discount_recruit_capacity", null)
	if not (cap_val is int):
		return Result.failure("PaydaySettlement: ctx.salary_discount_recruit_capacity 类型错误（期望 int）")
	return Result.success(int(cap_val)).with_warnings(warnings)

static func _get_salary_total_delta(_state: GameState, player: Dictionary) -> Result:
	assert(player.has("milestones") and (player["milestones"] is Array), "PaydaySettlement: player.milestones 缺失或类型错误（期望 Array）")
	var milestones: Array = player["milestones"]

	var delta := 0
	for i in range(milestones.size()):
		var mid_val = milestones[i]
		if not (mid_val is String):
			return Result.failure("PaydaySettlement: player.milestones[%d] 类型错误（期望 String）" % i)
		var mid: String = str(mid_val)
		if mid.is_empty():
			return Result.failure("PaydaySettlement: player.milestones 不应包含空字符串")

		var def_val = MilestoneRegistryClass.get_def(mid)
		if def_val == null:
			return Result.failure("PaydaySettlement: 未知里程碑定义: %s" % mid)
		if not (def_val is MilestoneDef):
			return Result.failure("PaydaySettlement: 里程碑定义类型错误（期望 MilestoneDef）: %s" % mid)
		var def: MilestoneDef = def_val

		for e_i in range(def.effects.size()):
			var eff_val = def.effects[e_i]
			if not (eff_val is Dictionary):
				return Result.failure("PaydaySettlement: %s.effects[%d] 类型错误（期望 Dictionary）" % [mid, e_i])
			var eff: Dictionary = eff_val
			var type_val = eff.get("type", null)
			if not (type_val is String):
				return Result.failure("PaydaySettlement: %s.effects[%d].type 类型错误（期望 String）" % [mid, e_i])
			var t: String = str(type_val)
			if t != "salary_total_delta":
				continue

			var value_val = eff.get("value", null)
			var v_read := _parse_int_value(value_val, "%s.effects[%d].value" % [mid, e_i])
			if not v_read.ok:
				return Result.failure("PaydaySettlement: %s" % v_read.error)
			delta += int(v_read.value)

	return Result.success(delta)

static func _count_employee_in_list(list: Array, employee_id: String) -> int:
	var count := 0
	for emp in list:
		assert(emp is String, "PaydaySettlement: 员工列表元素类型错误（期望 String）: %s" % str(emp))
		var id: String = emp
		if id == employee_id:
			count += 1
	return count

static func _parse_int_value(value, path: String) -> Result:
	if value is int:
		return Result.success(int(value))
	if value is float:
		var f: float = float(value)
		if f == int(f):
			return Result.success(int(f))
		return Result.failure("%s 必须为整数（不允许小数）" % path)
	return Result.failure("%s 必须为整数" % path)
