# 游戏引擎
# 命令执行入口，支持回放、存档、校验点
class_name GameEngine
extends RefCounted

const MapBakerClass = preload("res://core/map/map_baker.gd")
const MapRuntimeClass = preload("res://core/map/map_runtime.gd")
const GameConfigClass = preload("res://core/data/game_config.gd")
const ActionWiringClass = preload("res://core/engine/game_engine/action_wiring.gd")
const CheckpointsClass = preload("res://core/engine/game_engine/checkpoints.gd")
const InvariantsClass = preload("res://core/engine/game_engine/invariants.gd")
const ArchiveClass = preload("res://core/engine/game_engine/archive.gd")
const ReplayClass = preload("res://core/engine/game_engine/replay.gd")
const DiagnosticsClass = preload("res://core/engine/game_engine/diagnostics.gd")
const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
const ModulesV2Class = preload("res://core/engine/game_engine/modules_v2.gd")
const AutoAdvanceClass = preload("res://core/engine/game_engine/auto_advance.gd")

# === 模块系统 V2（Strict Mode，逐步落地） ===
const EmployeePoolPatchRegistryClass = preload("res://core/rules/employee_pool_patch_registry.gd")
const TileRegistryClass = preload("res://core/map/tile_registry.gd")

# === 核心组件 ===
var state: GameState
var phase_manager: PhaseManager
var action_registry: ActionRegistry
var random_manager: RandomManager
var game_data: GameData = null

# 模块系统 V2（每局内容与启用计划；当前阶段仅装配，不接管运行时）
var module_plan_v2: Array[String] = []
var module_manifests_v2: Dictionary = {}  # module_id -> ModuleManifest
var content_catalog_v2 = null  # ContentCatalog
var ruleset_v2 = null  # RulesetV2
var modules_v2_base_dir: String = ""

# === 命令历史 ===
var command_history: Array[Command] = []
var current_command_index: int = -1

# === 校验点 ===
var checkpoints: Array[Dictionary] = []  # [{index, state_dict, hash}]
var checkpoint_interval: int = 50  # 每 N 条命令创建校验点

# === 配置 ===
var validate_invariants: bool = true

# 用于不变量检查（现金守恒）
var _initial_total_cash: int = 0
# 用于不变量检查（员工供应池守恒）
var _initial_employee_totals: Dictionary = {}  # employee_id -> total_count (pool + all players)

# === 内部工具 ===

func _ensure_initialized() -> Result:
	if state == null:
		return Result.failure("游戏引擎未初始化")
	if action_registry == null:
		return Result.failure("ActionRegistry 未初始化")
	if random_manager == null:
		return Result.failure("RandomManager 未初始化")
	return Result.success()

# 若曾 rewind 到历史中的某个位置，再执行新命令会产生“分支”。
# 当前实现选择丢弃未来命令与未来校验点，保持线性时间线。
func _truncate_future_history() -> void:
	var target_size := current_command_index + 1
	if target_size >= command_history.size():
		return

	while command_history.size() > target_size:
		command_history.pop_back()

	# checkpoint.index 表示“已执行命令数”（command_history.size()）
	for i in range(checkpoints.size() - 1, -1, -1):
		var checkpoint_val = checkpoints[i]
		assert(checkpoint_val is Dictionary, "GameEngine._truncate_future_history: checkpoint 类型错误（期望 Dictionary）")
		var checkpoint: Dictionary = checkpoint_val
		assert(checkpoint.has("index"), "GameEngine._truncate_future_history: checkpoint 缺少字段: index")
		assert(checkpoint["index"] is int, "GameEngine._truncate_future_history: checkpoint.index 类型错误（期望 int）")
		var checkpoint_index: int = int(checkpoint["index"])
		if checkpoint_index > target_size:
			checkpoints.remove_at(i)

# === 初始化 ===

func _init() -> void:
	phase_manager = PhaseManager.new()
	action_registry = ActionRegistry.new()
	_reset_modules_v2()

