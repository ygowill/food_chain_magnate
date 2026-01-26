# 游戏引擎
# 命令执行入口，支持回放、存档、校验点
class_name GameEngine
extends RefCounted

const ActionWiringClass = preload("res://core/engine/game_engine/action_wiring.gd")
const AutoAdvanceClass = preload("res://core/engine/game_engine/auto_advance.gd")
const CheckpointsClass = preload("res://core/engine/game_engine/checkpoints.gd")
const CommandRunnerClass = preload("res://core/engine/game_engine/command_runner.gd")
const InitializerClass = preload("res://core/engine/game_engine/initializer.gd")
const InvariantsClass = preload("res://core/engine/game_engine/invariants.gd")
const LoaderClass = preload("res://core/engine/game_engine/loader.gd")
const ArchiveClass = preload("res://core/engine/game_engine/archive.gd")
const ReplayClass = preload("res://core/engine/game_engine/replay.gd")
const EventHistoryRebuildClass = preload("res://core/engine/game_engine/event_history_rebuild.gd")
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

# 可注入的事件输出（默认使用 EventBus autoload）
var event_sink = null

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

func ensure_initialized() -> Result:
	return _ensure_initialized()

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

func truncate_future_history() -> void:
	_truncate_future_history()

func clear_event_history_for_new_session() -> void:
	if event_sink != null:
		if event_sink.has_method("clear_history_and_reset_sequence"):
			event_sink.clear_history_and_reset_sequence()
			return
		if event_sink.has_method("clear_history"):
			event_sink.clear_history()
			return
	if EventBus == null:
		return
	if EventBus.has_method("clear_history_and_reset_sequence"):
		EventBus.clear_history_and_reset_sequence()
	elif EventBus.has_method("clear_history"):
		EventBus.clear_history()

func set_event_sink(sink) -> void:
	event_sink = sink

func emit_event(event_type: String, data: Dictionary) -> void:
	if event_sink != null and event_sink.has_method("emit_event"):
		event_sink.emit_event(event_type, data)
		return
	if EventBus != null and EventBus.has_method("emit_event"):
		EventBus.emit_event(event_type, data)

# === 初始化 ===

func _init() -> void:
	phase_manager = PhaseManager.new()
	action_registry = ActionRegistry.new()
	_reset_modules_v2()

func _setup_action_registry(piece_registry: Dictionary = {}) -> Result:
	return ActionWiringClass.setup_action_registry(self, piece_registry)

func setup_action_registry(piece_registry: Dictionary = {}) -> Result:
	return _setup_action_registry(piece_registry)

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

func _reset_modules_v2() -> void:
	ModulesV2Class.reset(self)

func reset_modules_v2() -> void:
	_reset_modules_v2()

func _apply_modules_v2(module_ids: Array[String], base_dir: String) -> Result:
	return ModulesV2Class.apply(self, module_ids, base_dir)

func apply_modules_v2(module_ids: Array[String], base_dir: String) -> Result:
	return _apply_modules_v2(module_ids, base_dir)

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

	var replay_result: Result = ReplayClass.rewind_to_command(command_history, checkpoints, action_registry, phase_manager, target_index)
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

	# 重要：回退会改变“当前时间线指针”，需要同步重建 EventBus.history，
	# 否则 UI 日志/回放验证会残留未来事件（undo/redo 视觉上不会真的回到过去）。
	var sink = event_sink
	if sink == null or (not sink.has_method("clear_history_and_reset_sequence")) or (not sink.has_method("record_event")):
		sink = EventBus if (EventBus != null) else null
	if sink != null and sink.has_method("clear_history_and_reset_sequence") and sink.has_method("record_event"):
		var history_r: Result = EventHistoryRebuildClass.build(self, target_index)
		if not history_r.ok:
			return Result.failure("回退成功，但重建事件历史失败: %s" % history_r.error).with_warnings(replay_result.warnings)
		var events: Array = history_r.value if (history_r.value is Array) else []
		sink.clear_history_and_reset_sequence()
		for ev_val in events:
			if not (ev_val is Dictionary):
				continue
			var ev: Dictionary = ev_val
			var t: String = str(ev.get("type", "")).strip_edges()
			if t.is_empty():
				continue
			var d_val = ev.get("data", {})
			var d: Dictionary = d_val if (d_val is Dictionary) else {}
			sink.record_event(t, d)
		return Result.success(state).with_warnings(replay_result.warnings).with_warnings(history_r.warnings)

	return Result.success(state).with_warnings(replay_result.warnings)

