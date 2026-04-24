extends RefCounted

# 手工复核存档：营销阶段动画。

const DEFAULT_PLAYER_COUNT := 2
const DEFAULT_SEED := 12345

static func get_cases() -> Array[Dictionary]:
	var cases: Array[Dictionary] = []

	cases.append(_case({
		"kind": "marketing",
		"id": "marketing_phase_animation_review",
		"title": "营销阶段动画复核",
		"enabled_modules": [],
		"builder": "marketing_phase_animation_review",
		"purpose": "载入后直接停在 Marketing 阶段，用于手工复核营销广告按 board_number 顺序自动播放结算动画。",
		"steps": [
			"从主菜单载入本存档，进入游戏画面后不要手动推进阶段。",
			"确认地图为正常随机板块地图，且地图上能看到四类营销广告件。",
			"观察营销结算控制条与地图动画：广告牌应按 #1 radio、#4 airplane、#7 mailbox、#14 billboard 的顺序播放。",
			"等待动画自动结束，确认游戏会执行 confirm_marketing 并继续推进到后续阶段。",
		],
		"expected": [
			"#1 radio：soda 需求以扩散动画飞向覆盖范围内房屋，并显示持续时间 2 > 1。",
			"#4 airplane：beer 沿边缘飞行条带生效，并显示持续时间 2 > 1。",
			"#7 mailbox：pizza 对同街区房屋生效，并显示持续时间 2 > 1。",
			"#14 billboard：burger 对相邻房屋生效，并显示持续时间 2 > 1。",
			"动画结束后 pending_phase_actions[Marketing] 被清除，阶段不再卡在 Marketing。",
		],
		"related_tests": [
			"core/tests/manual_marketing_review_save_test.gd",
			"core/tests/marketing_campaigns_test.gd",
			"core/tests/confirm_marketing_availability_test.gd",
			"ui/scenes/tests/marketing_animation_orders_builder_test.gd",
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
