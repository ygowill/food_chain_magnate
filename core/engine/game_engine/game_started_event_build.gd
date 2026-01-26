# GameStarted 事件数据构建（抽离重复逻辑）
# 目标：统一 initializer / event_timeline_build / step_timeline_build 对 GAME_STARTED 的数据字段与计算方式。
extends RefCounted

static func build_from_state(state: GameState, state_hash_override: String = "") -> Result:
	if state == null:
		return Result.failure("GameStartedEventBuild: state 为空")
	if not (state.players is Array):
		return Result.failure("GameStartedEventBuild: state.players 类型错误（期望 Array）")

	var state_hash := state_hash_override
	if state_hash.is_empty():
		state_hash = str(state.compute_hash())

	return Result.success({
		"player_count": state.players.size(),
		"seed": int(state.seed),
		"state_hash": state_hash,
	})

static func build_from_state_dict(state_dict: Dictionary, prefix: String) -> Result:
	if prefix.is_empty():
		prefix = "GameStartedEventBuild"
	if not (state_dict is Dictionary):
		return Result.failure("%s: state_dict 类型错误（期望 Dictionary）" % prefix)

	var restore_r := GameState.from_dict(state_dict)
	if not restore_r.ok:
		return Result.failure("%s: 恢复 state 失败: %s" % [prefix, restore_r.error])
	var state: GameState = restore_r.value
	if state == null:
		return Result.failure("%s: 恢复 state 失败: state 为空" % prefix)

	return build_from_state(state)
