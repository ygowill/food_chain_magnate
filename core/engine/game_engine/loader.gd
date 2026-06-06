# GameEngine 存档加载（抽离自 core/engine/game_engine.gd）
extends RefCounted

const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
const InvariantsClass = preload("res://core/engine/game_engine/invariants.gd")
const JsonValueParseHelpersClass = preload("res://core/utils/json_value_parse_helpers.gd")
const AutoloadAccessClass = preload("res://core/utils/autoload_access.gd")
const ModuleDirSpecClass = preload("res://core/modules/v2/module_dir_spec.gd")
const BankStateAccessClass = preload("res://core/state/bank_state_access.gd")
const OnlinePerfTraceClass = preload("res://core/debug/online_perf_trace.gd")

const DEFAULT_RESERVE_CARD_TYPES: Array[int] = [5, 10, 20]
const LEGACY_DEFAULT_RESERVE_CARD_CASH: Array[int] = [50, 100, 150]
const DEFAULT_RESERVE_CARD_CASH: Array[int] = [100, 200, 300]
const DEFAULT_RESERVE_CARD_CEO_SLOTS: Array[int] = [2, 3, 4]

static func load_from_archive(engine: GameEngine, archive: Dictionary, progress_callback: Callable = Callable()) -> Result:
	engine.reset_modules_v2()

	var all_warnings: Array[String] = []
	var load_span := OnlinePerfTraceClass.begin_span("engine.archive_load.total", {
		"has_progress_callback": bool(progress_callback.is_valid()),
		"archive_command_count": Array(archive.get("commands", [])).size() if archive.get("commands", null) is Array else -1,
	})

	# EventBus.history 为“单局”语义：加载存档视为进入一局新对局时间线，应清空历史，避免跨对局混入。
	engine.clear_event_history_for_new_session()
	_emit_progress(progress_callback, {
		"stage": "prepare",
		"current": 0,
		"total": 0,
		"ratio": 0.0,
		"round_number": -1,
		"phase": "",
		"sub_phase": "",
	})

	# 验证存档格式
	if not archive.has("initial_state") or not archive.has("commands"):
		OnlinePerfTraceClass.end_span(load_span, {"ok": false, "error": "archive.invalid"})
		return Result.failure("无效的存档格式")
	if not archive.has("schema_version"):
		OnlinePerfTraceClass.end_span(load_span, {"ok": false, "error": "archive.schema_version_missing"})
		return Result.failure("无效的存档格式: schema_version")
	var schema_read := JsonValueParseHelpersClass.parse_int_value(archive["schema_version"], "archive.schema_version")
	if not schema_read.ok:
		OnlinePerfTraceClass.end_span(load_span, {"ok": false, "error": str(schema_read.error)})
		return schema_read
	var schema_version: int = int(schema_read.value)
	if schema_version != GameState.SCHEMA_VERSION:
		OnlinePerfTraceClass.end_span(load_span, {
			"ok": false,
			"error": "archive.schema_version_mismatch",
			"schema_version": int(schema_version),
		})
		return Result.failure("不支持的存档 schema_version: %d (期望: %d)" % [schema_version, GameState.SCHEMA_VERSION])

	# 恢复初始状态
	var initial_state_val = archive.get("initial_state", null)
	if initial_state_val == null or not (initial_state_val is Dictionary):
		OnlinePerfTraceClass.end_span(load_span, {"ok": false, "error": "archive.initial_state_invalid"})
		return Result.failure("无效的存档格式: initial_state")
	var initial_data: Dictionary = (initial_state_val as Dictionary).duplicate(true)

	# V2 strict：必须先按存档 initial_state.modules 装配 ruleset/state schema，再解析 GameState（否则 round_state 的 int-key dict 会在读档后变成 string-key）
	var modules_val = initial_data.get("modules", null)
	if not (modules_val is Array) or (modules_val as Array).is_empty():
		OnlinePerfTraceClass.end_span(load_span, {"ok": false, "error": "archive.modules_missing"})
		return Result.failure("无效的 initial_state：modules 不能为空（需要模块系统 V2 装配）")
	var modules_any: Array = modules_val
	var enabled_modules: Array[String] = []
	var module_seen := {}
	for i in range(modules_any.size()):
		var m_val = modules_any[i]
		if not (m_val is String):
			OnlinePerfTraceClass.end_span(load_span, {"ok": false, "error": "archive.modules_type_invalid", "index": i})
			return Result.failure("无效的 initial_state：modules[%d] 类型错误（期望 String）" % i)
		var mid: String = str(m_val)
		if mid.is_empty():
			OnlinePerfTraceClass.end_span(load_span, {"ok": false, "error": "archive.modules_empty", "index": i})
			return Result.failure("无效的 initial_state：modules[%d] 不能为空" % i)
		if module_seen.has(mid):
			OnlinePerfTraceClass.end_span(load_span, {"ok": false, "error": "archive.modules_duplicate", "module_id": mid})
			return Result.failure("无效的 initial_state：modules 出现重复 id: %s" % mid)
		module_seen[mid] = true
		enabled_modules.append(mid)

	var reserve_migrated := _migrate_legacy_default_reserve_card_cash(initial_data)
	if reserve_migrated > 0:
		all_warnings.append("已迁移旧默认储备卡金额：%d 位玩家从 50/100/150 更新为 100/200/300" % reserve_migrated)

	var base_dir := GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR
	if archive.has("modules_v2_base_dir"):
		var base_dir_val = archive.get("modules_v2_base_dir", null)
		if not (base_dir_val is String):
			return Result.failure("无效的存档格式: modules_v2_base_dir")
		var base_dir_read: String = str(base_dir_val).strip_edges()
		if base_dir_read.is_empty():
			return Result.failure("无效的存档格式: modules_v2_base_dir 不能为空")
		base_dir = base_dir_read
	var base_dirs_read = ModuleDirSpecClass.parse_base_dirs(base_dir)
	if not base_dirs_read.ok:
		OnlinePerfTraceClass.end_span(load_span, {"ok": false, "error": str(base_dirs_read.error)})
		return Result.failure("无效的存档格式: modules_v2_base_dir: %s" % base_dirs_read.error)

	var modules_v2_read := engine.apply_modules_v2(enabled_modules, base_dir)
	if not modules_v2_read.ok:
		OnlinePerfTraceClass.end_span(load_span, {"ok": false, "error": str(modules_v2_read.error)})
		return Result.failure("存档加载失败：模块系统 V2 装配失败: %s" % modules_v2_read.error)
	all_warnings.append_array(modules_v2_read.warnings)
	var expected_plan := Array(enabled_modules, TYPE_STRING, "", null)
	if engine.module_plan_v2 != expected_plan:
		return Result.failure("存档加载失败：模块计划不一致: archive=%s current=%s" % [str(expected_plan), str(engine.module_plan_v2)])

	var state_result := GameState.from_dict(initial_data)
	if not state_result.ok:
		OnlinePerfTraceClass.end_span(load_span, {"ok": false, "error": str(state_result.error)})
		return Result.failure("无效的 initial_state: %s" % state_result.error)
	engine.state = state_result.value
	all_warnings.append_array(state_result.warnings)

	var rng_val = archive.get("rng", null)
	if not (rng_val is Dictionary):
		OnlinePerfTraceClass.end_span(load_span, {"ok": false, "error": "archive.rng_invalid"})
		return Result.failure("无效的存档格式: rng")
	var rng_data: Dictionary = rng_val
	if rng_data.is_empty():
		OnlinePerfTraceClass.end_span(load_span, {"ok": false, "error": "archive.rng_empty"})
		return Result.failure("无效的存档格式: rng 不能为空")
	var rng_result := RandomManager.from_dict(rng_data)
	if not rng_result.ok:
		OnlinePerfTraceClass.end_span(load_span, {"ok": false, "error": str(rng_result.error)})
		return Result.failure("无效的存档 rng: %s" % rng_result.error)
	engine.random_manager = rng_result.value

	var data_result := GameData.from_catalog(engine.content_catalog_v2)
	if not data_result.ok:
		OnlinePerfTraceClass.end_span(load_span, {"ok": false, "error": str(data_result.error)})
		return Result.failure("加载数据失败: %s" % data_result.error)
	engine.game_data = data_result.value
	var setup_actions := engine.setup_action_registry(engine.game_data.pieces)
	if not setup_actions.ok:
		OnlinePerfTraceClass.end_span(load_span, {"ok": false, "error": str(setup_actions.error)})
		return Result.failure("存档加载失败：ActionRegistry 设置失败: %s" % setup_actions.error)

	var total_cash_read := InvariantsClass.compute_total_cash(engine.state)
	if not total_cash_read.ok:
		OnlinePerfTraceClass.end_span(load_span, {"ok": false, "error": str(total_cash_read.error)})
		return Result.failure("无效的 initial_state：无法计算初始现金总额: %s" % total_cash_read.error)
	var reserve_added_total_read := BankStateAccessClass.require_reserve_added_total(engine.state, "无效的 initial_state")
	if not reserve_added_total_read.ok:
		OnlinePerfTraceClass.end_span(load_span, {"ok": false, "error": str(reserve_added_total_read.error)})
		return reserve_added_total_read
	var removed_total_read := BankStateAccessClass.require_removed_total(engine.state, "无效的 initial_state")
	if not removed_total_read.ok:
		OnlinePerfTraceClass.end_span(load_span, {"ok": false, "error": str(removed_total_read.error)})
		return removed_total_read
	# _initial_total_cash 语义：不包含“后续注入/移除”的 delta（以便 invariant 使用 base + delta 计算）。
	engine.set_initial_total_cash_for_invariants(int(total_cash_read.value) - int(reserve_added_total_read.value) + int(removed_total_read.value))
	var employee_totals_read := InvariantsClass.compute_employee_base_totals_for_invariants(engine.state)
	if not employee_totals_read.ok:
		OnlinePerfTraceClass.end_span(load_span, {"ok": false, "error": str(employee_totals_read.error)})
		return Result.failure("无效的 initial_state：无法计算初始员工总量: %s" % employee_totals_read.error)
	engine.set_initial_employee_totals_for_invariants(employee_totals_read.value)

	# 重放命令
	engine.command_history.clear()
	engine.checkpoints.clear()
	engine.current_command_index = -1

	engine.create_checkpoint(0)

	var commands_val = archive.get("commands", null)
	if commands_val == null or not (commands_val is Array):
		OnlinePerfTraceClass.end_span(load_span, {"ok": false, "error": "archive.commands_invalid"})
		return Result.failure("无效的存档格式: commands")

	var commands: Array = commands_val
	var replay_span := OnlinePerfTraceClass.begin_span("engine.archive_load.replay_commands", {
		"command_count": int(commands.size()),
	})
	var last_progress_round := -999999
	var last_progress_phase := "__unset__"
	var last_progress_sub_phase := "__unset__"
	for i in range(commands.size()):
		var cmd_data = commands[i]
		if not (cmd_data is Dictionary):
			OnlinePerfTraceClass.end_span(replay_span, {"ok": false, "error": "command.type_invalid", "index": i})
			OnlinePerfTraceClass.end_span(load_span, {"ok": false, "error": "command.type_invalid", "index": i})
			return Result.failure("回放命令 #%d 格式错误" % i)
		var cmd_read := Command.from_dict(cmd_data)
		if not cmd_read.ok:
			OnlinePerfTraceClass.end_span(replay_span, {"ok": false, "error": str(cmd_read.error), "index": i})
			OnlinePerfTraceClass.end_span(load_span, {"ok": false, "error": str(cmd_read.error), "index": i})
			return Result.failure("回放命令 #%d 无效: %s" % [i, cmd_read.error])
		var cmd: Command = cmd_read.value
		if cmd.timestamp < 0:
			OnlinePerfTraceClass.end_span(replay_span, {"ok": false, "error": "command.timestamp_missing", "index": i})
			OnlinePerfTraceClass.end_span(load_span, {"ok": false, "error": "command.timestamp_missing", "index": i})
			return Result.failure("回放命令 #%d 缺少 timestamp" % i)
		var result := engine.execute_command(cmd, true)  # 回放模式
		if not result.ok:
			OnlinePerfTraceClass.end_span(replay_span, {"ok": false, "error": str(result.error), "index": i})
			OnlinePerfTraceClass.end_span(load_span, {"ok": false, "error": str(result.error), "index": i})
			return Result.failure("回放命令 #%d 失败: %s" % [i, result.error])
		var state_now = engine.get_state()
		var round_number := int(state_now.round_number) if state_now != null else -1
		var phase_name := str(state_now.phase) if state_now != null else ""
		var sub_phase_name := str(state_now.sub_phase) if state_now != null else ""
		var should_emit_progress := i == commands.size() - 1 \
			or (i + 1) % 8 == 0 \
			or round_number != last_progress_round \
			or phase_name != last_progress_phase \
			or sub_phase_name != last_progress_sub_phase
		if should_emit_progress:
			last_progress_round = round_number
			last_progress_phase = phase_name
			last_progress_sub_phase = sub_phase_name
			_emit_progress(progress_callback, {
				"stage": "replay",
				"current": i + 1,
				"total": int(commands.size()),
				"ratio": float(i + 1) / float(maxi(1, commands.size())),
				"round_number": round_number,
				"phase": phase_name,
				"sub_phase": sub_phase_name,
			})

	# 若存档记录了当前指针（undo/redo），则回到该位置
	if not archive.has("current_index"):
		OnlinePerfTraceClass.end_span(replay_span, {"ok": false, "error": "archive.current_index_missing"})
		OnlinePerfTraceClass.end_span(load_span, {"ok": false, "error": "archive.current_index_missing"})
		return Result.failure("无效的存档格式: current_index")
	var desired_index_read := JsonValueParseHelpersClass.parse_int_value(archive["current_index"], "archive.current_index")
	if not desired_index_read.ok:
		OnlinePerfTraceClass.end_span(replay_span, {"ok": false, "error": str(desired_index_read.error)})
		OnlinePerfTraceClass.end_span(load_span, {"ok": false, "error": str(desired_index_read.error)})
		return desired_index_read
	var desired_index: int = int(desired_index_read.value)
	if desired_index < -1 or desired_index >= engine.command_history.size():
		OnlinePerfTraceClass.end_span(replay_span, {"ok": false, "error": "archive.current_index_invalid", "desired_index": desired_index})
		OnlinePerfTraceClass.end_span(load_span, {"ok": false, "error": "archive.current_index_invalid", "desired_index": desired_index})
		return Result.failure("无效的 current_index: %s" % str(archive["current_index"]))
	if desired_index != engine.command_history.size() - 1:
		var rewind_result := engine.rewind_to_command(desired_index)
		if not rewind_result.ok:
			OnlinePerfTraceClass.end_span(replay_span, {"ok": false, "error": str(rewind_result.error), "desired_index": desired_index})
			OnlinePerfTraceClass.end_span(load_span, {"ok": false, "error": str(rewind_result.error), "desired_index": desired_index})
			return Result.failure("回退到 current_index 失败: %s" % rewind_result.error)
	_emit_progress(progress_callback, {
		"stage": "finalize",
		"current": int(engine.current_command_index) + 1,
		"total": int(commands.size()),
		"ratio": 1.0,
		"round_number": int(engine.state.round_number) if engine.state != null else -1,
		"phase": str(engine.state.phase) if engine.state != null else "",
		"sub_phase": str(engine.state.sub_phase) if engine.state != null else "",
	})
	OnlinePerfTraceClass.end_span(replay_span, {
		"ok": true,
		"command_count": int(commands.size()),
		"final_current_index": int(engine.current_command_index),
	})

	AutoloadAccessClass.log_info("GameEngine", "存档加载完成 - 回放 %d 条命令 (current: %d)" % [
		engine.command_history.size(), engine.current_command_index
	])
	OnlinePerfTraceClass.end_span(load_span, {
		"ok": true,
		"command_count": int(engine.command_history.size()),
		"current_index": int(engine.current_command_index),
	})
	return Result.success(engine.state).with_warnings(all_warnings)

