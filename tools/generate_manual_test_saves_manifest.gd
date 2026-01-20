extends RefCounted

# 手工复核存档（员工/里程碑）场景清单
#
# 约定：
# - 每个员工/里程碑至少 1 个 case；每个 case 会生成同名 JSON+MD。
# - steps/expected 允许偏“操作指引”，详细测试点请对照 `docs/manual_test_saves_plan.md`。

const DEFAULT_PLAYER_COUNT := 2
const DEFAULT_SEED := 12345

static func get_cases() -> Array[Dictionary]:
	var cases: Array[Dictionary] = []

	# === 阶段A：示例（保留） ===
	cases.append(_case({
		"kind": "employee",
		"id": "kitchen_trainee",
		"title": "见习厨师（kitchen_trainee）",
		"enabled_modules": [],
		"builder": "employee_kitchen_trainee_get_food",
		"purpose": "验证 produce_food 对“多选生产”员工的参数校验与库存变化。",
		"steps": [
			"载入后应处于 Working/GetFood，且玩家 0 在岗包含 kitchen_trainee。",
			"行动面板选择「生产食物」。",
			"选择 employee_type=kitchen_trainee，并选择 food_type=burger（或 pizza），确认执行。",
		],
		"expected": [
			"玩家 0 库存 burger +1（或 pizza +1）。",
			"同一子阶段再次对同一 kitchen_trainee 执行 produce_food 应提示次数耗尽。",
		],
		"related_tests": [
			"core/tests/produce_food_test.gd",
		],
	}))

	cases.append(_case({
		"kind": "employee",
		"id": "marketing_trainee",
		"title": "营销实习生（marketing_trainee）",
		"enabled_modules": [],
		"builder": "employee_marketing_trainee_billboard",
		"builder_params": {
			"board_number": 14,
			"product": "burger",
			"duration": 1,
		},
		"purpose": "验证 initiate_marketing(billboard) 的可用性、距离限制与放置合法性。",
		"steps": [
			"载入后应处于 Working/Marketing，且玩家 0 在岗包含 marketing_trainee，并已拥有至少 1 家餐厅。",
			"行动面板选择「发起营销」。",
			"选择 employee_type=marketing_trainee，board_number=14（billboard），product=burger，duration=1，并按说明文件中的推荐坐标放置。",
		],
		"expected": [
			"营销板件成功放置，marketing_trainee 进入 busy_marketers；并在 state.map.marketing_placements 占用 board_number。",
			"若放在错误位置（非贴边/超距/占地冲突），应给出明确拒绝原因。",
		],
		"related_tests": [
			"core/tests/marketing_campaigns_test.gd",
			"core/tests/new_milestones_marketing_trainee_v2_test.gd",
		],
	}))

	cases.append(_case({
		"kind": "milestone",
		"id": "first_lower_prices",
		"title": "首个降价（first_lower_prices）",
		"enabled_modules": [],
		"builder": "milestone_first_lower_prices",
		"purpose": "验证 set_price 会触发 first_lower_prices，并写入 round_state.price_modifiers。",
		"steps": [
			"载入后应处于 Working 阶段，且玩家 0 在岗包含 pricing_manager（定价经理）。",
			"行动面板选择强制动作「设定价格（-$1）」并执行。",
		],
		"expected": [
			"玩家 0 获得里程碑 first_lower_prices（player.milestones）。",
			"state.round_state.price_modifiers[0][pricing_manager] == -1。",
		],
		"related_tests": [
			"core/tests/milestone_system_test.gd",
			"core/tests/milestone_effect_values_test.gd",
			"core/tests/mandatory_actions_test.gd",
		],
	}))

	cases.append(_case({
		"kind": "milestone",
		"id": "first_train",
		"title": "首个培训员工（first_train）",
		"enabled_modules": [],
		"builder": "milestone_first_train",
		"builder_params": {
			"from_employee": "management_trainee",
			"to_employee": "new_business_developer",
		},
		"purpose": "验证 train 会触发 first_train，并在后续 Payday 永久降低薪资总额（salary_total_delta=-15）。",
		"steps": [
			"载入后应处于 Working/Train，且玩家 0 在岗包含 trainer；待命区 reserve_employees 包含 management_trainee。",
			"行动面板选择「培训」，将 management_trainee 培训为 new_business_developer 并执行。",
		],
		"expected": [
			"玩家 0 获得里程碑 first_train（player.milestones）。",
			"培训后：management_trainee 从 reserve_employees 移除；new_business_developer 加入 reserve_employees。",
			"（后续回合验证）进入 Payday 时，薪资总额应永久 -15（最低到 0）。",
		],
		"related_tests": [
			"core/tests/milestone_system_test.gd",
			"core/tests/payday_salary_test.gd",
		],
	}))

	# === 里程碑：base_milestones ===
	cases.append(_case({
		"kind": "milestone",
		"id": "first_billboard",
		"title": "首个放置广告牌（first_billboard）",
		"enabled_modules": [],
		"builder": "milestone_first_billboard",
		"builder_params": {
			"employee_type": "marketing_trainee",
			"board_number": 14,
			"product": "burger",
			"duration": 1,
		},
		"purpose": "验证 InitiateMarketing(type=billboard) 会触发里程碑 first_billboard。",
		"steps": [
			"载入后应处于 Working/Marketing，且玩家 0 在岗包含 marketing_trainee。",
			"行动面板选择「发起营销」，按推荐参数放置 billboard #14。",
		],
		"expected": [
			"玩家 0 获得里程碑 first_billboard（player.milestones）。",
			"state.map.marketing_placements['14'].type == 'billboard'。",
		],
		"related_tests": [
			"core/tests/marketing_campaigns_test.gd",
		],
	}))

	cases.append(_case({
		"kind": "milestone",
		"id": "first_airplane",
		"title": "首个进行飞机营销（first_airplane）",
		"enabled_modules": [],
		"builder": "milestone_first_airplane",
		"builder_params": {
			"employee_type": "brand_manager",
			"board_number": 4,
			"product": "beer",
			"duration": 1,
		},
		"purpose": "验证 InitiateMarketing(type=airplane) 会触发里程碑 first_airplane。",
		"steps": [
			"载入后应处于 Working/Marketing，且玩家 0 在岗包含 brand_manager。",
			"行动面板选择「发起营销」，按推荐参数放置 airplane #4。",
		],
		"expected": [
			"玩家 0 获得里程碑 first_airplane（player.milestones）。",
			"state.map.marketing_placements['4'].type == 'airplane'。",
		],
		"related_tests": [
			"core/tests/marketing_campaigns_test.gd",
		],
	}))

	cases.append(_case({
		"kind": "milestone",
		"id": "first_radio",
		"title": "首个进行电波营销（first_radio）",
		"enabled_modules": [],
		"builder": "milestone_first_radio",
		"builder_params": {
			"employee_type": "brand_director",
			"board_number": 1,
			"product": "burger",
			"duration": 1,
		},
		"purpose": "验证 InitiateMarketing(type=radio) 会触发里程碑 first_radio。",
		"steps": [
			"载入后应处于 Working/Marketing，且玩家 0 在岗包含 brand_director。",
			"行动面板选择「发起营销」，按推荐参数放置 radio #1。",
		],
		"expected": [
			"玩家 0 获得里程碑 first_radio（player.milestones）。",
			"state.map.marketing_placements['1'].type == 'radio'。",
		],
		"related_tests": [
			"core/tests/marketing_campaigns_test.gd",
		],
	}))

	cases.append(_case({
		"kind": "milestone",
		"id": "first_burger_produced",
		"title": "首个生产汉堡（first_burger_produced）",
		"enabled_modules": [],
		"builder": "milestone_first_burger_produced",
		"builder_params": {"employee_type": "burger_cook"},
		"purpose": "验证 Produce(product=burger) 会触发里程碑 first_burger_produced。",
		"steps": [
			"载入后应处于 Working/GetFood，且玩家 0 在岗包含 burger_cook。",
			"行动面板选择「生产食物」并执行（employee_type=burger_cook）。",
		],
		"expected": [
			"玩家 0 获得里程碑 first_burger_produced（player.milestones）。",
			"玩家 0 库存 burger 增加。",
		],
		"related_tests": [
			"core/tests/milestone_system_test.gd",
			"core/tests/produce_food_test.gd",
		],
	}))

	cases.append(_case({
		"kind": "milestone",
		"id": "first_pizza_produced",
		"title": "首个生产披萨（first_pizza_produced）",
		"enabled_modules": [],
		"builder": "milestone_first_pizza_produced",
		"builder_params": {"employee_type": "pizza_cook"},
		"purpose": "验证 Produce(product=pizza) 会触发里程碑 first_pizza_produced。",
		"steps": [
			"载入后应处于 Working/GetFood，且玩家 0 在岗包含 pizza_cook。",
			"行动面板选择「生产食物」并执行（employee_type=pizza_cook）。",
		],
		"expected": [
			"玩家 0 获得里程碑 first_pizza_produced（player.milestones）。",
			"玩家 0 库存 pizza 增加。",
		],
		"related_tests": [
			"core/tests/produce_food_test.gd",
		],
	}))

	cases.append(_case({
		"kind": "milestone",
		"id": "first_burger_marketed",
		"title": "首个营销汉堡（first_burger_marketed）",
		"enabled_modules": [],
		"builder": "milestone_first_burger_marketed",
		"purpose": "验证 Marketing 结算产生需求时，会触发 DemandMarked(product=burger)。",
		"steps": [
			"载入后应处于 Payday 阶段。",
			"点击「推进阶段」进入 Marketing（会自动结算并跳过到下一可停留阶段）。",
		],
		"expected": [
			"玩家 0 获得里程碑 first_burger_marketed（player.milestones）。",
			"state.map.houses['house_1'].demands 应新增 product=burger 的需求。",
		],
		"related_tests": [
			"core/tests/milestone_system_test.gd",
		],
	}))

	cases.append(_case({
		"kind": "milestone",
		"id": "first_drink_marketed",
		"title": "首个营销饮料（first_drink_marketed）",
		"enabled_modules": [],
		"builder": "milestone_first_drink_marketed",
		"purpose": "验证 Marketing 结算产生饮料需求时，会触发 DemandMarked(product=drink)。",
		"steps": [
			"载入后应处于 Payday 阶段。",
			"点击「推进阶段」进入 Marketing（会自动结算并跳过到下一可停留阶段）。",
		],
		"expected": [
			"玩家 0 获得里程碑 first_drink_marketed（player.milestones）。",
			"state.map.houses['house_1'].demands 应新增 product=soda 的需求（里程碑按 drink 归一化）。",
		],
		"related_tests": [
			"core/rules/phase/marketing_settlement.gd",
		],
	}))

	cases.append(_case({
		"kind": "milestone",
		"id": "first_pizza_marketed",
		"title": "首个营销披萨（first_pizza_marketed）",
		"enabled_modules": [],
		"builder": "milestone_first_pizza_marketed",
		"purpose": "验证 Marketing 结算产生披萨需求时，会触发 DemandMarked(product=pizza)。",
		"steps": [
			"载入后应处于 Payday 阶段。",
			"点击「推进阶段」进入 Marketing（会自动结算并跳过到下一可停留阶段）。",
		],
		"expected": [
			"玩家 0 获得里程碑 first_pizza_marketed（player.milestones）。",
			"state.map.houses['house_1'].demands 应新增 product=pizza 的需求。",
		],
		"related_tests": [
			"core/rules/phase/marketing_settlement.gd",
		],
	}))

	cases.append(_case({
		"kind": "milestone",
		"id": "first_hire_3",
		"title": "首个一回合雇佣三人（first_hire_3）",
		"enabled_modules": [],
		"builder": "milestone_first_hire_3",
		"builder_params": {"employee_type": "hr_director", "recruit_target": "waitress"},
		"purpose": "验证 Recruit 子阶段第 3 次 recruit 会触发 first_hire_3，并获得 2 张 management_trainee。",
		"steps": [
			"载入后应处于 Working/Recruit，且玩家 0 在岗包含 hr_director。",
			"依次执行 3 次「招聘」（任意 entry_level 员工均可）。",
		],
		"expected": [
			"第 3 次 recruit 后：玩家 0 获得里程碑 first_hire_3（player.milestones）。",
			"玩家 0 reserve_employees 新增 2 张 management_trainee。",
		],
		"related_tests": [
			"core/tests/milestone_system_test.gd",
		],
	}))

	cases.append(_case({
		"kind": "milestone",
		"id": "first_pay_20_salaries",
		"title": "首个支付$20+薪水（first_pay_20_salaries）",
		"enabled_modules": [],
		"builder": "milestone_first_pay_20_salaries",
		"purpose": "验证离开 Payday 时若实际支付 paid>=20，会触发 first_pay_20_salaries（multi_trainer_on_one=true）。",
		"steps": [
			"载入后应处于 Payday 阶段（玩家 0 已准备 4 名需薪员工与足够现金）。",
			"点击「推进阶段」离开 Payday（会自动计算薪资并继续推进）。",
		],
		"expected": [
			"玩家 0 获得里程碑 first_pay_20_salaries（player.milestones）。",
			"玩家 0 multi_trainer_on_one == true。",
			"state.round_state.payday.details[0].paid >= 20。",
		],
		"related_tests": [
			"core/tests/milestone_system_test.gd",
			"core/tests/payday_salary_test.gd",
		],
	}))

	cases.append(_case({
		"kind": "milestone",
		"id": "first_have_20",
		"title": "首个拥有$20（first_have_20）",
		"enabled_modules": [],
		"builder": "milestone_first_have_20",
		"purpose": "验证 pay_bank_to_player 后 cash>=20 会触发 first_have_20。",
		"steps": [
			"载入后应处于 Working/PlaceRestaurants，且本回合已准备好一笔晚餐收入（cash 约为 15）。",
			"点击「推进子阶段」离开 Working：进入晚餐结算后会自动跳到 Payday。",
		],
		"expected": [
			"玩家 0 获得里程碑 first_have_20（player.milestones）。",
			"玩家 0 现金应 >= 20。",
		],
		"related_tests": [
			"core/tests/milestone_system_test.gd",
		],
	}))

	cases.append(_case({
		"kind": "milestone",
		"id": "first_have_100",
		"title": "首个拥有$100（first_have_100）",
		"enabled_modules": [],
		"builder": "milestone_first_have_100",
		"purpose": "验证 pay_bank_to_player 后 cash>=100 会触发 first_have_100（可能同时触发 first_have_20）。",
		"steps": [
			"载入后应处于 Working/PlaceRestaurants，且本回合已准备好一笔晚餐收入（cash 约为 95）。",
			"点击「推进子阶段」离开 Working：进入晚餐结算后会自动跳到 Payday。",
		],
		"expected": [
			"玩家 0 获得里程碑 first_have_100（player.milestones）。",
			"玩家 0 现金应 >= 100。",
		],
		"related_tests": [
			"core/tests/milestone_system_test.gd",
		],
	}))

	cases.append(_case({
		"kind": "milestone",
		"id": "first_throw_away",
		"title": "首个丢弃食物/饮品（first_throw_away）",
		"enabled_modules": [],
		"builder": "milestone_first_throw_away",
		"purpose": "验证进入 Cleanup 时若有库存被清空，会触发 CleanupDiscard -> first_throw_away。",
		"steps": [
			"载入后应处于 Payday 阶段，且玩家 0 库存包含 burger/soda。",
			"点击「推进阶段」离开 Payday（Marketing/Cleanup 会自动结算并跳过）。",
		],
		"expected": [
			"玩家 0 获得里程碑 first_throw_away（player.milestones）。",
			"进入 Cleanup 后库存被清空（无冰箱）。",
		],
		"related_tests": [
			"core/rules/phase/cleanup_settlement.gd",
			"core/tests/cleanup_inventory_test.gd",
		],
	}))

	cases.append(_case({
		"kind": "milestone",
		"id": "first_waitress",
		"title": "首个使用女服务员（first_waitress）",
		"enabled_modules": [],
		"builder": "milestone_first_waitress",
		"purpose": "验证晚餐结算时 UseEmployee(waitress) 会触发 first_waitress，并将 tips 提升到 5。",
		"steps": [
			"载入后应处于 Working/PlaceRestaurants，且玩家 0 在岗包含 waitress。",
			"点击「推进子阶段」离开 Working：进入晚餐结算后会自动跳到 Payday。",
		],
		"expected": [
			"玩家 0 获得里程碑 first_waitress（player.milestones）。",
			"本次晚餐 tips 应按 5 计算（可在 dinnertime 报告或 cash 变化中观察）。",
		],
		"related_tests": [
			"core/tests/dinnertime_settlement_test.gd",
		],
	}))

	cases.append(_case({
		"kind": "milestone",
		"id": "first_cart_operator",
		"title": "首个打出手推车操作员（first_cart_operator）",
		"enabled_modules": [],
		"builder": "milestone_first_cart_operator",
		"builder_params": {"employee_type": "cart_operator"},
		"purpose": "验证 procure_drinks 会触发 UseEmployee(cart_operator) -> first_cart_operator。",
		"steps": [
			"载入后应处于 Working/GetDrinks，且玩家 0 在岗包含 cart_operator。",
			"行动面板选择「采购饮料」，在地图上点选饮料源生成路线并执行。",
		],
		"expected": [
			"玩家 0 获得里程碑 first_cart_operator（player.milestones）。",
		],
		"related_tests": [
			"core/tests/procure_drinks_test.gd",
			"core/tests/procure_drinks_route_rules_test.gd",
		],
	}))

	cases.append(_case({
		"kind": "milestone",
		"id": "first_errand_boy",
		"title": "首个打出跑腿伙计（first_errand_boy）",
		"enabled_modules": [],
		"builder": "milestone_first_errand_boy",
		"builder_params": {"drink_type": "soda"},
		"purpose": "验证 errand_boy 的 procure_drinks 会触发 UseEmployee(errand_boy) -> first_errand_boy。",
		"steps": [
			"载入后应处于 Working/GetDrinks，且玩家 0 在岗包含 errand_boy。",
			"行动面板选择「采购饮料」，选择 employee_type=errand_boy drink_type=soda 并执行。",
		],
		"expected": [
			"玩家 0 获得里程碑 first_errand_boy（player.milestones）。",
			"玩家 0 库存 soda +1。",
		],
		"related_tests": [
			"core/tests/procure_drinks_route_rules_test.gd",
		],
	}))

	# === 里程碑：ketchup_mechanism ===
	cases.append(_case({
		"kind": "milestone",
		"id": "ketchup_sold_your_demand",
		"title": "有人卖了你的需求（ketchup_sold_your_demand）",
		"enabled_modules": ["ketchup_mechanism"],
		"builder": "milestone_ketchup_sold_your_demand",
		"purpose": "验证“他人卖出你营销产生的需求”后，你会在晚餐结算结束时获得番茄酱里程碑。",
		"steps": [
			"载入后应处于 Working/PlaceRestaurants（已预置：玩家 1 会卖出玩家 0 的 burger 需求）。",
			"点击「推进子阶段」离开 Working（晚餐会自动结算并跳到 Payday）。",
		],
		"expected": [
			"玩家 0 获得里程碑 ketchup_sold_your_demand（player.milestones）。",
			"该里程碑提供番茄酱效果：晚餐距离 -1（clamp 到 0）。",
		],
		"related_tests": [
			"core/tests/ketchup_mechanism_v2_test.gd",
		],
	}))

	# === 里程碑：lobbyists ===
	cases.append(_case({
		"kind": "milestone",
		"id": "first_lobbyist_used",
		"title": "首个使用说客（first_lobbyist_used）",
		"enabled_modules": ["lobbyists"],
		"builder": "milestone_first_lobbyist_used",
		"purpose": "验证 Lobbyists 子阶段放置道路会触发 first_lobbyist_used，并为该玩家生成 extra tile 放置权限。",
		"steps": [
			"载入后应处于 Working/Lobbyists，且玩家 0 在岗包含 lobbyist。",
			"按说明文件的推荐参数执行「放置道路（说客）」动作（place_lobbyists_road）。",
		],
		"expected": [
			"玩家 0 获得里程碑 first_lobbyist_used（player.milestones）。",
			"round_state.lobbyists_extra_tile_pending[0] == true（随后可执行 place_lobbyists_extra_map_tile）。",
		],
		"related_tests": [
			"core/tests/lobbyists_v2_test.gd",
		],
	}))

	# === 里程碑：rural_marketeers ===
	cases.append(_case({
		"kind": "milestone",
		"id": "first_rural_marketeer_used",
		"title": "首个使用乡村营销员（first_rural_marketeer_used）",
		"enabled_modules": ["rural_marketeers"],
		"builder": "milestone_first_rural_marketeer_used",
		"builder_params": {"side": "N", "product": "burger"},
		"purpose": "验证放置巨型广告牌会触发 first_rural_marketeer_used，并生成 offramp pending。",
		"steps": [
			"载入后应处于 Working/Marketing，且玩家 0 在岗包含 rural_marketeer。",
			"执行「放置巨型广告牌（place_giant_billboard）」动作（side=N product=burger）。",
		],
		"expected": [
			"玩家 0 获得里程碑 first_rural_marketeer_used（player.milestones）。",
			"round_state.rural_marketeers_offramp_pending[0] == true。",
		],
		"related_tests": [
			"core/tests/rural_marketeers_v2_test.gd",
		],
	}))

	# === 里程碑：new_milestones（注意：该模块与 base_milestones 冲突） ===
	cases.append(_case({
		"kind": "milestone",
		"id": "first_marketing_trainee_used",
		"title": "首个使用营销实习生（first_marketing_trainee_used）",
		"enabled_modules": ["new_milestones"],
		"exclude_modules": ["base_milestones"],
		"builder": "milestone_first_marketing_trainee_used",
		"builder_params": {"employee_type": "marketing_trainee", "board_number": 11, "product": "burger", "duration": 1},
		"purpose": "验证 marketing_trainee 发起营销会触发里程碑，并获得 kitchen_trainee + errand_boy 各 1 张。",
		"steps": [
			"载入后应处于 Working/Marketing，且玩家 0 在岗包含 marketing_trainee。",
			"执行「发起营销」并放置 billboard #11（参数见推荐）。",
		],
		"expected": [
			"玩家 0 获得里程碑 first_marketing_trainee_used（player.milestones）。",
			"玩家 0 reserve_employees 新增 kitchen_trainee 与 errand_boy。",
			"（可能同时获得 first_marketeer_used，这是正常的）。",
		],
		"related_tests": [
			"core/tests/new_milestones_marketing_trainee_v2_test.gd",
		],
	}))

	cases.append(_case({
		"kind": "milestone",
		"id": "first_campaign_manager_used",
		"title": "首个使用营销经理（first_campaign_manager_used）",
		"enabled_modules": ["new_milestones"],
		"exclude_modules": ["base_milestones"],
		"builder": "milestone_first_campaign_manager_used",
		"builder_params": {"employee_type": "campaign_manager", "board_number": 7, "product": "burger", "duration": 1},
		"purpose": "验证 campaign_manager 发起营销会触发里程碑，并在同回合允许放置第二张同类型板件。",
		"steps": [
			"载入后应处于 Working/Marketing，且玩家 0 在岗包含 campaign_manager。",
			"执行「发起营销」放置 mailbox #7（参数见推荐）。",
			"同回合应出现动作 place_campaign_manager_second_tile：选择 board_number=8 并放置第二张同类型板件。",
		],
		"expected": [
			"玩家 0 获得里程碑 first_campaign_manager_used（player.milestones）。",
			"第二张板件放置成功；campaign_manager 应保持 busy，直到两张板件都到期后才返回。",
		],
		"related_tests": [
			"core/tests/new_milestones_campaign_manager_v2_test.gd",
		],
	}))

	cases.append(_case({
		"kind": "milestone",
		"id": "first_brand_manager_used",
		"title": "首个使用品牌经理（first_brand_manager_used）",
		"enabled_modules": ["new_milestones"],
		"exclude_modules": ["base_milestones"],
		"builder": "milestone_first_brand_manager_used",
		"builder_params": {"employee_type": "brand_manager", "board_number": 4, "product": "beer", "duration": 1},
		"purpose": "验证 brand_manager 放置 airplane 会触发里程碑，并允许同回合追加第二种商品。",
		"steps": [
			"载入后应处于 Working/Marketing，且玩家 0 在岗包含 brand_manager。",
			"执行「发起营销」放置 airplane #4（参数见推荐）。",
			"同回合执行动作 set_brand_manager_airplane_second_good，设置 product_b=burger。",
		],
		"expected": [
			"玩家 0 获得里程碑 first_brand_manager_used（player.milestones）。",
			"追加第二种商品成功（同回合仅一次）。",
		],
		"related_tests": [
			"core/tests/new_milestones_brand_manager_v2_test.gd",
		],
	}))

	cases.append(_case({
		"kind": "milestone",
		"id": "first_brand_director_used",
		"title": "首个使用品牌总监（first_brand_director_used）",
		"enabled_modules": ["new_milestones"],
		"exclude_modules": ["base_milestones"],
		"builder": "milestone_first_brand_director_used",
		"builder_params": {"employee_type": "brand_director", "board_number": 1, "product": "soda", "duration": 1},
		"purpose": "验证 brand_director 发起营销会触发里程碑：radio 永久（duration=-1），且 brand_director 忙碌到游戏结束。",
		"steps": [
			"载入后应处于 Working/Marketing，且玩家 0 在岗包含 brand_director。",
			"执行「发起营销」放置 radio #1（参数见推荐）。",
		],
		"expected": [
			"玩家 0 获得里程碑 first_brand_director_used（player.milestones）。",
			"该 radio 的 remaining_duration 应为 -1，且 brand_director 应保持 busy（不会因到期返回）。",
		],
		"related_tests": [
			"core/tests/new_milestones_brand_director_v2_test.gd",
		],
	}))

	cases.append(_case({
		"kind": "milestone",
		"id": "first_marketeer_used",
		"title": "首个使用营销员（first_marketeer_used）",
		"enabled_modules": ["new_milestones"],
		"exclude_modules": ["base_milestones"],
		"builder": "milestone_first_marketeer_used",
		"builder_params": {"employee_type": "campaign_manager", "board_number": 7, "product": "burger", "duration": 1},
		"purpose": "验证首次使用任意营销员发起营销会触发 first_marketeer_used（Marketing 每放 1 个需求 +$5；Dinnertime distance -2 可为负）。",
		"steps": [
			"载入后应处于 Working/Marketing，且玩家 0 在岗包含 campaign_manager。",
			"执行「发起营销」放置 mailbox #7（参数见推荐）。",
			"（可选）推进到 Marketing/Dinnertime 结算，观察 cash +5/需求与负距离逻辑。",
		],
		"expected": [
			"玩家 0 获得里程碑 first_marketeer_used（player.milestones）。",
		],
		"related_tests": [
			"core/tests/new_milestones_v2_test.gd",
		],
	}))

	cases.append(_case({
		"kind": "milestone",
		"id": "first_trainer_used",
		"title": "首个使用培训讲师（first_trainer_used）",
		"enabled_modules": ["new_milestones"],
		"exclude_modules": ["base_milestones"],
		"builder": "milestone_first_trainer_used",
		"builder_params": {"trainer_type": "trainer", "from_employee": "management_trainee", "to_employee": "new_business_developer"},
		"purpose": "验证 train 会推导 UseEmployee(trainer) 并触发里程碑；效果包含 gain_card(trainer) 与允许欠薪离开 Payday。",
		"steps": [
			"载入后应处于 Working/Train，且玩家 0 在岗包含 trainer；reserve_employees 包含 management_trainee。",
			"执行 train(management_trainee -> new_business_developer)。",
		],
		"expected": [
			"玩家 0 获得里程碑 first_trainer_used（player.milestones）。",
			"玩家 0 reserve_employees 应新增 1 张 trainer（gain_card）。",
		],
		"related_tests": [
			"core/tests/new_milestones_beer_trainer_payday_v2_test.gd",
		],
	}))

	cases.append(_case({
		"kind": "milestone",
		"id": "first_recruiting_girl_used",
		"title": "首个使用人力资源专员（first_recruiting_girl_used）",
		"enabled_modules": ["new_milestones"],
		"exclude_modules": ["base_milestones"],
		"builder": "milestone_first_recruiting_girl_used",
		"builder_params": {"employee_type": "recruiting_girl", "recruit_target": "waitress"},
		"purpose": "验证 recruiting_girl 的 recruit 容量在第 2 次招聘时必然被推导使用，从而触发里程碑并获得 executive_vice_president（永久免薪）。",
		"steps": [
			"载入后应处于 Working/Recruit，且玩家 0 在岗包含 recruiting_girl。",
			"连续执行 2 次 recruit（任意入门级员工均可）。",
		],
		"expected": [
			"第 2 次 recruit 后：玩家 0 获得里程碑 first_recruiting_girl_used（player.milestones）。",
			"玩家 0 reserve_employees 新增 executive_vice_president，且其永久免薪。",
		],
		"related_tests": [
			"core/tests/new_milestones_recruiter_waitress_v2_test.gd",
		],
	}))

	cases.append(_case({
		"kind": "milestone",
		"id": "first_discount_manager_used",
		"title": "首个使用折扣经理（first_discount_manager_used）",
		"enabled_modules": ["new_milestones"],
		"exclude_modules": ["base_milestones"],
		"builder": "milestone_first_discount_manager_used",
		"builder_params": {"employee_type": "discount_manager", "action_id": "set_discount"},
		"purpose": "验证 set_discount 会触发里程碑，并在下一回合 Restructuring 结束扣除银行 $100。",
		"steps": [
			"载入后应处于 Working 阶段，且玩家 0 在岗包含 discount_manager。",
			"执行强制动作 set_discount（-$3）。",
			"（后续）进入下一回合 Restructuring 并推进离开，观察 bank.total -100，且 bank_burn_pending 被清除。",
		],
		"expected": [
			"玩家 0 获得里程碑 first_discount_manager_used（player.milestones），且 bank_burn_pending=true。",
		],
		"related_tests": [
			"core/tests/new_milestones_discount_manager_bank_burn_v2_test.gd",
		],
	}))

	cases.append(_case({
		"kind": "milestone",
		"id": "first_cart_operator_used",
		"title": "首个使用手推车操作员（first_cart_operator_used）",
		"enabled_modules": ["new_milestones"],
		"exclude_modules": ["base_milestones"],
		"builder": "milestone_first_cart_operator_used",
		"builder_params": {"employee_type": "cart_operator"},
		"purpose": "验证 procure_drinks 会触发 UseEmployee(cart_operator) 并获得里程碑（不同采购员每源+饮料数量增量）。",
		"steps": [
			"载入后应处于 Working/GetDrinks，且玩家 0 在岗包含 cart_operator。",
			"执行「采购饮料」并在地图上选择饮料来源生成路线后确认执行。",
		],
		"expected": [
			"玩家 0 获得里程碑 first_cart_operator_used（player.milestones）。",
		],
		"related_tests": [
			"core/tests/procure_drinks_test.gd",
		],
	}))

	cases.append(_case({
		"kind": "milestone",
		"id": "first_waitress_used",
		"title": "首个使用女服务员（first_waitress_used）",
		"enabled_modules": ["new_milestones"],
		"exclude_modules": ["base_milestones"],
		"builder": "milestone_first_waitress_used",
		"purpose": "验证晚餐结算触发 UseEmployee(waitress) -> first_waitress_used，并将该玩家薪水改为每人 $3。",
		"steps": [
			"载入后应处于 Working/PlaceRestaurants，且玩家 0 在岗包含 waitress（并已准备至少 1 名需薪员工）。",
			"点击「推进子阶段」离开 Working：晚餐会自动结算并跳到 Payday。",
		],
		"expected": [
			"玩家 0 获得里程碑 first_waitress_used（player.milestones）。",
			"player.salary_cost_override == 3（Payday 计算薪水时可观察）。",
		],
		"related_tests": [
			"core/tests/new_milestones_recruiter_waitress_v2_test.gd",
		],
	}))

	cases.append(_case({
		"kind": "milestone",
		"id": "first_new_restaurant",
		"title": "首个新餐厅（first_new_restaurant）",
		"enabled_modules": ["new_milestones"],
		"exclude_modules": ["base_milestones"],
		"builder": "milestone_first_new_restaurant",
		"builder_params": {"employee_type": "local_manager"},
		"purpose": "验证首次在 Working 阶段放置新餐厅会触发里程碑，并允许放置一个永久 mailbox（#5-#10，同街区）。",
		"steps": [
			"载入后应处于 Working/PlaceRestaurants，且玩家 0 在岗包含 local_manager。",
			"执行 place_restaurant 放置一间新餐厅（参数见推荐）。",
			"随后执行动作 place_new_restaurant_mailbox（board_number=5 product=burger position=[0,2] rotation=0）。",
		],
		"expected": [
			"放置新餐厅后：玩家 0 获得里程碑 first_new_restaurant（player.milestones）。",
			"place_new_restaurant_mailbox 成功后：marketing_placements 占用 #5，且 remaining_duration=-1。",
		],
		"related_tests": [
			"core/tests/new_milestones_new_restaurant_v2_test.gd",
		],
	}))

	cases.append(_case({
		"kind": "milestone",
		"id": "first_house_built",
		"title": "首个建造房屋（first_house_built）",
		"enabled_modules": ["new_milestones"],
		"exclude_modules": ["base_milestones"],
		"builder": "milestone_first_house_built",
		"builder_params": {"employee_type": "new_business_developer", "employee_count": 1},
		"purpose": "验证 place_house 触发 HouseBuilt -> first_house_built，并启用 multi_trainer_on_one。",
		"steps": [
			"载入后应处于 Working/PlaceHouses，且玩家 0 在岗包含 new_business_developer。",
			"执行 place_house 放置任意房屋（参数见推荐）。",
		],
		"expected": [
			"玩家 0 获得里程碑 first_house_built（player.milestones）。",
			"player.multi_trainer_on_one == true。",
		],
		"related_tests": [
			"core/tests/place_house_rules_test.gd",
		],
	}))

	cases.append(_case({
		"kind": "milestone",
		"id": "first_beer_sold",
		"title": "首个卖出啤酒（first_beer_sold）",
		"enabled_modules": ["new_milestones"],
		"exclude_modules": ["base_milestones"],
		"builder": "milestone_first_beer_sold",
		"purpose": "验证晚餐卖出 beer 会触发里程碑，并允许在 Payday 用 token 支付薪水（并消耗库存）。",
		"steps": [
			"载入后应处于 Working/PlaceRestaurants（已预置 beer 需求与库存，且现金=0）。",
			"点击「推进子阶段」离开 Working，完成晚餐/清理后进入 Payday。",
			"在 Payday 点击「推进阶段」离开：应允许用 token 支付薪水并消耗库存。",
		],
		"expected": [
			"玩家 0 获得里程碑 first_beer_sold（player.milestones）。",
			"离开 Payday 时应消耗一定数量的 food/drink token 用于支付薪水。",
		],
		"related_tests": [
			"core/tests/new_milestones_beer_trainer_payday_v2_test.gd",
		],
	}))

	cases.append(_case({
		"kind": "milestone",
		"id": "first_coke_sold",
		"title": "首个卖出可乐（first_coke_sold）",
		"enabled_modules": ["new_milestones"],
		"exclude_modules": ["base_milestones"],
		"builder": "milestone_first_coke_sold",
		"purpose": "验证晚餐卖出 soda 会触发里程碑，并获得 freezer（gain_fridge=10）：Cleanup 后库存应保留到 10。",
		"steps": [
			"载入后应处于 Working/PlaceRestaurants（已预置 soda 需求与库存 soda=12）。",
			"点击「推进子阶段」离开 Working，完成晚餐与 Cleanup 后进入 Payday。",
		],
		"expected": [
			"玩家 0 获得里程碑 first_coke_sold（player.milestones）。",
			"进入 Payday 时 soda 库存应为 10（Cleanup 后按 freezer 容量限幅）。",
		],
		"related_tests": [
			"core/tests/new_milestones_coke_sold_v2_test.gd",
		],
	}))

	cases.append(_case({
		"kind": "milestone",
		"id": "first_lemonade_sold",
		"title": "首个卖出柠檬水（first_lemonade_sold）",
		"enabled_modules": ["new_milestones"],
		"exclude_modules": ["base_milestones"],
		"builder": "milestone_first_lemonade_sold",
		"purpose": "验证晚餐卖出 lemonade 会触发里程碑，并启用“在岗同色培训”等规则变化。",
		"steps": [
			"载入后应处于 Working/PlaceRestaurants（已预置 lemonade 需求与库存）。",
			"点击「推进子阶段」离开 Working，完成晚餐结算并进入 Payday（里程碑应在此过程中获得）。",
		],
		"expected": [
			"玩家 0 获得里程碑 first_lemonade_sold（player.milestones）。",
		],
		"related_tests": [
			"core/tests/new_milestones_lemonade_sold_v2_test.gd",
		],
	}))

	cases.append(_case({
		"kind": "milestone",
		"id": "first_burger_sold",
		"title": "首个卖出汉堡（first_burger_sold）",
		"enabled_modules": ["new_milestones"],
		"exclude_modules": ["base_milestones"],
		"builder": "milestone_first_burger_sold",
		"purpose": "验证晚餐卖出 burger 会触发里程碑，并将 CEO 卡槽至少提升到 4。",
		"steps": [
			"载入后应处于 Working/PlaceRestaurants（已预置 burger 需求与库存）。",
			"点击「推进子阶段」离开 Working，完成晚餐结算并跳到 Payday。",
		],
		"expected": [
			"玩家 0 获得里程碑 first_burger_sold（player.milestones）。",
			"player.company_structure.ceo_slots 应为 4。",
		],
		"related_tests": [
			"core/tests/new_milestones_burger_sold_v2_test.gd",
		],
	}))

	cases.append(_case({
		"kind": "milestone",
		"id": "first_pizza_sold",
		"title": "首个卖出披萨（first_pizza_sold）",
		"enabled_modules": ["new_milestones"],
		"exclude_modules": ["base_milestones"],
		"builder": "milestone_first_pizza_sold",
		"purpose": "验证晚餐卖出 pizza 会触发里程碑：生成 3 个待放置 radio（#1-#3），放完前阻断推进阶段。",
		"steps": [
			"载入后应处于 Working/PlaceRestaurants（已预置 3 个 pizza 需求与库存）。",
			"点击「推进子阶段」离开 Working：应进入 Dinnertime，且出现 3 个 pizza radio pending。",
			"依次执行 place_pizza_radio（position 选取任意合法空位）放置 3 个 radio；放完后才可推进阶段。",
		],
		"expected": [
			"玩家 0 获得里程碑 first_pizza_sold（player.milestones）。",
			"应放置 3 个 radio marketing_instances：board_number=1..3、product=pizza、remaining_duration=2、employee_type=__milestone__。",
		],
		"related_tests": [
			"core/tests/new_milestones_pizza_sold_v2_test.gd",
		],
	}))

	# === 员工：produce_food（固定产量）===
	for emp_id in [
		"burger_cook",
		"burger_chef",
		"pizza_cook",
		"pizza_chef",
	]:
		cases.append(_employee_produce_food_fixed(emp_id, [], "core/tests/produce_food_test.gd"))

	# coffee
	for emp_id in ["barista_trainee", "barista", "lead_barista"]:
		cases.append(_employee_produce_food_fixed(emp_id, ["coffee"], "core/tests/coffee_v2_test.gd"))

	# noodles
	for emp_id in ["noodle_cook", "noodle_chef"]:
		cases.append(_employee_produce_food_fixed(emp_id, ["noodles"], "core/tests/noodles_sushi_v2_test.gd"))

	# sushi
	for emp_id in ["sushi_cook", "sushi_chef"]:
		cases.append(_employee_produce_food_fixed(emp_id, ["sushi"], "core/tests/noodles_sushi_v2_test.gd"))

	# === 员工：采购饮料 ===
	cases.append(_employee_procure_errand_boy())
	for emp_id in ["cart_operator", "truck_driver", "zeppelin_pilot"]:
		cases.append(_employee_procure_route(emp_id))

	# === 员工：营销 ===
	cases.append(_employee_initiate_marketing("campaign_manager", 10, ["core/tests/marketing_campaigns_test.gd"]))
	# airplane_15 仅 4 人局可用；这里用 2 人局也可放置的 airplane_4（board_number=4）来复核 brand_manager。
	cases.append(_employee_initiate_marketing("brand_manager", 4, ["core/tests/marketing_campaigns_test.gd"]))
	cases.append(_employee_initiate_marketing("brand_director", 1, ["core/tests/marketing_campaigns_test.gd"]))
	cases.append(_employee_initiate_marketing("gourmet_food_critic", 17, ["core/tests/gourmet_food_critics_v2_test.gd"], ["gourmet_food_critics"]))
	cases.append(_employee_rural_marketeer())
	cases.append(_employee_mass_marketeer())

	# === 员工：说客 ===
	cases.append(_employee_lobbyist())

	# === 员工：夜班经理 ===
	cases.append(_employee_night_shift_manager())

	# === 员工：电影明星 ===
	for emp_id in ["movie_star_b", "movie_star_c", "movie_star_d"]:
		cases.append(_employee_movie_star(emp_id))

	# === 员工：新开店/搬店 ===
	cases.append(_employee_place_restaurant("local_manager"))
	cases.append(_employee_move_restaurant("regional_manager"))

	# === 员工：建房/花园 ===
	cases.append(_employee_place_house_and_garden("new_business_developer"))

	# === 员工：强制定价动作 ===
	cases.append(_employee_mandatory_action("pricing_manager", "set_price"))
	cases.append(_employee_mandatory_action("discount_manager", "set_discount"))
	cases.append(_employee_mandatory_action("luxury_manager", "set_luxury_price"))

	# === 员工：招聘次数 ===
	cases.append(_employee_recruit_capacity("ceo"))
	cases.append(_employee_recruit_capacity("recruiting_girl"))
	cases.append(_employee_recruit_capacity("recruiting_manager"))
	cases.append(_employee_recruit_capacity("hr_director"))

	# === 员工：培训次数 ===
	cases.append(_employee_train_once("trainer", "management_trainee", "new_business_developer"))
	cases.append(_employee_train_once("coach", "management_trainee", "new_business_developer"))
	cases.append(_employee_train_once("guru", "management_trainee", "new_business_developer"))

	# === 员工：经理链（以“可被培训”作为主要复核点）===
	cases.append(_employee_train_from("management_trainee", "trainer", "junior_vice_president"))
	cases.append(_employee_train_from("junior_vice_president", "trainer", "vice_president"))
	cases.append(_employee_train_from("vice_president", "trainer", "senior_vice_president"))
	cases.append(_employee_train_from("senior_vice_president", "trainer", "executive_vice_president"))
	cases.append(_employee_restructuring_showcase("executive_vice_president"))

	# === 员工：晚餐/清理被动效果 ===
	cases.append(_employee_waitress())
	cases.append(_employee_cfo())
	cases.append(_employee_fry_chef())
	cases.append(_employee_kimchi_master())

	return cases

