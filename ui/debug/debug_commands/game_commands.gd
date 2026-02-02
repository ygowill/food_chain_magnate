# 游戏流程调试命令（UI/开发工具）
extends RefCounted

const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")
const ActionIdsClass = preload("res://core/actions/action_ids.gd")

static func register_all(registry: DebugCommandRegistry) -> void:
	registry.register("advance", _cmd_advance.bind(registry), "推进阶段", "advance [phase|sub_phase]", ["target"])
	registry.register("skip", _cmd_skip.bind(registry), "跳过玩家回合", "skip <player>", ["player"])
	registry.register("give_money", _cmd_give_money.bind(registry), "给玩家金钱", "give_money <player> <amount>", ["player", "amount"])
	registry.register("set_phase", _cmd_set_phase.bind(registry), "设置当前阶段", "set_phase <phase_name>", ["phase"])
	registry.register("next_round", _cmd_next_round.bind(registry), "跳到下一回合", "next_round")

static func _mark_debug_force(cmd: Command) -> void:
	if not DebugFlags.is_debug_mode():
		return
	if not DebugFlags.force_execute_commands:
		return
	if not (cmd.metadata is Dictionary):
		cmd.metadata = {}
	cmd.metadata["debug_force"] = true

static func _parse_player_id_arg(arg, state: GameState) -> Result:
	if state == null:
		return Result.failure("游戏状态为空")
	var player_count := state.players.size()
	if player_count <= 0:
		return Result.failure("玩家数量无效: %d" % player_count)

	var token := str(arg).strip_edges()
	if token.is_empty():
		return Result.failure("player 不能为空")

	var lower := token.to_lower()
	if lower.begins_with("id:"):
		var id_str := token.substr(3).strip_edges()
		if not id_str.is_valid_int():
			return Result.failure("player_id 格式错误: %s" % token)
		var pid := int(id_str)
		if pid < 0 or pid >= player_count:
			return Result.failure("无效的 player_id: %d（有效范围 0..%d）" % [pid, player_count - 1])
		return Result.success(pid)

	if lower.begins_with("pid:"):
		var id_str2 := token.substr(4).strip_edges()
		if not id_str2.is_valid_int():
			return Result.failure("player_id 格式错误: %s" % token)
		var pid2 := int(id_str2)
		if pid2 < 0 or pid2 >= player_count:
			return Result.failure("无效的 player_id: %d（有效范围 0..%d）" % [pid2, player_count - 1])
		return Result.success(pid2)

	# 默认按玩家顺位 1..N 解析（不允许“当前玩家”隐式行为）
	if not token.is_valid_int():
		return Result.failure("player 必须为 1..%d（或使用 id:<player_id>）" % player_count)
	var pnum := int(token)
	if pnum < 1 or pnum > player_count:
		return Result.failure("无效的玩家顺位: %d（有效范围 1..%d）" % [pnum, player_count])
	return Result.success(pnum - 1)

static func _cmd_advance(args: Array, registry: DebugCommandRegistry) -> Result:
	var engine := registry.get_game_engine()
	if engine == null:
		return Result.failure("游戏引擎未初始化")

	var target := "phase"
	if not args.is_empty():
		target = str(args[0])

	var cmd: Command
	if target == "sub_phase":
		cmd = Command.create_system(ActionIdsClass.ADVANCE_PHASE, {"target": "sub_phase"})
	else:
		cmd = Command.create_system(ActionIdsClass.ADVANCE_PHASE)

	_mark_debug_force(cmd)
	var result := engine.execute_command(cmd)
	if not result.ok:
		return result

	var state := engine.get_state()
	return Result.success("阶段已推进到: %s / %s" % [state.phase, state.sub_phase])

static func _cmd_skip(args: Array, registry: DebugCommandRegistry) -> Result:
	var engine := registry.get_game_engine()
	if engine == null:
		return Result.failure("游戏引擎未初始化")

	var state := engine.get_state()
	if args.is_empty():
		return Result.failure("用法: skip <player>")
	var player_id_r := _parse_player_id_arg(args[0], state)
	if not player_id_r.ok:
		return player_id_r
	var player_id := int(player_id_r.value)

	var cmd := Command.create(ActionIdsClass.SKIP, player_id)
	_mark_debug_force(cmd)
	var result := engine.execute_command(cmd)
	if not result.ok:
		return result

	return Result.success("玩家 %d 已跳过" % player_id)

