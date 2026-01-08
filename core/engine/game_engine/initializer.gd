# GameEngine 初始化流程（抽离自 core/engine/game_engine.gd）
extends RefCounted

const MapBakerClass = preload("res://core/map/map_baker.gd")
const MapRuntimeClass = preload("res://core/map/map_runtime.gd")
const GameConfigClass = preload("res://core/data/game_config.gd")
const InvariantsClass = preload("res://core/engine/game_engine/invariants.gd")
const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
const ModulesV2Class = preload("res://core/engine/game_engine/modules_v2.gd")
const EmployeePoolPatchRegistryClass = preload("res://core/rules/employee_pool_patch_registry.gd")
const TileRegistryClass = preload("res://core/map/tile_registry.gd")

static func initialize_new_game(
	engine: GameEngine,
	player_count: int,
	seed_value: int,
	enabled_modules_v2: Array[String],
	modules_v2_base_dir: String,
	reserve_card_selected_by_player: Array[int] = []
) -> Result:
	engine._reset_modules_v2()
	var init_warnings: Array[String] = []

	if enabled_modules_v2.is_empty():
		enabled_modules_v2 = GameDefaultsClass.build_default_enabled_modules_v2()
	if modules_v2_base_dir.is_empty():
		modules_v2_base_dir = GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR

	var config_result := GameConfigClass.load_default()
	if not config_result.ok:
		return Result.failure("加载 GameConfig 失败: %s" % config_result.error)

	engine.random_manager = RandomManager.new(seed_value)

	var modules_v2_result := engine._apply_modules_v2(enabled_modules_v2, modules_v2_base_dir)
	if not modules_v2_result.ok:
		return modules_v2_result
	init_warnings.append_array(modules_v2_result.warnings)

	var cfg = config_result.value
	var inv_check := ModulesV2Class.validate_starting_inventory_products(cfg)
	if not inv_check.ok:
		return inv_check

	var data_result := GameData.from_catalog(engine.content_catalog_v2)
	if not data_result.ok:
		return Result.failure("加载数据失败: %s" % data_result.error)
	engine.game_data = data_result.value
	var setup_actions := engine._setup_action_registry(engine.game_data.pieces)
	if not setup_actions.ok:
		return Result.failure("初始化失败：ActionRegistry 设置失败: %s" % setup_actions.error)

	var state_result := GameState.create_initial_state_with_rng(player_count, seed_value, engine.random_manager, config_result.value)
	if not state_result.ok:
		return Result.failure("创建初始状态失败: %s" % state_result.error)
	engine.state = state_result.value
	var state: GameState = engine.state
	var reserve_apply := _apply_reserve_card_selections(state, reserve_card_selected_by_player)
	if not reserve_apply.ok:
		return Result.failure("创建初始状态失败：%s" % reserve_apply.error)
	state.modules = Array(engine.module_plan_v2, TYPE_STRING, "", null)
	state.round_state["phase_order"] = engine.phase_manager.get_phase_order_names()

	var pool_patch_state := EmployeePoolPatchRegistryClass.apply_to_state(state)
	if not pool_patch_state.ok:
		return Result.failure("初始化失败：employee_pool patch 应用失败: %s" % pool_patch_state.error)

	var map_opt_result := engine.game_data.get_map_for_player_count(player_count)
	if not map_opt_result.ok:
		return Result.failure("选择地图失败: %s" % map_opt_result.error)
	var map_option = map_opt_result.value

	for i in range(map_option.required_modules.size()):
		var mid_val = map_option.required_modules[i]
		if not (mid_val is String):
			return Result.failure("MapOptionDef.required_modules[%d] 类型错误（期望 String）" % i)
		var mid: String = str(mid_val)
		if mid.is_empty():
			return Result.failure("MapOptionDef.required_modules[%d] 不能为空" % i)
		if not engine.module_plan_v2.has(mid):
			return Result.failure("地图需要模块但未启用: %s (map=%s)" % [mid, map_option.id])

	if engine.ruleset_v2 == null or engine.ruleset_v2.map_generation_registry == null or not engine.ruleset_v2.map_generation_registry.has_primary():
		return Result.failure("模块系统 V2：缺少 primary map generator（地图生成器）")

	var map_def_read: Result = engine.ruleset_v2.map_generation_registry.generate_map_def(player_count, engine.content_catalog_v2, map_option, engine.random_manager)
	if not map_def_read.ok:
		return Result.failure("生成地图失败: %s" % map_def_read.error)
	var map_def: MapDef = map_def_read.value

	var bake_result := MapBakerClass.bake(map_def, engine.game_data.tiles, engine.game_data.pieces)
	if not bake_result.ok:
		return Result.failure("地图烘焙失败: %s" % bake_result.error)
	var apply_map_result := MapRuntimeClass.apply_baked_map(state, bake_result.value)
	if not apply_map_result.ok:
		return Result.failure("写入地图失败: %s" % apply_map_result.error)
	var tile_supply_init := _initialize_tile_supply_remaining(state)
	if not tile_supply_init.ok:
		return Result.failure("初始化失败：%s" % tile_supply_init.error)

	if engine.ruleset_v2 != null and engine.ruleset_v2.has_method("apply_state_initializers"):
		var init_state_r: Result = engine.ruleset_v2.apply_state_initializers(state, engine.random_manager)
		if not init_state_r.ok:
			return Result.failure("初始化失败：state initializer 失败: %s" % init_state_r.error)
		init_warnings.append_array(init_state_r.warnings)

	var total_cash_read := InvariantsClass.compute_total_cash(state)
	if not total_cash_read.ok:
		return Result.failure("初始化失败：无法计算初始现金总额: %s" % total_cash_read.error)
	if not (state.bank is Dictionary):
		return Result.failure("初始化失败：state.bank 类型错误（期望 Dictionary）")
	if not state.bank.has("reserve_added_total") or not (state.bank["reserve_added_total"] is int):
		return Result.failure("初始化失败：state.bank.reserve_added_total 缺失或类型错误（期望 int）")
	if not state.bank.has("removed_total") or not (state.bank["removed_total"] is int):
		return Result.failure("初始化失败：state.bank.removed_total 缺失或类型错误（期望 int）")
	engine._initial_total_cash = int(total_cash_read.value) - int(state.bank["reserve_added_total"]) + int(state.bank["removed_total"])

	var employee_totals_read := InvariantsClass.compute_employee_totals(state)
	if not employee_totals_read.ok:
		return Result.failure("初始化失败：无法计算初始员工总量: %s" % employee_totals_read.error)
	engine._initial_employee_totals = employee_totals_read.value

	engine.command_history.clear()
	engine.checkpoints.clear()
	engine.current_command_index = -1

	engine._create_checkpoint(0)

	GameLog.info("GameEngine", "游戏初始化完成 - 玩家: %d, 种子: %d" % [player_count, seed_value])

	EventBus.emit_event(EventBus.EventType.GAME_STARTED, {
		"player_count": player_count,
		"seed": seed_value,
		"state_hash": state.compute_hash()
	})

	return Result.success(state).with_warnings(init_warnings)

