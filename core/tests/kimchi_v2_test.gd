# Kimchi（模块5）规则测试（V2）
class_name KimchiV2Test
extends RefCounted

const RoadGraphCacheClass = preload("res://core/map/map_runtime/road_graph_cache.gd")
const PhaseDefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const SettlementRegistryClass = preload("res://core/rules/settlement_registry.gd")
const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const ProductRegistryClass = preload("res://core/data/product_registry.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")

const Phase = PhaseDefsClass.Phase
const Point = SettlementRegistryClass.Point

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	if player_count != 2:
		return Result.failure("本测试目前固定为 2 人局（实际: %d）" % player_count)

	var r0 := _test_kimchi_master_entry_level_and_pool(seed_val)
	if not r0.ok:
		return r0

	var r0b := _test_kimchi_master_can_be_directly_recruited(seed_val)
	if not r0b.ok:
		return r0b

	var r0c := _test_kimchi_master_requires_salary_in_payday(seed_val)
	if not r0c.ok:
		return r0c

	var r0d := _test_kimchi_master_does_nothing_in_9_to_5(seed_val)
	if not r0d.ok:
		return r0d

	var r1 := _test_prefers_kimchi_restaurant_even_if_score_worse(seed_val)
	if not r1.ok:
		return r1

	var r2 := _test_cleanup_produces_and_forces_kimchi_storage(seed_val)
	if not r2.ok:
		return r2

	var r2b := _test_cleanup_kimchi_storage_can_decline_and_proceed_to_fridge(seed_val)
	if not r2b.ok:
		return r2b

	var r3 := _test_garden_prefers_kimchi_plus_noodles_over_sushi_and_base(seed_val)
	if not r3.ok:
		return r3

	var r3b := _test_garden_prefers_kimchi_plus_sushi_over_kimchi_plus_base(seed_val)
	if not r3b.ok:
		return r3b

	var r4 := _test_cleanup_preserves_existing_kimchi_without_fridge(seed_val)
	if not r4.ok:
		return r4

	var r5 := _test_cleanup_kimchi_unblocks_fridge_pending(seed_val)
	if not r5.ok:
		return r5

	var r6 := _test_extra_luxury_manager_patch(seed_val)
	if not r6.ok:
		return r6

	var r7 := _test_kimchi_product_is_no_marketing(seed_val)
	if not r7.ok:
		return r7

	var r8 := _test_cleanup_clamps_kimchi_to_10(seed_val)
	if not r8.ok:
		return r8

	return Result.success({
		"cases": 14,
		"seed": seed_val,
	})

static func _test_kimchi_master_entry_level_and_pool(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"kimchi",
	]
	var init := engine.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	if not EmployeeRulesClass.is_entry_level("kimchi_master"):
		return Result.failure("kimchi_master 应为可直接招聘的入门级员工（tags.entry_level 缺失？）")

	var one_x := int(state.rules.get("one_x_employee_copies", -1))
	if one_x <= 0:
		return Result.failure("state.rules.one_x_employee_copies 无效: %d" % one_x)
	var pool_val = state.employee_pool.get("kimchi_master", null)
	if not (pool_val is int):
		return Result.failure("employee_pool.kimchi_master 缺失或类型错误（期望 int）")
	var pool_count: int = int(pool_val)
	if pool_count != one_x:
		return Result.failure("kimchi_master 为 1x 员工：2p 下应为 %d，实际: %d" % [one_x, pool_count])

	return Result.success()

static func _test_kimchi_master_can_be_directly_recruited(seed_val: int) -> Result:
	var e := GameEngine.new()
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"kimchi",
	]
	var init := e.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := e.get_state()
	_force_turn_order(state)
	state.phase = PhaseDefsClass.PHASE_WORKING
	state.sub_phase = PhaseDefsClass.SUB_PHASE_RECRUIT
	if not (state.round_state is Dictionary):
		state.round_state = {}
	state.round_state["sub_phase_passed"] = {0: false, 1: false}

	var before_pool := int(state.employee_pool.get("kimchi_master", 0))
	if before_pool <= 0:
		return Result.failure("employee_pool 中没有 kimchi_master")

	var r := e.execute_command(Command.create("recruit", 0, {"employee_type": "kimchi_master"}))
	if not r.ok:
		return Result.failure("recruit(kimchi_master) 失败: %s" % r.error)

	state = e.get_state()
	var after_pool := int(state.employee_pool.get("kimchi_master", 0))
	if after_pool != before_pool - 1:
		return Result.failure("recruit 后 employee_pool.kimchi_master 应减少 1: before=%d after=%d" % [before_pool, after_pool])
	var reserve: Array = state.players[0].get("reserve_employees", [])
	if not (reserve is Array) or reserve.find("kimchi_master") < 0:
		return Result.failure("recruit 后 reserve_employees 应包含 kimchi_master，实际: %s" % str(reserve))

	return Result.success()

