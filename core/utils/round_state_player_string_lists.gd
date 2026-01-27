# RoundState：按玩家维护 String 列表的读写工具（Fail Fast）
# 用途：统一 round_state 下“player_id -> Array[String]”结构的读取/校验与去重添加，减少重复样板。
class_name RoundStatePlayerStringLists
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

static func require_player_string_array(round_state: Dictionary, key: String, player_id: int, prefix_label: String) -> Result:
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

	var list_val = all.get(player_id, null)
	if not (list_val is Array):
		return Result.failure("%sround_state.%s[%d] 类型错误（期望 Array）" % [prefix, key, player_id])
	var list: Array = list_val

	for i in range(list.size()):
		var v = list[i]
		if not (v is String):
			return Result.failure("%sround_state.%s[%d][%d] 类型错误（期望 String）" % [prefix, key, player_id, i])
		var s: String = str(v)
		if s.is_empty():
			return Result.failure("%sround_state.%s[%d][%d] 不能为空" % [prefix, key, player_id, i])

	return Result.success(list)

static func has_value(round_state: Dictionary, key: String, player_id: int, value: String, prefix_label: String) -> Result:
	var prefix := _prefix(prefix_label)
	if value.is_empty():
		return Result.failure("%svalue 不能为空" % prefix)

	var list_read := require_player_string_array(round_state, key, player_id, prefix_label)
	if not list_read.ok:
		return list_read
	var list: Array = list_read.value
	return Result.success(list.has(value))

static func add_unique_value(round_state: Dictionary, key: String, player_id: int, value: String, prefix_label: String) -> Result:
	var prefix := _prefix(prefix_label)
	if value.is_empty():
		return Result.failure("%svalue 不能为空" % prefix)

	var list_read := require_player_string_array(round_state, key, player_id, prefix_label)
	if not list_read.ok:
		return list_read
	var list: Array = list_read.value
	if not list.has(value):
		list.append(value)
	return Result.success()
