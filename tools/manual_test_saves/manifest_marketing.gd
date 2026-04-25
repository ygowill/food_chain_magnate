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
			"观察营销结算控制条与地图动画：广告牌应按 #1 radio、#6 airplane、#7 mailbox、#14 billboard 的顺序播放。",
			"等待动画自动结束后，点击右侧动作区的「确认营销结算」继续推进到后续阶段。",
		],
		"expected": [
			"#1 radio：电波动画在需求发射期间持续循环，soda 需求逐个飞向覆盖范围内房屋。",
			"#6 airplane：飞机广告板件缓慢飞过地图，并在飞行途中以投放方式向覆盖房屋丢下 beer 需求。",
			"#7 mailbox：pizza 对同街区房屋生效，不再额外显示持续时间变化提示。",
			"#14 billboard：burger 对相邻房屋生效，不再额外显示持续时间变化提示。",
			"动画结束前右侧动作区可跳过营销结算；动画结束后才可确认营销结算，确认后 pending_phase_actions[Marketing] 被清除。",
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
