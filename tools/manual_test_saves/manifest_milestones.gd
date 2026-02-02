extends RefCounted

# 手工复核存档（员工/里程碑/日志）场景清单（拆分文件）
# 原始入口：res://tools/generate_manual_test_saves_manifest.gd

const DEFAULT_PLAYER_COUNT := 2
const DEFAULT_SEED := 12345

static func get_cases() -> Array[Dictionary]:
	var cases: Array[Dictionary] = []

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

	return cases

static func _case(overrides: Dictionary) -> Dictionary:
	var c := {
		"player_count": DEFAULT_PLAYER_COUNT,
		"seed": DEFAULT_SEED,
	}
	for k in overrides.keys():
		c[k] = overrides[k]
	return c