func _setup_action_registry(piece_registry: Dictionary = {}) -> Result:
	return ActionWiringClass.setup_action_registry(self, piece_registry)

# 初始化新游戏
func initialize(
	player_count: int,
	seed_value: int,
	enabled_modules_v2: Array[String] = [],
	modules_v2_base_dir: String = ""
) -> Result:
	_reset_modules_v2()
	var init_warnings: Array[String] = []

	if enabled_modules_v2.is_empty():
		enabled_modules_v2 = GameDefaultsClass.build_default_enabled_modules_v2()
	if modules_v2_base_dir.is_empty():
		modules_v2_base_dir = GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR

	var config_result := GameConfigClass.load_default()
	if not config_result.ok:
		return Result.failure("加载 GameConfig 失败: %s" % config_result.error)

	random_manager = RandomManager.new(seed_value)

	var modules_v2_result := _apply_modules_v2(enabled_modules_v2, modules_v2_base_dir)
	if not modules_v2_result.ok:
		return modules_v2_result
	init_warnings.append_array(modules_v2_result.warnings)

	var cfg = config_result.value
	var inv_check := ModulesV2Class.validate_starting_inventory_products(cfg)
	if not inv_check.ok:
		return inv_check

	var data_result := GameData.from_catalog(content_catalog_v2)
	if not data_result.ok:
		return Result.failure("加载数据失败: %s" % data_result.error)
	game_data = data_result.value
	var setup_actions := _setup_action_registry(game_data.pieces)
	if not setup_actions.ok:
		return Result.failure("初始化失败：ActionRegistry 设置失败: %s" % setup_actions.error)

	var state_result := GameState.create_initial_state_with_rng(player_count, seed_value, random_manager, config_result.value)
	if not state_result.ok:
		return Result.failure("创建初始状态失败: %s" % state_result.error)
	state = state_result.value
	state.modules = Array(module_plan_v2, TYPE_STRING, "", null)
	state.round_state["phase_order"] = phase_manager.get_phase_order_names()

	var pool_patch_state := EmployeePoolPatchRegistryClass.apply_to_state(state)
	if not pool_patch_state.ok:
		return Result.failure("初始化失败：employee_pool patch 应用失败: %s" % pool_patch_state.error)

	# 地图烘焙并写入 state.map（M2）
	var map_opt_result := game_data.get_map_for_player_count(player_count)
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
		if not module_plan_v2.has(mid):
			return Result.failure("地图需要模块但未启用: %s (map=%s)" % [mid, map_option.id])

	if ruleset_v2 == null or ruleset_v2.map_generation_registry == null or not ruleset_v2.map_generation_registry.has_primary():
		return Result.failure("模块系统 V2：缺少 primary map generator（地图生成器）")

	var map_def_read: Result = ruleset_v2.map_generation_registry.generate_map_def(player_count, content_catalog_v2, map_option, random_manager)
	if not map_def_read.ok:
		return Result.failure("生成地图失败: %s" % map_def_read.error)
	var map_def: MapDef = map_def_read.value

	var bake_result := MapBakerClass.bake(map_def, game_data.tiles, game_data.pieces)
	if not bake_result.ok:
		return Result.failure("地图烘焙失败: %s" % bake_result.error)
	var apply_map_result := MapRuntimeClass.apply_baked_map(state, bake_result.value)
	if not apply_map_result.ok:
		return Result.failure("写入地图失败: %s" % apply_map_result.error)
	var tile_supply_init := _initialize_tile_supply_remaining(state)
	if not tile_supply_init.ok:
		return Result.failure("初始化失败：%s" % tile_supply_init.error)

	# V2：模块可在初始化阶段对 state 做确定性的补丁（例如：新增 per-player token / map 扩展字段）
	if ruleset_v2 != null and ruleset_v2.has_method("apply_state_initializers"):
		var init_state_r: Result = ruleset_v2.apply_state_initializers(state, random_manager)
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
	# _initial_total_cash 语义：不包含“后续注入/移除”的 delta（以便 invariant 使用 base + delta 计算）。
	_initial_total_cash = int(total_cash_read.value) - int(state.bank["reserve_added_total"]) + int(state.bank["removed_total"])

	var employee_totals_read := InvariantsClass.compute_employee_totals(state)
	if not employee_totals_read.ok:
		return Result.failure("初始化失败：无法计算初始员工总量: %s" % employee_totals_read.error)
	_initial_employee_totals = employee_totals_read.value

	command_history.clear()
	checkpoints.clear()
	current_command_index = -1

	# 创建初始校验点
	_create_checkpoint(0)

	GameLog.info("GameEngine", "游戏初始化完成 - 玩家: %d, 种子: %d" % [player_count, seed_value])

	# 发送游戏开始事件
	EventBus.emit_event(EventBus.EventType.GAME_STARTED, {
		"player_count": player_count,
		"seed": seed_value,
		"state_hash": state.compute_hash()
	})

	return Result.success(state).with_warnings(init_warnings)

