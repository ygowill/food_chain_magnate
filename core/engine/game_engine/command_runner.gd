# GameEngine 命令执行主流程（抽离自 core/engine/game_engine.gd）
extends RefCounted

const AutoAdvanceClass = preload("res://core/engine/game_engine/auto_advance.gd")

static func execute_command(engine: GameEngine, command: Command, is_replay: bool = false) -> Result:
	var init_check := engine._ensure_initialized()
	if not init_check.ok:
		return init_check

	# 若不在命令末尾执行新命令，则视为开始新分支：丢弃未来命令/校验点
	if not is_replay and engine.current_command_index < engine.command_history.size() - 1:
		engine._truncate_future_history()

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

	# 运行全局校验器
	var validator_result := engine.action_registry.run_validators(engine.state, command)
	if not validator_result.ok:
		return validator_result

	# 执行动作
	var execute_result := executor.compute_new_state(engine.state, command)
	if not execute_result.ok:
		return execute_result

	var old_state := engine.state
	var new_state: GameState = execute_result.value

	# 生成事件
	var events := executor.generate_events(old_state, new_state, command)
	events.append_array(_build_player_cash_changed_events(old_state, new_state, command))

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

	# 更新状态
	engine.state = new_state

	# 记录命令
	command.index = engine.command_history.size()
	engine.command_history.append(command)
	engine.current_command_index = command.index

	# 校验不变量
	if engine.validate_invariants and DebugFlags.validate_invariants:
		var invariant_result := engine._check_invariants()
		if not invariant_result.ok:
			GameLog.error("GameEngine", "不变量校验失败: %s" % invariant_result.error)
			# 回滚状态
			engine.state = old_state
			engine.command_history.pop_back()
			engine.current_command_index -= 1
			return invariant_result

	# 创建校验点
	if engine.command_history.size() % engine.checkpoint_interval == 0:
		engine._create_checkpoint(engine.command_history.size())

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
	return Result.success(engine.state).with_warnings(all_warnings)

static func _drain_auto_advances(engine: GameEngine, state_in: GameState) -> Result:
	if state_in == null:
		return Result.failure("auto_advance: state 为空")

	var events: Array[Dictionary] = []
	var all_warnings: Array[String] = []
	var safety := 0

	while safety < 32:
		safety += 1
		var before := state_in.duplicate_state()
		var step := AutoAdvanceClass.try_advance_one(state_in, engine.phase_manager, engine.action_registry)
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

static func _build_phase_change_events(old_state: GameState, new_state: GameState) -> Array[Dictionary]:
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

static func _build_player_cash_changed_events(old_state: GameState, new_state: GameState, command: Command) -> Array[Dictionary]:
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
