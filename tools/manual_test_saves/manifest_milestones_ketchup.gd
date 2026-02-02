extends RefCounted

# 手工复核存档（员工/里程碑/日志）场景清单（拆分文件）
# 原始入口：res://tools/generate_manual_test_saves_manifest.gd

const DEFAULT_PLAYER_COUNT := 2
const DEFAULT_SEED := 12345

static func get_cases() -> Array[Dictionary]:
	var cases: Array[Dictionary] = []

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

	return cases

static func _case(overrides: Dictionary) -> Dictionary:
	var c := {
		"player_count": DEFAULT_PLAYER_COUNT,
		"seed": DEFAULT_SEED,
	}
	for k in overrides.keys():
		c[k] = overrides[k]
	return c