static func _case(overrides: Dictionary) -> Dictionary:
	var c := {
		"player_count": DEFAULT_PLAYER_COUNT,
		"seed": DEFAULT_SEED,
	}
	for k in overrides.keys():
		c[k] = overrides[k]
	return c

static func _employee_produce_food_fixed(emp_id: String, enabled_modules: Array, related_test: String) -> Dictionary:
	return _case({
		"kind": "employee",
		"id": emp_id,
		"title": "员工（%s）" % emp_id,
		"enabled_modules": enabled_modules,
		"builder": "employee_produce_food_fixed",
		"builder_params": {"employee_type": emp_id},
		"purpose": "验证 produce_food 可用，并按员工定义将产物加入库存。",
		"steps": [
			"载入后应处于 Working/GetFood，且玩家 0 在岗包含 %s。" % emp_id,
			"行动面板选择「生产食物」并执行。",
		],
		"expected": [
			"玩家 0 对应产物库存增加（数量取决于员工 produces.amount）。",
		],
		"related_tests": [related_test],
	})

static func _employee_procure_errand_boy() -> Dictionary:
	return _case({
		"kind": "employee",
		"id": "errand_boy",
		"title": "跑腿伙计（errand_boy）",
		"enabled_modules": [],
		"builder": "employee_procure_drinks_errand_boy",
		"builder_params": {"drink_type": "soda"},
		"purpose": "验证 errand_boy 的特殊采购（直接获得指定饮料 1 瓶）。",
		"steps": [
			"载入后应处于 Working/GetDrinks，且玩家 0 在岗包含 errand_boy。",
			"行动面板选择「采购饮料」。",
			"选择 employee_type=errand_boy，并指定 drink_type=soda，确认执行。",
		],
		"expected": [
			"玩家 0 库存 soda +1。",
		],
		"related_tests": [
			"core/tests/procure_drinks_route_rules_test.gd",
		],
	})

