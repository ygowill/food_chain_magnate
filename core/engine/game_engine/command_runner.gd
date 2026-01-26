# GameEngine 命令执行主流程（抽离自 core/engine/game_engine.gd）
extends RefCounted

const AutoAdvanceClass = preload("res://core/engine/game_engine/auto_advance.gd")

const EVENT_BUILD_PROVIDER_PATH_SETTING = "fcm/command_runner_event_build_provider_path"
static var event_build_provider_path_override: String = ""
static var _event_build_provider_cache = null
static var _event_build_provider_cache_path: String = ""

static func set_event_build_provider_path(path: String) -> void:
	event_build_provider_path_override = str(path).strip_edges()
	_event_build_provider_cache = null
	_event_build_provider_cache_path = ""

static func _resolve_event_build_provider_path() -> String:
	if not event_build_provider_path_override.is_empty():
		return event_build_provider_path_override
	if not ProjectSettings.has_setting(EVENT_BUILD_PROVIDER_PATH_SETTING):
		return ""
	var v = ProjectSettings.get_setting(EVENT_BUILD_PROVIDER_PATH_SETTING)
	if not (v is String):
		return ""
	return str(v).strip_edges()

static func _get_event_build_provider():
	var provider_path := _resolve_event_build_provider_path()
	if provider_path.is_empty():
		return null
	if _event_build_provider_cache != null and _event_build_provider_cache_path == provider_path:
		return _event_build_provider_cache

	var provider = load(provider_path)
	if provider == null:
		GameLog.error("CommandRunner", "缺少事件构建 provider: %s" % provider_path)
		_event_build_provider_cache = null
		_event_build_provider_cache_path = provider_path
		return null

	_event_build_provider_cache = provider
	_event_build_provider_cache_path = provider_path
	return provider

static func execute_command(engine: GameEngine, command: Command, is_replay: bool = false) -> Result:
	var init_check := engine.ensure_initialized()
	if not init_check.ok:
		return init_check

	# 若不在命令末尾执行新命令，则视为开始新分支：丢弃未来命令/校验点
	if not is_replay and engine.current_command_index < engine.command_history.size() - 1:
		engine.truncate_future_history()

	# 获取执行器
	var executor := engine.action_registry.get_executor(command.action_id)
	if executor == null:
		return Result.failure("未知的动作: %s" % command.action_id)

	# 填充命令上下文
	if command.phase.is_empty():
		command.phase = engine.state.phase
	if command.sub_phase.is_empty():
		command.sub_phase = engine.state.sub_phase

	# 仅在“运行时执行”（非回放）写入确定性的游戏内时间戳
	if not is_replay:
		command.timestamp = PhaseManager.compute_timestamp(engine.state)
	else:
		# 回放命令必须带 timestamp（禁止兼容旧存档）
		if command.timestamp < 0:
			return Result.failure("回放命令缺少 timestamp: %s" % str(command))

	var force_execute := _should_force_execute(engine, command, is_replay)

	# 运行全局校验器（强制模式跳过）
	var execute_result: Result = null
	if force_execute:
		var force_check := _validate_force_execute(engine.state, command, executor)
		if not force_check.ok:
			return force_check
		execute_result = executor.compute_new_state_force(engine.state, command)
	else:
		var validator_result := engine.action_registry.run_validators(engine.state, command)
		if not validator_result.ok:
			return validator_result
		execute_result = executor.compute_new_state(engine.state, command)

	if not execute_result.ok:
		return execute_result

	var old_state := engine.state
	var new_state: GameState = execute_result.value

	# 生成事件
	var events := executor.generate_events(old_state, new_state, command)
	var event_build_provider = _get_event_build_provider()
	if event_build_provider != null:
		events.append_array(event_build_provider.build_player_cash_changed_events(old_state, new_state, command))

	# 自动推进（首轮无操作阶段 / 结算阶段默认跳过）
	var auto_r := _drain_auto_advances(engine, new_state)
	if not auto_r.ok:
		return auto_r
	if auto_r.value is Dictionary:
		var auto_info: Dictionary = auto_r.value
		var auto_events_val = auto_info.get("events", null)
		if auto_events_val is Array:
			events.append_array(Array(auto_events_val))
	new_state = auto_r.value.get("state", new_state) if (auto_r.value is Dictionary) else new_state

	# 里程碑事件：从 state 差异中推导（用于 UI 日志/提示）
	if event_build_provider != null:
		events.append_array(event_build_provider.build_milestone_achieved_events(old_state, new_state, command))

	# 更新状态
	engine.state = new_state

	# 记录命令
	command.index = engine.command_history.size()
	engine.command_history.append(command)
	engine.current_command_index = command.index

	# 校验不变量
	if engine.validate_invariants and DebugFlags.validate_invariants:
		var invariant_result := engine.check_invariants()
		if not invariant_result.ok:
			GameLog.error("GameEngine", "不变量校验失败: %s" % invariant_result.error)
			# 回滚状态
			engine.state = old_state
			engine.command_history.pop_back()
			engine.current_command_index -= 1
			return invariant_result

	# 创建校验点
	if engine.command_history.size() % engine.checkpoint_interval == 0:
		engine.create_checkpoint(engine.command_history.size())

	# 发送事件
	# 重要：为每条事件补齐 command_index，确保读档后从 EventBus.history 恢复日志时不会把整段历史压扁到同一个索引。
	var cmd_index := int(command.index)
	for event_val in events:
		if not (event_val is Dictionary):
			continue
		var event: Dictionary = event_val
		var t: String = str(event.get("type", "")).strip_edges()
		if t.is_empty():
			continue

		var data_val = event.get("data", null)
		var data: Dictionary = data_val if (data_val is Dictionary) else {}
		data["command_index"] = cmd_index
		event["data"] = data

		engine.emit_event(t, data)

	engine.emit_event(EventBus.EventType.COMMAND_EXECUTED, {
		"command_index": command.index,
		"action_id": command.action_id,
		"actor": command.actor
	})

	if DebugFlags.verbose_logging:
		GameLog.debug("GameEngine", "执行命令 #%d: %s" % [command.index, command.action_id])

	var all_warnings: Array[String] = []
	all_warnings.append_array(execute_result.warnings)
	all_warnings.append_array(auto_r.warnings)
	return Result.success(engine.state).with_warnings(all_warnings)