static func _test_kimchi_master_requires_salary_in_payday(seed_val: int) -> Result:
	var e := GameEngine.new()
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"kimchi",
	]
	var init := e.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := e.get_state()
	_force_turn_order(state)

	# 隔离：只保留 kimchi_master 作为付薪员工，避免其它初始员工影响断言。
	state.players[0]["employees"] = ["kimchi_master"]
	state.players[0]["reserve_employees"] = []
	state.players[0]["busy_marketers"] = []
	state.players[0]["milestones"] = []
	state.players[0]["cash"] = 100

	var salary_cost: int = state.get_rule_int("salary_cost")
	if salary_cost <= 0:
		return Result.failure("salary_cost 无效: %d" % salary_cost)

	var pm = e.phase_manager
	if pm == null:
		return Result.failure("phase_manager 为空")
	var reg = pm.get_settlement_registry()
	if reg == null:
		return Result.failure("SettlementRegistry 为空")

	var r: Result = reg.run(Phase.PAYDAY, Point.EXIT, state, pm)
	if not r.ok:
		return Result.failure("Payday 结算失败: %s" % r.error)

	state = e.get_state()
	var cash_after := int(state.players[0].get("cash", -1))
	var expected := 100 - salary_cost
	if cash_after != expected:
		return Result.failure("kimchi_master 应在 Payday 支付薪水: expected=%d got=%d salary_cost=%d" % [expected, cash_after, salary_cost])

	return Result.success()

static func _test_kimchi_master_does_nothing_in_9_to_5(seed_val: int) -> Result:
	var e := GameEngine.new()
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"kimchi",
	]
	var init := e.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := e.get_state()
	_force_turn_order(state)
	state.phase = PhaseDefsClass.PHASE_WORKING
	state.sub_phase = PhaseDefsClass.SUB_PHASE_GET_FOOD
	if not (state.round_state is Dictionary):
		state.round_state = {}
	state.round_state["sub_phase_passed"] = {0: false, 1: false}

	# kimchi_master 的 role=produce_food，但没有生产选项；尝试 produce_food 应失败。
	var r := e.execute_command(Command.create("produce_food", 0, {"employee_type": "kimchi_master"}))
	if r.ok:
		return Result.failure("kimchi_master 不应在 9-5(GetFood) 阶段生产食物")

	return Result.success()

static func _test_extra_luxury_manager_patch(seed_val: int) -> Result:
	# 基线（2 人局 one_x=1）：base_rules 的 luxury_manager 应为 1
	var e0 := GameEngine.new()
	var init0 := e0.initialize(2, seed_val)
	if not init0.ok:
		return Result.failure("初始化失败: %s" % init0.error)
	var s0 := e0.get_state()
	var lm0: int = int(s0.employee_pool.get("luxury_manager", -1))
	if lm0 != 1:
		return Result.failure("基线 luxury_manager 应为 1，实际: %d" % lm0)

	# 启用 kimchi：+1
	var e1 := GameEngine.new()
	var init1 := e1.initialize(2, seed_val, [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"kimchi",
	])
	if not init1.ok:
		return Result.failure("初始化失败: %s" % init1.error)
	var s1 := e1.get_state()
	var lm1: int = int(s1.employee_pool.get("luxury_manager", -1))
	if lm1 != 2:
		return Result.failure("启用 kimchi 后 luxury_manager 应为 2，实际: %d" % lm1)

	# 启用 kimchi + noodles + sushi：仍只加一次（去重）
	var e2 := GameEngine.new()
	var init2 := e2.initialize(2, seed_val, [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"kimchi",
		"noodles",
		"sushi",
	])
	if not init2.ok:
		return Result.failure("初始化失败: %s" % init2.error)
	var s2 := e2.get_state()
	var lm2: int = int(s2.employee_pool.get("luxury_manager", -1))
	if lm2 != 2:
		return Result.failure("启用 kimchi+noodles+sushi 后 luxury_manager 应为 2（只加一次），实际: %d" % lm2)

	return Result.success()

