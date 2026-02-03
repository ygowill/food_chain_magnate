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

	cases.append(_case({
		"kind": "milestone",
		"id": "first_lobbyist_used_multi_player_same_round",
		"title": "同回合多玩家扩边（first_lobbyist_used）",
		"enabled_modules": ["lobbyists"],
		"builder": "milestone_first_lobbyist_used_multi_player_same_round",
		"purpose": "验证同一回合内多名玩家先后使用说客后，都能获得 first_lobbyist_used 并当场二选一（使用扩边/放弃）；同时扩边产生的 void 区域不应显示红叉 blocked 覆盖。",
		"steps": [
			"载入后应处于 Working/Lobbyists，且玩家 0/1 在岗包含 lobbyist；此时两名玩家都不应已获得 first_lobbyist_used。",
			"玩家 0：放置 1 个「说客道路/公园」（place_lobbyists_road / place_lobbyists_park）以触发里程碑；随后应当场弹出「使用/放弃」二选一；选择“使用”，并在地图上放置 1 个额外 tile（注意扩边后空余区域不应显示红色叉）。",
			"玩家 0：快速跳过后续子阶段直到轮到玩家 1（同一回合内）。",
			"玩家 1：同样放置 1 个「说客道路/公园」触发里程碑；应弹出二选一；选择“使用”，并放置 1 个额外 tile（可复核多名玩家同回合均可扩边）。",
		],
		"expected": [
			"玩家 0/1 均在各自首次使用说客后获得 first_lobbyist_used，并在 Lobbyists 子阶段弹出二选一并成功执行扩边放置。",
			"扩边造成的空余（void）区域不应显示红叉 blocked 覆盖（仍可能用于后续放置/扩边）。",
		],
		"related_tests": [
			"core/tests/lobbyists_v2_test.gd",
			"ui/scenes/tests/map_blocked_overlay_skips_void_cells_test.gd",
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
