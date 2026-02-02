extends RefCounted

# 手工复核存档（员工/里程碑/日志）场景清单（拆分文件）
# 原始入口：res://tools/generate_manual_test_saves_manifest.gd

const DEFAULT_PLAYER_COUNT := 2
const DEFAULT_SEED := 12345

static func get_cases() -> Array[Dictionary]:
	var cases: Array[Dictionary] = []

	# === 里程碑：lobbyists ===
	cases.append(_case({
		"kind": "milestone",
		"id": "first_lobbyist_used",
		"title": "首个使用说客（first_lobbyist_used）",
		"enabled_modules": ["lobbyists"],
		"builder": "milestone_first_lobbyist_used",
		"purpose": "验证 Lobbyists 子阶段放置道路会触发 first_lobbyist_used，并为该玩家生成 extra tile 放置权限。",
		"steps": [
			"载入后应处于 Working/Lobbyists，且玩家 0 在岗包含 lobbyist。",
			"按说明文件的推荐参数执行「放置道路（说客）」动作（place_lobbyists_road）。",
		],
		"expected": [
			"玩家 0 获得里程碑 first_lobbyist_used（player.milestones）。",
			"round_state.lobbyists_extra_tile_pending[0] == true（随后可执行 place_lobbyists_extra_map_tile）。",
		],
		"related_tests": [
			"core/tests/lobbyists_v2_test.gd",
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