static func _test_kimchi_product_is_no_marketing(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val, [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"kimchi",
	])
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	if not ProductRegistryClass.has("kimchi"):
		return Result.failure("应存在产品 kimchi（ProductRegistry 缺失？）")
	var def = ProductRegistryClass.get_def("kimchi")
	if def == null or not def.has_method("has_tag"):
		return Result.failure("kimchi 产品定义无效")
	if not def.has_tag("no_marketing"):
		return Result.failure("kimchi 不应允许被营销（tags.no_marketing 缺失？）")

	return Result.success()

static func _test_cleanup_clamps_kimchi_to_10(seed_val: int) -> Result:
	var e := GameEngine.new()
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"kimchi",
	]
	var init := e.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := e.get_state()
	_prepare_cleanup(state)

	# 玩家0：已有大量 kimchi，应在 cleanup 后被 clamp 到 10（且其余产品清空）。
	state.players[0]["inventory"]["kimchi"] = 12
	state.players[0]["inventory"]["burger"] = 2

	var pm = e.phase_manager
	if pm == null:
		return Result.failure("phase_manager 为空")
	var reg = pm.get_settlement_registry()
	if reg == null:
		return Result.failure("SettlementRegistry 为空")

	var r: Result = reg.run(Phase.CLEANUP, Point.ENTER, state, pm)
	if not r.ok:
		return Result.failure("Cleanup 结算失败: %s" % r.error)

	var choose := e.execute_command(Command.create("choose_kimchi_storage", 0, {"store": true}))
	if not choose.ok:
		return Result.failure("choose_kimchi_storage 失败: %s" % choose.error)

	state = e.get_state()
	var inv: Dictionary = state.players[0]["inventory"]
	if int(inv.get("kimchi", 0)) != 10:
		return Result.failure("kimchi freezer 应 clamp 到 10，实际: %d inv=%s" % [int(inv.get("kimchi", 0)), str(inv)])
	if int(inv.get("burger", 0)) != 0:
		return Result.failure("存储 kimchi 时其他产品应被丢弃，实际 inv=%s" % str(inv))

	return Result.success()

static func _test_prefers_kimchi_restaurant_even_if_score_worse(seed_val: int) -> Result:
	var e := GameEngine.new()
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"kimchi",
	]
	var init := e.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := e.get_state()
	_force_turn_order(state)
	_apply_test_map(state)

	# house_left 需求 1 个 burger；两家餐厅都能满足 base，但只有玩家0 有 kimchi
	_set_house_demands(state, "house_left", [{"product": "burger"}])
	_set_house_demands(state, "house_right", [])

	state.players[0]["inventory"]["burger"] = 1
	state.players[0]["inventory"]["kimchi"] = 1
	state.players[1]["inventory"]["burger"] = 1
	state.players[1]["inventory"]["kimchi"] = 0

	# 让 base score 倾向玩家1（玩家0 单价更高）
	state.round_state["price_modifiers"] = {
		0: {"test": 1},
		1: {"test": 0},
	}

	var adv := _advance_to_dinnertime(e)
	if not adv.ok:
		return adv

	state = e.get_state()
	if int(state.players[0].get("cash", 0)) != 22:
		return Result.failure("Kimchi+base（2 件）收入应为 22，实际: %d" % int(state.players[0].get("cash", 0)))
	if int(state.players[1].get("cash", 0)) != 0:
		return Result.failure("玩家1 不应售出，现金应为 0，实际: %d" % int(state.players[1].get("cash", 0)))

	if int(state.players[0]["inventory"].get("burger", 0)) != 0:
		return Result.failure("burger 应被扣减，实际: %d" % int(state.players[0]["inventory"].get("burger", 0)))
	if int(state.players[0]["inventory"].get("kimchi", 0)) != 0:
		return Result.failure("kimchi 应被扣减，实际: %d" % int(state.players[0]["inventory"].get("kimchi", 0)))

	var dt: Dictionary = state.round_state.get("dinnertime", {})
	var sales: Array = dt.get("sales", [])
	if sales.is_empty():
		return Result.failure("应存在 1 条 sale 记录")
	var s0: Dictionary = sales[0]
	if str(s0.get("demand_variant_id", "")) != "kimchi:kimchi_plus_base":
		return Result.failure("demand_variant_id 应为 kimchi:kimchi_plus_base，实际: %s" % str(s0.get("demand_variant_id", null)))

	return Result.success()

