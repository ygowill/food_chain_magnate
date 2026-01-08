extends RefCounted

static func get_action_count(state: GameState, player_id: int, action_id: String) -> int:
	assert(not action_id.is_empty(), "action_id 不能为空")
	assert(state.round_state is Dictionary, "round_state 类型错误（期望 Dictionary）")
	assert(state.round_state.has("action_counts"), "round_state 缺少字段: action_counts")
	var counts_val = state.round_state["action_counts"]
	assert(counts_val is Dictionary, "round_state.action_counts 类型错误（期望 Dictionary）")
	var counts: Dictionary = counts_val
	assert(not counts.has(str(player_id)), "round_state.action_counts 不应包含字符串玩家 key: %s" % str(player_id))
	if not counts.has(player_id):
		return 0
	var per_val = counts[player_id]
	assert(per_val is Dictionary, "round_state.action_counts[%d] 类型错误（期望 Dictionary）" % player_id)
	var per_player: Dictionary = per_val
	if not per_player.has(action_id):
		return 0
	var v = per_player[action_id]
	assert(v is int, "round_state.action_counts[%d].%s 类型错误（期望 int）" % [player_id, action_id])
	assert(int(v) >= 0, "round_state.action_counts[%d].%s 不能为负数: %d" % [player_id, action_id, int(v)])
	return int(v)

static func increment_action_count(state: GameState, player_id: int, action_id: String) -> int:
	assert(not action_id.is_empty(), "action_id 不能为空")
	assert(state.round_state is Dictionary, "round_state 类型错误（期望 Dictionary）")
	assert(state.round_state.has("action_counts"), "round_state 缺少字段: action_counts")
	var counts_val = state.round_state["action_counts"]
	assert(counts_val is Dictionary, "round_state.action_counts 类型错误（期望 Dictionary）")
	var counts: Dictionary = counts_val
	assert(not counts.has(str(player_id)), "round_state.action_counts 不应包含字符串玩家 key: %s" % str(player_id))

	var per_player: Dictionary = {}
	if counts.has(player_id):
		var per_val = counts[player_id]
		assert(per_val is Dictionary, "round_state.action_counts[%d] 类型错误（期望 Dictionary）" % player_id)
		per_player = per_val

	var current := 0
	if per_player.has(action_id):
		var v = per_player[action_id]
		assert(v is int, "round_state.action_counts[%d].%s 类型错误（期望 int）" % [player_id, action_id])
		assert(int(v) >= 0, "round_state.action_counts[%d].%s 不能为负数: %d" % [player_id, action_id, int(v)])
		current = int(v)

	var new_value := current + 1
	per_player[action_id] = new_value
	counts[player_id] = per_player
	state.round_state["action_counts"] = counts
	return new_value

static func reset_action_counts(state: GameState) -> void:
	assert(state.round_state is Dictionary, "round_state 类型错误（期望 Dictionary）")
	state.round_state["action_counts"] = {}

