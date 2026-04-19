extends RefCounted

# 手工复核存档（员工/里程碑/日志）场景清单（拆分文件）
# 原始入口：res://tools/generate_manual_test_saves_manifest.gd

const DEFAULT_PLAYER_COUNT := 2
const DEFAULT_SEED := 12345

static func get_cases() -> Array[Dictionary]:
	var cases: Array[Dictionary] = []

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
	# board_number=15（billboard_15）仅 4 人局可用；这里用 2 人局也可放置的 airplane_4（board_number=4）来复核 brand_manager。
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
	cases.append(_employee_multi_trainers())
	cases.append(_employee_train_panel_refresh())
	cases.append(_employee_fire_panel_refresh())

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

static func _employee_multi_trainers() -> Dictionary:
	return _case({
		"kind": "employee",
		"id": "multi_trainers",
		"title": "多个训练员工综合测试（multi_trainers）",
		"enabled_modules": [],
		"builder": "employee_multi_trainers",
		"purpose": "在单个存档中同时验证多个相同训练员、不同训练员、无里程碑时禁止多名训练员连续训练同一员工，以及 coach/guru 的多级培训能力。",
		"steps": [
			"载入后应处于 Working/Train，玩家 0 在岗包含 2 名 trainer、2 名 coach、1 名 guru。",
			"待命区应包含 3 名 marketing_trainee、2 名 management_trainee、2 名 kitchen_trainee。",
			"选择一名 trainer，将某个 marketing_trainee 培训为 campaign_manager；随后尝试选择另一名 trainer 继续将同一个 staff_id 培训为 brand_manager，应失败。",
			"选择 coach，将另一个 marketing_trainee 一次性培训为 brand_manager，应成功并消耗 2 次培训容量。",
			"选择 guru，将一个 management_trainee 一次性培训为 senior_vice_president，应成功并消耗 3 次培训容量。",
		],
		"expected": [
			"多个相同 trainer 应显示为多个可选择实例，每个实例各 1 次培训容量。",
			"无 multi_trainer_on_one 时，同一名员工被某一训练员培训后，不能换另一名训练员继续训练。",
			"coach 单实例剩余容量为 2，可完成 2 步培训。",
			"guru 单实例剩余容量为 3，可完成 3 步培训。",
		],
		"related_tests": [
			"core/tests/manual_multi_trainers_save_test.gd",
			"core/tests/milestone_system/milestone_system_train_rules_test.gd",
			"core/tests/train_action_state_access_test.gd",
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

static func _employee_train_panel_refresh() -> Dictionary:
	return _case({
		"kind": "employee",
		"id": "train_panel_refresh",
		"title": "培训面板刷新（双 trainer）",
		"enabled_modules": [],
		"builder": "employee_train_panel_refresh",
		"purpose": "验证 Train 面板在执行一次培训后，会立刻刷新可继续培训的员工列表，并且刚被培训过的员工不会在同回合再次出现在来源列表中。",
		"steps": [
			"载入后应处于 Working/Train，且玩家 0 在岗包含 trainer x2；reserve_employees 至少包含 marketing_trainee 与 management_trainee。",
			"先打开培训面板，确认可选来源列表里有 marketing_trainee 与 management_trainee。",
			"执行一次培训：将 marketing_trainee 培训为 campaign_manager。",
			"不要切换面板，直接观察当前培训面板中的可选来源列表。",
		],
		"expected": [
			"培训后仍停留在 Working/Train，因为还有 1 次培训额度且 management_trainee 仍可培训。",
			"面板应立即移除 marketing_trainee，不需要手动关闭重开。",
			"新得到的 campaign_manager 不应在本回合立刻出现在来源列表里，因此不能继续把同一名员工再培训到 brand_manager。",
			"此时可继续培训的来源应只剩 management_trainee。",
		],
		"related_tests": [
			"core/tests/train_state_access_test.gd",
			"ui/scenes/tests/working_panels_visible_sync_test.gd",
		],
	})

static func _employee_fire_panel_refresh() -> Dictionary:
	return _case({
		"kind": "employee",
		"id": "fire_panel_refresh",
		"title": "发薪日解雇面板刷新",
		"enabled_modules": [],
		"builder": "employee_payday_fire_panel_refresh",
		"purpose": "验证 Payday 面板在执行解雇后，会立刻刷新员工列表与薪资汇总，不再显示已解雇员工。",
		"steps": [
			"载入后应处于 Payday，且玩家 0 员工列表中至少有一名在岗 waitress 与一名待命 trainer。",
			"打开发薪日面板，先确认 waitress 显示为在岗员工，trainer 显示为待命员工。",
			"在面板中勾选并解雇 waitress。",
			"不要关闭面板，直接观察当前列表与汇总。",
		],
		"expected": [
			"waitress 会立刻从面板列表中消失，不需要重新打开 Payday 面板。",
			"trainer 仍然保留在待命列表中。",
			"薪资汇总会同步下降；若只剩 trainer，则应不再需要为 waitress 支付薪水。",
		],
		"related_tests": [
			"core/tests/fire_action_test.gd",
			"ui/scenes/tests/working_panels_visible_sync_test.gd",
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
		"title": "薯条主厨（fry_chef）",
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
