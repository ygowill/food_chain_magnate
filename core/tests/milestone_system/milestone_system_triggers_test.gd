# MilestoneSystemTest module: triggers (split from milestone_system_test.gd)
extends RefCounted

const Support = preload("res://core/tests/milestone_system/milestone_system_test_support.gd")
const StateUpdaterClass = preload("res://core/state/state_updater.gd")
const EmployeeRulesClass = preload("res://core/rules/employee_rules.gd")
const RoadGraphCacheClass = preload("res://core/map/map_runtime/road_graph_cache.gd")
const CleanupSettlementClass = preload("res://modules/base_rules/rules/phase/cleanup_settlement.gd")
const PaydaySettlementClass = preload("res://modules/base_rules/rules/phase/payday_settlement.gd")
const BankruptcyRulesClass = preload("res://core/rules/economy/bankruptcy_rules.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")

static func run(seed_val: int) -> Result:
	var r := _run_all(seed_val)
	if not r.ok:
		return r
	return Result.success({"cases": 9})

static func _run_all(seed_val: int) -> Result:
	var r_multi_claim_and_cleanup := _test_multi_claim_and_cleanup(seed_val)
	if not r_multi_claim_and_cleanup.ok:
		return r_multi_claim_and_cleanup

	var r_train_triggers_first_train := _test_train_triggers_first_train(seed_val)
	if not r_train_triggers_first_train.ok:
		return r_train_triggers_first_train

	var r_lower_price_triggers_first_lower_prices := _test_lower_price_triggers_first_lower_prices(seed_val)
	if not r_lower_price_triggers_first_lower_prices.ok:
		return r_lower_price_triggers_first_lower_prices

	var r_action_milestone_failure_is_fatal := _test_action_milestone_failure_is_fatal(seed_val)
	if not r_action_milestone_failure_is_fatal.ok:
		return r_action_milestone_failure_is_fatal

	var r_produce_triggers_first_burger_produced := _test_produce_triggers_first_burger_produced(seed_val)
	if not r_produce_triggers_first_burger_produced.ok:
		return r_produce_triggers_first_burger_produced

	var r_demand_marked_triggers_first_burger_marketed := _test_demand_marked_triggers_first_burger_marketed(seed_val)
	if not r_demand_marked_triggers_first_burger_marketed.ok:
		return r_demand_marked_triggers_first_burger_marketed

	var r_recruit_triggers_first_hire_3 := _test_recruit_triggers_first_hire_3(seed_val)
	if not r_recruit_triggers_first_hire_3.ok:
		return r_recruit_triggers_first_hire_3

	var r_pay_salaries_triggers_first_pay_20_salaries := _test_pay_salaries_triggers_first_pay_20_salaries(seed_val)
	if not r_pay_salaries_triggers_first_pay_20_salaries.ok:
		return r_pay_salaries_triggers_first_pay_20_salaries

	var r_cash_reached_triggers_first_have_20_and_100 := _test_cash_reached_triggers_first_have_20_and_100(seed_val)
	if not r_cash_reached_triggers_first_have_20_and_100.ok:
		return r_cash_reached_triggers_first_have_20_and_100

	return Result.success()

