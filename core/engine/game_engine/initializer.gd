# GameEngine 初始化流程（抽离自 core/engine/game_engine.gd）
extends RefCounted

const MapBakeClass = preload("res://core/map/map_baker/bake.gd")
const BakedMapClass = preload("res://core/map/map_runtime/baked_map.gd")
const GameConfigClass = preload("res://core/data/game_config.gd")
const InvariantsClass = preload("res://core/engine/game_engine/invariants.gd")
const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
const ModulesV2Class = preload("res://core/engine/game_engine/modules_v2.gd")
const ModuleDirSpecClass = preload("res://core/modules/v2/module_dir_spec.gd")
const EmployeePoolPatchRegistryClass = preload("res://core/rules/employee_pool_patch_registry.gd")
const TileRegistryClass = preload("res://core/map/tile_registry.gd")
const PerfTraceClass = preload("res://core/debug/perf_trace.gd")
const GameStartedEventBuildClass = preload("res://core/engine/game_engine/game_started_event_build.gd")
const AutoloadAccessClass = preload("res://core/utils/autoload_access.gd")
const BankStateAccessClass = preload("res://core/state/bank_state_access.gd")
const CommandRunnerClass = preload("res://core/engine/game_engine/command_runner.gd")

static func initialize_new_game(
	engine: GameEngine,
	player_count: int,
	seed_value: int,
	enabled_modules_v2: Array[String],
	modules_v2_base_dir: String,
	reserve_card_selected_by_player: Array[int] = [],
	restaurant_logo_choices_by_player: Array[int] = []
) -> Result:
	var span_total := PerfTraceClass.begin_span("init:GameEngine.initialize_new_game")
	engine.reset_modules_v2()
	var init_warnings: Array[String] = []

	# EventBus.history 为“单局”语义：新开一局时应清空，避免跨对局的事件混入（影响日志/回退定位等功能）。
	engine.clear_event_history_for_new_session()

	if enabled_modules_v2.is_empty():
		enabled_modules_v2 = GameDefaultsClass.build_default_enabled_modules_v2()
	if modules_v2_base_dir.is_empty():
		modules_v2_base_dir = GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR
	else:
		var base_dirs_read = ModuleDirSpecClass.parse_base_dirs(modules_v2_base_dir)
		if not base_dirs_read.ok:
			return Result.failure("初始化失败：modules_v2_base_dir 无效: %s" % base_dirs_read.error)

	var span_cfg := PerfTraceClass.begin_span("init:GameConfig.load_default")
	var config_result := GameConfigClass.load_default()
	PerfTraceClass.end_span(span_cfg)
	if not config_result.ok:
		return Result.failure("加载 GameConfig 失败: %s" % config_result.error)

	engine.random_manager = RandomManager.new(seed_value)

	var span_modules := PerfTraceClass.begin_span("init:ModulesV2.apply")
	var modules_v2_result := engine.apply_modules_v2(enabled_modules_v2, modules_v2_base_dir)
	PerfTraceClass.end_span(span_modules)
	if not modules_v2_result.ok:
		return modules_v2_result
	init_warnings.append_array(modules_v2_result.warnings)

	var cfg = config_result.value

	# 应用高级配置覆盖 / 游戏选项覆盖。调用方必须通过 GameEngineDependencies 显式注入，
	# 避免 core/server 初始化语义依赖 Globals 这类跨场景单例。
	var injected_config_overrides = null
	var injected_option_overrides = null
	var effective_option_overrides: Dictionary = {}
	if engine.has_method("get_dependencies") and engine.get_dependencies() != null:
		injected_config_overrides = engine.get_dependencies().game_config_overrides
		injected_option_overrides = engine.get_dependencies().game_option_overrides

	if injected_config_overrides != null:
		if not (injected_config_overrides is Dictionary):
			return Result.failure("初始化失败：GameEngineDependencies.game_config_overrides 类型错误（期望 Dictionary）")
		var overrides: Dictionary = injected_config_overrides
		if not overrides.is_empty():
			cfg.apply_overrides(overrides)
			AutoloadAccessClass.log_info("GameEngine", "已应用 %d 项注入的高级配置覆盖" % overrides.size())

	if injected_option_overrides != null:
		if not (injected_option_overrides is Dictionary):
			return Result.failure("初始化失败：GameEngineDependencies.game_option_overrides 类型错误（期望 Dictionary）")
		var opt_overrides: Dictionary = injected_option_overrides
		effective_option_overrides = opt_overrides.duplicate(true)
		if not opt_overrides.is_empty():
			cfg.apply_overrides(opt_overrides)
			AutoloadAccessClass.log_info("GameEngine", "已应用 %d 项注入的游戏选项覆盖" % opt_overrides.size())

	var legacy_short_game := _is_legacy_short_game_option_patch(effective_option_overrides)
	if legacy_short_game:
		cfg.bank_default_per_player = 75
		cfg.rule_bankruptcy_extra_reserve_per_player = 0
		AutoloadAccessClass.log_info("GameEngine", "检测到旧版短游戏配置：已兼容为“银行初始资金 $75/人 + 跳过储备卡选择”")

	var span_inv := PerfTraceClass.begin_span("init:ModulesV2.validate_starting_inventory_products")
	var inv_check := ModulesV2Class.validate_starting_inventory_products(cfg)
	PerfTraceClass.end_span(span_inv)
	if not inv_check.ok:
		return inv_check

	var span_data := PerfTraceClass.begin_span("init:GameData.from_catalog")
	var data_result := GameData.from_catalog(engine.content_catalog_v2)
	PerfTraceClass.end_span(span_data)
	if not data_result.ok:
		return Result.failure("加载数据失败: %s" % data_result.error)
	engine.game_data = data_result.value
	var event_provider_r := CommandRunnerClass.validate_event_build_provider(engine)
	if not event_provider_r.ok:
		return Result.failure("初始化失败：CommandRunner event build provider 设置失败: %s" % event_provider_r.error)
	var span_actions := PerfTraceClass.begin_span("init:ActionRegistry.setup_action_registry")
	var setup_actions := engine.setup_action_registry(engine.game_data.pieces)
	PerfTraceClass.end_span(span_actions)
	if not setup_actions.ok:
		return Result.failure("初始化失败：ActionRegistry 设置失败: %s" % setup_actions.error)

	var span_state := PerfTraceClass.begin_span("init:GameState.create_initial_state_with_rng")
	var logo_provider = null
	if engine.has_method("get_dependencies") and engine.get_dependencies() != null:
		logo_provider = engine.get_dependencies().restaurant_logo_assignment_provider
	var state_result := GameState.create_initial_state_with_rng(
		player_count,
		seed_value,
		engine.random_manager,
		cfg,
		restaurant_logo_choices_by_player,
		logo_provider
	)
	PerfTraceClass.end_span(span_state)
	if not state_result.ok:
		return Result.failure("创建初始状态失败: %s" % state_result.error)
	engine.state = state_result.value
	var state: GameState = engine.state
	var effective_reserve_card_selected_by_player: Array[int] = []
	if reserve_card_selected_by_player != null:
		for sel_val in reserve_card_selected_by_player:
			effective_reserve_card_selected_by_player.append(int(sel_val))
	if effective_reserve_card_selected_by_player.is_empty() and _should_auto_select_reserve_cards(effective_option_overrides, legacy_short_game):
		var auto_select_read := _build_auto_reserve_card_selections(state, cfg)
		if not auto_select_read.ok:
			return Result.failure("创建初始状态失败：%s" % auto_select_read.error)
		effective_reserve_card_selected_by_player = auto_select_read.value
	var reserve_apply := _apply_reserve_card_selections(state, effective_reserve_card_selected_by_player)
	if not reserve_apply.ok:
		return Result.failure("创建初始状态失败：%s" % reserve_apply.error)
	# 若初始化时已注入每位玩家的储备卡选择，则跳过 Setup/ReserveCards，直接进入起始餐厅放置流程。
	if not effective_reserve_card_selected_by_player.is_empty():
		state.sub_phase = ""
		state.current_player_index = max(0, state.turn_order.size() - 1)
	state.modules = Array(engine.module_plan_v2, TYPE_STRING, "", null)
	state.round_state["phase_order"] = engine.phase_manager.get_phase_order_names()

	var span_pool_patch := PerfTraceClass.begin_span("init:EmployeePoolPatchRegistry.apply_to_state")
	var pool_patch_state := EmployeePoolPatchRegistryClass.apply_to_state(state)
	PerfTraceClass.end_span(span_pool_patch)
	if not pool_patch_state.ok:
		return Result.failure("初始化失败：employee_pool patch 应用失败: %s" % pool_patch_state.error)

	var span_map_opt := PerfTraceClass.begin_span("init:GameData.get_map_for_player_count")
	var map_opt_result := engine.game_data.get_map_for_player_count(player_count)
	PerfTraceClass.end_span(span_map_opt)
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

	var span_map_gen := PerfTraceClass.begin_span("init:MapGenerationRegistry.generate_map_def")
	var map_def_read: Result = engine.ruleset_v2.map_generation_registry.generate_map_def(player_count, engine.content_catalog_v2, map_option, engine.random_manager)
	PerfTraceClass.end_span(span_map_gen)
	if not map_def_read.ok:
		return Result.failure("生成地图失败: %s" % map_def_read.error)
	var map_def: MapDef = map_def_read.value

	var span_bake := PerfTraceClass.begin_span("init:MapBake.bake")
	var bake_result := MapBakeClass.bake(map_def, engine.game_data.tiles, engine.game_data.pieces)
	PerfTraceClass.end_span(span_bake)
	if not bake_result.ok:
		return Result.failure("地图烘焙失败: %s" % bake_result.error)
	var span_apply_map := PerfTraceClass.begin_span("init:BakedMap.apply_baked_map")
	var apply_map_result := BakedMapClass.apply_baked_map(state, bake_result.value)
	PerfTraceClass.end_span(span_apply_map)
	if not apply_map_result.ok:
		return Result.failure("写入地图失败: %s" % apply_map_result.error)
	var span_tile_supply := PerfTraceClass.begin_span("init:tile_supply_remaining")
	var tile_supply_init := _initialize_tile_supply_remaining(state)
	PerfTraceClass.end_span(span_tile_supply)
	if not tile_supply_init.ok:
		return Result.failure("初始化失败：%s" % tile_supply_init.error)

	if engine.ruleset_v2 != null and engine.ruleset_v2.has_method("apply_state_initializers"):
		var span_init_state := PerfTraceClass.begin_span("init:RulesetV2.apply_state_initializers")
		var init_state_r: Result = engine.ruleset_v2.apply_state_initializers(state, engine.random_manager)
		PerfTraceClass.end_span(span_init_state)
		if not init_state_r.ok:
			return Result.failure("初始化失败：state initializer 失败: %s" % init_state_r.error)
		init_warnings.append_array(init_state_r.warnings)

	var span_cash := PerfTraceClass.begin_span("init:Invariants.compute_total_cash")
	var total_cash_read := InvariantsClass.compute_total_cash(state)
	PerfTraceClass.end_span(span_cash)
	if not total_cash_read.ok:
		return Result.failure("初始化失败：无法计算初始现金总额: %s" % total_cash_read.error)
	var reserve_added_total_read := BankStateAccessClass.require_reserve_added_total(state, "初始化失败")
	if not reserve_added_total_read.ok:
		return reserve_added_total_read
	var removed_total_read := BankStateAccessClass.require_removed_total(state, "初始化失败")
	if not removed_total_read.ok:
		return removed_total_read
	engine.set_initial_total_cash_for_invariants(int(total_cash_read.value) - int(reserve_added_total_read.value) + int(removed_total_read.value))

	var span_emp_totals := PerfTraceClass.begin_span("init:Invariants.compute_employee_totals")
	var employee_totals_read := InvariantsClass.compute_employee_totals(state)
	PerfTraceClass.end_span(span_emp_totals)
	if not employee_totals_read.ok:
		return Result.failure("初始化失败：无法计算初始员工总量: %s" % employee_totals_read.error)
	engine.set_initial_employee_totals_for_invariants(employee_totals_read.value)

	engine.command_history.clear()
	engine.checkpoints.clear()
	engine.current_command_index = -1

	var span_checkpoint := PerfTraceClass.begin_span("init:GameEngine.create_checkpoint")
	engine.create_checkpoint(0)
	PerfTraceClass.end_span(span_checkpoint)

	AutoloadAccessClass.log_info("GameEngine", "游戏初始化完成 - 玩家: %d, 种子: %d" % [player_count, seed_value])

	var span_state_hash := PerfTraceClass.begin_span("init:GameState.compute_hash")
	var state_hash := state.compute_hash()
	PerfTraceClass.end_span(span_state_hash)

	var span_emit := PerfTraceClass.begin_span("init:GameEngine.emit_event(GAME_STARTED)")
	var started_data_read := GameStartedEventBuildClass.build_from_state(state, str(state_hash))
	if not started_data_read.ok:
		return Result.failure("初始化失败：GAME_STARTED 构建失败: %s" % started_data_read.error).with_warnings(init_warnings)
	var started_data: Dictionary = started_data_read.value
	# 对齐历史行为：seed 取 initialize_new_game(...) 的入参。
	started_data["seed"] = seed_value
	engine.emit_event("game_started", started_data)
	PerfTraceClass.end_span(span_emit)

	PerfTraceClass.end_span(span_total)

	return Result.success(state).with_warnings(init_warnings)