static func _employee_procure_route(emp_id: String) -> Dictionary:
	return _case({
		"kind": "employee",
		"id": emp_id,
		"title": "采购员工（%s）" % emp_id,
		"enabled_modules": [],
		"builder": "employee_procure_drinks_route",
		"builder_params": {"employee_type": emp_id},
		"purpose": "验证 procure_drinks 的路线/范围校验与库存增加（route/selected_sources 由 UI 生成）。",
		"steps": [
			"载入后应处于 Working/GetDrinks，且玩家 0 在岗包含 %s。" % emp_id,
			"行动面板选择「采购饮料」。",
			"选择 employee_type=%s，并在地图上点选 1~N 个饮料来源生成路线后确认执行。" % emp_id,
		],
		"expected": [
			"库存获得饮料（数量受里程碑与员工影响）。",
			"超范围/不连通/未经过选定来源等场景应被拒绝并给出原因。",
		],
		"related_tests": [
			"core/tests/procure_drinks_test.gd",
			"core/tests/procure_drinks_route_rules_test.gd",
		],
	})

static func _employee_initiate_marketing(emp_id: String, board_number: int, related_tests: Array, enabled_modules: Array = []) -> Dictionary:
	return _case({
		"kind": "employee",
		"id": emp_id,
		"title": "营销员工（%s）" % emp_id,
		"enabled_modules": enabled_modules,
		"builder": "employee_initiate_marketing",
		"builder_params": {
			"employee_type": emp_id,
			"board_number": board_number,
			"product": "burger",
			"duration": 1,
		},
		"purpose": "验证 initiate_marketing(board=%d) 可用与放置合法性。" % board_number,
		"steps": [
			"载入后应处于 Working/Marketing，且玩家 0 在岗包含 %s。" % emp_id,
			"行动面板选择「发起营销」，并按说明文件中的推荐坐标放置。",
		],
		"expected": [
			"营销板件成功放置，并写入 state.map.marketing_placements；员工进入 busy_marketers。",
		],
		"related_tests": related_tests,
	})

