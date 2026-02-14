# 游戏引擎
# 命令执行入口，支持回放、存档、校验点
class_name GameEngine
extends RefCounted

const ActionWiringClass = preload("res://core/engine/game_engine/action_wiring.gd")
const CheckpointsClass = preload("res://core/engine/game_engine/checkpoints.gd")
const CommandRunnerClass = preload("res://core/engine/game_engine/command_runner.gd")
const InitializerClass = preload("res://core/engine/game_engine/initializer.gd")
const InvariantsClass = preload("res://core/engine/game_engine/invariants.gd")
const LoaderClass = preload("res://core/engine/game_engine/loader.gd")
const ArchiveClass = preload("res://core/engine/game_engine/archive.gd")
const CommandIndexQueriesClass = preload("res://core/engine/game_engine/command_index_queries.gd")
const DiagnosticsClass = preload("res://core/engine/game_engine/diagnostics.gd")
const ModulesV2Class = preload("res://core/engine/game_engine/modules_v2.gd")
const RewindOpsClass = preload("res://core/engine/game_engine/rewind_ops.gd")
const AutoloadAccessClass = preload("res://core/utils/autoload_access.gd")

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

# 可注入的事件输出（默认使用 EventBus autoload）
var event_sink = null

# 用于不变量检查（现金守恒）
var _initial_total_cash: int = 0
# 用于不变量检查（员工供应池守恒）
var _initial_employee_totals: Dictionary = {}  # employee_id -> total_count (pool + all players)

# === 内部工具 ===

func ensure_initialized() -> Result:
	if state == null:
		return Result.failure("游戏引擎未初始化")
	if action_registry == null:
		return Result.failure("ActionRegistry 未初始化")
	if random_manager == null:
		return Result.failure("RandomManager 未初始化")
	return Result.success()

# 若曾 rewind 到历史中的某个位置，再执行新命令会产生“分支”。
# 当前实现选择丢弃未来命令与未来校验点，保持线性时间线。
func truncate_future_history() -> void:
	var target_size := current_command_index + 1
	if target_size >= command_history.size():
		return

	while command_history.size() > target_size:
		command_history.pop_back()

	# checkpoint.index 表示“已执行命令数”（command_history.size()）
	for i in range(checkpoints.size() - 1, -1, -1):
		var checkpoint_val = checkpoints[i]
		assert(checkpoint_val is Dictionary, "GameEngine.truncate_future_history: checkpoint 类型错误（期望 Dictionary）")
		var checkpoint: Dictionary = checkpoint_val
		assert(checkpoint.has("index"), "GameEngine.truncate_future_history: checkpoint 缺少字段: index")
		assert(checkpoint["index"] is int, "GameEngine.truncate_future_history: checkpoint.index 类型错误（期望 int）")
		var checkpoint_index: int = int(checkpoint["index"])
		if checkpoint_index > target_size:
			checkpoints.remove_at(i)

func clear_event_history_for_new_session() -> void:
	if event_sink != null:
		if event_sink.has_method("clear_history_and_reset_sequence"):
			event_sink.clear_history_and_reset_sequence()
			return
		if event_sink.has_method("clear_history"):
			event_sink.clear_history()
			return

	var bus = AutoloadAccessClass.get_autoload("EventBus")
	if bus == null:
		return
	if bus.has_method("clear_history_and_reset_sequence"):
		bus.clear_history_and_reset_sequence()
	elif bus.has_method("clear_history"):
		bus.clear_history()

func set_event_sink(sink) -> void:
	event_sink = sink

func emit_event(event_type: String, data: Dictionary) -> void:
	if event_sink != null and event_sink.has_method("emit_event"):
		event_sink.emit_event(event_type, data)
		return
	var bus = AutoloadAccessClass.get_autoload("EventBus")
	if bus != null and bus.has_method("emit_event"):
		bus.emit_event(event_type, data)

# === 初始化 ===

func _init() -> void:
	phase_manager = PhaseManager.new()
	action_registry = ActionRegistry.new()
	reset_modules_v2()

func setup_action_registry(piece_registry: Dictionary = {}) -> Result:
	return ActionWiringClass.setup_action_registry(self, piece_registry)

