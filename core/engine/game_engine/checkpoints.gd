# GameEngine：校验点管理
# 负责：创建/查找/校验 checkpoint（用于 rewind/replay 与存档）。
extends RefCounted

static func create_checkpoint(
	checkpoints: Array[Dictionary],
	state: GameState,
	random_manager: RandomManager,
	index: int
) -> void:
	assert(state != null, "内部错误：GameState 未初始化")
	assert(random_manager != null, "内部错误：RandomManager 未初始化")

	var state_dict: Dictionary = state.to_dict().duplicate(true)
	var checkpoint := {
		"index": index,
		"state_dict": state_dict,
		"hash": state.compute_hash(),
		"rng_calls": random_manager.get_call_count(),
		"timestamp": Time.get_unix_time_from_system()
	}
	checkpoints.append(checkpoint)

	if DebugFlags.verbose_logging:
		GameLog.debug("GameEngine", "创建校验点 #%d (hash: %s...)" % [
			index, str(checkpoint.hash).substr(0, 8)
		])

static func find_nearest_checkpoint(checkpoints: Array[Dictionary], target_index: int) -> Dictionary:
	var best: Dictionary = {}
	for checkpoint in checkpoints:
		if checkpoint.index <= target_index:
			if best.is_empty() or checkpoint.index > best.index:
				best = checkpoint
	return best

static func verify_checkpoints(checkpoints: Array[Dictionary]) -> Result:
	for checkpoint in checkpoints:
		var temp_state_result := GameState.from_dict(checkpoint.state_dict)
		if not temp_state_result.ok:
			return Result.failure("校验点 #%d state_dict 无效: %s" % [int(checkpoint.index), temp_state_result.error])

		var temp_state: GameState = temp_state_result.value
		var computed_hash: String = temp_state.compute_hash()

		if computed_hash != checkpoint.hash:
			return Result.failure("校验点 #%d 哈希不匹配: 期望 %s, 实际 %s" % [
				checkpoint.index,
				checkpoint.hash.substr(0, 8),
				computed_hash.substr(0, 8)
			])

	return Result.success("所有 %d 个校验点验证通过" % checkpoints.size())