static func _test_action_milestone_failure_is_fatal(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	Support._force_turn_order(state)
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = ""

	var take := StateUpdaterClass.take_from_pool(state, "pricing_manager", 1)
	if not take.ok:
		return Result.failure("从员工池取出 pricing_manager 失败: %s" % take.error)
	var add := StateUpdaterClass.add_employee(state, 0, "pricing_manager", false)
	if not add.ok:
		return Result.failure("添加 pricing_manager 失败: %s" % add.error)

	var registry = engine.ruleset_v2.milestone_effect_registry
	if registry == null:
		return Result.failure("测试前置失败：缺少 milestone_effect_registry")
	var handlers: Dictionary = registry._handlers
	if not handlers.has("base_price_delta"):
		return Result.failure("测试前置失败：缺少 base_price_delta handler")
	var handler_meta: Dictionary = handlers["base_price_delta"]
	var previous_callback: Callable = handler_meta.get("callback", Callable())
	handler_meta["callback"] = Callable()
	handlers["base_price_delta"] = handler_meta
	var round_before := str(state.round_state)
	var command_count_before := engine.command_history.size()
	var r := engine.execute_command(Command.create("set_price", 0))
	handler_meta["callback"] = previous_callback
	handlers["base_price_delta"] = handler_meta
	if r.ok:
		return Result.failure("set_price 的里程碑触发失败不应降级为 warning")
	var err := str(r.error)
	if err.find("LowerPrice") < 0 or err.find("base_price_delta") < 0:
		return Result.failure("错误信息应包含 LowerPrice 与 base_price_delta，实际: %s" % err)
	if str(engine.get_state().round_state) != round_before:
		return Result.failure("里程碑失败时不应写入 price_modifiers 或 mandatory completion")
	if engine.command_history.size() != command_count_before:
		return Result.failure("里程碑失败时不应记录命令历史")
	return Result.success()

static func _test_multi_claim_and_cleanup(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var state := engine.get_state()
	Support._force_turn_order(state)

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
	Support._force_turn_order(state)
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_TRAIN

	# 准备在岗 trainer（提供培训次数）
	var take_trainer := StateUpdaterClass.take_from_pool(state, "trainer", 1)
	if not take_trainer.ok:
		return Result.failure("从员工池取出 trainer 失败: %s" % take_trainer.error)
	var add_trainer := StateUpdaterClass.add_employee(state, 0, "trainer", false)
	if not add_trainer.ok:
		return Result.failure("添加 trainer 失败: %s" % add_trainer.error)

	# 准备待命员工（from_employee）
	var take_from := StateUpdaterClass.take_from_pool(state, "management_trainee", 1)
	if not take_from.ok:
		return Result.failure("从员工池取出 management_trainee 失败: %s" % take_from.error)
	var add_from := StateUpdaterClass.add_employee(state, 0, "management_trainee", true)
	if not add_from.ok:
		return Result.failure("添加 management_trainee 到待命区失败: %s" % add_from.error)

	var cmd := Command.create("train", 0, {
		"from_employee": "management_trainee",
		"to_employee": "new_business_developer",
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
	Support._force_turn_order(state)
	state.phase = DefsClass.PHASE_WORKING
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
	Support._force_turn_order(state)
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_GET_FOOD

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
	Support._force_turn_order(state)

	state.map = Support._build_billboard_map()
	RoadGraphCacheClass.invalidate_road_graph(state)

	# 直接注入一个 billboard 营销实例（避免依赖发起动作与员工卡），验证 Marketing 阶段 DemandMarked 触发。
	state.marketing_instances = [{
		"board_number": 11,
		"type": "billboard",
		"owner": 0,
		"employee_type": "marketing_trainee",
		"product": "burger",
		"world_pos": Vector2i(1, 2),
		"footprint_size": Vector2i.ONE,
		"rotation": 0,
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
		"footprint_size": Vector2i.ONE,
		"rotation": 0,
		"remaining_duration": 1,
		"axis": "",
		"tile_index": -1,
	}
	var take := StateUpdaterClass.take_from_pool(state, "marketing_trainee", 1)
	if not take.ok:
		return Result.failure("从员工池取出 marketing_trainee 失败: %s" % take.error)
	state.players[0]["busy_marketers"] = ["marketing_trainee"]

	state.phase = DefsClass.PHASE_PAYDAY
	state.sub_phase = ""
	var adv := engine.execute_command(Command.create_system(ActionIdsClass.ADVANCE_PHASE))
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
	Support._force_turn_order(state)
	state.phase = DefsClass.PHASE_WORKING
	state.sub_phase = DefsClass.SUB_PHASE_RECRUIT

	# 准备 hr_director（提供 4 次招聘；加上 CEO=1，总计>=3）
	var take_hr := StateUpdaterClass.take_from_pool(state, "hr_director", 1)
	if not take_hr.ok:
		return Result.failure("从员工池取出 hr_director 失败: %s" % take_hr.error)
	var add_hr := StateUpdaterClass.add_employee(state, 0, "hr_director", false)
	if not add_hr.ok:
		return Result.failure("添加 hr_director 失败: %s" % add_hr.error)

	var r1 := engine.execute_command(Command.create("recruit", 0, {"employee_type": "recruiting_girl"}))
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
	Support._force_turn_order(state)

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
	Support._force_turn_order(state)

	# 测试中可能触发“银行第一次破产”（例如 pay100 超过初始银行余额），需先伪造储备卡选择。
	for pid in range(state.players.size()):
		state.players[pid]["reserve_card_selected"] = 0
		state.players[pid]["reserve_card_revealed"] = false

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
