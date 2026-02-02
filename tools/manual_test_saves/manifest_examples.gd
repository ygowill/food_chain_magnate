extends RefCounted

# 手工复核存档（员工/里程碑/日志）场景清单（拆分文件）
# 原始入口：res://tools/generate_manual_test_saves_manifest.gd

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

	cases.append(_case({
		"kind": "milestone",
		"id": "status_matrix",
		"title": "里程碑状态矩阵（status_matrix）",
		"enabled_modules": ["hard_choices"],
		"builder": "milestone_status_matrix",
		"purpose": "用于验收里程碑全屏面板：可获得/不可获得/已获得 + 拥有者图标 + 过期提示 + 5列布局。",
		"steps": [
			"载入后打开顶部栏「里程碑」面板。",
			"检查三态样式：可获得=浅绿色边框；已获得=浅绿色背景；不可获得=保持默认颜色。",
			"定位以下里程碑卡片并核对：",
			"- first_billboard：应为「已获得」（浅绿色背景），右下角显示玩家1 logo。",
			"- first_burger_produced：应为「可获得」（浅绿色边框），右下角显示玩家2 logo（用于验证“有人拥有但仍可获得”）。",
			"- first_burger_marketed：应为「不可获得」且显示「已过期」。",
			"- first_hire_3：应为「可获得」且显示「剩余 0 回合」。",
			"检查：默认每行 5 个；窄屏放不下时自动降列/换行。",
		],
		"expected": [
			"first_billboard/first_burger_produced/first_burger_marketed/first_hire_3 的状态与文案符合预期。",
			"拥有者图标显示正确（玩家1/玩家2）。",
			"过期提示显示正确（剩余/已过期）。",
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

