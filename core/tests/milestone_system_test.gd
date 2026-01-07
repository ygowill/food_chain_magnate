# 里程碑系统测试（M5 起步）
# 覆盖：同回合多名可获得（Cleanup 统一移除供给）+ 若干关键触发点（Train/LowerPrice/Produce/DemandMarked）
class_name MilestoneSystemTest
extends RefCounted

const StateUpdaterClass = preload("res://core/state/state_updater.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const MilestoneRegistryClass = preload("res://core/data/milestone_registry.gd")
const MapRuntimeClass = preload("res://core/map/map_runtime.gd")
const CleanupSettlementClass = preload("res://core/rules/phase/cleanup_settlement.gd")
const PaydaySettlementClass = preload("res://core/rules/phase/payday_settlement.gd")
const BankruptcyRulesClass = preload("res://core/rules/economy/bankruptcy_rules.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	EmployeeRegistryClass.reset()
	MilestoneRegistryClass.reset()

	if player_count != 2:
		return Result.failure("本测试目前固定为 2 人局（实际: %d）" % player_count)

	var r1 := _test_multi_claim_and_cleanup(seed_val)
	if not r1.ok:
		return r1

	var r2 := _test_train_triggers_first_train(seed_val)
	if not r2.ok:
		return r2

	var r3 := _test_lower_price_triggers_first_lower_prices(seed_val)
	if not r3.ok:
		return r3

	var r4 := _test_produce_triggers_first_burger_produced(seed_val)
	if not r4.ok:
		return r4

	var r5 := _test_demand_marked_triggers_first_burger_marketed(seed_val)
	if not r5.ok:
		return r5

	var r6 := _test_recruit_triggers_first_hire_3(seed_val)
	if not r6.ok:
		return r6

	var r7 := _test_pay_salaries_triggers_first_pay_20_salaries(seed_val)
	if not r7.ok:
		return r7

	var r8 := _test_cash_reached_triggers_first_have_20_and_100(seed_val)
	if not r8.ok:
		return r8

	var r9 := _test_chain_train_restricted_without_milestone(seed_val)
	if not r9.ok:
		return r9

	var r10 := _test_chain_train_allowed_with_milestone(seed_val)
	if not r10.ok:
		return r10

	return Result.success({
		"player_count": player_count,
		"seed": seed_val,
		"cases": 10,
	})

static func _test_multi_claim_and_cleanup(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	_force_turn_order(state)

	if not StateUpdaterClass.is_milestone_available(state, "first_train"):
		return Result.failure("first_train 应在里程碑供给中")

	var c0 := StateUpdaterClass.claim_milestone(state, 0, "first_train")
	if not c0.ok:
		return Result.failure("玩家0 领取 first_train 失败: %s" % c0.error)

	var c1 := StateUpdaterClass.claim_milestone(state, 1, "first_train")
	if not c1.ok:
		return Result.failure("玩家1 同回合领取 first_train 失败: %s" % c1.error)

	# 同回合可多名获得：在 Cleanup 前仍应保持供给可用
	if not StateUpdaterClass.is_milestone_available(state, "first_train"):
		return Result.failure("Cleanup 前 first_train 仍应可用（允许同回合多名获得）")

	# 运行 Cleanup 结算：统一从 supply 移除
	var cleanup := CleanupSettlementClass.apply(state)
	if not cleanup.ok:
		return Result.failure("CleanupSettlement 失败: %s" % cleanup.error)

	if StateUpdaterClass.is_milestone_available(state, "first_train"):
		return Result.failure("Cleanup 后 first_train 应从供给中移除")

	var m0: Array = state.players[0].get("milestones", [])
	var m1: Array = state.players[1].get("milestones", [])
	if not m0.has("first_train") or not m1.has("first_train"):
		return Result.failure("玩家0/1 都应持有 first_train，实际: p0=%s p1=%s" % [str(m0), str(m1)])

	return Result.success()

static func _test_train_triggers_first_train(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	_force_turn_order(state)
	state.phase = "Working"
	state.sub_phase = "Train"

	# 准备在岗 trainer（提供培训次数）
	var take_trainer := StateUpdaterClass.take_from_pool(state, "trainer", 1)
	if not take_trainer.ok:
		return Result.failure("从员工池取出 trainer 失败: %s" % take_trainer.error)
	var add_trainer := StateUpdaterClass.add_employee(state, 0, "trainer", false)
	if not add_trainer.ok:
		return Result.failure("添加 trainer 失败: %s" % add_trainer.error)

	# 准备待命员工（from_employee）
	var take_from := StateUpdaterClass.take_from_pool(state, "recruiter", 1)
	if not take_from.ok:
		return Result.failure("从员工池取出 recruiter 失败: %s" % take_from.error)
	var add_from := StateUpdaterClass.add_employee(state, 0, "recruiter", true)
	if not add_from.ok:
		return Result.failure("添加 recruiter 到待命区失败: %s" % add_from.error)

	var cmd := Command.create("train", 0, {
		"from_employee": "recruiter",
		"to_employee": "trainer",
	})
	var r := engine.execute_command(cmd)
	if not r.ok:
		return Result.failure("train 执行失败: %s" % r.error)

	state = engine.get_state()
	var milestones: Array = state.players[0].get("milestones", [])
	if not milestones.has("first_train"):
		return Result.failure("train 后应自动获得 first_train，实际: %s" % str(milestones))

	return Result.success()

static func _test_lower_price_triggers_first_lower_prices(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	_force_turn_order(state)
	state.phase = "Working"
	state.sub_phase = ""

	var take := StateUpdaterClass.take_from_pool(state, "pricing_manager", 1)
	if not take.ok:
		return Result.failure("从员工池取出 pricing_manager 失败: %s" % take.error)
	var add := StateUpdaterClass.add_employee(state, 0, "pricing_manager", false)
	if not add.ok:
		return Result.failure("添加 pricing_manager 失败: %s" % add.error)

	var r := engine.execute_command(Command.create("set_price", 0))
	if not r.ok:
		return Result.failure("set_price 执行失败: %s" % r.error)

	state = engine.get_state()
	var milestones: Array = state.players[0].get("milestones", [])
	if not milestones.has("first_lower_prices"):
		return Result.failure("set_price 后应自动获得 first_lower_prices，实际: %s" % str(milestones))

	return Result.success()

static func _test_produce_triggers_first_burger_produced(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	_force_turn_order(state)
	state.phase = "Working"
	state.sub_phase = "GetFood"

	var take := StateUpdaterClass.take_from_pool(state, "burger_cook", 1)
	if not take.ok:
		return Result.failure("从员工池取出 burger_cook 失败: %s" % take.error)
	var add := StateUpdaterClass.add_employee(state, 0, "burger_cook", false)
	if not add.ok:
		return Result.failure("添加 burger_cook 失败: %s" % add.error)

	var r := engine.execute_command(Command.create("produce_food", 0, {"employee_type": "burger_cook"}))
	if not r.ok:
		return Result.failure("produce_food 执行失败: %s" % r.error)

	state = engine.get_state()
	var milestones: Array = state.players[0].get("milestones", [])
	if not milestones.has("first_burger_produced"):
		return Result.failure("produce_food 后应自动获得 first_burger_produced，实际: %s" % str(milestones))

	return Result.success()

static func _test_demand_marked_triggers_first_burger_marketed(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	_force_turn_order(state)

	state.map = _build_billboard_map()
	MapRuntimeClass.invalidate_road_graph(state)

	# 直接注入一个 billboard 营销实例（避免依赖发起动作与员工卡），验证 Marketing 阶段 DemandMarked 触发。
	state.marketing_instances = [{
		"board_number": 11,
		"type": "billboard",
		"owner": 0,
		"employee_type": "marketer",
		"product": "burger",
		"world_pos": Vector2i(1, 2),
		"remaining_duration": 1,
		"axis": "",
		"tile_index": -1,
		"created_round": state.round_number,
	}]
	state.map["marketing_placements"]["11"] = {
		"board_number": 11,
		"type": "billboard",
		"owner": 0,
		"product": "burger",
		"world_pos": Vector2i(1, 2),
		"remaining_duration": 1,
		"axis": "",
		"tile_index": -1,
	}
	var take := StateUpdaterClass.take_from_pool(state, "marketer", 1)
	if not take.ok:
		return Result.failure("从员工池取出 marketer 失败: %s" % take.error)
	state.players[0]["busy_marketers"] = ["marketer"]

	state.phase = "Payday"
	state.sub_phase = ""
	var adv := engine.execute_command(Command.create_system("advance_phase"))
	if not adv.ok:
		return Result.failure("推进到 Marketing 失败: %s" % adv.error)

	state = engine.get_state()

	var milestones: Array = state.players[0].get("milestones", [])
	if not milestones.has("first_burger_marketed"):
		return Result.failure("Marketing 需求生成后应自动获得 first_burger_marketed，实际: %s" % str(milestones))

	return Result.success()

static func _test_recruit_triggers_first_hire_3(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	_force_turn_order(state)
	state.phase = "Working"
	state.sub_phase = "Recruit"

	# 准备 hr_director（提供 4 次招聘；加上 CEO=1，总计>=3）
	var take_hr := StateUpdaterClass.take_from_pool(state, "hr_director", 1)
	if not take_hr.ok:
		return Result.failure("从员工池取出 hr_director 失败: %s" % take_hr.error)
	var add_hr := StateUpdaterClass.add_employee(state, 0, "hr_director", false)
	if not add_hr.ok:
		return Result.failure("添加 hr_director 失败: %s" % add_hr.error)

	var r1 := engine.execute_command(Command.create("recruit", 0, {"employee_type": "recruiter"}))
	if not r1.ok:
		return Result.failure("recruit #1 失败: %s" % r1.error)
	var r2 := engine.execute_command(Command.create("recruit", 0, {"employee_type": "trainer"}))
	if not r2.ok:
		return Result.failure("recruit #2 失败: %s" % r2.error)
	var r3 := engine.execute_command(Command.create("recruit", 0, {"employee_type": "waitress"}))
	if not r3.ok:
		return Result.failure("recruit #3 失败: %s" % r3.error)

	state = engine.get_state()
	var milestones: Array = state.players[0].get("milestones", [])
	if not milestones.has("first_hire_3"):
		return Result.failure("第三次招聘后应获得 first_hire_3，实际: %s" % str(milestones))

	var reserve: Array = state.players[0].get("reserve_employees", [])
	var trainee_count := 0
	for emp in reserve:
		if emp is String and str(emp) == "management_trainee":
			trainee_count += 1
	if trainee_count != 2:
		return Result.failure("first_hire_3 应获得 2 张 management_trainee，实际: %d reserve=%s" % [trainee_count, str(reserve)])

	return Result.success()

static func _test_pay_salaries_triggers_first_pay_20_salaries(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	_force_turn_order(state)

	# 准备 4 名需薪员工 => base_due = 4 * salary_cost = 20
	for _i in range(4):
		var take := StateUpdaterClass.take_from_pool(state, "burger_cook", 1)
		if not take.ok:
			return Result.failure("从员工池取出 burger_cook 失败: %s" % take.error)
		var add := StateUpdaterClass.add_employee(state, 0, "burger_cook", false)
		if not add.ok:
			return Result.failure("添加 burger_cook 失败: %s" % add.error)

	var grant := StateUpdaterClass.player_receive_from_bank(state, 0, 100)
	if not grant.ok:
		return Result.failure("转入现金失败: %s" % grant.error)

	var apply := PaydaySettlementClass.apply(state, engine.phase_manager)
	if not apply.ok:
		return Result.failure("PaydaySettlement 失败: %s" % apply.error)

	var milestones: Array = state.players[0].get("milestones", [])
	if not milestones.has("first_pay_20_salaries"):
		return Result.failure("支付 $20+ 薪水后应获得 first_pay_20_salaries，实际: %s" % str(milestones))

	var multi_val = state.players[0].get("multi_trainer_on_one", null)
	if not (multi_val is bool and bool(multi_val)):
		return Result.failure("获得 first_pay_20_salaries 后 multi_trainer_on_one 应为 true，实际: %s" % str(multi_val))

	return Result.success()

static func _test_cash_reached_triggers_first_have_20_and_100(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	_force_turn_order(state)

	# 先给玩家0一个 CFO，验证 first_have_100 的 ban_card 会自动移除
	var take_cfo := StateUpdaterClass.take_from_pool(state, "cfo", 1)
	if not take_cfo.ok:
		return Result.failure("从员工池取出 cfo 失败: %s" % take_cfo.error)
	var add_cfo := StateUpdaterClass.add_employee(state, 0, "cfo", false)
	if not add_cfo.ok:
		return Result.failure("添加 cfo 失败: %s" % add_cfo.error)

	var pay20 := BankruptcyRulesClass.pay_bank_to_player(state, 0, 20, "test_cash_reached_20")
	if not pay20.ok:
		return Result.failure("发放现金失败: %s" % pay20.error)

	var milestones: Array = state.players[0].get("milestones", [])
	if not milestones.has("first_have_20"):
		return Result.failure("现金达到 $20 后应获得 first_have_20，实际: %s" % str(milestones))
	var peek_val = state.players[0].get("can_peek_all_reserve_cards", null)
	if not (peek_val is bool and bool(peek_val)):
		return Result.failure("获得 first_have_20 后 can_peek_all_reserve_cards 应为 true，实际: %s" % str(peek_val))

	var pay100 := BankruptcyRulesClass.pay_bank_to_player(state, 0, 100, "test_cash_reached_100")
	if not pay100.ok:
		return Result.failure("发放现金失败: %s" % pay100.error)

	milestones = state.players[0].get("milestones", [])
	if not milestones.has("first_have_100"):
		return Result.failure("现金达到 $100 后应获得 first_have_100，实际: %s" % str(milestones))

	# ban_card：只能对获得者禁用，且若已有则自动移除并归还供应池
	var banned: Array = state.players[0].get("banned_employee_ids", [])
	if not banned.has("cfo"):
		return Result.failure("获得 first_have_100 后 banned_employee_ids 应包含 cfo，实际: %s" % str(banned))
	var emps: Array = state.players[0].get("employees", [])
	if emps.has("cfo"):
		return Result.failure("获得 first_have_100 后应自动移除 cfo，实际 employees=%s" % str(emps))

	var start_round_val = state.players[0].get("ceo_cfo_ability_start_round", null)
	if not (start_round_val is int):
		return Result.failure("ceo_cfo_ability_start_round 类型错误（期望 int）: %s" % str(start_round_val))
	var start_round: int = int(start_round_val)
	if start_round != state.round_number + 1:
		return Result.failure("ceo_cfo_ability_start_round 不匹配: %d != %d" % [start_round, state.round_number + 1])

	# next-round：本回合不生效，下一回合开始生效
	var effect_registry = engine.phase_manager.get_effect_registry()
	if effect_registry == null:
		return Result.failure("effect_registry 为空")

	var ctx0 := {"base_gain": 100, "extra": 0, "once": {}}
	var e0 = effect_registry.invoke("base_rules:dinnertime:income_bonus:ceo_get_cfo", [state, 0, ctx0])
	if not e0.ok:
		return Result.failure("invoke income_bonus:ceo_get_cfo 失败: %s" % e0.error)
	if int(ctx0.get("extra", -1)) != 0:
		return Result.failure("本回合不应获得 CFO 加成，实际 extra=%s" % str(ctx0.get("extra", null)))

	var old_round: int = state.round_number
	state.round_number = start_round
	var ctx1 := {"base_gain": 100, "extra": 0, "once": {}}
	var e1 = effect_registry.invoke("base_rules:dinnertime:income_bonus:ceo_get_cfo", [state, 0, ctx1])
	state.round_number = old_round
	if not e1.ok:
		return Result.failure("invoke income_bonus:ceo_get_cfo 失败: %s" % e1.error)

	var bonus_percent := state.get_rule_int("cfo_bonus_percent")
	var denom := 100
	var expected_extra := int((100 * bonus_percent + denom - 1) / denom)
	if int(ctx1.get("extra", -1)) != expected_extra:
		return Result.failure("下一回合 CFO 加成不匹配: %d != %d" % [int(ctx1.get("extra", -1)), expected_extra])

	return Result.success()

static func _test_chain_train_restricted_without_milestone(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	_force_turn_order(state)
	state.phase = "Working"
	state.sub_phase = "Train"

	# 2 名 trainer => 2 次培训
	for _i in range(2):
		var take_trainer := StateUpdaterClass.take_from_pool(state, "trainer", 1)
		if not take_trainer.ok:
			return Result.failure("从员工池取出 trainer 失败: %s" % take_trainer.error)
		var add_trainer := StateUpdaterClass.add_employee(state, 0, "trainer", false)
		if not add_trainer.ok:
			return Result.failure("添加 trainer 失败: %s" % add_trainer.error)

	# 待命 recruiter
	var take_from := StateUpdaterClass.take_from_pool(state, "recruiter", 1)
	if not take_from.ok:
		return Result.failure("从员工池取出 recruiter 失败: %s" % take_from.error)
	var add_from := StateUpdaterClass.add_employee(state, 0, "recruiter", true)
	if not add_from.ok:
		return Result.failure("添加 recruiter 到待命区失败: %s" % add_from.error)

	var t1 := engine.execute_command(Command.create("train", 0, {"from_employee": "recruiter", "to_employee": "trainer"}))
	if not t1.ok:
		return Result.failure("train #1 失败: %s" % t1.error)

	# 默认：不能继续培训本子阶段新培训得到的员工（trainer）
	var t2 := engine.execute_command(Command.create("train", 0, {"from_employee": "trainer", "to_employee": "recruiter"}))
	if t2.ok:
		return Result.failure("默认规则下不应允许链式培训（trainer -> recruiter）")

	return Result.success()

static func _test_chain_train_allowed_with_milestone(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	_force_turn_order(state)
	state.phase = "Working"
	state.sub_phase = "Train"
	state.players[0]["multi_trainer_on_one"] = true

	for _i in range(2):
		var take_trainer := StateUpdaterClass.take_from_pool(state, "trainer", 1)
		if not take_trainer.ok:
			return Result.failure("从员工池取出 trainer 失败: %s" % take_trainer.error)
		var add_trainer := StateUpdaterClass.add_employee(state, 0, "trainer", false)
		if not add_trainer.ok:
			return Result.failure("添加 trainer 失败: %s" % add_trainer.error)

	var take_from := StateUpdaterClass.take_from_pool(state, "recruiter", 1)
	if not take_from.ok:
		return Result.failure("从员工池取出 recruiter 失败: %s" % take_from.error)
	var add_from := StateUpdaterClass.add_employee(state, 0, "recruiter", true)
	if not add_from.ok:
		return Result.failure("添加 recruiter 到待命区失败: %s" % add_from.error)

	var t1 := engine.execute_command(Command.create("train", 0, {"from_employee": "recruiter", "to_employee": "trainer"}))
	if not t1.ok:
		return Result.failure("train #1 失败: %s" % t1.error)
	var t2 := engine.execute_command(Command.create("train", 0, {"from_employee": "trainer", "to_employee": "recruiter"}))
	if not t2.ok:
		return Result.failure("multi_trainer_on_one=true 时应允许链式培训，实际: %s" % t2.error)

	return Result.success()

static func _force_turn_order(state: GameState) -> void:
	state.turn_order = [0, 1]
	state.current_player_index = 0

static func _build_billboard_map() -> Dictionary:
	var grid_size := Vector2i(3, 3)
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

	# 房屋放在 (1,1)，billboard 放在 (1,2) 时会影响 (1,1)
	cells[1][1]["structure"] = {
		"piece_id": "house",
		"house_id": "house_1",
		"house_number": 1,
		"has_garden": false,
		"dynamic": true
	}

	var houses := {
		"house_1": {
			"house_id": "house_1",
			"house_number": 1,
			"anchor_pos": Vector2i(1, 1),
			"cells": [Vector2i(1, 1)],
			"has_garden": false,
			"is_apartment": false,
			"printed": false,
			"owner": -1,
			"demands": []
		}
	}

	return {
		"grid_size": grid_size,
		"tile_grid_size": Vector2i(1, 1),
		"cells": cells,
		"houses": houses,
		"restaurants": {},
		"drink_sources": [],
		"next_house_number": 2,
		"next_restaurant_id": 1,
		"boundary_index": {},
		"marketing_placements": {}
	}