static func _employee_rural_marketeer() -> Dictionary:
	return _case({
		"kind": "employee",
		"id": "rural_marketeer",
		"title": "乡村营销员（rural_marketeer）",
		"enabled_modules": ["rural_marketeers"],
		"builder": "employee_rural_marketeer_giant_billboard",
		"builder_params": {"side": "N", "product": "burger"},
		"purpose": "验证 place_giant_billboard（巨型广告牌）与员工永久忙碌。",
		"steps": [
			"载入后应处于 Working/Marketing，且玩家 0 在岗包含 rural_marketeer。",
			"行动面板选择「放置巨型广告牌」，选择 side=N product=burger 并确认。",
		],
		"expected": [
			"rural_area.giant_billboards[N] 被写入；rural_marketeer 从 employees 移到 busy_marketers。",
		],
		"related_tests": [
			"core/tests/rural_marketeers_v2_test.gd",
		],
	})

static func _employee_mass_marketeer() -> Dictionary:
	return _case({
		"kind": "employee",
		"id": "mass_marketeer",
		"title": "大众营销员（mass_marketeer）",
		"enabled_modules": ["mass_marketeers"],
		"builder": "employee_mass_marketeer_marketing_rounds",
		"purpose": "验证进入 Marketing 结算时，marketing_rounds=1+在岗 mass_marketeer 数量。",
		"steps": [
			"载入后应处于 Working/Marketing，且玩家 0 在岗包含 mass_marketeer 与 marketing_trainee。",
			"使用 marketing_trainee 放置 1 个 billboard（按推荐坐标）。",
			"结束本回合/推进到 Marketing 结算后，观察产生的需求数量应为 2 轮的叠加效果。",
		],
		"expected": [
			"state.round_state.marketing_rounds 应为 2（1 + 1 个 mass_marketeer）。",
		],
		"related_tests": [
			"core/tests/mass_marketeers_v2_test.gd",
		],
	})