func _initialize_tile_supply_remaining(state_in: GameState) -> Result:
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

# 从存档恢复
func load_from_archive(archive: Dictionary) -> Result:
	_reset_modules_v2()
	# 验证存档格式
	if not archive.has("initial_state") or not archive.has("commands"):
		return Result.failure("无效的存档格式")
	if not archive.has("schema_version"):
		return Result.failure("无效的存档格式: schema_version")
	var schema_read := _parse_int_value(archive["schema_version"], "archive.schema_version")
	if not schema_read.ok:
		return schema_read
	var schema_version: int = int(schema_read.value)
	if schema_version != GameState.SCHEMA_VERSION:
		return Result.failure("不支持的存档 schema_version: %d (期望: %d)" % [schema_version, GameState.SCHEMA_VERSION])

	# 恢复初始状态
	var initial_state_val = archive.get("initial_state", null)
	if initial_state_val == null or not (initial_state_val is Dictionary):
		return Result.failure("无效的存档格式: initial_state")
	var initial_data: Dictionary = initial_state_val
	var state_result := GameState.from_dict(initial_data)
	if not state_result.ok:
		return Result.failure("无效的 initial_state: %s" % state_result.error)
	state = state_result.value

	var rng_val = archive.get("rng", null)
	if not (rng_val is Dictionary):
		return Result.failure("无效的存档格式: rng")
	var rng_data: Dictionary = rng_val
	if rng_data.is_empty():
		return Result.failure("无效的存档格式: rng 不能为空")
	var rng_result := RandomManager.from_dict(rng_data)
	if not rng_result.ok:
		return Result.failure("无效的存档 rng: %s" % rng_result.error)
	random_manager = rng_result.value

	# V2 strict：必须从存档 state.modules 装配当前对局内容（employees/milestones）与 ruleset
	if not (state.modules is Array) or state.modules.is_empty():
		return Result.failure("无效的 initial_state：modules 不能为空（需要模块系统 V2 装配）")

	var base_dir := GameDefaultsClass.DEFAULT_MODULES_V2_BASE_DIR
	if archive.has("modules_v2_base_dir"):
		var base_dir_val = archive.get("modules_v2_base_dir", null)
		if not (base_dir_val is String):
			return Result.failure("无效的存档格式: modules_v2_base_dir")
		var base_dir_read: String = str(base_dir_val).strip_edges()
		if base_dir_read.is_empty():
			return Result.failure("无效的存档格式: modules_v2_base_dir 不能为空")
		base_dir = base_dir_read

	var modules_v2_read := _apply_modules_v2(Array(state.modules, TYPE_STRING, "", null), base_dir)
	if not modules_v2_read.ok:
		return Result.failure("存档加载失败：模块系统 V2 装配失败: %s" % modules_v2_read.error)
	var expected_plan := Array(state.modules, TYPE_STRING, "", null)
	if module_plan_v2 != expected_plan:
		return Result.failure("存档加载失败：模块计划不一致: archive=%s current=%s" % [str(expected_plan), str(module_plan_v2)])

	var data_result := GameData.from_catalog(content_catalog_v2)
	if not data_result.ok:
		return Result.failure("加载数据失败: %s" % data_result.error)
	game_data = data_result.value
	var setup_actions := _setup_action_registry(game_data.pieces)
	if not setup_actions.ok:
		return Result.failure("存档加载失败：ActionRegistry 设置失败: %s" % setup_actions.error)

	var total_cash_read := InvariantsClass.compute_total_cash(state)
	if not total_cash_read.ok:
		return Result.failure("无效的 initial_state：无法计算初始现金总额: %s" % total_cash_read.error)
	if not (state.bank is Dictionary):
		return Result.failure("无效的 initial_state：state.bank 类型错误（期望 Dictionary）")
	if not state.bank.has("reserve_added_total") or not (state.bank["reserve_added_total"] is int):
		return Result.failure("无效的 initial_state：state.bank.reserve_added_total 缺失或类型错误（期望 int）")
	if not state.bank.has("removed_total") or not (state.bank["removed_total"] is int):
		return Result.failure("无效的 initial_state：state.bank.removed_total 缺失或类型错误（期望 int）")
	# _initial_total_cash 语义：不包含“后续注入/移除”的 delta（以便 invariant 使用 base + delta 计算）。
	_initial_total_cash = int(total_cash_read.value) - int(state.bank["reserve_added_total"]) + int(state.bank["removed_total"])
	var employee_totals_read := InvariantsClass.compute_employee_totals(state)
	if not employee_totals_read.ok:
		return Result.failure("无效的 initial_state：无法计算初始员工总量: %s" % employee_totals_read.error)
	_initial_employee_totals = employee_totals_read.value

	# 重放命令
	command_history.clear()
	checkpoints.clear()
	current_command_index = -1

	_create_checkpoint(0)

	var commands_val = archive.get("commands", null)
	if commands_val == null or not (commands_val is Array):
		return Result.failure("无效的存档格式: commands")

	var commands: Array = commands_val
	for i in range(commands.size()):
		var cmd_data = commands[i]
		if not (cmd_data is Dictionary):
			return Result.failure("回放命令 #%d 格式错误" % i)
		var cmd_read := Command.from_dict(cmd_data)
		if not cmd_read.ok:
			return Result.failure("回放命令 #%d 无效: %s" % [i, cmd_read.error])
		var cmd: Command = cmd_read.value
		if cmd.timestamp < 0:
			return Result.failure("回放命令 #%d 缺少 timestamp" % i)
		var result := execute_command(cmd, true)  # 回放模式
		if not result.ok:
			return Result.failure("回放命令 #%d 失败: %s" % [i, result.error])

	# 若存档记录了当前指针（undo/redo），则回到该位置
	if not archive.has("current_index"):
		return Result.failure("无效的存档格式: current_index")
	var desired_index_read := _parse_int_value(archive["current_index"], "archive.current_index")
	if not desired_index_read.ok:
		return desired_index_read
	var desired_index: int = int(desired_index_read.value)
	if desired_index < -1 or desired_index >= command_history.size():
		return Result.failure("无效的 current_index: %s" % str(archive["current_index"]))
	if desired_index != command_history.size() - 1:
		var rewind_result := rewind_to_command(desired_index)
		if not rewind_result.ok:
			return Result.failure("回退到 current_index 失败: %s" % rewind_result.error)

	GameLog.info("GameEngine", "存档加载完成 - 回放 %d 条命令 (current: %d)" % [
		command_history.size(), current_command_index
	])
	return Result.success(state)