static func _test_cleanup_produces_and_forces_kimchi_storage(seed_val: int) -> Result:
	var e := GameEngine.new()
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"kimchi",
	]
	var init := e.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := e.get_state()
	_prepare_cleanup(state)

	# 注入 kimchi_master（在岗），并给一些其他库存，验证 cleanup 后只保留 kimchi
	if int(state.employee_pool.get("kimchi_master", 0)) <= 0:
		return Result.failure("employee_pool 中没有 kimchi_master")
	state.employee_pool["kimchi_master"] = int(state.employee_pool.get("kimchi_master", 0)) - 1
	state.players[0]["employees"].append("kimchi_master")

	state.players[0]["inventory"]["burger"] = 3
	state.players[0]["inventory"]["pizza"] = 2

	var pm = e.phase_manager
	if pm == null:
		return Result.failure("phase_manager 为空")
	var reg = pm.get_settlement_registry()
	if reg == null:
		return Result.failure("SettlementRegistry 为空")

	var r: Result = reg.run(Phase.CLEANUP, Point.ENTER, state, pm)
	if not r.ok:
		return Result.failure("Cleanup 结算失败: %s" % r.error)

	var rs_kimchi: Dictionary = state.round_state.get("kimchi", {})
	var produced: Array = rs_kimchi.get("produced", [])
	if produced.is_empty():
		return Result.failure("round_state.kimchi.produced 应记录生产事件")

	# 规则：泡菜在丢弃之后生产；因此在玩家做出“是否存泡菜”选择前，不应提前写入库存。
	var inv_before_choice: Dictionary = state.players[0]["inventory"]
	if int(inv_before_choice.get("kimchi", 0)) != 0:
		return Result.failure("选择前 kimchi 库存应为 0（生产应在选择/丢弃后落地），实际: %d inv=%s" % [int(inv_before_choice.get("kimchi", 0)), str(inv_before_choice)])

	var choose := e.execute_command(Command.create("choose_kimchi_storage", 0, {"store": true}))
	if not choose.ok:
		return Result.failure("choose_kimchi_storage 失败: %s" % choose.error)

	state = e.get_state()
	var inv: Dictionary = state.players[0]["inventory"]
	if int(inv.get("kimchi", 0)) != 1:
		return Result.failure("kimchi 应被生产并保留 1，实际: %d" % int(inv.get("kimchi", 0)))
	if int(inv.get("burger", 0)) != 0 or int(inv.get("pizza", 0)) != 0:
		return Result.failure("存储 kimchi 时其他产品应被丢弃，实际 inv=%s" % str(inv))

	return Result.success()

