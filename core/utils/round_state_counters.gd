# RoundState 计数工具（去重模块）
# 负责：统一 round_state 下“按玩家/按类型”的计数读写，并对结构/类型做严格校验（Fail Fast）。
class_name RoundStateCounters
extends RefCounted

static func get_player_count(round_state: Dictionary, counter_key: String, player_id: int) -> Result:
	if counter_key.is_empty():
		return Result.failure("counter_key 不能为空")
	if not (round_state is Dictionary):
		return Result.failure("round_state 类型错误（期望 Dictionary）")

	if not round_state.has(counter_key):
		return Result.success(0)

	var all_val = round_state.get(counter_key, null)
	if not (all_val is Dictionary):
		return Result.failure("round_state.%s 类型错误（期望 Dictionary）" % counter_key)
	var all: Dictionary = all_val
	assert(not all.has(str(player_id)), "round_state.%s 不应包含字符串玩家 key: %s" % [counter_key, str(player_id)])

	if not all.has(player_id):
		return Result.success(0)

	var v = all.get(player_id, null)
	if not (v is int):
		return Result.failure("round_state.%s[%d] 类型错误（期望 int）" % [counter_key, player_id])
	return Result.success(int(v))

static func increment_player_count(
	round_state: Dictionary,
	counter_key: String,
	player_id: int,
	delta: int = 1
) -> Result:
	if counter_key.is_empty():
		return Result.failure("counter_key 不能为空")
	if not (round_state is Dictionary):
		return Result.failure("round_state 类型错误（期望 Dictionary）")
	if delta <= 0:
		return Result.failure("delta 必须 > 0")

	if not round_state.has(counter_key):
		round_state[counter_key] = {}

	var all_val = round_state.get(counter_key, null)
	if not (all_val is Dictionary):
		return Result.failure("round_state.%s 类型错误（期望 Dictionary）" % counter_key)
	var all: Dictionary = all_val
	assert(not all.has(str(player_id)), "round_state.%s 不应包含字符串玩家 key: %s" % [counter_key, str(player_id)])

	var current := 0
	if all.has(player_id):
		var v = all.get(player_id, null)
		if not (v is int):
			return Result.failure("round_state.%s[%d] 类型错误（期望 int）" % [counter_key, player_id])
		current = int(v)

	var new_value := current + delta
	all[player_id] = new_value
	round_state[counter_key] = all
	return Result.success(new_value)

static func get_player_key_count(
	round_state: Dictionary,
	counter_key: String,
	player_id: int,
	item_key: String
) -> Result:
	if counter_key.is_empty():
		return Result.failure("counter_key 不能为空")
	if item_key.is_empty():
		return Result.failure("item_key 不能为空")
	if not (round_state is Dictionary):
		return Result.failure("round_state 类型错误（期望 Dictionary）")

	if not round_state.has(counter_key):
		return Result.success(0)

	var all_val = round_state.get(counter_key, null)
	if not (all_val is Dictionary):
		return Result.failure("round_state.%s 类型错误（期望 Dictionary）" % counter_key)
	var all: Dictionary = all_val
	assert(not all.has(str(player_id)), "round_state.%s 不应包含字符串玩家 key: %s" % [counter_key, str(player_id)])

	if not all.has(player_id):
		return Result.success(0)

	var per_player_val = all.get(player_id, null)
	if not (per_player_val is Dictionary):
		return Result.failure("round_state.%s[%d] 类型错误（期望 Dictionary）" % [counter_key, player_id])
	var per_player: Dictionary = per_player_val

	if not per_player.has(item_key):
		return Result.success(0)

	var v = per_player.get(item_key, null)
	if not (v is int):
		return Result.failure("round_state.%s[%d].%s 类型错误（期望 int）" % [counter_key, player_id, item_key])
	return Result.success(int(v))

static func increment_player_key_count(
	round_state: Dictionary,
	counter_key: String,
	player_id: int,
	item_key: String,
	delta: int = 1
) -> Result:
	if counter_key.is_empty():
		return Result.failure("counter_key 不能为空")
	if item_key.is_empty():
		return Result.failure("item_key 不能为空")
	if not (round_state is Dictionary):
		return Result.failure("round_state 类型错误（期望 Dictionary）")
	if delta <= 0:
		return Result.failure("delta 必须 > 0")

	if not round_state.has(counter_key):
		round_state[counter_key] = {}

	var all_val = round_state.get(counter_key, null)
	if not (all_val is Dictionary):
		return Result.failure("round_state.%s 类型错误（期望 Dictionary）" % counter_key)
	var all: Dictionary = all_val
	assert(not all.has(str(player_id)), "round_state.%s 不应包含字符串玩家 key: %s" % [counter_key, str(player_id)])

	if not all.has(player_id):
		all[player_id] = {}

	var per_player_val = all.get(player_id, null)
	if not (per_player_val is Dictionary):
		return Result.failure("round_state.%s[%d] 类型错误（期望 Dictionary）" % [counter_key, player_id])
	var per_player: Dictionary = per_player_val

	var current := 0
	if per_player.has(item_key):
		var v = per_player.get(item_key, null)
		if not (v is int):
			return Result.failure("round_state.%s[%d].%s 类型错误（期望 int）" % [counter_key, player_id, item_key])
		current = int(v)

	var new_value := current + delta
	per_player[item_key] = new_value
	all[player_id] = per_player
	round_state[counter_key] = all
	return Result.success(new_value)