func _reset_modules_v2() -> void:
	ModulesV2Class.reset(self)

func _apply_modules_v2(module_ids: Array[String], base_dir: String) -> Result:
	return ModulesV2Class.apply(self, module_ids, base_dir)

# 解析“应为整数”的值：允许 JSON 数字用 float 表示，但必须是整值；不允许小数与字符串等容错。
func _parse_int_value(value, path: String) -> Result:
	if value is int:
		return Result.success(int(value))
	if value is float:
		var f: float = float(value)
		if f != floor(f):
			return Result.failure("%s 必须为整数（不允许小数），实际: %s" % [path, str(value)])
		return Result.success(int(f))
	return Result.failure("%s 类型错误（期望整数），实际: %s" % [path, typeof(value)])

# === 命令执行 ===

# 执行命令
func execute_command(command: Command, is_replay: bool = false) -> Result:
	var init_check := _ensure_initialized()
	if not init_check.ok:
		return init_check

	# 若不在命令末尾执行新命令，则视为开始新分支：丢弃未来命令/校验点
	if not is_replay and current_command_index < command_history.size() - 1:
		_truncate_future_history()

	# 获取执行器
	var executor := action_registry.get_executor(command.action_id)
	if executor == null:
		return Result.failure("未知的动作: %s" % command.action_id)

	# 填充命令上下文
	if command.phase.is_empty():
		command.phase = state.phase
	if command.sub_phase.is_empty():
		command.sub_phase = state.sub_phase

	# 仅在“运行时执行”（非回放）写入确定性的游戏内时间戳
	if not is_replay:
		command.timestamp = PhaseManager.compute_timestamp(state)
	else:
		# 回放命令必须带 timestamp（禁止兼容旧存档）
		if command.timestamp < 0:
			return Result.failure("回放命令缺少 timestamp: %s" % str(command))

	# 运行全局校验器
	var validator_result := action_registry.run_validators(state, command)
	if not validator_result.ok:
		return validator_result

	# 执行动作
	var execute_result := executor.compute_new_state(state, command)
	if not execute_result.ok:
		return execute_result

	var old_state := state
	var new_state: GameState = execute_result.value

	# 生成事件
	var events := executor.generate_events(old_state, new_state, command)
	events.append_array(_build_player_cash_changed_events(old_state, new_state, command))

	# 自动推进（首轮无操作阶段 / 结算阶段默认跳过）
	var auto_r := _drain_auto_advances(new_state)
	if not auto_r.ok:
		return auto_r
	if auto_r.value is Dictionary:
		var auto_info: Dictionary = auto_r.value
		var auto_events_val = auto_info.get("events", null)
		if auto_events_val is Array:
			events.append_array(Array(auto_events_val))
	new_state = auto_r.value.get("state", new_state) if (auto_r.value is Dictionary) else new_state

	# 更新状态
	state = new_state

	# 记录命令
	command.index = command_history.size()
	command_history.append(command)
	current_command_index = command.index

	# 校验不变量
	if validate_invariants and DebugFlags.validate_invariants:
		var invariant_result := _check_invariants()
		if not invariant_result.ok:
			GameLog.error("GameEngine", "不变量校验失败: %s" % invariant_result.error)
			# 回滚状态
			state = old_state
			command_history.pop_back()
			current_command_index -= 1
			return invariant_result

	# 创建校验点
	if command_history.size() % checkpoint_interval == 0:
		_create_checkpoint(command_history.size())

	# 发送事件
	for event in events:
		EventBus.emit_event(event.type, event.get("data", {}))

	EventBus.emit_event(EventBus.EventType.COMMAND_EXECUTED, {
		"command_index": command.index,
		"action_id": command.action_id,
		"actor": command.actor
	})

	if DebugFlags.verbose_logging:
		GameLog.debug("GameEngine", "执行命令 #%d: %s" % [command.index, command.action_id])

	var all_warnings: Array[String] = []
	all_warnings.append_array(execute_result.warnings)
	all_warnings.append_array(auto_r.warnings)
	return Result.success(state).with_warnings(all_warnings)