# 初始化新游戏
func initialize(
	player_count: int,
	seed_value: int,
	enabled_modules_v2: Array[String] = [],
	modules_v2_base_dir: String = "",
	reserve_card_selected_by_player: Array[int] = [],
	restaurant_logo_choices_by_player: Array[int] = []
) -> Result:
	return InitializerClass.initialize_new_game(self, player_count, seed_value, enabled_modules_v2, modules_v2_base_dir, reserve_card_selected_by_player, restaurant_logo_choices_by_player)

# 从存档恢复
func load_from_archive(archive: Dictionary) -> Result:
	return LoaderClass.load_from_archive(self, archive)

func reset_modules_v2() -> void:
	ModulesV2Class.reset(self)

func apply_modules_v2(module_ids: Array[String], base_dir: String) -> Result:
	return ModulesV2Class.apply(self, module_ids, base_dir)

func dispose() -> void:
	if action_registry != null and action_registry.has_method("clear_all"):
		action_registry.clear_all()
	reset_modules_v2()
	if random_manager != null and random_manager.has_method("reset"):
		random_manager.reset()
	CommandRunnerClass.clear_event_build_provider_cache()

	state = null
	game_data = null
	command_history.clear()
	checkpoints.clear()
	current_command_index = -1

	module_plan_v2.clear()
	module_manifests_v2.clear()
	content_catalog_v2 = null
	ruleset_v2 = null
	modules_v2_base_dir = ""

	_initial_total_cash = 0
	_initial_employee_totals.clear()

	event_sink = null
	action_registry = null
	phase_manager = null
	random_manager = null

# 执行命令
func execute_command(command: Command, is_replay: bool = false) -> Result:
	return CommandRunnerClass.execute_command(self, command, is_replay)

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
	return RewindOpsClass.rewind_to_command(self, target_index)

# 完整重放（从头开始）
func full_replay() -> Result:
	return RewindOpsClass.full_replay(self)

# === 校验点管理 ===

func create_checkpoint(index: int) -> void:
	CheckpointsClass.create_checkpoint(checkpoints, state, random_manager, index)

# 验证校验点哈希
func verify_checkpoints() -> Result:
	return CheckpointsClass.verify_checkpoints(checkpoints)

# === 不变量检查 ===

func set_initial_total_cash_for_invariants(total_cash: int) -> void:
	_initial_total_cash = int(total_cash)

func set_initial_employee_totals_for_invariants(employee_totals: Dictionary) -> void:
	_initial_employee_totals = employee_totals

func check_invariants() -> Result:
	return InvariantsClass.check_invariants(state, _initial_total_cash, _initial_employee_totals)

# === 存档 ===

# 创建存档
func create_archive() -> Result:
	var init_check := ensure_initialized()
	if not init_check.ok:
		return init_check
	return ArchiveClass.create_archive(state, random_manager, checkpoints, command_history, current_command_index, modules_v2_base_dir)

# 保存到文件
func save_to_file(path: String) -> Result:
	var init_check := ensure_initialized()
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

func get_checkpoints() -> Array[Dictionary]:
	return checkpoints

# 查找“当前阶段开始”对应的命令索引（用于 UI 的“一键回退本阶段”）。
# 语义：返回 target_index，用于 rewind_to_command(target_index)。
# - 若当前阶段尚未执行任何命令，则返回 current_command_index（回退为 no-op）。
# - 若本局尚未执行任何命令，则返回 -1。
func find_phase_start_command_index() -> Result:
	return CommandIndexQueriesClass.find_phase_start_command_index(self)

# 查找“当前玩家在当前阶段的回合开始”对应的命令索引（用于 UI 的“一键回退当前玩家回合”）。
# 语义：返回 target_index，用于 rewind_to_command(target_index)。
# - 目标是撤销“当前玩家在当前阶段内”的操作（不跨阶段）。
# - 仅依赖 PLAYER_TURN_STARTED 会漏掉“阶段变化但当前玩家不变”的场景（例如 OrderOfBusiness 自动进入 Working），
#   从而把回合开始错误定位到更早的阶段（例如 Payday）。因此这里同时考虑 phase/round 变化。
func find_current_player_turn_start_command_index() -> Result:
	return CommandIndexQueriesClass.find_current_player_turn_start_command_index(self)

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