# 完整重放（从头开始）
func full_replay() -> Result:
	var init_check := _ensure_initialized()
	if not init_check.ok:
		return init_check

	if command_history.is_empty():
		return Result.success(state)

	var replay_result: Result = ReplayClass.full_replay(command_history, checkpoints, action_registry, phase_manager)
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

func create_checkpoint(index: int) -> void:
	_create_checkpoint(index)

func _find_nearest_checkpoint(target_index: int) -> Dictionary:
	return CheckpointsClass.find_nearest_checkpoint(checkpoints, target_index)

# 验证校验点哈希
func verify_checkpoints() -> Result:
	return CheckpointsClass.verify_checkpoints(checkpoints)

# === 不变量检查 ===

func set_initial_total_cash_for_invariants(total_cash: int) -> void:
	_initial_total_cash = int(total_cash)

func set_initial_employee_totals_for_invariants(employee_totals: Dictionary) -> void:
	_initial_employee_totals = employee_totals

func _check_invariants() -> Result:
	return InvariantsClass.check_invariants(state, _initial_total_cash, _initial_employee_totals)

func check_invariants() -> Result:
	return _check_invariants()

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

func get_checkpoints() -> Array[Dictionary]:
	return checkpoints

# 查找“当前阶段开始”对应的命令索引（用于 UI 的“一键回退本阶段”）。
# 语义：返回 target_index，用于 rewind_to_command(target_index)。
# - 若当前阶段尚未执行任何命令，则返回 current_command_index（回退为 no-op）。
# - 若本局尚未执行任何命令，则返回 -1。
func find_phase_start_command_index() -> Result:
	var init_check := _ensure_initialized()
	if not init_check.ok:
		return init_check
	if state == null:
		return Result.failure("游戏状态为空")

	if current_command_index < 0:
		return Result.success(-1)

	var phase_name := str(state.phase)
	var round_num := int(state.round_number)

	var first_in_phase := -1
	for i in range(current_command_index + 1):
		var cmd: Command = command_history[i]
		if cmd == null:
			continue
		if str(cmd.phase) != phase_name:
			continue
		# timestamp = round*1000 + ...（CommandRunner 写入），用于区分不同回合的同名阶段
		if int(cmd.timestamp) >= 0 and int(int(cmd.timestamp) / 1000) != round_num:
			continue
		first_in_phase = i
		break

	if first_in_phase < 0:
		# 当前阶段还没有命令：已经位于阶段开始
		return Result.success(current_command_index)

	return Result.success(first_in_phase - 1)

# 查找“当前玩家在当前阶段的回合开始”对应的命令索引（用于 UI 的“一键回退当前玩家回合”）。
# 语义：返回 target_index，用于 rewind_to_command(target_index)。
# - 目标是撤销“当前玩家在当前阶段内”的操作（不跨阶段）。
# - 仅依赖 PLAYER_TURN_STARTED 会漏掉“阶段变化但当前玩家不变”的场景（例如 OrderOfBusiness 自动进入 Working），
#   从而把回合开始错误定位到更早的阶段（例如 Payday）。因此这里同时考虑 phase/round 变化。
func find_current_player_turn_start_command_index() -> Result:
	var init_check := _ensure_initialized()
	if not init_check.ok:
		return init_check
	if state == null:
		return Result.failure("游戏状态为空")

	var pid := state.get_current_player_id()
	if pid < 0:
		return Result.failure("当前玩家无效")

	if current_command_index < 0:
		return Result.success(-1)

	var phase_name := str(state.phase)
	var round_num := int(state.round_number)

	# 目标：撤销“当前玩家在当前阶段内”的所有命令。
	# 因此应回到“该玩家在该阶段内的第一个命令之前”的位置（而非“最近一次进入该玩家/阶段组合”的位置），
	# 以覆盖可能存在的“临时切换当前玩家后又切回”的场景。
	var first_cmd_in_phase_for_player := -1
	for i in range(int(current_command_index) + 1):
		var cmd: Command = command_history[i]
		if cmd == null:
			continue
		if int(cmd.actor) != int(pid):
			continue
		if str(cmd.phase) != phase_name:
			continue
		# timestamp = round*1000 + ...（CommandRunner 写入），用于区分不同回合的同名阶段
		if int(cmd.timestamp) >= 0 and int(int(cmd.timestamp) / 1000) != round_num:
			continue
		first_cmd_in_phase_for_player = i
		break

	if first_cmd_in_phase_for_player < 0:
		# 当前阶段内该玩家尚未执行任何命令：已经位于回合开始
		return Result.success(int(current_command_index))

	return Result.success(first_cmd_in_phase_for_player - 1)