func _drain_auto_advances(state_in: GameState) -> Result:
	if state_in == null:
		return Result.failure("auto_advance: state 为空")

	var events: Array[Dictionary] = []
	var all_warnings: Array[String] = []
	var safety := 0

	while safety < 32:
		safety += 1
		var before := state_in.duplicate_state()
		var step := AutoAdvanceClass.try_advance_one(state_in, phase_manager, action_registry)
		if not step.ok:
			return step
		all_warnings.append_array(step.warnings)
		if not bool(step.value):
			break

		events.append_array(_build_phase_change_events(before, state_in))
		events.append_array(_build_player_cash_changed_events(before, state_in, Command.create_system("auto_advance")))

	if safety >= 32:
		return Result.failure("auto_advance: exceeded max steps (possible loop)")

	return Result.success({
		"state": state_in,
		"events": events
	}).with_warnings(all_warnings)

func _build_phase_change_events(old_state: GameState, new_state: GameState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if old_state == null or new_state == null:
		return events

	# 阶段变化事件
	if old_state.phase != new_state.phase:
		events.append({
			"type": EventBus.EventType.PHASE_CHANGED,
			"data": {
				"old_phase": old_state.phase,
				"new_phase": new_state.phase,
				"round": new_state.round_number
			}
		})

		# 回合开始事件
		if old_state.round_number != new_state.round_number:
			events.append({
				"type": EventBus.EventType.ROUND_STARTED,
				"data": {
					"round": new_state.round_number
				}
			})

	# 子阶段变化事件
	if old_state.sub_phase != new_state.sub_phase and not new_state.sub_phase.is_empty():
		events.append({
			"type": EventBus.EventType.SUB_PHASE_CHANGED,
			"data": {
				"old_sub_phase": old_state.sub_phase,
				"new_sub_phase": new_state.sub_phase
			}
		})

	return events

func _build_player_cash_changed_events(old_state: GameState, new_state: GameState, command: Command) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if old_state == null or new_state == null:
		return events
	if not (old_state.players is Array) or not (new_state.players is Array):
		return events

	var count := mini(old_state.players.size(), new_state.players.size())
	for player_id in range(count):
		var old_val = old_state.players[player_id]
		var new_val = new_state.players[player_id]
		if not (old_val is Dictionary) or not (new_val is Dictionary):
			continue
		var old_player: Dictionary = old_val
		var new_player: Dictionary = new_val
		var old_cash := int(old_player.get("cash", 0))
		var new_cash := int(new_player.get("cash", 0))
		if old_cash == new_cash:
			continue
		events.append({
			"type": EventBus.EventType.PLAYER_CASH_CHANGED,
			"data": {
				"player_id": player_id,
				"old_cash": old_cash,
				"new_cash": new_cash,
				"delta": new_cash - old_cash,
				"action_id": str(command.action_id),
				"phase": str(new_state.phase),
				"sub_phase": str(new_state.sub_phase),
			}
		})

	return events

# 批量执行命令
func execute_commands(commands: Array[Command]) -> Result:
	var results: Array[Result] = []
	for i in range(commands.size()):
		var cmd := commands[i]
		var result := execute_command(cmd)
		results.append(result)
		if not result.ok:
			return Result.failure("命令 #%d 执行失败: %s" % [i, result.error])

	return Result.success(results)

# === 回放与倒带 ===

# 回退到指定命令
func rewind_to_command(target_index: int) -> Result:
	var init_check := _ensure_initialized()
	if not init_check.ok:
		return init_check

	var replay_result := ReplayClass.rewind_to_command(command_history, checkpoints, action_registry, phase_manager, target_index)
	if not replay_result.ok:
		return replay_result

	var data: Dictionary = replay_result.value
	if not data.has("state") or not (data["state"] is GameState):
		return Result.failure("内部错误: rewind_result.state 类型错误")
	if not data.has("random_manager") or not (data["random_manager"] is RandomManager):
		return Result.failure("内部错误: rewind_result.random_manager 类型错误")
	if not data.has("current_command_index") or not (data["current_command_index"] is int):
		return Result.failure("内部错误: rewind_result.current_command_index 类型错误")

	state = data["state"]
	random_manager = data["random_manager"]
	current_command_index = data["current_command_index"]
	return Result.success(state)

# 完整重放（从头开始）
func full_replay() -> Result:
	var init_check := _ensure_initialized()
	if not init_check.ok:
		return init_check

	if command_history.is_empty():
		return Result.success(state)

	var replay_result := ReplayClass.full_replay(command_history, checkpoints, action_registry, phase_manager)
	if not replay_result.ok:
		return replay_result

	var data: Dictionary = replay_result.value
	if not data.has("state") or not (data["state"] is GameState):
		return Result.failure("内部错误: replay_result.state 类型错误")
	if not data.has("random_manager") or not (data["random_manager"] is RandomManager):
		return Result.failure("内部错误: replay_result.random_manager 类型错误")
	if not data.has("current_command_index") or not (data["current_command_index"] is int):
		return Result.failure("内部错误: replay_result.current_command_index 类型错误")

	state = data["state"]
	random_manager = data["random_manager"]
	current_command_index = data["current_command_index"]
	return Result.success(state)

# === 校验点管理 ===

func _create_checkpoint(index: int) -> void:
	CheckpointsClass.create_checkpoint(checkpoints, state, random_manager, index)

func _find_nearest_checkpoint(target_index: int) -> Dictionary:
	return CheckpointsClass.find_nearest_checkpoint(checkpoints, target_index)

# 验证校验点哈希
func verify_checkpoints() -> Result:
	return CheckpointsClass.verify_checkpoints(checkpoints)

# === 不变量检查 ===

func _check_invariants() -> Result:
	return InvariantsClass.check_invariants(state, _initial_total_cash, _initial_employee_totals)

# === 存档 ===

# 创建存档
func create_archive() -> Result:
	var init_check := _ensure_initialized()
	if not init_check.ok:
		return init_check
	return ArchiveClass.create_archive(state, random_manager, checkpoints, command_history, current_command_index, modules_v2_base_dir)

# 保存到文件
func save_to_file(path: String) -> Result:
	var init_check := _ensure_initialized()
	if not init_check.ok:
		return init_check

	var archive_result := create_archive()
	if not archive_result.ok:
		return archive_result
	var archive: Dictionary = archive_result.value
	return ArchiveClass.save_archive_to_file(archive, path)

# 从文件加载
func load_from_file(path: String) -> Result:
	var archive_result := ArchiveClass.load_archive_from_file(path)
	if not archive_result.ok:
		return archive_result
	var archive: Dictionary = archive_result.value
	return load_from_archive(archive)

# === 查询方法 ===

# 获取当前状态
func get_state() -> GameState:
	return state

func get_module_plan_v2() -> Array[String]:
	return Array(module_plan_v2, TYPE_STRING, "", null)

func get_content_catalog_v2():
	return content_catalog_v2

# 获取命令历史
func get_command_history() -> Array[Command]:
	return command_history

# 获取特定范围的命令
func get_commands_range(from: int, to: int) -> Array[Command]:
	var result: Array[Command] = []
	for i in range(max(0, from), min(to, command_history.size())):
		result.append(command_history[i])
	return result

# 获取最后 N 条命令
func get_recent_commands(count: int) -> Array[Command]:
	var start = max(0, command_history.size() - count)
	return get_commands_range(start, command_history.size())

# 获取可用动作
func get_available_actions() -> Array[String]:
	if state == null or action_registry == null:
		return []
	return action_registry.get_available_actions(state)

func get_action_registry() -> ActionRegistry:
	return action_registry

# 获取玩家可用动作
func get_player_actions(player_id: int) -> Array[String]:
	if state == null or action_registry == null:
		return []
	return action_registry.get_player_available_actions(state, player_id)

# === 调试 ===

func dump() -> String:
	return DiagnosticsClass.dump(state, command_history, current_command_index, checkpoints)

func get_status() -> Dictionary:
	return DiagnosticsClass.get_status(state, command_history, current_command_index, checkpoints)
