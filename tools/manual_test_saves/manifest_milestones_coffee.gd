extends RefCounted

const DEFAULT_PLAYER_COUNT := 2
const DEFAULT_SEED := 12345

static func get_cases() -> Array[Dictionary]:
	var cases: Array[Dictionary] = []

	cases.append(_case({
		"kind": "milestone",
		"id": "first_coffee_sold",
		"title": "首个卖出咖啡（first_coffee_sold）",
		"player_count": 3,
		"enabled_modules": ["coffee"],
		"builder": "milestone_first_coffee_sold",
		"purpose": "验证 Dinnertime 路线购买中的咖啡销售会触发 ProductSold(product=coffee)，并授予里程碑 first_coffee_sold。",
		"steps": [
			"载入后应处于 Working/PlaceRestaurants。",
			"点击「推进子阶段」离开 Working：将自动进入 Dinnertime 结算后到 Payday。",
			"（可选）继续推进到 Cleanup，观察咖啡里程碑奖励待处理动作注入。",
		],
		"expected": [
			"玩家 1 与玩家 2 获得里程碑 first_coffee_sold（player.milestones）。",
			"state.round_state.dinnertime.sales[*].route_purchases 中可看到 kind=coffee 的购买记录。",
			"（可选）到 Cleanup 后，pending_phase_actions['Cleanup'] 中出现 coffee_first_coffee_sold_bonus_coffee_shop 待处理任务（按 turn_order 排序）。",
		],
		"related_tests": [
			"core/tests/coffee_v2_test.gd",
		],
	}))

	return cases

static func _case(data: Dictionary) -> Dictionary:
	var out := data.duplicate(true)
	if not out.has("player_count"):
		out["player_count"] = DEFAULT_PLAYER_COUNT
	if not out.has("seed"):
		out["seed"] = DEFAULT_SEED
	return out