static func _employee_lobbyist() -> Dictionary:
	return _case({
		"kind": "employee",
		"id": "lobbyist",
		"title": "说客（lobbyist）",
		"enabled_modules": ["lobbyists"],
		"builder": "employee_lobbyist_place_road",
		"purpose": "验证 Lobbyists 子阶段与放置建设中道路/公园的合法性。",
		"steps": [
			"载入后应处于 Working/Lobbyists，且玩家 0 在岗包含 lobbyist。",
			"行动面板选择「说客：放置道路（建设中）」并按推荐参数放置。",
		],
		"expected": [
			"state.map.lobbyists_pending_roads 增加 1 条；并消耗道路供应计数。",
		],
		"related_tests": [
			"core/tests/lobbyists_v2_test.gd",
		],
	})

static func _employee_night_shift_manager() -> Dictionary:
	return _case({
		"kind": "employee",
		"id": "night_shift_manager",
		"title": "夜班经理（night_shift_manager）",
		"enabled_modules": ["night_shift_managers"],
		"builder": "employee_night_shift_manager_double_action",
		"builder_params": {"target_employee": "kitchen_trainee"},
		"purpose": "验证夜班经理让免薪员工在 Working 子阶段可工作两次（最简单：produce_food 两次）。",
		"steps": [
			"载入后应处于 Working/GetFood，且玩家 0 在岗包含 night_shift_manager 与 kitchen_trainee。",
			"用 kitchen_trainee 执行 produce_food 第一次。",
			"同一子阶段再次用 kitchen_trainee 执行 produce_food，应仍允许（次数为 2）。",
		],
		"expected": [
			"第二次 produce_food 不应被拒绝为“次数耗尽”。",
		],
		"related_tests": [
			"core/tests/night_shift_managers_v2_test.gd",
		],
	})