static func _test_cleanup_kimchi_storage_can_decline_and_proceed_to_fridge(seed_val: int) -> Result:
	var e := GameEngine.new()
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"kimchi",
	]
	var init := e.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := e.get_state()
	_prepare_cleanup(state)

	# 玩家0：有冰箱且库存超出容量 -> 会进入冰箱选择 pending。
	var claim := StateUpdater.claim_milestone(state, 0, "first_throw_away")
	if not claim.ok:
		return Result.failure("为玩家 0 领取 first_throw_away 失败: %s" % claim.error)

	state.players[0]["inventory"]["kimchi"] = 1
	state.players[0]["inventory"]["burger"] = 12
	state.players[0]["inventory"]["pizza"] = 9

	var pm = e.phase_manager
	if pm == null:
		return Result.failure("phase_manager 为空")
	var reg = pm.get_settlement_registry()
	if reg == null:
		return Result.failure("SettlementRegistry 为空")

	var r: Result = reg.run(Phase.CLEANUP, Point.ENTER, state, pm)
	if not r.ok:
		return Result.failure("Cleanup 结算失败: %s" % r.error)

	# kimchi 选择优先于冰箱选择
	var cleanup_val = state.round_state.get("cleanup", null)
	if not (cleanup_val is Dictionary):
		return Result.failure("round_state.cleanup 缺失或类型错误（期望 Dictionary）")
	var cleanup: Dictionary = cleanup_val
	if str(cleanup.get("pending_choice_kind", "")) != "kimchi":
		return Result.failure("pending_choice_kind 应为 kimchi，实际: %s" % str(cleanup.get("pending_choice_kind", null)))

	var choose0 := e.execute_command(Command.create("choose_kimchi_storage", 0, {"store": false}))
	if not choose0.ok:
		return Result.failure("choose_kimchi_storage(store=false) 失败: %s" % choose0.error)

	state = e.get_state()

	# 不存泡菜后应进入冰箱选择
	var cleanup2_val = state.round_state.get("cleanup", null)
	if not (cleanup2_val is Dictionary):
		return Result.failure("round_state.cleanup 类型错误（期望 Dictionary）")
	var cleanup2: Dictionary = cleanup2_val
	if str(cleanup2.get("pending_choice_kind", "")) != "fridge":
		return Result.failure("pending_choice_kind 应为 fridge，实际: %s" % str(cleanup2.get("pending_choice_kind", null)))

	var inv_mid: Dictionary = state.players[0]["inventory"]
	if int(inv_mid.get("kimchi", 0)) != 0:
		return Result.failure("选择不存泡菜后 kimchi 应为 0，实际: %d inv=%s" % [int(inv_mid.get("kimchi", 0)), str(inv_mid)])
	if int(inv_mid.get("burger", 0)) != 12 or int(inv_mid.get("pizza", 0)) != 9:
		return Result.failure("选择不存泡菜不应影响其它库存（应仍待冰箱选择），实际 inv=%s" % str(inv_mid))

	var choose_fridge := e.execute_command(Command.create("choose_fridge_keep", 0, {"keep": {"burger": 5, "pizza": 5}}))
	if not choose_fridge.ok:
		return Result.failure("choose_fridge_keep 失败: %s" % choose_fridge.error)

	state = e.get_state()
	var ppa_val = state.round_state.get("pending_phase_actions", null)
	if ppa_val is Dictionary and Dictionary(ppa_val).has(PhaseDefsClass.PHASE_CLEANUP):
		return Result.failure("结算后不应残留 pending_phase_actions[Cleanup]，实际: %s" % str(ppa_val))

	var inv_after: Dictionary = state.players[0]["inventory"]
	if int(inv_after.get("kimchi", 0)) != 0:
		return Result.failure("最终 kimchi 应为 0，实际: %d inv=%s" % [int(inv_after.get("kimchi", 0)), str(inv_after)])
	if int(inv_after.get("burger", 0)) != 5 or int(inv_after.get("pizza", 0)) != 5:
		return Result.failure("最终冰箱保留数量不正确，实际 inv=%s" % str(inv_after))

	return Result.success()

static func _test_garden_prefers_kimchi_plus_noodles_over_sushi_and_base(seed_val: int) -> Result:
	var e := GameEngine.new()
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"noodles",
		"sushi",
		"kimchi",
	]
	var init := e.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := e.get_state()
	_force_turn_order(state)
	_apply_test_map(state)

	# house_left 为花园房屋：需求 burger+beer（total=2）
	var houses: Dictionary = state.map.get("houses", {})
	var left: Dictionary = houses.get("house_left", {})
	left["has_garden"] = true
	houses["house_left"] = left
	state.map["houses"] = houses

	_set_house_demands(state, "house_left", [{"product": "burger"}, {"product": "beer"}])
	_set_house_demands(state, "house_right", [])

	# 玩家0：可卖 Sushi(2) 或 Base(burger+beer)，但没有 kimchi
	state.players[0]["inventory"]["sushi"] = 2
	state.players[0]["inventory"]["burger"] = 1
	state.players[0]["inventory"]["beer"] = 1
	state.players[0]["inventory"]["kimchi"] = 0
	state.players[0]["inventory"]["noodles"] = 0

	# 玩家1：仅可卖 Kimchi+Noodles（noodles=2 + kimchi=1）
	state.players[1]["inventory"]["noodles"] = 2
	state.players[1]["inventory"]["kimchi"] = 1
	state.players[1]["inventory"]["sushi"] = 0
	state.players[1]["inventory"]["burger"] = 0
	state.players[1]["inventory"]["beer"] = 0

	var adv := _advance_to_dinnertime(e)
	if not adv.ok:
		return adv

	state = e.get_state()
	var dt: Dictionary = state.round_state.get("dinnertime", {})
	var sales: Array = dt.get("sales", [])
	if sales.size() != 1:
		return Result.failure("应存在 1 条 sale 记录，实际: %d" % sales.size())
	var s0: Dictionary = sales[0]
	if int(s0.get("winner_owner", -1)) != 1:
		return Result.failure("应由玩家1 售出（Kimchi+Noodles 优先），实际 winner_owner=%s" % str(s0.get("winner_owner", null)))
	if str(s0.get("demand_variant_id", "")) != "kimchi:kimchi_plus_noodles":
		return Result.failure("demand_variant_id 应为 kimchi:kimchi_plus_noodles，实际: %s" % str(s0.get("demand_variant_id", null)))

	if int(state.players[0].get("cash", 0)) != 0:
		return Result.failure("玩家0 不应售出，现金应为 0，实际: %d" % int(state.players[0].get("cash", 0)))
	if int(state.players[1].get("cash", 0)) <= 0:
		return Result.failure("玩家1 应售出并获得收入，实际 cash=%d" % int(state.players[1].get("cash", 0)))

	return Result.success()