static func _migrate_legacy_default_reserve_card_cash(initial_data: Dictionary) -> int:
	var players_val = initial_data.get("players", null)
	if not (players_val is Array):
		return 0
	var players: Array = players_val
	var migrated := 0
	for pid in range(players.size()):
		var player_val = players[pid]
		if not (player_val is Dictionary):
			continue
		var player: Dictionary = player_val
		var cards_val = player.get("reserve_cards", null)
		if not _is_legacy_default_reserve_cards(cards_val):
			continue
		var cards: Array = (cards_val as Array).duplicate(true)
		for i in range(cards.size()):
			var card: Dictionary = cards[i]
			card["cash"] = DEFAULT_RESERVE_CARD_CASH[i]
			cards[i] = card
		player["reserve_cards"] = cards
		players[pid] = player
		migrated += 1
	initial_data["players"] = players
	return migrated

static func _is_legacy_default_reserve_cards(cards_val) -> bool:
	if not (cards_val is Array):
		return false
	var cards: Array = cards_val
	if cards.size() != DEFAULT_RESERVE_CARD_TYPES.size():
		return false
	for i in range(DEFAULT_RESERVE_CARD_TYPES.size()):
		var card_val = cards[i]
		if not (card_val is Dictionary):
			return false
		var card: Dictionary = card_val
		if not (card.get("type", null) is int) or int(card.get("type", -1)) != DEFAULT_RESERVE_CARD_TYPES[i]:
			return false
		if not (card.get("cash", null) is int) or int(card.get("cash", -1)) != LEGACY_DEFAULT_RESERVE_CARD_CASH[i]:
			return false
		if not (card.get("ceo_slots", null) is int) or int(card.get("ceo_slots", -1)) != DEFAULT_RESERVE_CARD_CEO_SLOTS[i]:
			return false
	return true

static func _emit_progress(progress_callback: Callable, payload: Dictionary) -> void:
	if not progress_callback.is_valid():
		return
	progress_callback.call(Dictionary(payload).duplicate(true))
