# 发薪日薪水扣除 smoke test（M3）
class_name PaydaySalaryTest
extends RefCounted

const TestPhaseUtilsClass = preload("res://core/tests/test_phase_utils.gd")
const PaydaySettlementClass = preload("res://core/rules/phase/payday_settlement.gd")
const EffectRegistryClass = preload("res://core/rules/effect_registry.gd")

static func run(player_count: int = 2, seed: int = 12345) -> Result:
	var r_strict := _test_recruit_capacity_strict_parsing()
	if not r_strict.ok:
		return r_strict

	var r_discount := _test_payday_salary_discount_uses_recruit_capacity_and_active_only()
	if not r_discount.ok:
		return r_discount

	var r0 := _test_salary_total_delta_uses_milestone_effect_value()
	if not r0.ok:
		return r0

	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	# Round 1：推进到 Working / Recruit，并招聘 1 名 recruiter（进入待命）
	var to_working := TestPhaseUtilsClass.advance_until_phase(engine, "Working", 30)
	if not to_working.ok:
		return to_working

	if engine.get_state().sub_phase != "Recruit":
		return Result.failure("Working 初始子阶段应为 Recruit，实际: %s" % engine.get_state().sub_phase)

	var target_player := engine.get_state().get_current_player_id()
	var r1 := engine.execute_command(Command.create("recruit", target_player, {"employee_type": "recruiter"}))
	if not r1.ok:
		return Result.failure("招聘 recruiter 失败: %s" % r1.error)

	# 推进到下一回合 Restructuring：待命 recruiter 自动激活
	var to_restructuring := TestPhaseUtilsClass.advance_until_phase(engine, "Restructuring", 50)
	if not to_restructuring.ok:
		return to_restructuring

	var p_after := engine.get_state().get_player(target_player)
	if not p_after.get("employees", []).has("recruiter"):
		return Result.failure("进入 Restructuring 后应自动激活 recruiter")

	# Round 2：推进到 Working / Recruit，并轮转到 target_player
	var to_working2 := TestPhaseUtilsClass.advance_until_phase(engine, "Working", 30)
	if not to_working2.ok:
		return to_working2

	var safety = 0
	while engine.get_state().get_current_player_id() != target_player:
		safety += 1
		if safety > 20:
			return Result.failure("轮转到目标玩家超出安全上限")
		var sk := engine.execute_command(Command.create("skip", engine.get_state().get_current_player_id()))
		if not sk.ok:
			return Result.failure("skip 失败: %s" % sk.error)

	# 有 recruiter：应允许 2 次招聘
	var rr1 := engine.execute_command(Command.create("recruit", target_player, {"employee_type": "trainer"}))
	if not rr1.ok:
		return Result.failure("第二回合第一次招聘失败: %s" % rr1.error)
	var rr2 := engine.execute_command(Command.create("recruit", target_player, {"employee_type": "burger_cook"}))
	if not rr2.ok:
		return Result.failure("第二回合第二次招聘失败: %s" % rr2.error)

	# 给目标玩家发放现金（从银行转入），用于发薪
	var state := engine.get_state()
	var cash_before: int = int(state.get_player(target_player).get("cash", 0))
	var bank_before: int = int(state.bank.get("total", 0))
	var grant := 20
	var grant_result := StateUpdater.player_receive_from_bank(state, target_player, grant)
	if not grant_result.ok:
		return Result.failure("转入现金失败: %s" % grant_result.error)

	var cash_after_grant: int = int(state.get_player(target_player).get("cash", 0))
	var bank_after_grant: int = int(state.bank.get("total", 0))
	if cash_after_grant != cash_before + grant:
		return Result.failure("现金转入后玩家现金不匹配: %d != %d" % [cash_after_grant, cash_before + grant])
	if bank_after_grant != bank_before - grant:
		return Result.failure("现金转入后银行余额不匹配: %d != %d" % [bank_after_grant, bank_before - grant])

	# 推进到 Payday：此时不应自动扣除薪水（薪资在离开 Payday 时统一结算）
	var to_payday := TestPhaseUtilsClass.advance_until_phase(engine, "Payday", 50)
	if not to_payday.ok:
		return to_payday

	state = engine.get_state()
	var cash_at_payday: int = int(state.get_player(target_player).get("cash", 0))
	var bank_at_payday: int = int(state.bank.get("total", 0))
	if cash_at_payday != cash_after_grant:
		return Result.failure("进入 Payday 后不应扣薪，玩家现金不匹配: %d != %d" % [cash_at_payday, cash_after_grant])
	if bank_at_payday != bank_after_grant:
		return Result.failure("进入 Payday 后不应扣薪，银行余额不匹配: %d != %d" % [bank_at_payday, bank_after_grant])

	# 离开 Payday 进入 Marketing：应在推进时结算薪水并写入 round_state.payday
	var to_marketing := engine.execute_command(Command.create_system("advance_phase"))
	if not to_marketing.ok:
		return Result.failure("推进到 Marketing 失败: %s" % to_marketing.error)

	state = engine.get_state()
	if state.phase != "Marketing":
		return Result.failure("当前应为 Marketing，实际: %s" % state.phase)
	var payday: Dictionary = state.round_state.get("payday", {})
	if payday.is_empty():
		return Result.failure("Payday 应写入 round_state.payday")

	var due_arr: Array = Array(payday.get("due", []))
	var paid_arr: Array = Array(payday.get("paid", []))
	var base_due_arr: Array = Array(payday.get("base_due", []))
	var discount_arr: Array = Array(payday.get("discount", []))
	var milestone_delta_arr: Array = Array(payday.get("milestone_delta", []))
	if due_arr.size() != player_count or paid_arr.size() != player_count or base_due_arr.size() != player_count:
		return Result.failure("Payday 数组长度不匹配")

	# 根据员工 JSON 定义：
	# - recruiter: salary=false（不需要薪水）
	# - trainer: salary=false（不需要薪水）
	# - burger_cook: salary=true（需要薪水）
	# 所以只有 burger_cook 需要薪水 = 1 人 * $5 = $5
	var salary_cost: int = state.get_rule_int("salary_cost")
	var expected_due: int = 1 * salary_cost
	var expected_paid: int = expected_due
	var due_amount: int = int(due_arr[target_player])
	var paid_amount: int = int(paid_arr[target_player])
	var base_due_amount: int = int(base_due_arr[target_player])
	var discount_amount: int = int(discount_arr[target_player])
	var milestone_delta_amount: int = int(milestone_delta_arr[target_player])

	if base_due_amount != expected_due:
		return Result.failure("薪水基础应付不匹配: %d != %d" % [base_due_amount, expected_due])
	if discount_amount != 0:
		return Result.failure("本用例不应产生薪资折扣，实际: %d" % discount_amount)
	if milestone_delta_amount != 0:
		return Result.failure("本用例不应产生里程碑薪资修正，实际: %d" % milestone_delta_amount)
	if due_amount != expected_due:
		return Result.failure("薪水应付不匹配: %d != %d" % [due_amount, expected_due])
	if paid_amount != expected_paid:
		return Result.failure("薪水实付不匹配: %d != %d" % [paid_amount, expected_paid])

	var cash_after_payday: int = int(state.get_player(target_player).get("cash", 0))
	var bank_after_payday: int = int(state.bank.get("total", 0))
	if cash_after_payday != cash_at_payday - expected_paid:
		return Result.failure("发薪后玩家现金不匹配: %d != %d" % [cash_after_payday, cash_at_payday - expected_paid])
	if bank_after_payday != bank_at_payday + expected_paid:
		return Result.failure("发薪后银行余额不匹配: %d != %d" % [bank_after_payday, bank_at_payday + expected_paid])

	return Result.success({
		"player_count": player_count,
		"seed": seed,
		"target_player": target_player,
		"due": expected_due,
		"paid": expected_paid
	})

