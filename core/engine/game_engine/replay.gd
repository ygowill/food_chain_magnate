# GameEngine：回放/倒带实现（基于 checkpoint + executor.compute_new_state）
extends RefCounted

static func rewind_to_command(
	command_history: Array[Command],
	checkpoints: Array[Dictionary],
	action_registry: ActionRegistry,
	target_index: int
) -> Result:
	if target_index < -1 or target_index >= command_history.size():
		return Result.failure("无效的命令索引: %d" % target_index)
	if checkpoints.is_empty():
		return Result.failure("缺少初始校验点")

	# 回到初始状态（尚未执行任何命令）
	if target_index == -1:
		var initial_checkpoint := checkpoints[0]
		var restore_result := GameState.from_dict(initial_checkpoint.state_dict)
		if not restore_result.ok:
			return Result.failure("恢复 initial_checkpoint 失败: %s" % restore_result.error)
		var restored_state: GameState = restore_result.value

		var rng_calls_read := _require_checkpoint_rng_calls(initial_checkpoint, "checkpoints[0].rng_calls")
		if not rng_calls_read.ok:
			return rng_calls_read
		var rng_calls: int = int(rng_calls_read.value)
		var rng_result := RandomManager.from_dict({
			"initial_seed": restored_state.seed,
			"call_count": rng_calls
		})
		if not rng_result.ok:
			return Result.failure("恢复 RandomManager 失败: %s" % rng_result.error)

		return Result.success({
			"state": restored_state,
			"random_manager": rng_result.value,
			"current_command_index": -1
		})

	# 找到最近的校验点
	var checkpoint := _find_nearest_checkpoint(checkpoints, target_index)
	if checkpoint.is_empty():
		return Result.failure("找不到合适的校验点")

	# 从校验点恢复状态
	var restore_result := GameState.from_dict(checkpoint.state_dict)
	if not restore_result.ok:
		return Result.failure("恢复 checkpoint 失败: %s" % restore_result.error)
	var restored_state: GameState = restore_result.value

	var rng_calls_read2 := _require_checkpoint_rng_calls(checkpoint, "checkpoint.rng_calls")
	if not rng_calls_read2.ok:
		return rng_calls_read2
	var rng_calls2: int = int(rng_calls_read2.value)
	var rng_result := RandomManager.from_dict({
		"initial_seed": restored_state.seed,
		"call_count": rng_calls2
	})
	if not rng_result.ok:
		return Result.failure("恢复 RandomManager 失败: %s" % rng_result.error)
	var restored_rng: RandomManager = rng_result.value

	# 重放到目标位置
	var start_index: int = int(checkpoint.index)
	var replay_state: GameState = restored_state
	for i in range(start_index, target_index + 1):
		var cmd: Command = command_history[i]
		var executor := action_registry.get_executor(cmd.action_id)
		if executor == null:
			return Result.failure("回放时找不到执行器: %s" % cmd.action_id)

		var step_result := executor.compute_new_state(replay_state, cmd)
		if not step_result.ok:
			return Result.failure("回放命令 #%d 失败: %s" % [i, step_result.error])
		replay_state = step_result.value

	GameLog.info("GameEngine", "回退到命令 #%d (从校验点 #%d 重放)" % [
		target_index, checkpoint.index
	])

	return Result.success({
		"state": replay_state,
		"random_manager": restored_rng,
		"current_command_index": target_index
	})

static func full_replay(
	command_history: Array[Command],
	checkpoints: Array[Dictionary],
	action_registry: ActionRegistry
) -> Result:
	if checkpoints.is_empty():
		return Result.failure("缺少初始校验点，无法重放")

	# 恢复初始状态
	var initial_checkpoint := checkpoints[0]
	var restore_result := GameState.from_dict(initial_checkpoint.state_dict)
	if not restore_result.ok:
		return Result.failure("恢复 initial_checkpoint 失败: %s" % restore_result.error)
	var restored_state: GameState = restore_result.value

	var rng_calls_read := _require_checkpoint_rng_calls(initial_checkpoint, "checkpoints[0].rng_calls")
	if not rng_calls_read.ok:
		return rng_calls_read
	var rng_calls: int = int(rng_calls_read.value)
	var rng_result := RandomManager.from_dict({
		"initial_seed": restored_state.seed,
		"call_count": rng_calls
	})
	if not rng_result.ok:
		return Result.failure("恢复 RandomManager 失败: %s" % rng_result.error)
	var restored_rng: RandomManager = rng_result.value

	# 重放所有命令
	var replay_state: GameState = restored_state
	for i in range(command_history.size()):
		var cmd: Command = command_history[i]
		var executor := action_registry.get_executor(cmd.action_id)
		if executor == null:
			return Result.failure("重放时找不到执行器: %s" % cmd.action_id)

		var step_result := executor.compute_new_state(replay_state, cmd)
		if not step_result.ok:
			return Result.failure("重放命令 #%d 失败: %s" % [i, step_result.error])
		replay_state = step_result.value

	GameLog.info("GameEngine", "完整重放 %d 条命令" % command_history.size())

	return Result.success({
		"state": replay_state,
		"random_manager": restored_rng,
		"current_command_index": command_history.size() - 1
	})

static func _require_checkpoint_rng_calls(checkpoint: Dictionary, path: String) -> Result:
	if not (checkpoint is Dictionary):
		return Result.failure("%s 的上级对象类型错误（期望 Dictionary）" % path)
	if not checkpoint.has("rng_calls"):
		return Result.failure("缺少字段: %s" % path)
	var v = checkpoint["rng_calls"]
	if v is int:
		var n: int = int(v)
		if n < 0:
			return Result.failure("%s 不能为负数: %d" % [path, n])
		return Result.success(n)
	if v is float:
		var f: float = float(v)
		if f != floor(f):
			return Result.failure("%s 必须为整数（不允许小数），实际: %s" % [path, str(v)])
		var n2: int = int(f)
		if n2 < 0:
			return Result.failure("%s 不能为负数: %d" % [path, n2])
		return Result.success(n2)
	return Result.failure("%s 类型错误（期望整数）" % path)

static func _find_nearest_checkpoint(checkpoints: Array[Dictionary], target_index: int) -> Dictionary:
	var best: Dictionary = {}
	for checkpoint in checkpoints:
		if checkpoint.index <= target_index:
			if best.is_empty() or checkpoint.index > best.index:
				best = checkpoint
	return best
