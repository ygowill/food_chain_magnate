extends RefCounted

# 手工复核存档（员工/里程碑/日志）场景清单（拆分文件）
# 原始入口：res://tools/generate_manual_test_saves_manifest.gd

const DEFAULT_PLAYER_COUNT := 2
const DEFAULT_SEED := 12345

static func get_cases() -> Array[Dictionary]:
	var cases: Array[Dictionary] = []

	# === 日志：回放验证（用于审查日志改动是否生效） ===
	cases.append(_case({
		"kind": "logs",
		"id": "event_log_review",
		"title": "日志回放验证（营销结算 + 采购路线）",
		"enabled_modules": [],
		"freeze_as_initial": false,
		"builder": "logs_event_review",
		"purpose": "用于手工复核日志：营销结算产生需求（DEMAND_GENERATED）与采购路线（DRINKS_PROCURED）的摘要/详情展示。",
		"steps": [
			"载入后打开日志视图（左侧「日志」按钮）。",
			"确认存在「采购饮料」日志（摘要含起点餐厅与选定进货点）。",
			"确认存在「产生需求/打上广告」日志（摘要含 board_number/新增需求数/房屋编号）。",
			"双击上述日志条目打开详情窗口，核对 details 中的 picked_sources / affected_house_numbers 等字段。",
		],
		"expected": [
			"日志可筛选玩家；「全部」可显示全体日志。",
			"双击条目可打开详情窗口。",
		],
		"related_tests": [
			"core/tests/marketing_demand_generated_event_test.gd",
			"core/tests/procure_drinks_route_rules_test.gd",
			"ui/scenes/tests/log_restore_after_load_test.gd",
		],
	}))

	cases.append(_case({
		"kind": "logs",
		"id": "event_log_employee_recruit_train",
		"title": "日志回放验证（强制定价 + 招聘 + 培训）",
		"enabled_modules": [],
		"freeze_as_initial": false,
		"builder": "logs_employee_recruit_train",
		"purpose": "用于手工复核员工相关日志：强制定价（COMMAND_EXECUTED）、招聘（EMPLOYEE_RECRUITED）与培训（EMPLOYEE_TRAINED）。",
		"steps": [
			"载入后打开日志视图（左侧「日志」按钮）。",
			"确认存在「设定价格（-$1）」日志。",
			"确认存在「招聘 ...（待命）」日志。",
			"确认存在「培训 ... -> ...」日志。",
		],
		"expected": [
			"日志条目可双击展开 details（含 action_id/employee ids 等）。",
		],
		"related_tests": [
			"core/tests/mandatory_actions_test.gd",
			"core/tests/recruit_on_credit_rules_test.gd",
			"core/tests/milestone_system_test.gd",
		],
	}))

	cases.append(_case({
		"kind": "logs",
		"id": "event_log_employee_fire",
		"title": "日志回放验证（Payday 解雇）",
		"enabled_modules": [],
		"freeze_as_initial": false,
		"builder": "logs_employee_fire",
		"purpose": "用于手工复核解雇日志：EMPLOYEE_FIRED。",
		"steps": [
			"载入后打开日志视图。",
			"确认存在「解雇 ...（待命）」日志。",
		],
		"expected": [
			"解雇日志包含 employee_id/location 等 details 字段。",
		],
		"related_tests": [
			"core/tests/fire_action_test.gd",
		],
	}))

	cases.append(_case({
		"kind": "logs",
		"id": "event_log_payday_details",
		"title": "日志回放验证（Payday 发薪明细）",
		"enabled_modules": [],
		"freeze_as_initial": false,
		"builder": "logs_payday_details",
		"purpose": "用于手工复核 Payday 日志细节：单独的解雇日志、逐员工发薪/免薪、招聘折扣来源、里程碑薪资修正。",
		"steps": [
			"载入后打开日志视图。",
			"先确认已经存在一条「解雇 ...」日志。",
			"点击「确认结束」完成当前 Payday。",
			"确认出现每位玩家的 Payday 总结日志。",
			"确认日志文本中包含逐员工明细、免薪原因、招聘折扣来源、里程碑薪资修正。",
		],
		"expected": [
			"解雇日志与最终发薪日志分开显示。",
			"玩家1的发薪日志应包含 hr_director 在岗发薪、campaign_manager 忙碌营销免薪，以及 first_train / first_billboard 带来的减免信息。",
		],
		"related_tests": [
			"core/tests/payday_salary_test.gd",
			"core/tests/payday_report_event_test.gd",
			"core/tests/fire_action_test.gd",
		],
	}))

	cases.append(_case({
		"kind": "logs",
		"id": "event_log_build_and_move",
		"title": "日志回放验证（建房 + 花园 + 开店 + 搬店）",
		"enabled_modules": [],
		"freeze_as_initial": false,
		"builder": "logs_build_and_move",
		"purpose": "用于手工复核地图建造日志：HOUSE_PLACED/GARDEN_ADDED/RESTAURANT_PLACED/RESTAURANT_MOVED。",
		"steps": [
			"载入后打开日志视图。",
			"确认存在放置房屋/添加花园/放置餐厅/移动餐厅相关日志。",
		],
		"expected": [
			"放置/移动日志摘要包含坐标；details 中包含 restaurant_id/house_id 等字段。",
		],
		"related_tests": [
			"core/tests/place_house_rules_test.gd",
			"core/tests/add_garden_rules_test.gd",
		],
	}))

	cases.append(_case({
		"kind": "logs",
		"id": "event_log_produce_and_cleanup",
		"title": "日志回放验证（生产食物 + Cleanup 丢弃）",
		"enabled_modules": [],
		"freeze_as_initial": false,
		"builder": "logs_produce_and_cleanup",
		"purpose": "用于手工复核生产与清理日志：FOOD_PRODUCED/FOOD_DISCARDED。",
		"steps": [
			"载入后打开日志视图。",
			"确认存在「生产食物」日志。",
			"确认存在「清理库存：丢弃 ...」日志。",
		],
		"expected": [
			"丢弃日志 details.discarded 为 product_id -> count 字典。",
		],
		"related_tests": [
			"core/tests/produce_food_test.gd",
		],
	}))

	cases.append(_case({
		"kind": "logs",
		"id": "event_log_dinnertime_sale",
		"title": "日志回放验证（晚餐结算：售出 + 现金变化）",
		"enabled_modules": ["coffee", "fry_chefs"],
		"freeze_as_initial": false,
		"builder": "logs_dinnertime_sale",
		"purpose": "用于手工复核晚餐结算日志：DINNERTIME_REPORT + FOOD_SOLD + PLAYER_CASH_CHANGED（覆盖花园翻倍、营销加成、沿路购买、服务员小费、CFO 加成、薯条主厨房屋奖）。",
		"steps": [
			"载入后打开日志视图。",
			"确认存在「晚餐结算」日志。",
			"确认存在多条「售出」日志（至少覆盖：花园翻倍、营销加成、房屋奖拆分）。",
			"子项顺序调整：售出在前、现金变化在后。",
			"确认存在「玩家 X 现金变化」日志，且摘要包含「晚餐收入来源」分解（至少覆盖：花园加成/营销加成/沿路购买收入/服务员收入/CFO 加成/薯条主厨加成）。",
		],
		"expected": [
			"售出日志 details.required/details.revenue/details.house_bonus_breakdown 正确填充。",
			"现金变化日志 details.income_breakdown.context == dinnertime_income，且 items 覆盖上述加成来源。",
		],
		"related_tests": [
			"core/tests/dinnertime_settlement_test.gd",
		],
	}))

	cases.append(_case({
		"kind": "logs",
		"id": "event_log_game_over_bankruptcy",
		"title": "游戏结束复核（银行二次破产 -> GameOver）",
		"enabled_modules": [],
		"builder": "logs_game_over_bankruptcy",
		"purpose": "用于手工复核终局：第二次破产触发 Working -> Dinnertime -> GameOver，并弹出 GameOver 面板且按钮可用（返回主菜单/再来一局）。",
		"steps": [
			"载入后确认当前位置为 Working/PlaceHouses。",
			"点击「跳过放置房屋」（skip_sub_phase），进入 PlaceRestaurants。",
			"点击「确认结束」（skip），触发晚餐结算与二次破产，阶段自动推进到 GameOver。",
			"确认弹出「游戏结束」面板，且「返回主菜单」「再来一局」按钮可点击并生效。",
		],
		"expected": [
			"触发终局时游戏不应卡死；GameOver 面板可正常展示排名与统计。",
			"可正常返回主菜单或重新开始游戏。",
		],
		"related_tests": [
			"core/tests/bankruptcy_test.gd",
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