static func _test_recruit_capacity_strict_parsing() -> Result:
	# use:recruit 时必须提供 recruit_capacity 且 > 0（严格模式）
	var base := {
		"id": "x",
		"name": "X",
		"description": "",
		"salary": false,
		"unique": false,
		"role": "recruit_train",
		"manager_slots": 0,
		"range": {"type": null, "value": 0},
		"train_to": [],
		"train_capacity": 0,
		"tags": [],
		"usage_tags": ["use:recruit"],
		"mandatory": false,
	}

	var missing := EmployeeDef.from_dict(base)
	if missing.ok:
		return Result.failure("use:recruit 缺少 recruit_capacity 时应解析失败")

	base["recruit_capacity"] = 1
	var ok_read := EmployeeDef.from_dict(base)
	if not ok_read.ok:
		return Result.failure("提供 recruit_capacity=1 时应解析成功: %s" % ok_read.error)

	var bad := base.duplicate(true)
	bad["usage_tags"] = []
	var bad_read := EmployeeDef.from_dict(bad)
	if bad_read.ok:
		return Result.failure("未声明 use:recruit 但提供 recruit_capacity 时应解析失败")

	return Result.success()

static func _test_payday_salary_discount_uses_recruit_capacity_and_active_only() -> Result:
	const NAME := "PaydayRecruitCapacity"

	# Case A: HR Director 在 reserve 时不计入薪资折扣次数
	var engine_a := GameEngine.new()
	var init_a := engine_a.initialize(2, 12345)
	if not init_a.ok:
		return Result.failure("%s(A) 初始化失败: %s" % [NAME, init_a.error])
	var state_a := engine_a.get_state()

	var take_a := StateUpdater.take_from_pool(state_a, "hr_director", 1)
	if not take_a.ok:
		return Result.failure("%s(A) 从员工池取出 hr_director 失败: %s" % [NAME, take_a.error])
	var add_a := StateUpdater.add_employee(state_a, 0, "hr_director", true)
	if not add_a.ok:
		return Result.failure("%s(A) 添加 hr_director 到 reserve 失败: %s" % [NAME, add_a.error])

	var cash_a := StateUpdater.player_receive_from_bank(state_a, 0, 50)
	if not cash_a.ok:
		return Result.failure("%s(A) 发放测试现金失败: %s" % [NAME, cash_a.error])

	var apply_a := PaydaySettlementClass.apply(state_a, engine_a.phase_manager)
	if not apply_a.ok:
		return Result.failure("%s(A) PaydaySettlement 失败: %s" % [NAME, apply_a.error])
	var payday_a: Dictionary = state_a.round_state.get("payday", {})
	var details_a: Array = payday_a.get("details", [])
	if details_a.size() < 1 or not (details_a[0] is Dictionary):
		return Result.failure("%s(A) payday.details 结构错误" % NAME)
	var cap_a = details_a[0].get("salary_discount_recruit_capacity", null)
	if not (cap_a is int):
		return Result.failure("%s(A) salary_discount_recruit_capacity 类型错误（期望 int）" % NAME)
	if int(cap_a) != 0:
		return Result.failure("%s(A) reserve hr_director 不应提供折扣次数，实际: %d" % [NAME, int(cap_a)])

	# Case B: HR Director 在岗时折扣次数从 recruit_capacity 读取（非硬编码 4）
	var engine_b := GameEngine.new()
	var init_b := engine_b.initialize(2, 12345)
	if not init_b.ok:
		return Result.failure("%s(B) 初始化失败: %s" % [NAME, init_b.error])
	var state_b := engine_b.get_state()

	var take_b := StateUpdater.take_from_pool(state_b, "hr_director", 1)
	if not take_b.ok:
		return Result.failure("%s(B) 从员工池取出 hr_director 失败: %s" % [NAME, take_b.error])
	var add_b := StateUpdater.add_employee(state_b, 0, "hr_director", false)
	if not add_b.ok:
		return Result.failure("%s(B) 添加 hr_director 到 employees 失败: %s" % [NAME, add_b.error])

	var cash_b := StateUpdater.player_receive_from_bank(state_b, 0, 50)
	if not cash_b.ok:
		return Result.failure("%s(B) 发放测试现金失败: %s" % [NAME, cash_b.error])

	var def_b = EmployeeRegistry.get_def("hr_director")
	if def_b == null or not (def_b is EmployeeDef):
		return Result.failure("%s(B) 获取 hr_director 定义失败" % NAME)
	var orig_cap: int = int(def_b.recruit_capacity)
	def_b.recruit_capacity = 3

	var apply_b := PaydaySettlementClass.apply(state_b, engine_b.phase_manager)
	def_b.recruit_capacity = orig_cap
	if not apply_b.ok:
		return Result.failure("%s(B) PaydaySettlement 失败: %s" % [NAME, apply_b.error])
	var payday_b: Dictionary = state_b.round_state.get("payday", {})
	var details_b: Array = payday_b.get("details", [])
	if details_b.size() < 1 or not (details_b[0] is Dictionary):
		return Result.failure("%s(B) payday.details 结构错误" % NAME)
	var cap_b = details_b[0].get("salary_discount_recruit_capacity", null)
	if not (cap_b is int):
		return Result.failure("%s(B) salary_discount_recruit_capacity 类型错误（期望 int）" % NAME)
	if int(cap_b) != 3:
		return Result.failure("%s(B) 折扣次数应来自 recruit_capacity=3，实际: %d" % [NAME, int(cap_b)])

	return Result.success()

