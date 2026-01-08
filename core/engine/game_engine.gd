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
const ReplayClass = preload("res://core/engine/game_engine/replay.gd")
const DiagnosticsClass = preload("res://core/engine/game_engine/diagnostics.gd")
const GameDefaultsClass = preload("res://core/engine/game_defaults.gd")
const ModulesV2Class = preload("res://core/engine/game_engine/modules_v2.gd")

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
	modules_v2_base_dir: String = "",
	reserve_card_selected_by_player: Array[int] = []
) -> Result:
	return InitializerClass.initialize_new_game(self, player_count, seed_value, enabled_modules_v2, modules_v2_base_dir, reserve_card_selected_by_player)

# 从存档恢复
func load_from_archive(archive: Dictionary) -> Result:
	return LoaderClass.load_from_archive(self, archive)

func _reset_modules_v2() -> void:
	ModulesV2Class.reset(self)

func _apply_modules_v2(module_ids: Array[String], base_dir: String) -> Result:
	return ModulesV2Class.apply(self, module_ids, base_dir)

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