static func _employee_movie_star(emp_id: String) -> Dictionary:
	return _case({
		"kind": "employee",
		"id": emp_id,
		"title": "电影明星（%s）" % emp_id,
		"enabled_modules": ["movie_stars"],
		"builder": "employee_movie_star_order_of_business",
		"builder_params": {"star_id": emp_id},
		"purpose": "验证 movie_star_* 会在 OrderOfBusiness 使持有者优先选顺序。",
		"steps": [
			"载入后应处于 OrderOfBusiness 阶段。",
			"观察 selection_order/turn_order：拥有电影明星的玩家应排在前面。",
		],
		"expected": [
			"玩家 0 应优先于玩家 1 进行顺序选择（由 movie_star_* 模块重排）。",
		],
		"related_tests": [
			"core/tests/movie_stars_v2_test.gd",
		],
	})

static func _employee_place_restaurant(emp_id: String) -> Dictionary:
	return _case({
		"kind": "employee",
		"id": emp_id,
		"title": "放置餐厅员工（%s）" % emp_id,
		"enabled_modules": [],
		"builder": "employee_place_restaurant",
		"builder_params": {"employee_type": emp_id},
		"purpose": "验证 place_restaurant 可用与放置合法性。",
		"steps": [
			"载入后应处于 Working/PlaceRestaurants，且玩家 0 在岗包含 %s。" % emp_id,
			"行动面板选择「放置餐厅」，并按推荐坐标放置。",
		],
		"expected": [
			"放置成功后：state.map.restaurants 增加新餐厅；玩家 drive_thru_active=true（本回合）。",
		],
		"related_tests": [
			"core/tests/place_restaurant_rules_test.gd",
		],
	})

