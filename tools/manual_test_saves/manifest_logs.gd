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
		"title": "日志回放验证（晚餐售出）",
		"enabled_modules": [],
		"freeze_as_initial": false,
		"builder": "logs_dinnertime_sale",
		"purpose": "用于手工复核晚餐日志：DINNERTIME_REPORT + FOOD_SOLD。",
		"steps": [
			"载入后打开日志视图。",
			"确认存在「晚餐结算」日志。",
			"确认存在至少 1 条「售出」日志。",
		],
		"expected": [
			"售出日志 details.required 与 details.revenue 正确填充。",
		],
		"related_tests": [
			"core/tests/dinnertime_settlement_test.gd",
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

