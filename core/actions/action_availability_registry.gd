# 动作可用性注册表（按 phase/sub_phase 决定动作是否可用）
# - 默认从 ActionExecutor.allowed_phases / allowed_sub_phases 推导
# - 模块可按 action_id 覆盖其可用点位（Fail Fast：引用不存在的 action_id 会导致初始化失败）
class_name ActionAvailabilityRegistry
extends RefCounted

var _default_points_by_action: Dictionary = {}  # action_id -> Array[{phase, sub_phase}]
var _override_by_action: Dictionary = {}        # action_id -> {points:Array, priority:int, source:String}

var _compiled: Dictionary = {}                 # phase -> Dictionary{sub_phase -> Array[String]}
var _compiled_any_phase: Array[String] = []    # 允许在任意阶段/子阶段的 action_id
var _compiled_ready: bool = false

func reset() -> void:
	_default_points_by_action.clear()
	_override_by_action.clear()
	_compiled.clear()
	_compiled_any_phase.clear()
	_compiled_ready = false

func build_defaults_from_executors(executors: Array) -> Result:
	_default_points_by_action.clear()
	_compiled_ready = false

	for i in range(executors.size()):
		var ex_val = executors[i]
		if ex_val == null:
			continue
		if not (ex_val is ActionExecutor):
			return Result.failure("ActionAvailabilityRegistry: executors[%d] 类型错误（期望 ActionExecutor）" % i)
		var ex: ActionExecutor = ex_val
		if ex.action_id.is_empty():
			return Result.failure("ActionAvailabilityRegistry: executors[%d] 缺少 action_id" % i)

		var points: Array[Dictionary] = []

		# allowed_phases 为空：表示任意阶段都可用（如 advance_phase/skip）
		if ex.allowed_phases.is_empty():
			_default_points_by_action[ex.action_id] = []
			continue

		for p in ex.allowed_phases:
			if not (p is String):
				return Result.failure("ActionAvailabilityRegistry: %s.allowed_phases 包含非字符串" % ex.action_id)
			var phase_name: String = str(p)
			if phase_name.is_empty():
				return Result.failure("ActionAvailabilityRegistry: %s.allowed_phases 不能为空" % ex.action_id)

			if ex.allowed_sub_phases.is_empty():
				points.append({"phase": phase_name, "sub_phase": ""})
				continue

			for sp in ex.allowed_sub_phases:
				if not (sp is String):
					return Result.failure("ActionAvailabilityRegistry: %s.allowed_sub_phases 包含非字符串" % ex.action_id)
				var sub_name: String = str(sp)
				if sub_name.is_empty():
					return Result.failure("ActionAvailabilityRegistry: %s.allowed_sub_phases 不能为空" % ex.action_id)
				points.append({"phase": phase_name, "sub_phase": sub_name})

		_default_points_by_action[ex.action_id] = points

	return Result.success()

func register_action_points_override(
	action_id: String,
	points: Array,
	priority: int = 100,
	source_module_id: String = ""
) -> Result:
	if action_id.is_empty():
		return Result.failure("ActionAvailabilityRegistry: action_id 不能为空")
	if not (points is Array):
		return Result.failure("ActionAvailabilityRegistry: points 类型错误（期望 Array）")

	for i in range(points.size()):
		var pv = points[i]
		if not (pv is Dictionary):
			return Result.failure("ActionAvailabilityRegistry: %s.points[%d] 类型错误（期望 Dictionary）" % [action_id, i])
		var p: Dictionary = pv
		var phase_name: String = str(p.get("phase", ""))
		var sub_name: String = str(p.get("sub_phase", ""))
		if phase_name.is_empty():
			return Result.failure("ActionAvailabilityRegistry: %s.points[%d].phase 不能为空" % [action_id, i])
		if not p.has("sub_phase"):
			return Result.failure("ActionAvailabilityRegistry: %s.points[%d] 缺少字段: sub_phase" % [action_id, i])
		if sub_name.is_empty() and str(p.get("sub_phase", "")) != "":
			return Result.failure("ActionAvailabilityRegistry: %s.points[%d].sub_phase 类型错误（期望 String）" % [action_id, i])

	_override_by_action[action_id] = {
		"points": points.duplicate(true),
		"priority": int(priority),
		"source": source_module_id,
	}
	_compiled_ready = false
	return Result.success()