static func build_player_cash_changed_events(old_state: GameState, new_state: GameState, command: Command) -> Array[Dictionary]:
	var provider = _get_event_build_provider()
	if provider == null:
		return []
	return provider.build_player_cash_changed_events(old_state, new_state, command)

static func build_milestone_achieved_events(old_state: GameState, new_state: GameState, command: Command) -> Array[Dictionary]:
	var provider = _get_event_build_provider()
	if provider == null:
		return []
	return provider.build_milestone_achieved_events(old_state, new_state, command)

static func build_phase_change_events(old_state: GameState, new_state: GameState) -> Array[Dictionary]:
	var provider = _get_event_build_provider()
	if provider == null:
		return []
	return provider.build_phase_change_events(old_state, new_state)

static func build_food_sold_events_from_dinnertime_report(dinnertime_state: GameState, report: Dictionary) -> Array[Dictionary]:
	var provider = _get_event_build_provider()
	if provider == null:
		return []
	return provider.build_food_sold_events_from_dinnertime_report(dinnertime_state, report)

static func build_marketing_demand_generated_events(marketing_state: GameState) -> Array[Dictionary]:
	var provider = _get_event_build_provider()
	if provider == null:
		return []
	return provider.build_marketing_demand_generated_events(marketing_state)

static func build_marketing_expired_events(marketing_state: GameState) -> Array[Dictionary]:
	var provider = _get_event_build_provider()
	if provider == null:
		return []
	return provider.build_marketing_expired_events(marketing_state)

static func build_cleanup_inventory_discarded_events(cleanup_state: GameState) -> Array[Dictionary]:
	var provider = _get_event_build_provider()
	if provider == null:
		return []
	return provider.build_cleanup_inventory_discarded_events(cleanup_state)

static func drain_auto_advances(engine: GameEngine, state_in: GameState) -> Result:
	return _drain_auto_advances(engine, state_in)

static func _should_force_execute(engine: GameEngine, command: Command, is_replay: bool) -> bool:
	if engine == null or command == null:
		return false
	if OS.has_feature("release"):
		return false
	if not _is_force_execute_requested(command):
		return false
	if is_replay:
		return true
	return DebugFlags.is_debug_mode() and DebugFlags.force_execute_commands

static func _is_force_execute_requested(command: Command) -> bool:
	if command == null:
		return false
	if not (command.metadata is Dictionary):
		return false
	return bool(Dictionary(command.metadata).get("debug_force", false))

static func _validate_force_execute(state: GameState, command: Command, executor: ActionExecutor) -> Result:
	if state == null:
		return Result.failure("force_execute: state 为空")
	if command == null:
		return Result.failure("force_execute: command 为空")
	if executor == null:
		return Result.failure("force_execute: executor 为空")

	# 强制模式：用于调试/回放，可允许“非当前玩家”执行；但仍需保证 actor 合法。
	if executor.requires_actor:
		# 强制模式下允许指定任意玩家（用于调试面板的“目标玩家”），但仍需保证 actor 合法。
		var count := state.players.size()
		if command.actor < 0 or command.actor >= count:
			return Result.failure("force_execute: actor 超出范围: actor=%d players=%d" % [command.actor, count])

	return Result.success()

static func _drain_auto_advances(engine: GameEngine, state_in: GameState) -> Result:
	if state_in == null:
		return Result.failure("auto_advance: state 为空")

	var events: Array[Dictionary] = []
	var all_warnings: Array[String] = []
	var safety := 0

	while safety < 32:
		safety += 1
		var before := state_in.duplicate_state()
		var step: Result = AutoAdvanceClass.try_advance_one(state_in, engine.phase_manager, engine.action_registry)
		if not step.ok:
			return step
		all_warnings.append_array(step.warnings)
		if not bool(step.value):
			break

		var provider = _get_event_build_provider()
		if provider != null:
			events.append_array(provider.build_phase_change_events(before, state_in))
			events.append_array(provider.build_player_cash_changed_events(before, state_in, Command.create_system("auto_advance")))

	if safety >= 32:
		return Result.failure("auto_advance: exceeded max steps (possible loop)")

	return Result.success({
		"state": state_in,
		"events": events
	}).with_warnings(all_warnings)