static func _cmd_give_money(args: Array, registry: DebugCommandRegistry) -> Result:
	var engine := registry.get_game_engine()
	if engine == null:
		return Result.failure("游戏引擎未初始化")

	if args.size() < 2:
		return Result.failure("用法: give_money <player> <amount>")

	var state := engine.get_state()
	var player_id_r := _parse_player_id_arg(args[0], state)
	if not player_id_r.ok:
		return player_id_r
	var player_id := int(player_id_r.value)
	var amount := int(args[1])

	var old_cash := 0
	if state.players[player_id] is Dictionary:
		old_cash = int(Dictionary(state.players[player_id]).get("cash", 0))

	# 通过内部 debug action 修改状态（保持命令历史/回放/不变量）
	var cmd := Command.create_system("debug_give_money", {
		"player_id": player_id,
		"amount": amount
	})

	_mark_debug_force(cmd)
	var result := engine.execute_command(cmd)
	if not result.ok:
		return Result.failure("执行失败: %s" % result.error)

	var new_state := engine.get_state()
	var new_cash := old_cash
	if new_state != null and new_state.players[player_id] is Dictionary:
		new_cash = int(Dictionary(new_state.players[player_id]).get("cash", old_cash))

	return Result.success("玩家 %d 金钱: $%d -> $%d" % [player_id, old_cash, new_cash])

static func _cmd_set_phase(args: Array, registry: DebugCommandRegistry) -> Result:
	var engine := registry.get_game_engine()
	if engine == null:
		return Result.failure("游戏引擎未初始化")

	if args.is_empty():
		return Result.failure("用法: set_phase <phase_name>")

	var phase_name := str(args[0])
	var state := engine.get_state()

	var order: Array = []
	if state != null and (state.round_state is Dictionary):
		var v = Dictionary(state.round_state).get("phase_order", null)
		if v is Array:
			order = Array(v)
	if order.is_empty() and engine.phase_manager != null and engine.phase_manager.has_method("get_phase_order_names"):
		order = engine.phase_manager.get_phase_order_names()

	if phase_name == DefsClass.PHASE_SETUP:
		return Result.failure("不支持跳回 Setup（请使用 undo/restore）")
	if not order.has(phase_name):
		return Result.failure("未知阶段: %s" % phase_name)

	var old_phase := state.phase
	if old_phase == phase_name:
		return Result.success("阶段未变化: %s" % old_phase)

	if order.has(old_phase):
		var cur_idx := order.find(old_phase)
		var target_idx := order.find(phase_name)
		if target_idx < cur_idx:
			return Result.failure("不支持回退阶段（目标 %s 早于当前 %s）；请使用 undo/restore" % [phase_name, old_phase])

	var max_steps := 64
	var safety := 0
	while safety < max_steps:
		safety += 1
		var step := _advance_one_step(engine)
		if not step.ok:
			return Result.failure("推进失败: %s" % step.error)

		state = engine.get_state()
		if state != null and state.phase == phase_name:
			return Result.success("阶段已推进: %s -> %s (steps=%d)" % [old_phase, phase_name, safety])

	return Result.failure("未能到达目标阶段（超出最大步数 %d），当前: %s" % [max_steps, engine.get_state().phase])

static func _cmd_next_round(args: Array, registry: DebugCommandRegistry) -> Result:
	var engine := registry.get_game_engine()
	if engine == null:
		return Result.failure("游戏引擎未初始化")

	var state := engine.get_state()
	var current_round := state.round_number

	# 持续推进直到回合变化或达到最大尝试次数
	var max_attempts := 256
	for i in range(max_attempts):
		var step := _advance_one_step(engine)
		if not step.ok:
			return Result.failure("推进失败: %s" % step.error)

		state = engine.get_state()
		if state.round_number > current_round:
			return Result.success("已进入回合 %d" % state.round_number)

	return Result.failure("无法进入下一回合（已尝试 %d 次）" % max_attempts)

static func _advance_one_step(engine: GameEngine) -> Result:
	if engine == null:
		return Result.failure("engine 为空")
	var state := engine.get_state()
	if state == null:
		return Result.failure("state 为空")

	var cmd: Command
	if not state.sub_phase.is_empty():
		cmd = Command.create_system(ActionIdsClass.ADVANCE_PHASE, {"target": "sub_phase"})
	else:
		cmd = Command.create_system(ActionIdsClass.ADVANCE_PHASE)

	_mark_debug_force(cmd)
	return engine.execute_command(cmd)