static func _employee_move_restaurant(emp_id: String) -> Dictionary:
	return _case({
		"kind": "employee",
		"id": emp_id,
		"title": "移动餐厅员工（%s）" % emp_id,
		"enabled_modules": [],
		"builder": "employee_move_restaurant",
		"builder_params": {"employee_type": emp_id},
		"purpose": "验证 move_restaurant 可用与移动合法性。",
		"steps": [
			"载入后应处于 Working/PlaceRestaurants，且玩家 0 在岗包含 %s。" % emp_id,
			"行动面板选择「移动餐厅」，并按推荐参数移动。",
		],
		"expected": [
			"移动成功后：餐厅 anchor_pos/entrance_pos 更新；drive_thru_active=true（本回合）。",
		],
		"related_tests": [
			"core/tests/move_restaurant_rules_test.gd",
		],
	})

static func _employee_place_house_and_garden(emp_id: String) -> Dictionary:
	return _case({
		"kind": "employee",
		"id": emp_id,
		"title": "建房/花园员工（%s）" % emp_id,
		"enabled_modules": [],
		"builder": "employee_place_house",
		"builder_params": {
			"employee_type": emp_id,
			"employee_count": 2,
		},
		"purpose": "验证 place_house/add_garden 两类动作可用（通过 2 张同类员工提供足够次数）。",
		"steps": [
			"载入后应处于 Working/PlaceHouses，且玩家 0 在岗包含 %s x2。" % emp_id,
			"行动面板选择「放置房屋」，按推荐参数放置并确认。",
			"同一子阶段再执行一次「添加花园」（选择任意无花园房屋与方向）应允许。",
		],
		"expected": [
			"place_house 成功后：state.map.houses 新增房屋；house_number_supply_remaining 消耗。",
			"add_garden 成功后：目标 house.has_garden=true 且占地更新为 house_with_garden。",
		],
		"related_tests": [
			"core/tests/place_house_rules_test.gd",
			"core/tests/add_garden_rules_test.gd",
		],
	})