static func _apply_reserve_card_selections(state: GameState, selections: Array[int]) -> Result:
	if state == null:
		return Result.failure("state 为空")
	if selections == null:
		return Result.failure("reserve_card_selected_by_player 为空")
	if selections.is_empty():
		return Result.success()
	if selections.size() != state.players.size():
		return Result.failure("reserve_card_selected_by_player 数量不匹配: got=%d expected=%d" % [selections.size(), state.players.size()])

	for pid in range(state.players.size()):
		var sel_val = selections[pid]
		if not (sel_val is int) and not (sel_val is float):
			return Result.failure("reserve_card_selected_by_player[%d] 类型错误（期望 int）" % pid)
		var sel: int = int(sel_val)

		var p_val = state.players[pid]
		if not (p_val is Dictionary):
			return Result.failure("players[%d] 类型错误（期望 Dictionary）" % pid)
		var player: Dictionary = p_val
		var cards_val = player.get("reserve_cards", null)
		if not (cards_val is Array):
			return Result.failure("players[%d].reserve_cards 缺失或类型错误（期望 Array）" % pid)
		var cards: Array = cards_val
		if sel < 0 or sel >= cards.size():
			return Result.failure("players[%d].reserve_card_selected 越界: %d (cards=%d)" % [pid, sel, cards.size()])

		player["reserve_card_selected"] = sel
		player["reserve_card_revealed"] = false
		state.players[pid] = player

	return Result.success()

static func _initialize_tile_supply_remaining(state_in: GameState) -> Result:
	if state_in == null or not (state_in.map is Dictionary):
		return Result.failure("tile_supply: state.map 类型错误（期望 Dictionary）")
	if not TileRegistryClass.is_loaded():
		return Result.failure("tile_supply: TileRegistry 未初始化")

	var used: Dictionary = {}
	if state_in.map.has("tile_placements") and (state_in.map["tile_placements"] is Array):
		var placements: Array = state_in.map["tile_placements"]
		for i in range(placements.size()):
			var p_val = placements[i]
			if not (p_val is Dictionary):
				return Result.failure("tile_supply: tile_placements[%d] 类型错误（期望 Dictionary）" % i)
			var p: Dictionary = p_val
			var tid_val = p.get("tile_id", null)
			if not (tid_val is String) or str(tid_val).is_empty():
				return Result.failure("tile_supply: tile_placements[%d].tile_id 缺失或类型错误（期望 String）" % i)
			used[str(tid_val)] = true

	if state_in.map.has("external_tile_placements") and (state_in.map["external_tile_placements"] is Array):
		var ext: Array = state_in.map["external_tile_placements"]
		for i in range(ext.size()):
			var p_val = ext[i]
			if not (p_val is Dictionary):
				return Result.failure("tile_supply: external_tile_placements[%d] 类型错误（期望 Dictionary）" % i)
			var p: Dictionary = p_val
			var tid_val = p.get("tile_id", null)
			if not (tid_val is String) or str(tid_val).is_empty():
				return Result.failure("tile_supply: external_tile_placements[%d].tile_id 缺失或类型错误（期望 String）" % i)
			used[str(tid_val)] = true

	var remaining: Array[String] = []
	var all_ids: Array[String] = TileRegistryClass.get_all_ids()
	for tid in all_ids:
		if used.has(tid):
			continue
		remaining.append(tid)

	state_in.map["tile_supply_remaining"] = remaining
	return Result.success(remaining.size())