static func _test_garden_prefers_kimchi_plus_sushi_over_kimchi_plus_base(seed_val: int) -> Result:
	var e := GameEngine.new()
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"sushi",
		"kimchi",
	]
	var init := e.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := e.get_state()
	_force_turn_order(state)
	_apply_test_map(state)

	# house_left 为花园房屋：需求 burger+beer（total=2）
	var houses: Dictionary = state.map.get("houses", {})
	var left: Dictionary = houses.get("house_left", {})
	left["has_garden"] = true
	houses["house_left"] = left
	state.map["houses"] = houses

	_set_house_demands(state, "house_left", [{"product": "burger"}, {"product": "beer"}])
	_set_house_demands(state, "house_right", [])

	# 玩家0：仅能卖 Kimchi+Base（更近）
	state.players[0]["inventory"]["burger"] = 1
	state.players[0]["inventory"]["beer"] = 1
	state.players[0]["inventory"]["kimchi"] = 1
	state.players[0]["inventory"]["sushi"] = 0

	# 玩家1：能卖 Kimchi+Sushi（应因优先级更高而胜出）
	state.players[1]["inventory"]["sushi"] = 2
	state.players[1]["inventory"]["kimchi"] = 1
	state.players[1]["inventory"]["burger"] = 0
	state.players[1]["inventory"]["beer"] = 0

	var adv := _advance_to_dinnertime(e)
	if not adv.ok:
		return adv

	state = e.get_state()
	var dt: Dictionary = state.round_state.get("dinnertime", {})
	var sales: Array = dt.get("sales", [])
	if sales.size() != 1:
		return Result.failure("应存在 1 条 sale 记录，实际: %d" % sales.size())
	var s0: Dictionary = sales[0]
	if int(s0.get("winner_owner", -1)) != 1:
		return Result.failure("应由玩家1 售出（Kimchi+Sushi 优先），实际 winner_owner=%s" % str(s0.get("winner_owner", null)))
	if str(s0.get("demand_variant_id", "")) != "kimchi:kimchi_plus_sushi":
		return Result.failure("demand_variant_id 应为 kimchi:kimchi_plus_sushi，实际: %s" % str(s0.get("demand_variant_id", null)))

	return Result.success()

static func _test_cleanup_preserves_existing_kimchi_without_fridge(seed_val: int) -> Result:
	var e := GameEngine.new()
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"kimchi",
	]
	var init := e.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := e.get_state()
	_prepare_cleanup(state)

	# 玩家0：无冰箱，但已有上回合存下来的 kimchi，应在 cleanup 后仍保留。
	state.players[0]["inventory"]["kimchi"] = 3
	state.players[0]["inventory"]["burger"] = 2

	var pm = e.phase_manager
	if pm == null:
		return Result.failure("phase_manager 为空")
	var reg = pm.get_settlement_registry()
	if reg == null:
		return Result.failure("SettlementRegistry 为空")

	var r: Result = reg.run(Phase.CLEANUP, Point.ENTER, state, pm)
	if not r.ok:
		return Result.failure("Cleanup 结算失败: %s" % r.error)

	var choose := e.execute_command(Command.create("choose_kimchi_storage", 0, {"store": true}))
	if not choose.ok:
		return Result.failure("choose_kimchi_storage 失败: %s" % choose.error)

	state = e.get_state()
	var inv: Dictionary = state.players[0]["inventory"]
	if int(inv.get("kimchi", 0)) != 3:
		return Result.failure("无冰箱时应保留已存 kimchi=3，实际: %d inv=%s" % [int(inv.get("kimchi", 0)), str(inv)])
	if int(inv.get("burger", 0)) != 0:
		return Result.failure("存储 kimchi 时其他产品应被丢弃，实际 inv=%s" % str(inv))

	return Result.success()

