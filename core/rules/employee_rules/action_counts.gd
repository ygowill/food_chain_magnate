extends RefCounted

const RoundStateCountersClass = preload("res://core/utils/round_state_counters.gd")

static func try_get_action_count(state: GameState, player_id: int, action_id: String) -> Result:
	if action_id.is_empty():
		return Result.failure("action_id 不能为空")
	if state == null:
		return Result.failure("get_action_count: state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("round_state 类型错误（期望 Dictionary）")
	var read := RoundStateCountersClass.get_player_key_count(state.round_state, "action_counts", player_id, action_id)
	if not read.ok:
		return read
	var count: int = int(read.value)
	if count < 0:
		return Result.failure("round_state.action_counts[%d].%s 不能为负数: %d" % [player_id, action_id, count])
	return Result.success(count)

static func get_action_count(state: GameState, player_id: int, action_id: String) -> int:
	var read := try_get_action_count(state, player_id, action_id)
	if not read.ok:
		return 0
	return int(read.value)

static func try_increment_action_count(state: GameState, player_id: int, action_id: String) -> Result:
	var current_read := try_get_action_count(state, player_id, action_id)
	if not current_read.ok:
		return current_read
	var inc_read := RoundStateCountersClass.increment_player_key_count(state.round_state, "action_counts", player_id, action_id, 1)
	if not inc_read.ok:
		return inc_read
	var new_value: int = int(inc_read.value)
	if new_value < 0:
		return Result.failure("round_state.action_counts[%d].%s 不能为负数: %d" % [player_id, action_id, new_value])
	return Result.success(new_value)

static func increment_action_count(state: GameState, player_id: int, action_id: String) -> int:
	var read := try_increment_action_count(state, player_id, action_id)
	if not read.ok:
		return 0
	return int(read.value)

static func reset_action_counts(state: GameState) -> void:
	assert(state.round_state is Dictionary, "round_state 类型错误（期望 Dictionary）")
	state.round_state["action_counts"] = {}