func compile_with_validation(action_ids: Array) -> Result:
	_compiled.clear()
	_compiled_any_phase.clear()

	var known := {}
	for v in action_ids:
		if v is String:
			var aid: String = str(v)
			if not aid.is_empty():
				known[aid] = true

	# 覆盖必须指向已存在的 action_id（Strict）
	for k in _override_by_action.keys():
		var aid2: String = str(k)
		if not known.has(aid2):
			var info: Dictionary = _override_by_action[aid2]
			var src: String = str(info.get("source", ""))
			return Result.failure("ActionAvailabilityRegistry: 覆盖了不存在的 action_id: %s (module:%s)" % [aid2, src])

	var all_action_ids: Array[String] = []
	for v in action_ids:
		if not (v is String):
			continue
		var aid3: String = str(v)
		if aid3.is_empty():
			continue
		all_action_ids.append(aid3)
	all_action_ids.sort()

	for aid4 in all_action_ids:
		var points: Array = _default_points_by_action.get(aid4, [])
		if _override_by_action.has(aid4):
			var info2: Dictionary = _override_by_action[aid4]
			var pts_val = info2.get("points", [])
			if not (pts_val is Array):
				return Result.failure("ActionAvailabilityRegistry: override.points 类型错误: %s" % aid4)
			points = pts_val

		# 允许任意阶段
		if points.is_empty():
			_compiled_any_phase.append(aid4)
			continue

		for pv2 in points:
			if not (pv2 is Dictionary):
				return Result.failure("ActionAvailabilityRegistry: points 类型错误: %s" % aid4)
			var p2: Dictionary = pv2
			var phase_name2: String = str(p2.get("phase", ""))
			var sub_name2: String = str(p2.get("sub_phase", ""))
			if phase_name2.is_empty():
				return Result.failure("ActionAvailabilityRegistry: points.phase 不能为空: %s" % aid4)
			if not p2.has("sub_phase"):
				return Result.failure("ActionAvailabilityRegistry: points 缺少字段 sub_phase: %s" % aid4)

			if not _compiled.has(phase_name2):
				_compiled[phase_name2] = {}
			var by_sub: Dictionary = _compiled[phase_name2]
			if not by_sub.has(sub_name2):
				by_sub[sub_name2] = []
			var list: Array = by_sub[sub_name2]
			list.append(aid4)
			by_sub[sub_name2] = list
			_compiled[phase_name2] = by_sub

	# 去重与排序（确定性）
	for phase_name3 in _compiled.keys():
		var by_sub2: Dictionary = _compiled[phase_name3]
		for sub_name3 in by_sub2.keys():
			var list2: Array = by_sub2[sub_name3]
			var seen := {}
			var uniq: Array[String] = []
			for a in list2:
				if not (a is String):
					continue
				var s: String = str(a)
				if s.is_empty() or seen.has(s):
					continue
				seen[s] = true
				uniq.append(s)
			uniq.sort()
			by_sub2[sub_name3] = uniq
		_compiled[phase_name3] = by_sub2

	_compiled_any_phase.sort()
	_compiled_ready = true
	return Result.success()

func is_action_available(action_id: String, phase: String, sub_phase: String) -> bool:
	if not _compiled_ready:
		return false
	if _compiled_any_phase.has(action_id):
		return true
	if not _compiled.has(phase):
		return false
	var by_sub: Dictionary = _compiled[phase]
	if sub_phase.is_empty():
		for k in by_sub.keys():
			var list0 = by_sub[k]
			if list0 is Array and Array(list0).has(action_id):
				return true
		return false
	if not sub_phase.is_empty() and by_sub.has(sub_phase):
		var list: Array = by_sub[sub_phase]
		if list.has(action_id):
			return true
	if by_sub.has(""):
		var list2: Array = by_sub[""]
		return list2.has(action_id)
	return false

func get_available_action_ids(phase: String, sub_phase: String) -> Array[String]:
	if not _compiled_ready:
		return []

	var result: Array[String] = []
	result.append_array(_compiled_any_phase)
	if not _compiled.has(phase):
		return result

	var by_sub: Dictionary = _compiled[phase]
	var added := {}
	for a in result:
		added[a] = true

	if sub_phase.is_empty():
		for k in by_sub.keys():
			var list0 = by_sub[k]
			if not (list0 is Array):
				continue
			for a in Array(list0):
				if not (a is String):
					continue
				var aid0: String = str(a)
				if aid0.is_empty() or added.has(aid0):
					continue
				added[aid0] = true
				result.append(aid0)
		result.sort()
		return result

	if not sub_phase.is_empty() and by_sub.has(sub_phase):
		for a in Array(by_sub[sub_phase]):
			if not (a is String):
				continue
			var aid: String = str(a)
			if aid.is_empty() or added.has(aid):
				continue
			added[aid] = true
			result.append(aid)

	if by_sub.has(""):
		for a in Array(by_sub[""]):
			if not (a is String):
				continue
			var aid2: String = str(a)
			if aid2.is_empty() or added.has(aid2):
				continue
			added[aid2] = true
			result.append(aid2)

	result.sort()
	return result

func validate_command(state: GameState, command: Command) -> Result:
	var phase_name: String = str(state.phase)
	var sub_name: String = str(state.sub_phase)
	if is_action_available(command.action_id, phase_name, sub_name):
		return Result.success()
	return Result.failure("动作不可用: %s (phase=%s sub_phase=%s)" % [command.action_id, phase_name, sub_name])
