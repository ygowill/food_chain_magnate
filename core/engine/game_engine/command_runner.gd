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

	# 里程碑事件：从 state 差异中推导（用于 UI 日志/提示）
	events.append_array(_build_milestone_achieved_events(old_state, new_state, command))

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

static func _build_milestone_achieved_events(old_state: GameState, new_state: GameState, command: Command) -> Array[Dictionary]:
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

		var old_ms_val = old_player.get("milestones", [])
		var new_ms_val = new_player.get("milestones", [])
		if not (old_ms_val is Array) or not (new_ms_val is Array):
			continue
		var old_ms: Array = old_ms_val
		var new_ms: Array = new_ms_val

		var old_set := {}
		for mid_val in old_ms:
			if not (mid_val is String):
				continue
			var mid: String = str(mid_val)
			if mid.is_empty():
				continue
			old_set[mid] = true

		var added: Array[String] = []
		for mid_val2 in new_ms:
			if not (mid_val2 is String):
				continue
			var mid2: String = str(mid_val2)
			if mid2.is_empty():
				continue
			if old_set.has(mid2):
				continue
			added.append(mid2)

		if added.is_empty():
			continue
		added.sort()

		for milestone_id in added:
			events.append({
				"type": EventBus.EventType.MILESTONE_ACHIEVED,
				"data": {
					"player_id": player_id,
					"milestone_id": milestone_id,
					"action_id": str(command.action_id),
					"phase": str(new_state.phase),
					"sub_phase": str(new_state.sub_phase),
					"round": int(new_state.round_number),
				}
			})

	return events

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
		# 最终行动顺序落地事件（首轮 OrderOfBusiness auto finalize 依赖此事件用于日志显示/回放恢复）。
		if str(old_state.phase) == "OrderOfBusiness":
			var old_finalized := false
			var new_finalized := false
			if old_state.round_state is Dictionary:
				var oob_old_val = Dictionary(old_state.round_state).get("order_of_business", null)
				if oob_old_val is Dictionary:
					var oob_old: Dictionary = oob_old_val
					if oob_old.has("finalized") and (oob_old["finalized"] is bool):
						old_finalized = bool(oob_old["finalized"])
			if new_state.round_state is Dictionary:
				var oob_new_val = Dictionary(new_state.round_state).get("order_of_business", null)
				if oob_new_val is Dictionary:
					var oob_new: Dictionary = oob_new_val
					if oob_new.has("finalized") and (oob_new["finalized"] is bool):
						new_finalized = bool(oob_new["finalized"])
			if (not old_finalized) and new_finalized:
				var final_order: Array[int] = []
				for pid in new_state.turn_order:
					final_order.append(int(pid))
				events.append({
					"type": EventBus.EventType.TURN_ORDER_FINALIZED,
					"data": {
						"round": int(new_state.round_number),
						"turn_order": final_order,
					}
				})

		# Dinnertime 结算报告：在离开 Dinnertime 时发射（便于 UI/日志按事件历史恢复，且不依赖当前 state）。
		if str(old_state.phase) == "Dinnertime":
			var report: Dictionary = {}
			if old_state.round_state is Dictionary:
				var v = Dictionary(old_state.round_state).get("dinnertime", null)
				if v is Dictionary:
					report = Dictionary(v).duplicate(true)
			events.append({
				"type": EventBus.EventType.DINNERTIME_REPORT,
				"data": {
					"round": old_state.round_number,
					"from_phase": str(old_state.phase),
					"to_phase": str(new_state.phase),
					"report": report,
				}
			})
			# 细粒度售卖事件：从 dinnertime 报告中拆分出来（便于 UI 日志筛选/回放核对）。
			events.append_array(_build_food_sold_events_from_dinnertime_report(old_state, report))

		# Marketing 结算摘要：在离开 Marketing 时发射（便于 UI 日志从 EventBus.history 恢复）。
		# issue_tracker #48: per board 1 log entry, with details in event data.
		if str(old_state.phase) == "Marketing":
			events.append_array(_build_marketing_demand_generated_events(old_state))
			events.append_array(_build_marketing_expired_events(old_state))

		# Cleanup 库存丢弃：在离开 Cleanup 时发射（便于 UI 日志恢复/回放核对）。
		if str(old_state.phase) == "Cleanup":
			events.append_array(_build_cleanup_inventory_discarded_events(old_state))

		events.append({
			"type": EventBus.EventType.PHASE_CHANGED,
			"data": {
				"old_phase": old_state.phase,
				"new_phase": new_state.phase,
				"round": new_state.round_number
			}
		})

		# 回合开始/结束事件
		if old_state.round_number != new_state.round_number:
			events.append({
				"type": EventBus.EventType.ROUND_ENDED,
				"data": {
					"round": old_state.round_number,
					"next_round": new_state.round_number,
				}
			})
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

