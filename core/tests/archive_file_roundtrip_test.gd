# 存档文件读写回归测试
# 覆盖：
# - save_to_file -> load_from_file 的完整 roundtrip（包含 JSON stringify/parse）
# - initial_state/commands/rng/modules_v2_base_dir 的基本一致性
class_name ArchiveFileRoundtripTest
extends RefCounted

const ActionIdsClass = preload("res://core/actions/action_ids.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	# 注入一个包含 Vector2i 的营销实例，覆盖“非 map 字段”的 Vector2i 存档回读。
	# 注意：Archive.initial_state 来自 checkpoints[0].state_dict，因此这里同步更新 checkpoint0，确保 replay 后状态一致。
	var s0 := engine.get_state()
	if s0 != null:
		s0.marketing_instances.append({
			"board_number": 99,
			"type": "__test__",
			"owner": 0,
			"employee_type": "__test__",
			"product": "burger",
			"world_pos": Vector2i(0, 0),
			"remaining_duration": 1,
			"axis": "",
			"tile_index": 0,
			"created_round": s0.round_number,
		})
		if engine.checkpoints.size() > 0 and (engine.checkpoints[0] is Dictionary):
			var cp0: Dictionary = engine.checkpoints[0]
			cp0["state_dict"] = s0.to_dict().duplicate(true)
			cp0["hash"] = s0.compute_hash()
			engine.checkpoints[0] = cp0

	# 生成至少 1 条命令，覆盖 commands/timestamp 的序列化与回放
	var adv := engine.execute_command(Command.create_system(ActionIdsClass.ADVANCE_PHASE))
	if not adv.ok:
		return Result.failure("预置命令 advance_phase 失败: %s" % adv.error)

	var save_path := "user://archive_roundtrip_test.json"
	var save_r := engine.save_to_file(save_path)
	if not save_r.ok:
		return Result.failure("保存失败: %s" % save_r.error)
	if not FileAccess.file_exists(save_path):
		return Result.failure("保存后文件不存在: %s" % save_path)

	var engine2 := GameEngine.new()
	var load_r := engine2.load_from_file(save_path)
	if not load_r.ok:
		return Result.failure("加载失败: %s" % load_r.error)

	var s1 := engine.get_state()
	var s2 := engine2.get_state()
	if s1 == null or s2 == null:
		return Result.failure("加载后 GameState 为空")

	# 关键类型回归：JSON -> state 解码后应恢复 Vector2i（避免 UI/规则层使用时报类型错误）
	var map2 = s2.map
	if not (map2 is Dictionary):
		return Result.failure("加载后 state.map 类型错误（期望 Dictionary）")
	var map_origin_val = map2.get("map_origin", null)
	if not (map_origin_val is Vector2i):
		return Result.failure("加载后 state.map.map_origin 类型错误（期望 Vector2i），实际: %s" % str(typeof(map_origin_val)))
	var grid_size_val = map2.get("grid_size", null)
	if not (grid_size_val is Vector2i):
		return Result.failure("加载后 state.map.grid_size 类型错误（期望 Vector2i），实际: %s" % str(typeof(grid_size_val)))
	var tile_grid_size_val = map2.get("tile_grid_size", null)
	if not (tile_grid_size_val is Vector2i):
		return Result.failure("加载后 state.map.tile_grid_size 类型错误（期望 Vector2i），实际: %s" % str(typeof(tile_grid_size_val)))
	var tps_val = map2.get("tile_placements", null)
	if tps_val is Array and not Array(tps_val).is_empty():
		var tp0 = Array(tps_val)[0]
		if tp0 is Dictionary:
			var board_pos_val = tp0.get("board_pos", null)
			if not (board_pos_val is Vector2i):
				return Result.failure("加载后 state.map.tile_placements[0].board_pos 类型错误（期望 Vector2i），实际: %s" % str(typeof(board_pos_val)))

	# marketing_instances[*].world_pos 也应为 Vector2i（加载后不得保留为 Array）
	if s2.marketing_instances.size() > 0:
		var inst0 = s2.marketing_instances[0]
		if inst0 is Dictionary:
			var world_pos_val = Dictionary(inst0).get("world_pos", null)
			if not (world_pos_val is Vector2i):
				return Result.failure("加载后 marketing_instances[0].world_pos 类型错误（期望 Vector2i），实际: %s" % str(typeof(world_pos_val)))

	var h1 := str(s1.compute_hash())
	var h2 := str(s2.compute_hash())
	if h1 != h2:
		return Result.failure("存档回读 hash 不一致: %s vs %s" % [h1, h2])

	var invalid_base_dir_r := _test_invalid_modules_base_dir_rejected(player_count, seed_val + 901)
	if not invalid_base_dir_r.ok:
		return invalid_base_dir_r

	var legacy_reserve_r := _test_legacy_default_reserve_card_cash_migration(player_count, seed_val + 902)
	if not legacy_reserve_r.ok:
		return legacy_reserve_r

	return Result.success({
		"save_path": save_path,
		"hash": h1.substr(0, 8),
		"commands": engine.get_command_history().size(),
	})

static func _test_invalid_modules_base_dir_rejected(player_count: int, seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化 invalid modules_v2_base_dir 用例失败: %s" % init.error)

	var archive_r := engine.create_archive()
	if not archive_r.ok:
		return Result.failure("创建存档失败: %s" % archive_r.error)
	var archive: Dictionary = archive_r.value
	archive["modules_v2_base_dir"] = "/tmp/not_res_modules"

	var loaded := GameEngine.new()
	var load_r := loaded.load_from_archive(archive)
	if load_r.ok:
		return Result.failure("非法 modules_v2_base_dir 的存档不应回退默认目录后加载成功")
	if str(load_r.error).find("modules_v2_base_dir") < 0:
		return Result.failure("错误信息应包含 modules_v2_base_dir，实际: %s" % load_r.error)

	return Result.success()

static func _test_legacy_default_reserve_card_cash_migration(player_count: int, seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化旧储备卡迁移用例失败: %s" % init.error)

	var archive_r := engine.create_archive()
	if not archive_r.ok:
		return Result.failure("创建旧储备卡迁移存档失败: %s" % archive_r.error)
	var archive: Dictionary = archive_r.value
	var initial: Dictionary = Dictionary(archive.get("initial_state", {})).duplicate(true)
	var players_val = initial.get("players", null)
	if not (players_val is Array):
		return Result.failure("测试前提不成立：initial_state.players 类型错误")
	var players: Array = (players_val as Array).duplicate(true)
	for pid in range(players.size()):
		if not (players[pid] is Dictionary):
			return Result.failure("测试前提不成立：players[%d] 类型错误" % pid)
		var player: Dictionary = Dictionary(players[pid]).duplicate(true)
		var cards_val = player.get("reserve_cards", null)
		if not (cards_val is Array):
			return Result.failure("测试前提不成立：players[%d].reserve_cards 类型错误" % pid)
		var cards: Array = (cards_val as Array).duplicate(true)
		var legacy_cash: Array[int] = [50, 100, 150]
		for i in range(legacy_cash.size()):
			if i >= cards.size() or not (cards[i] is Dictionary):
				return Result.failure("测试前提不成立：players[%d].reserve_cards[%d] 类型错误" % [pid, i])
			var card: Dictionary = Dictionary(cards[i]).duplicate(true)
			card["cash"] = legacy_cash[i]
			cards[i] = card
		player["reserve_cards"] = cards
		players[pid] = player
	initial["players"] = players
	archive["initial_state"] = initial
	archive["commands"] = []
	archive["current_index"] = -1

	var loaded := GameEngine.new()
	var load_r := loaded.load_from_archive(archive)
	if not load_r.ok:
		return Result.failure("旧默认储备卡金额存档加载失败: %s" % load_r.error)
	var state := loaded.get_state()
	if state == null:
		return Result.failure("旧默认储备卡金额存档加载后 state 为空")
	for pid in range(state.players.size()):
		var player: Dictionary = state.players[pid]
		var check_r := _assert_default_reserve_card_cash(player.get("reserve_cards", null), "loaded.players[%d].reserve_cards" % pid)
		if not check_r.ok:
			return check_r
	var warning_seen := false
	for warning in load_r.warnings:
		if str(warning).find("旧默认储备卡金额") >= 0:
			warning_seen = true
			break
	if not warning_seen:
		return Result.failure("旧默认储备卡金额迁移应返回 warning")

	return Result.success()

static func _assert_default_reserve_card_cash(cards_val, path: String) -> Result:
	if not (cards_val is Array):
		return Result.failure("%s 类型错误（期望 Array）" % path)
	var cards: Array = cards_val
	var expected_cash: Array[int] = [100, 200, 300]
	if cards.size() != expected_cash.size():
		return Result.failure("%s 张数应为 %d，实际: %d" % [path, expected_cash.size(), cards.size()])
	for i in range(expected_cash.size()):
		if not (cards[i] is Dictionary):
			return Result.failure("%s[%d] 类型错误（期望 Dictionary）" % [path, i])
		var card: Dictionary = cards[i]
		if int(card.get("cash", -1)) != expected_cash[i]:
			return Result.failure("%s[%d].cash 应为 %d，实际: %s" % [path, i, expected_cash[i], str(card.get("cash", null))])
	return Result.success()