func _infer_current_player_turn_start_command_index_by_replay(player_id: int, target_index: int, target_phase: String, target_round: int) -> Result:
	if target_index < 0:
		return Result.success(-1)
	if checkpoints.is_empty():
		return Result.failure("缺少初始校验点")

	var initial_checkpoint := checkpoints[0]
	if not (initial_checkpoint is Dictionary):
		return Result.failure("checkpoints[0] 类型错误（期望 Dictionary）")
	var state_dict_val = Dictionary(initial_checkpoint).get("state_dict", null)
	if not (state_dict_val is Dictionary):
		return Result.failure("checkpoints[0].state_dict 缺失或类型错误（期望 Dictionary）")

	var restore_result := GameState.from_dict(state_dict_val)
	if not restore_result.ok:
		return Result.failure("恢复初始 state 失败: %s" % restore_result.error)
	var replay_state: GameState = restore_result.value
	if replay_state == null:
		return Result.failure("恢复初始 state 失败: state 为空")

	var phase_name := str(target_phase).strip_edges()
	var round_num := int(target_round)
	var last_turn_start := -999
	var prev_pid := replay_state.get_current_player_id()
	var prev_phase := str(replay_state.phase)
	var prev_round := int(replay_state.round_number)
	if prev_pid == player_id and prev_phase == phase_name and prev_round == round_num:
		last_turn_start = -1

	var warnings: Array[String] = []
	for i in range(mini(target_index, command_history.size() - 1) + 1):
		var cmd: Command = command_history[i]
		if cmd == null:
			return Result.failure("command_history[%d] 为空" % i).with_warnings(warnings)
		var executor := action_registry.get_executor(cmd.action_id)
		if executor == null:
			return Result.failure("回放时找不到执行器: %s" % str(cmd.action_id)).with_warnings(warnings)

		var force_execute := _should_force_execute_in_replay(cmd)
		if force_execute and executor.requires_actor:
			var current_player_id := replay_state.get_current_player_id()
			if cmd.actor != current_player_id:
				return Result.failure("回放强制命令 #%d actor 非当前玩家: actor=%d current=%d" % [i, cmd.actor, current_player_id]).with_warnings(warnings)

		var step_result := executor.compute_new_state_force(replay_state, cmd) if force_execute else executor.compute_new_state(replay_state, cmd)
		if not step_result.ok:
			return Result.failure("回放命令 #%d 失败: %s" % [i, step_result.error]).with_warnings(warnings)
		warnings.append_array(step_result.warnings)

		var new_state: GameState = step_result.value
		if new_state == null:
			return Result.failure("回放命令 #%d 失败: state 为空" % i).with_warnings(warnings)

		var auto_r: Result = AutoAdvanceClass.drain(new_state, phase_manager, action_registry)
		if not auto_r.ok:
			return Result.failure("回放命令 #%d auto_advance 失败: %s" % [i, auto_r.error]).with_warnings(warnings)
		warnings.append_array(auto_r.warnings)

		var now_pid := new_state.get_current_player_id()
		var now_phase := str(new_state.phase)
		var now_round := int(new_state.round_number)
		if now_pid == player_id and now_phase == phase_name and now_round == round_num:
			if now_pid != prev_pid or now_phase != prev_phase or now_round != prev_round:
				last_turn_start = i
		prev_pid = now_pid
		prev_phase = now_phase
		prev_round = now_round
		replay_state = new_state

	if last_turn_start == -999:
		# 未能进入目标阶段（可能 target_phase/round 不匹配或回放失败未触达）
		return Result.failure("回放推导失败：未找到 turn_start（player=%d phase=%s round=%d）" % [player_id, phase_name, round_num]).with_warnings(warnings)
	return Result.success(last_turn_start).with_warnings(warnings)

func _should_force_execute_in_replay(command: Command) -> bool:
	if command == null:
		return false
	if OS.has_feature("release"):
		return false
	if not (command.metadata is Dictionary):
		return false
	return bool(Dictionary(command.metadata).get("debug_force", false))

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