static func _employee_mandatory_action(emp_id: String, action_id: String) -> Dictionary:
	return _case({
		"kind": "employee",
		"id": emp_id,
		"title": "强制定价员工（%s）" % emp_id,
		"enabled_modules": [],
		"builder": "employee_mandatory_action",
		"builder_params": {"employee_type": emp_id, "action_id": action_id},
		"purpose": "验证强制动作 %s 的可执行性与 round_state 写入。" % action_id,
		"steps": [
			"载入后应处于 Working 阶段，且玩家 0 在岗包含 %s。" % emp_id,
			"行动面板选择强制动作并执行。",
		],
		"expected": [
			"round_state 中应写入对应价格修正（price_modifiers/discount_modifiers/luxury_price_modifiers 等）。",
		],
		"related_tests": [
			"core/tests/mandatory_actions_test.gd",
		],
	})

static func _employee_recruit_capacity(emp_id: String) -> Dictionary:
	return _case({
		"kind": "employee",
		"id": emp_id,
		"title": "招聘能力员工（%s）" % emp_id,
		"enabled_modules": [],
		"builder": "employee_recruit_capacity",
		"builder_params": {"employee_type": emp_id, "recruit_target": "waitress"},
		"purpose": "验证 Recruit 子阶段招聘次数上限（CEO 1 + recruit_capacity 加成）。",
		"steps": [
			"载入后应处于 Working/Recruit，且玩家 0 在岗包含 %s。" % emp_id,
			"重复执行 recruit，直到达到上限（上限随员工不同）。",
		],
		"expected": [
			"超过上限后应被拒绝（\"本子阶段招聘次数已用完\"）。",
		],
		"related_tests": [
			"core/tests/employee_action_test.gd",
		],
	})

static func _employee_train_once(trainer_type: String, from_employee: String, to_employee: String, custom_title: String = "") -> Dictionary:
	var title := custom_title
	if title.is_empty():
		title = "培训员工（%s）" % trainer_type
	return _case({
		"kind": "employee",
		"id": trainer_type,
		"title": title,
		"enabled_modules": [],
		"builder": "employee_train_once",
		"builder_params": {
			"trainer_type": trainer_type,
			"from_employee": from_employee,
			"to_employee": to_employee,
		},
		"purpose": "验证 Train 子阶段可执行一次培训，并遵循 train_to 链与供应池约束。",
		"steps": [
			"载入后应处于 Working/Train，且玩家 0 在岗包含 %s；reserve_employees 包含 %s。" % [trainer_type, from_employee],
			"行动面板选择「培训」，将 %s 培训为 %s 并执行。" % [from_employee, to_employee],
		],
		"expected": [
			"%s 从 reserve_employees 移除；%s 加入 reserve_employees。" % [from_employee, to_employee],
		],
		"related_tests": [
			"core/tests/milestone_system_test.gd",
		],
	})

static func _employee_train_from(emp_id: String, trainer_type: String, to_employee: String) -> Dictionary:
	return _case({
		"kind": "employee",
		"id": emp_id,
		"title": "经理链员工（%s）" % emp_id,
		"enabled_modules": [],
		"builder": "employee_train_once",
		"builder_params": {
			"trainer_type": trainer_type,
			"from_employee": emp_id,
			"to_employee": to_employee,
		},
		"purpose": "验证 %s 可作为 from_employee 被培训为 %s。" % [emp_id, to_employee],
		"steps": [
			"载入后应处于 Working/Train，且玩家 0 在岗包含 %s；reserve_employees 包含 %s。" % [trainer_type, emp_id],
			"将 %s 培训为 %s 并执行。" % [emp_id, to_employee],
		],
		"expected": [
			"%s 从 reserve_employees 移除；%s 加入 reserve_employees。" % [emp_id, to_employee],
		],
		"related_tests": [
			"core/tests/company_structure_test.gd",
		],
	})

static func _employee_restructuring_showcase(emp_id: String) -> Dictionary:
	return _case({
		"kind": "employee",
		"id": emp_id,
		"title": "经理展示（%s）" % emp_id,
		"enabled_modules": [],
		"builder": "employee_restructuring_showcase",
		"builder_params": {"employee_type": emp_id, "to_reserve": true},
		"purpose": "验证该经理卡可存在于本局员工池，并可在重组阶段纳入公司结构（手工复核 UI/容量）。",
		"steps": [
			"载入后应处于 Restructuring 阶段，且玩家 0 预备区包含 %s。" % emp_id,
			"（可选）在重组界面将其激活/纳入公司结构并提交。",
		],
		"expected": [
			"提交成功；公司结构容量/空槽变化符合该卡 manager_slots 描述（手工核对）。",
		],
		"related_tests": [
			"core/tests/company_structure_test.gd",
		],
	})

static func _employee_waitress() -> Dictionary:
	return _case({
		"kind": "employee",
		"id": "waitress",
		"title": "女服务员（waitress）",
		"enabled_modules": [],
		"builder": "employee_waitress_tips",
		"purpose": "验证 waitress tips（默认 +$3）在晚餐结算中生效。",
		"steps": [
			"载入后应处于 Payday（该存档已推进过晚餐结算）。",
			"观察玩家 0 现金应比玩家 1 多 $5（仅玩家 0 拥有 waitress；且会触发 first_waitress 将 tips 提升为 $5）。",
		],
		"expected": [
			"players[0].cash == players[1].cash + 5。",
		],
		"related_tests": [
			"core/tests/dinnertime_settlement_test.gd",
		],
	})

static func _employee_cfo() -> Dictionary:
	return _case({
		"kind": "employee",
		"id": "cfo",
		"title": "CFO（cfo）",
		"enabled_modules": [],
		"builder": "employee_cfo_bonus_on_tips",
		"purpose": "用 tips 触发 CFO +50%（向上取整）加成，便于手工对照差额。",
		"steps": [
			"载入后应处于 Payday（该存档已推进过晚餐结算）。",
			"观察玩家 0 现金应比玩家 1 多 $3（双方都有 waitress tips=$5，但仅玩家 0 有 CFO，CFO 加成为 ceil(5*50%)=$3）。",
		],
		"expected": [
			"players[0].cash == players[1].cash + 3。",
		],
		"related_tests": [
			"core/tests/dinnertime_settlement_test.gd",
			"core/tests/milestone_system_test.gd",
		],
	})

static func _employee_fry_chef() -> Dictionary:
	return _case({
		"kind": "employee",
		"id": "fry_chef",
		"title": "薯条厨师（fry_chef）",
		"enabled_modules": ["fry_chefs"],
		"builder": "employee_fry_chef_dinnertime_bonus",
		"purpose": "构造双方各卖 1 个房屋的局面，验证 fry_chef 每房屋额外 +$10。",
		"steps": [
			"载入后应处于 Payday（该存档已推进过晚餐结算）。",
			"观察玩家 0 现金应比玩家 1 多 $10（仅玩家 0 拥有 fry_chef）。",
		],
		"expected": [
			"players[0].cash == players[1].cash + 10。",
		],
		"related_tests": [
			"core/tests/fry_chefs_v2_test.gd",
		],
	})

static func _employee_kimchi_master() -> Dictionary:
	return _case({
		"kind": "employee",
		"id": "kimchi_master",
		"title": "泡菜大师（kimchi_master）",
		"enabled_modules": ["kimchi"],
		"builder": "employee_kimchi_master_cleanup",
		"purpose": "验证 Cleanup 丢弃食物后 kimchi_master 自动产出 kimchi。",
		"steps": [
			"载入后应处于 Payday（该存档已推进过 Cleanup）。",
			"观察玩家 0 库存应包含 kimchi +1（并且 burger 被丢弃为 0）。",
		],
		"expected": [
			"players[0].inventory.kimchi >= 1。",
		],
		"related_tests": [
			"core/tests/kimchi_v2_test.gd",
		],
	})
