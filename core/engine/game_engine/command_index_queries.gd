# GameEngine：命令索引查询（从 game_engine.gd 抽离）
# 目的：缩短 GameEngine 单文件体积，将“纯查询/推导”职责集中到独立模块中。
extends RefCounted

const AutoAdvanceClass = preload("res://core/engine/game_engine/auto_advance.gd")
const ReplayStepRunnerClass = preload("res://core/engine/game_engine/replay_step_runner.gd")
const DefsClass = preload("res://core/engine/phase_manager/definitions.gd")

# 查找“当前阶段开始”对应的命令索引（用于 UI 的“一键回退本阶段”）。
# 语义：返回 target_index，用于 engine.rewind_to_command(target_index)。
# - 若当前阶段尚未执行任何命令，则返回 current_command_index（回退为 no-op）。
# - 若本局尚未执行任何命令，则返回 -1。
static func find_phase_start_command_index(engine: GameEngine) -> Result:
	var init_check := engine.ensure_initialized()
	if not init_check.ok:
		return init_check
	if engine.state == null:
		return Result.failure("游戏状态为空")

	if engine.current_command_index < 0:
		return Result.success(-1)

	var phase_name := str(engine.state.phase)
	var round_num := int(engine.state.round_number)

	var first_in_phase := -1
	for i in range(engine.current_command_index + 1):
		var cmd: Command = engine.command_history[i]
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
		return Result.success(engine.current_command_index)

	return Result.success(first_in_phase - 1)

# 查找“当前玩家在当前阶段的回合开始”对应的命令索引（用于 UI 的“一键回退当前玩家回合”）。
# 语义：返回 target_index，用于 engine.rewind_to_command(target_index)。
# - 目标是撤销“当前玩家在当前阶段内”的操作（不跨阶段）。
# - 仅依赖 PLAYER_TURN_STARTED 会漏掉“阶段变化但当前玩家不变”的场景（例如 OrderOfBusiness 自动进入 Working），
#   从而把回合开始错误定位到更早的阶段（例如 Payday）。因此这里同时考虑 phase/round 变化。
static func find_current_player_turn_start_command_index(engine: GameEngine, player_id: int = -1) -> Result:
	var init_check := engine.ensure_initialized()
	if not init_check.ok:
		return init_check
	if engine.state == null:
		return Result.failure("游戏状态为空")

	var pid := int(player_id)
	if pid < 0:
		pid = engine.state.get_current_player_id()
	if pid < 0 or pid >= engine.state.players.size():
		return Result.failure("当前玩家无效: %d" % pid)

	if engine.current_command_index < 0:
		return Result.success(-1)

	var phase_name := str(engine.state.phase)
	var round_num := int(engine.state.round_number)
	var sub_phase_name := str(engine.state.sub_phase)

	# Setup/ReserveCards 是一个独立的“轮转小流程”：
	# - ReserveCards 完成后进入起始餐厅放置，此时回退工具应回到“放置流程开始”（即 ReserveCards 最后一条命令之后），
	#   避免把用户带回储备卡选择（尤其在联机模式下会让体验非常突兀）。
	if phase_name == DefsClass.PHASE_SETUP and sub_phase_name != DefsClass.SUB_PHASE_RESERVE_CARDS:
		for i in range(int(engine.current_command_index), -1, -1):
			var cmd_sc: Command = engine.command_history[i]
			if cmd_sc == null:
				continue
			if str(cmd_sc.phase) != phase_name:
				continue
			# timestamp = round*1000 + ...（CommandRunner 写入），用于区分不同回合的同名阶段
			if int(cmd_sc.timestamp) >= 0 and int(int(cmd_sc.timestamp) / 1000) != round_num:
				continue
			if str(cmd_sc.sub_phase) != DefsClass.SUB_PHASE_RESERVE_CARDS:
				continue
			return Result.success(i)

	# 目标：撤销“当前玩家在当前阶段内”的所有命令。
	# 因此应回到“该玩家在该阶段内的第一个命令之前”的位置（而非“最近一次进入该玩家/阶段组合”的位置），
	# 以覆盖可能存在的“临时切换当前玩家后又切回”的场景。
	var first_cmd_in_phase_for_player := -1
	for i in range(int(engine.current_command_index) + 1):
		var cmd: Command = engine.command_history[i]
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
		return Result.success(int(engine.current_command_index))

	return Result.success(first_cmd_in_phase_for_player - 1)

static func infer_current_player_turn_start_command_index_by_replay(
	engine: GameEngine,
	player_id: int,
	target_index: int,
	target_phase: String,
	target_round: int
) -> Result:
	if target_index < 0:
		return Result.success(-1)
	if engine.checkpoints.is_empty():
		return Result.failure("缺少初始校验点")

	var initial_checkpoint := engine.checkpoints[0]
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
	for i in range(mini(target_index, engine.command_history.size() - 1) + 1):
		var cmd: Command = engine.command_history[i]
		var step_result := ReplayStepRunnerClass.apply_replay_command(replay_state, cmd, engine.action_registry, i, "CommandIndexQueries")
		if not step_result.ok:
			return step_result.with_warnings(warnings)
		warnings.append_array(step_result.warnings)
		var step_info: Dictionary = Dictionary(step_result.value)

		var new_state: GameState = step_info.get("state", null)
		if new_state == null:
			return Result.failure("回放命令 #%d 失败: state 为空" % i).with_warnings(warnings)

		var auto_r: Result = AutoAdvanceClass.drain(new_state, engine.phase_manager, engine.action_registry)
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
