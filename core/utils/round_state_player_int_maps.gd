# RoundState：按玩家维护 String->int 映射的读写工具（Fail Fast）
# 用途：统一 round_state 下“player_id -> {key -> int}”结构的读取/校验/写入，减少重复样板。
class_name RoundStatePlayerIntMaps
extends RefCounted

static func _prefix(label: String) -> String:
	if label.is_empty():
		return ""
	if label.ends_with(": "):
		return label
	if label.ends_with("： "):
		return label
	if label.ends_with(":"):
		return "%s " % label
	if label.ends_with("："):
		return "%s " % label
	return "%s: " % label

static func require_player_int_map(round_state: Dictionary, key: String, player_id: int, prefix_label: String) -> Result:
	var prefix := _prefix(prefix_label)
	if key.is_empty():
		return Result.failure("%skey 不能为空" % prefix)
	if not (round_state is Dictionary):
		return Result.failure("%sround_state 类型错误（期望 Dictionary）" % prefix)
	if not round_state.has(key):
		return Result.failure("%sround_state.%s 缺失" % [prefix, key])

	var all_val = round_state.get(key, null)
	if not (all_val is Dictionary):
		return Result.failure("%sround_state.%s 类型错误（期望 Dictionary）" % [prefix, key])
	var all: Dictionary = all_val
	if all.has(str(player_id)):
		return Result.failure("%sround_state.%s 不应包含字符串玩家 key: %s" % [prefix, key, str(player_id)])
	if not all.has(player_id):
		return Result.failure("%sround_state.%s 缺失玩家 key: %d" % [prefix, key, player_id])

	var per_val = all.get(player_id, null)
	if not (per_val is Dictionary):
		return Result.failure("%sround_state.%s[%d] 类型错误（期望 Dictionary）" % [prefix, key, player_id])
	var per: Dictionary = per_val
	for item_key in per.keys():
		if not (item_key is String):
			return Result.failure("%sround_state.%s[%d] key 类型错误（期望 String）" % [prefix, key, player_id])
		var value = per.get(item_key, null)
		if not (value is int):
			return Result.failure("%sround_state.%s[%d].%s 类型错误（期望 int）" % [prefix, key, player_id, str(item_key)])
	return Result.success(per)

static func set_player_key_int(
	round_state: Dictionary,
	key: String,
	player_id: int,
	item_key: String,
	value: int,
	prefix_label: String
) -> Result:
	var prefix := _prefix(prefix_label)
	if key.is_empty():
		return Result.failure("%skey 不能为空" % prefix)
	if item_key.is_empty():
		return Result.failure("%sitem_key 不能为空" % prefix)
	if not (round_state is Dictionary):
		return Result.failure("%sround_state 类型错误（期望 Dictionary）" % prefix)

	if not round_state.has(key):
		round_state[key] = {}

	var all_val = round_state.get(key, null)
	if not (all_val is Dictionary):
		return Result.failure("%sround_state.%s 类型错误（期望 Dictionary）" % [prefix, key])
	var all: Dictionary = all_val
	if all.has(str(player_id)):
		return Result.failure("%sround_state.%s 不应包含字符串玩家 key: %s" % [prefix, key, str(player_id)])

	var per: Dictionary = {}
	if all.has(player_id):
		var per_read := require_player_int_map(round_state, key, player_id, prefix_label)
		if not per_read.ok:
			return per_read
		per = Dictionary(per_read.value).duplicate(true)

	per[item_key] = value
	all[player_id] = per
	round_state[key] = all
	return Result.success(value)