static func _test_cleanup_kimchi_unblocks_fridge_pending(seed_val: int) -> Result:
	var e := GameEngine.new()
	var enabled_modules: Array[String] = [
		"base_rules",
		"base_products",
		"base_pieces",
		"base_tiles",
		"base_maps",
		"base_employees",
		"base_milestones",
		"base_marketing",
		"kimchi",
	]
	var init := e.initialize(2, seed_val, enabled_modules)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := e.get_state()
	_prepare_cleanup(state)

	# 玩家0：先获得冰箱里程碑（cap=10），再给超出 cap 的库存，按 base 规则会进入 pending。
	var claim := StateUpdater.claim_milestone(state, 0, "first_throw_away")
	if not claim.ok:
		return Result.failure("为玩家 0 领取 first_throw_away 失败: %s" % claim.error)

	state.players[0]["inventory"]["kimchi"] = 1
	state.players[0]["inventory"]["burger"] = 12
	state.players[0]["inventory"]["pizza"] = 9

	var pm = e.phase_manager
	if pm == null:
		return Result.failure("phase_manager 为空")
	var reg = pm.get_settlement_registry()
	if reg == null:
		return Result.failure("SettlementRegistry 为空")

	var r: Result = reg.run(Phase.CLEANUP, Point.ENTER, state, pm)
	if not r.ok:
		return Result.failure("Cleanup 结算失败: %s" % r.error)

	var choose := e.execute_command(Command.create("choose_kimchi_storage", 0, {"store": true}))
	if not choose.ok:
		return Result.failure("choose_kimchi_storage 失败: %s" % choose.error)

	state = e.get_state()
	var ppa_val = state.round_state.get("pending_phase_actions", null)
	if ppa_val is Dictionary and Dictionary(ppa_val).has(PhaseDefsClass.PHASE_CLEANUP):
		return Result.failure("kimchi freezer 结算后不应残留 pending_phase_actions[Cleanup]，实际: %s" % str(ppa_val))

	var inv: Dictionary = state.players[0]["inventory"]
	if int(inv.get("kimchi", 0)) != 1:
		return Result.failure("Cleanup 后应保留 kimchi=1，实际: %d inv=%s" % [int(inv.get("kimchi", 0)), str(inv)])
	if int(inv.get("burger", 0)) != 0 or int(inv.get("pizza", 0)) != 0:
		return Result.failure("存储 kimchi 时其他产品应被丢弃，实际 inv=%s" % str(inv))

	return Result.success()

static func _prepare_cleanup(state: GameState) -> void:
	if state == null:
		return
	state.phase = PhaseDefsClass.PHASE_CLEANUP
	state.sub_phase = ""
	state.round_number = 1
	_force_turn_order(state)
	if not (state.round_state is Dictionary):
		state.round_state = {}

static func _advance_to_dinnertime(engine: GameEngine) -> Result:
	var state := engine.get_state()
	state.phase = PhaseDefsClass.PHASE_WORKING
	state.sub_phase = PhaseDefsClass.SUB_PHASE_PLACE_RESTAURANTS
	if not (state.round_state is Dictionary):
		state.round_state = {}
	var passed := {}
	for pid in range(state.players.size()):
		passed[pid] = true
	state.round_state["sub_phase_passed"] = passed

	var adv := engine.execute_command(Command.create_system(ActionIdsClass.ADVANCE_PHASE, {"target": "sub_phase"}))
	if not adv.ok:
		return Result.failure("推进到 Dinnertime 失败: %s" % adv.error)
	return Result.success()

static func _force_turn_order(state: GameState) -> void:
	state.turn_order = [0, 1]
	state.current_player_index = 0

