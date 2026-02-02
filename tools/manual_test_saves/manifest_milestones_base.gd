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

	return cases

static func _case(overrides: Dictionary) -> Dictionary:
	var c := {
		"player_count": DEFAULT_PLAYER_COUNT,
		"seed": DEFAULT_SEED,
	}
	for k in overrides.keys():
		c[k] = overrides[k]
	return c