static func _should_auto_select_reserve_cards(option_overrides: Dictionary, legacy_short_game: bool) -> bool:
	if legacy_short_game:
		return true
	if option_overrides == null or option_overrides.is_empty():
		return false
	if not option_overrides.has("setup.auto_select_reserve_cards"):
		return false
	return bool(option_overrides.get("setup.auto_select_reserve_cards", false))

static func _is_legacy_short_game_option_patch(option_overrides: Dictionary) -> bool:
	if option_overrides == null or option_overrides.is_empty():
		return false
	if int(option_overrides.get("rules.salary_cost", -1)) != 0:
		return false
	if int(option_overrides.get("rules.bankruptcy_max_breaks", -1)) != 1:
		return false
	if int(option_overrides.get("rules.bankruptcy_extra_reserve_per_player", -1)) != 75:
		return false
	return true

static func _build_auto_reserve_card_selections(state: GameState, cfg) -> Result:
	if state == null:
		return Result.failure("自动选择储备卡失败：state 为空")
	if cfg == null:
		return Result.failure("自动选择储备卡失败：cfg 为空")
	if not (state.players is Array):
		return Result.failure("自动选择储备卡失败：state.players 类型错误（期望 Array）")

	var selected_index := int(cfg.player_reserve_card_selected)
	var out: Array[int] = []
	for pid in range(state.players.size()):
		var player_val = state.players[pid]
		if not (player_val is Dictionary):
			return Result.failure("自动选择储备卡失败：players[%d] 类型错误（期望 Dictionary）" % pid)
		var player: Dictionary = player_val
		var cards_val = player.get("reserve_cards", null)
		if not (cards_val is Array):
			return Result.failure("自动选择储备卡失败：players[%d].reserve_cards 缺失或类型错误（期望 Array）" % pid)
		var cards: Array = cards_val
		if cards.is_empty():
			return Result.failure("自动选择储备卡失败：players[%d].reserve_cards 不能为空" % pid)
		var idx := clampi(selected_index, 0, cards.size() - 1)
		out.append(idx)
	return Result.success(out)

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