static func _build_empty_cells(grid_size: Vector2i) -> Array:
	var cells: Array = []
	for y in range(grid_size.y):
		var row: Array = []
		for x in range(grid_size.x):
			row.append({
				"terrain_type": "empty",
				"structure": {},
				"road_segments": [],
				"blocked": false
			})
		cells.append(row)
	return cells

static func _set_road_segment(cells: Array, pos: Vector2i, dirs: Array) -> void:
	cells[pos.y][pos.x]["road_segments"] = [{"dirs": dirs}]

static func _set_house(cells: Array, house_id: String, house_number: int, footprint: Array[Vector2i], has_garden: bool) -> void:
	for p in footprint:
		cells[p.y][p.x]["structure"] = {
			"piece_id": "house",
			"house_id": house_id,
			"house_number": house_number,
			"has_garden": has_garden,
			"dynamic": true
		}

static func _set_restaurant(cells: Array, restaurant_id: String, owner: int, footprint: Array[Vector2i]) -> void:
	for p in footprint:
		cells[p.y][p.x]["structure"] = {
			"piece_id": "restaurant",
			"owner": owner,
			"restaurant_id": restaurant_id,
			"dynamic": true
		}

static func _apply_test_map(state: GameState) -> void:
	var grid_size := Vector2i(10, 5)
	var cells := _build_empty_cells(grid_size)

	for x in range(grid_size.x):
		var dirs: Array = []
		if x > 0:
			dirs.append("W")
		if x < grid_size.x - 1:
			dirs.append("E")
		_set_road_segment(cells, Vector2i(x, 2), dirs)

	var left_house_cells: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 0),
		Vector2i(0, 1), Vector2i(1, 1),
	]
	var right_house_cells: Array[Vector2i] = [
		Vector2i(8, 0), Vector2i(9, 0),
		Vector2i(8, 1), Vector2i(9, 1),
	]
	_set_house(cells, "house_left", 1, left_house_cells, false)
	_set_house(cells, "house_right", 2, right_house_cells, false)

	var rest0_cells: Array[Vector2i] = [
		Vector2i(0, 3), Vector2i(1, 3),
		Vector2i(0, 4), Vector2i(1, 4),
	]
	var rest1_cells: Array[Vector2i] = [
		Vector2i(8, 3), Vector2i(9, 3),
		Vector2i(8, 4), Vector2i(9, 4),
	]
	_set_restaurant(cells, "rest_0", 0, rest0_cells)
	_set_restaurant(cells, "rest_1", 1, rest1_cells)

	state.map = {
		"grid_size": grid_size,
		"tile_grid_size": Vector2i(2, 1),
		"cells": cells,
		"houses": {
			"house_left": {
				"house_id": "house_left",
				"house_number": 1,
				"anchor_pos": Vector2i(0, 0),
				"cells": left_house_cells,
				"has_garden": false,
				"is_apartment": false,
				"printed": false,
				"owner": -1,
				"demands": []
			},
			"house_right": {
				"house_id": "house_right",
				"house_number": 2,
				"anchor_pos": Vector2i(8, 0),
				"cells": right_house_cells,
				"has_garden": false,
				"is_apartment": false,
				"printed": false,
				"owner": -1,
				"demands": []
			},
		},
		"restaurants": {
			"rest_0": {
				"restaurant_id": "rest_0",
				"owner": 0,
				"anchor_pos": Vector2i(0, 3),
				"entrance_pos": Vector2i(0, 3),
				"cells": rest0_cells,
			},
			"rest_1": {
				"restaurant_id": "rest_1",
				"owner": 1,
				"anchor_pos": Vector2i(8, 3),
				"entrance_pos": Vector2i(9, 3),
				"cells": rest1_cells,
			},
		},
		"drink_sources": [],
		"next_house_number": 3,
		"next_restaurant_id": 2,
		"boundary_index": {},
		"marketing_placements": {}
	}

	state.players[0]["restaurants"] = ["rest_0"]
	state.players[1]["restaurants"] = ["rest_1"]
	RoadGraphCacheClass.invalidate_road_graph(state)

static func _set_house_demands(state: GameState, house_id: String, demands: Array) -> void:
	var houses: Dictionary = state.map.get("houses", {})
	var house: Dictionary = houses.get(house_id, {})
	house["demands"] = demands
	houses[house_id] = house
	state.map["houses"] = houses