static func _build_food_sold_events_from_dinnertime_report(dinnertime_state: GameState, report: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if dinnertime_state == null:
		return out
	if report == null or not (report is Dictionary):
		return out

	var sales_val = Dictionary(report).get("sales", null)
	if not (sales_val is Array):
		return out
	var round := int(dinnertime_state.round_number)

	for s_val in Array(sales_val):
		if not (s_val is Dictionary):
			continue
		var s: Dictionary = s_val
		var player_id := int(s.get("winner_owner", -1))
		if player_id < 0:
			continue

		var required: Dictionary = {}
		var required_val = s.get("required", null)
		if required_val is Dictionary:
			required = Dictionary(required_val).duplicate(true)

		out.append({
			"type": EventBus.EventType.FOOD_SOLD,
			"data": {
				"round": round,
				"player_id": player_id,
				"house_id": str(s.get("house_id", "")).strip_edges(),
				"house_number": s.get("house_number", null),
				"restaurant_id": str(s.get("winner_restaurant_id", "")).strip_edges(),
				"required": required,
				"revenue": int(s.get("revenue", 0)),
				"bonus": int(s.get("bonus", 0)),
				"house_bonus": int(s.get("house_bonus", 0)),
			}
		})

	return out

static func _build_marketing_demand_generated_events(marketing_state: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if marketing_state == null:
		return out
	if not (marketing_state.round_state is Dictionary):
		return out

	var marketing_val = Dictionary(marketing_state.round_state).get("marketing", null)
	if not (marketing_val is Dictionary):
		return out
	var marketing: Dictionary = marketing_val
	var processed_val = marketing.get("processed", null)
	if not (processed_val is Array):
		return out

	var houses_by_id: Dictionary = {}
	if marketing_state.map is Dictionary:
		var houses_val = Dictionary(marketing_state.map).get("houses", null)
		if houses_val is Dictionary:
			houses_by_id = houses_val

	for p_val in Array(processed_val):
		if not (p_val is Dictionary):
			continue
		var p: Dictionary = p_val

		var board_number := int(p.get("board_number", 0))
		var owner := int(p.get("owner", -1))
		var marketing_type := str(p.get("type", "")).strip_edges()
		var employee_type := str(p.get("employee_type", "")).strip_edges()
		var product := str(p.get("product", "")).strip_edges()
		var demands_added := int(p.get("demands_added", 0))

		var affected_ids: Array[String] = []
		var affected_numbers: Array[int] = []
		var affected_val = p.get("affected_houses", null)
		if affected_val is Array:
			for hid_val in Array(affected_val):
				var hid := str(hid_val).strip_edges()
				if hid.is_empty():
					continue
				affected_ids.append(hid)
				var hn := _try_get_house_number(houses_by_id, hid)
				if hn > 0:
					affected_numbers.append(hn)

		var pos_arr: Array = []
		var wp_val = p.get("world_pos", null)
		if wp_val is Vector2i:
			var wp: Vector2i = wp_val
			pos_arr = [wp.x, wp.y]
		elif wp_val is Array:
			pos_arr = Array(wp_val)

		out.append({
			"type": EventBus.EventType.DEMAND_GENERATED,
			"data": {
				"round": int(marketing_state.round_number),
				"player_id": owner,
				"board_number": board_number,
				"marketing_type": marketing_type,
				"employee_type": employee_type,
				"product": product,
				"demands_added": demands_added,
				"affected_houses": affected_ids,
				"affected_house_numbers": affected_numbers,
				"position": pos_arr,
			}
		})

	return out

static func _build_marketing_expired_events(marketing_state: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if marketing_state == null:
		return out
	if not (marketing_state.round_state is Dictionary):
		return out

	var marketing_val = Dictionary(marketing_state.round_state).get("marketing", null)
	if not (marketing_val is Dictionary):
		return out
	var marketing: Dictionary = marketing_val
	var processed_val = marketing.get("processed", null)
	if not (processed_val is Array):
		return out

	var round := int(marketing_state.round_number)

	for p_val in Array(processed_val):
		if not (p_val is Dictionary):
			continue
		var p: Dictionary = p_val
		if not bool(p.get("expired", false)):
			continue

		var board_number := int(p.get("board_number", 0))
		var owner := int(p.get("owner", -1))
		if owner < 0:
			continue
		var marketing_type := str(p.get("type", "")).strip_edges()
		var employee_type := str(p.get("employee_type", "")).strip_edges()
		var product := str(p.get("product", "")).strip_edges()

		var pos_arr: Array = []
		var wp_val = p.get("world_pos", null)
		if wp_val is Vector2i:
			var wp: Vector2i = wp_val
			pos_arr = [wp.x, wp.y]
		elif wp_val is Array:
			pos_arr = Array(wp_val)

		out.append({
			"type": EventBus.EventType.MARKETING_EXPIRED,
			"data": {
				"round": round,
				"player_id": owner,
				"board_number": board_number,
				"marketing_type": marketing_type,
				"employee_type": employee_type,
				"product": product,
				"position": pos_arr,
				"duration_before": int(p.get("duration_before", 0)),
				"duration_after": int(p.get("duration_after", 0)),
			}
		})

	return out

static func _build_cleanup_inventory_discarded_events(cleanup_state: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if cleanup_state == null:
		return out
	if not (cleanup_state.round_state is Dictionary):
		return out

	var cleanup_val = Dictionary(cleanup_state.round_state).get("cleanup", null)
	if not (cleanup_val is Dictionary):
		return out
	var cleanup: Dictionary = cleanup_val
	var inv_val = cleanup.get("inventory_discarded", null)
	if not (inv_val is Array):
		return out
	var round := int(cleanup_state.round_number)

	for item_val in Array(inv_val):
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		var player_id := int(item.get("player_id", -1))
		if player_id < 0:
			continue

		var discarded_val = item.get("discarded", null)
		if not (discarded_val is Dictionary):
			continue
		var discarded: Dictionary = Dictionary(discarded_val).duplicate(true)
		if discarded.is_empty():
			continue

		out.append({
			"type": EventBus.EventType.FOOD_DISCARDED,
			"data": {
				"round": round,
				"player_id": player_id,
				"has_fridge": bool(item.get("has_fridge", false)),
				"discarded": discarded,
			}
		})

	return out

static func _try_get_house_number(houses_by_id: Dictionary, house_id: String) -> int:
	if houses_by_id == null or houses_by_id.is_empty():
		return -1
	var hid := str(house_id).strip_edges()
	if hid.is_empty():
		return -1
	if not houses_by_id.has(hid):
		return -1
	var h_val = houses_by_id.get(hid, null)
	if not (h_val is Dictionary):
		return -1
	var h: Dictionary = h_val
	var n_val = h.get("house_number", null)
	if n_val is int:
		return int(n_val)
	if n_val is float:
		var f: float = float(n_val)
		if f == floor(f):
			return int(f)
	return -1

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