static func _test_salary_total_delta_uses_milestone_effect_value() -> Result:
	# first_train: salary_total_delta = -15（来自 modules/base_milestones/content/milestones/first_train.json）
	var state := GameState.new()
	state.rules = {
		"salary_cost": 5,
	}
	state.players = [
		{
			"cash": 0,
			"employees": [],
			"reserve_employees": [],
			"busy_marketers": [],
			"milestones": ["first_train"],
		}
	]
	state.round_state = {}

	var pm := _DummyPhaseManager.new(EffectRegistryClass.new())
	var r := PaydaySettlementClass.apply(state, pm)
	if not r.ok:
		return Result.failure("PaydaySettlement 失败: %s" % r.error)

	var payday: Dictionary = state.round_state.get("payday", {})
	if payday.is_empty():
		return Result.failure("PaydaySettlement 应写入 round_state.payday")
	var delta_arr: Array = Array(payday.get("milestone_delta", []))
	if delta_arr.size() != 1:
		return Result.failure("milestone_delta 数组长度不匹配: %d" % delta_arr.size())
	var delta_val = delta_arr[0]
	if not (delta_val is int):
		return Result.failure("milestone_delta[0] 类型错误（期望 int）")
	if int(delta_val) != -15:
		return Result.failure("milestone_delta 应来自 milestone JSON effects.value: -15，实际: %d" % int(delta_val))

	return Result.success()

class _DummyPhaseManager:
	extends RefCounted

	var _effect_registry = null

	func _init(effect_registry) -> void:
		_effect_registry = effect_registry

	func get_effect_registry():
		return _effect_registry

static func _complete_order_of_business(engine: GameEngine) -> Result:
	var state := engine.get_state()
	var player_count := state.players.size()
	var safety := 0
	while state.phase == "OrderOfBusiness":
		safety += 1
		if safety > player_count + 2:
			return Result.failure("OrderOfBusiness 选择循环超出安全上限")

		var oob: Dictionary = state.round_state.get("order_of_business", {})
		var picks: Array = oob.get("picks", [])
		if picks.size() != player_count:
			return Result.failure("OrderOfBusiness picks 长度不匹配")
		if bool(oob.get("finalized", false)):
			return Result.success()

		var actor := state.get_current_player_id()
		var pos := picks.find(-1)
		if pos < 0:
			return Result.failure("OrderOfBusiness picks 未包含空位")

		var pick := engine.execute_command(Command.create("choose_turn_order", actor, {"position": pos}))
		if not pick.ok:
			return Result.failure("选择顺序失败: %s" % pick.error)

		state = engine.get_state()

	return Result.success()
