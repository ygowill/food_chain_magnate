extends RefCounted

# 手工复核存档（员工/里程碑/日志）场景清单（拆分文件）
# 原始入口：res://tools/generate_manual_test_saves_manifest.gd

const DEFAULT_PLAYER_COUNT := 2
const DEFAULT_SEED := 12345

static func get_cases() -> Array[Dictionary]:
	var cases: Array[Dictionary] = []

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

	return cases

static func _case(overrides: Dictionary) -> Dictionary:
	var c := {
		"player_count": DEFAULT_PLAYER_COUNT,
		"seed": DEFAULT_SEED,
	}
	for k in overrides.keys():
		c[k] = overrides[k]
	return c

