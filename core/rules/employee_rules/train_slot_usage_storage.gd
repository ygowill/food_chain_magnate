extends RefCounted

const RoundStateCountersClass = preload("res://core/utils/round_state_counters.gd")

const ROUND_STATE_KEY := "train_slot_usage"
const ROUND_STATE_KEY_INSTANCES := "train_slot_usage_instances"

static func reset_train_slot_usage(state: GameState) -> void:
	# 子阶段级别：与 action_counts 同步重置（避免跨子阶段残留导致误判）
	if state == null:
		return
	if not (state.round_state is Dictionary):
		return
	state.round_state[ROUND_STATE_KEY] = {}
	state.round_state[ROUND_STATE_KEY_INSTANCES] = {}

static func get_train_slot_usage_round_state_key() -> String:
	return ROUND_STATE_KEY

static func _read_used_slots_total(state: GameState, player_id: int, trainer_id: String) -> int:
	if trainer_id.is_empty():
		return 0
	if state == null or not (state.round_state is Dictionary):
		return 0
	var read := RoundStateCountersClass.get_player_key_count(state.round_state, ROUND_STATE_KEY, player_id, trainer_id)
	assert(read.ok, "train_slot_usage 结构损坏: %s" % read.error)
	return int(read.value)

static func _compute_used_by_instance_from_total(used_total: int, instances: int, cap_per_instance: int) -> Array[int]:
	# 兼容旧版（仅记录 trainer_id 总用量）：将用量尽量集中到少数实例上，得到一个确定的 per-instance 分配。
	var out: Array[int] = []
	if instances <= 0 or cap_per_instance <= 0:
		return out
	var remaining := maxi(0, used_total)
	for _i in range(instances):
		var take := mini(cap_per_instance, remaining)
		out.append(take)
		remaining -= take
	return out

static func read_used_slots_by_instance(state: GameState, player_id: int, trainer_id: String, instances: int, cap_per_instance: int) -> Result:
	if trainer_id.is_empty():
		return Result.failure("trainer_id 不能为空")
	if state == null or not (state.round_state is Dictionary):
		return Result.failure("train_slot_usage_instances: state/round_state 无效")
	if instances <= 0:
		return Result.success([])

	var all_val = state.round_state.get(ROUND_STATE_KEY_INSTANCES, null)
	if all_val != null:
		if not (all_val is Dictionary):
			return Result.failure("train_slot_usage_instances 类型错误（期望 Dictionary）")
		var all: Dictionary = all_val
		assert(not all.has(str(player_id)), "round_state.%s 不应包含字符串玩家 key: %s" % [ROUND_STATE_KEY_INSTANCES, str(player_id)])
		if all.has(player_id):
			var per_val = all.get(player_id, null)
			if not (per_val is Dictionary):
				return Result.failure("round_state.%s[%d] 类型错误（期望 Dictionary）" % [ROUND_STATE_KEY_INSTANCES, player_id])
			var per: Dictionary = per_val
			if per.has(trainer_id):
				var arr_val = per.get(trainer_id, null)
				if not (arr_val is Array):
					return Result.failure("round_state.%s[%d].%s 类型错误（期望 Array[int]）" % [ROUND_STATE_KEY_INSTANCES, player_id, trainer_id])
				var arr_any: Array = arr_val
				var out: Array[int] = []
				for i in range(instances):
					var v := 0
					if i < arr_any.size():
						var item = arr_any[i]
						if item is int:
							v = int(item)
						elif item is float:
							var f: float = float(item)
							if f == int(f):
								v = int(f)
							else:
								return Result.failure("round_state.%s[%d].%s[%d] 类型错误（期望 int）" % [ROUND_STATE_KEY_INSTANCES, player_id, trainer_id, i])
						else:
							return Result.failure("round_state.%s[%d].%s[%d] 类型错误（期望 int）" % [ROUND_STATE_KEY_INSTANCES, player_id, trainer_id, i])
					if v < 0:
						return Result.failure("round_state.%s[%d].%s[%d] 不能为负数: %d" % [ROUND_STATE_KEY_INSTANCES, player_id, trainer_id, i, v])
					out.append(v)
				return Result.success(out)

	# fallback：旧版 train_slot_usage（总用量）
	var used_total := _read_used_slots_total(state, player_id, trainer_id)
	var used_by_instance := _compute_used_by_instance_from_total(used_total, instances, cap_per_instance)
	return Result.success(used_by_instance)

static func write_used_slots_by_instance(state: GameState, player_id: int, trainer_id: String, used_by_instance: Array[int]) -> Result:
	if trainer_id.is_empty():
		return Result.failure("trainer_id 不能为空")
	if state == null or not (state.round_state is Dictionary):
		return Result.failure("train_slot_usage_instances: state/round_state 无效")

	if not state.round_state.has(ROUND_STATE_KEY_INSTANCES):
		state.round_state[ROUND_STATE_KEY_INSTANCES] = {}
	var all_val = state.round_state.get(ROUND_STATE_KEY_INSTANCES, null)
	if not (all_val is Dictionary):
		return Result.failure("round_state.%s 类型错误（期望 Dictionary）" % ROUND_STATE_KEY_INSTANCES)
	var all: Dictionary = all_val
	assert(not all.has(str(player_id)), "round_state.%s 不应包含字符串玩家 key: %s" % [ROUND_STATE_KEY_INSTANCES, str(player_id)])

	if not all.has(player_id):
		all[player_id] = {}
	var per_val = all.get(player_id, null)
	if not (per_val is Dictionary):
		return Result.failure("round_state.%s[%d] 类型错误（期望 Dictionary）" % [ROUND_STATE_KEY_INSTANCES, player_id])
	var per: Dictionary = per_val

	per[trainer_id] = used_by_instance
	all[player_id] = per
	state.round_state[ROUND_STATE_KEY_INSTANCES] = all
	return Result.success()

static func increment_used_slots_total(state: GameState, player_id: int, trainer_id: String, slots: int) -> Result:
	if state == null or not (state.round_state is Dictionary):
		return Result.failure("train_slot_usage: state/round_state 无效")
	if trainer_id.is_empty():
		return Result.failure("trainer_id 不能为空")
	if slots <= 0:
		return Result.success()
	return RoundStateCountersClass.increment_player_key_count(state.round_state, ROUND_STATE_KEY, player_id, trainer_id, slots)
