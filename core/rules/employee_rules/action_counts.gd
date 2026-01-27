extends RefCounted

const RoundStateCountersClass = preload("res://core/utils/round_state_counters.gd")

static func get_action_count(state: GameState, player_id: int, action_id: String) -> int:
	assert(not action_id.is_empty(), "action_id 不能为空")
	assert(state.round_state is Dictionary, "round_state 类型错误（期望 Dictionary）")
	assert(state.round_state.has("action_counts"), "round_state 缺少字段: action_counts")
	var read := RoundStateCountersClass.get_player_key_count(state.round_state, "action_counts", player_id, action_id)
	assert(read.ok, read.error)
	var count: int = int(read.value)
	assert(count >= 0, "round_state.action_counts[%d].%s 不能为负数: %d" % [player_id, action_id, count])
	return count

static func increment_action_count(state: GameState, player_id: int, action_id: String) -> int:
	assert(not action_id.is_empty(), "action_id 不能为空")
	assert(state.round_state is Dictionary, "round_state 类型错误（期望 Dictionary）")
	assert(state.round_state.has("action_counts"), "round_state 缺少字段: action_counts")
	var current_read := RoundStateCountersClass.get_player_key_count(state.round_state, "action_counts", player_id, action_id)
	assert(current_read.ok, current_read.error)
	var current: int = int(current_read.value)
	assert(current >= 0, "round_state.action_counts[%d].%s 不能为负数: %d" % [player_id, action_id, current])

	var inc_read := RoundStateCountersClass.increment_player_key_count(state.round_state, "action_counts", player_id, action_id, 1)
	assert(inc_read.ok, inc_read.error)
	var new_value: int = int(inc_read.value)
	assert(new_value >= 0, "round_state.action_counts[%d].%s 不能为负数: %d" % [player_id, action_id, new_value])
	return new_value

static func reset_action_counts(state: GameState) -> void:
	assert(state.round_state is Dictionary, "round_state 类型错误（期望 Dictionary）")
	state.round_state["action_counts"] = {}
