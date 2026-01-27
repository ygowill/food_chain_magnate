# Payday 结算（从 PhaseManager 抽离）
# 目标：聚合 Payday 阶段“发薪/折扣/里程碑修正/round_state.payday 记录”逻辑，便于测试与复用。
class_name PaydaySettlement
extends RefCounted

const StateUpdaterClass = preload("res://core/state/state_updater.gd")
const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const MilestoneSystemClass = preload("res://core/rules/milestone_system.gd")
const MilestoneEffectQueriesClass = preload("res://core/rules/milestone_effect_queries.gd")
const SalaryDiscountClass = preload("res://core/rules/phase/payday/payday_salary_discount.gd")
const SalaryTokenPaymentClass = preload("res://core/rules/phase/payday/payday_salary_token_payment.gd")
const PlayerStateAccessClass = preload("res://core/state/player_state_access.gd")

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

		var cap_read := SalaryDiscountClass.get_salary_discount_recruit_capacity(state, i, player, effect_registry)
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
			tokens_available = SalaryTokenPaymentClass.count_food_drink_tokens(inventory)

		var tokens_used := 0
		if pay_with_tokens and tokens_available > 0 and paid_employee_count > 0:
			var need := SalaryTokenPaymentClass.compute_min_tokens_needed(
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
			var token_pay := SalaryTokenPaymentClass.pay_with_tokens(state, i, tokens_used)
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
	return SalaryTokenPaymentClass.count_food_drink_tokens(inventory)

static func _pay_with_tokens(state: GameState, player_id: int, tokens_needed: int) -> Result:
	return SalaryTokenPaymentClass.pay_with_tokens(state, player_id, tokens_needed)

static func _get_salary_total_delta(_state: GameState, player: Dictionary) -> Result:
	var milestones_read := PlayerStateAccessClass.require_milestones(player, "player", "PaydaySettlement")
	if not milestones_read.ok:
		return milestones_read
	var milestones: Array = milestones_read.value

	return MilestoneEffectQueriesClass.sum_int_values(
		milestones,
		"salary_total_delta",
		"PaydaySettlement: ",
		"player.milestones"
	)
