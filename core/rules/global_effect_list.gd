# GlobalEffectList：全局效果列表读写封装
# 用途：统一 global_effect_ids 的创建/校验/去重添加，避免模块直接写裸数组导致契约漂移。
class_name GlobalEffectList
extends RefCounted

const KEY := "global_effect_ids"

static func ensure_map_list(state: GameState) -> Result:
	if state == null:
		return Result.failure("GlobalEffectList.ensure_map_list: state 为空")
	if not (state.map is Dictionary):
		return Result.failure("GlobalEffectList.ensure_map_list: state.map 类型错误（期望 Dictionary）")
	return _ensure_list(state.map, "state.map.%s" % KEY)

static func ensure_round_state_list(state: GameState) -> Result:
	if state == null:
		return Result.failure("GlobalEffectList.ensure_round_state_list: state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("GlobalEffectList.ensure_round_state_list: state.round_state 类型错误（期望 Dictionary）")
	return _ensure_list(state.round_state, "state.round_state.%s" % KEY)

static func add_to_map(state: GameState, effect_id: String) -> Result:
	if effect_id.is_empty():
		return Result.failure("GlobalEffectList.add_to_map: effect_id 不能为空")
	var list_read := ensure_map_list(state)
	if not list_read.ok:
		return list_read
	var ids: Array[String] = list_read.value
	if ids.find(effect_id) == -1:
		ids.append(effect_id)
	state.map[KEY] = ids
	return Result.success()

static func add_to_round_state(state: GameState, effect_id: String) -> Result:
	if effect_id.is_empty():
		return Result.failure("GlobalEffectList.add_to_round_state: effect_id 不能为空")
	var list_read := ensure_round_state_list(state)
	if not list_read.ok:
		return list_read
	var ids: Array[String] = list_read.value
	if ids.find(effect_id) == -1:
		ids.append(effect_id)
	state.round_state[KEY] = ids
	return Result.success()

static func get_all_effect_ids(state: GameState) -> Result:
	if state == null:
		return Result.failure("GlobalEffectList.get_all_effect_ids: state 为空")
	if not (state.round_state is Dictionary):
		return Result.failure("GlobalEffectList.get_all_effect_ids: state.round_state 类型错误（期望 Dictionary）")
	if not (state.map is Dictionary):
		return Result.failure("GlobalEffectList.get_all_effect_ids: state.map 类型错误（期望 Dictionary）")

	var warnings: Array[String] = []
	var out: Array[String] = []

	var sources := [
		{"container": state.round_state, "path": "state.round_state.%s" % KEY},
		{"container": state.map, "path": "state.map.%s" % KEY},
	]

	for src_val in sources:
		var src: Dictionary = src_val
		var container: Dictionary = src["container"]
		var path: String = str(src["path"])
		if not container.has(KEY):
			continue
		var list_val = container.get(KEY, null)
		if list_val == null:
			continue
		if not (list_val is Array):
			return Result.failure("%s 类型错误（期望 Array[String]）" % path)
		var ids_any: Array = list_val
		for i in range(ids_any.size()):
			var v = ids_any[i]
			if not (v is String):
				return Result.failure("%s[%d] 类型错误（期望 String）" % [path, i])
			var eid: String = str(v)
			if eid.is_empty():
				return Result.failure("%s[%d] 不能为空" % [path, i])
			out.append(eid)

	# 兼容：不改变行为（允许重复），但记录 warning 便于定位来源问题
	var seen := {}
	for eid in out:
		if seen.has(eid):
			warnings.append("global_effect_ids 重复: %s" % eid)
		else:
			seen[eid] = true

	return Result.success(out).with_warnings(warnings)

static func _ensure_list(container: Dictionary, path: String) -> Result:
	if not container.has(KEY):
		container[KEY] = []
	var val = container.get(KEY, null)
	if not (val is Array):
		return Result.failure("%s 类型错误（期望 Array[String]）" % path)
	var any: Array = val
	var out: Array[String] = []
	for i in range(any.size()):
		var v = any[i]
		if not (v is String):
			return Result.failure("%s[%d] 类型错误（期望 String）" % [path, i])
		var s: String = str(v)
		if s.is_empty():
			return Result.failure("%s[%d] 不能为空" % [path, i])
		out.append(s)
	container[KEY] = out
	return Result.success(out)

