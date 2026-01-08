# RulesetV2：动作/营销类型注册逻辑下沉
class_name RulesetV2ActionRegistration
extends RefCounted

static func register_action_executor(ruleset, executor, source_module_id: String = "") -> Result:
	# 允许模块注册自定义 ActionExecutor（Strict Mode：重复 action_id 直接失败）。
	if executor == null:
		return Result.failure("RulesetV2: executor 为空")
	if not (executor is ActionExecutor):
		return Result.failure("RulesetV2: executor 类型错误（期望 ActionExecutor）")
	if executor.action_id.is_empty():
		return Result.failure("RulesetV2: executor.action_id 不能为空 (%s)" % source_module_id)
	for existing in ruleset.action_executors:
		if existing is ActionExecutor and str(existing.action_id) == str(executor.action_id):
			return Result.failure("RulesetV2: action executor 重复注册: %s (module:%s)" % [executor.action_id, source_module_id])
	ruleset.action_executors.append(executor)
	return Result.success()

static func register_marketing_type(ruleset, type_id: String, config: Dictionary, range_handler: Callable, source_module_id: String = "") -> Result:
	if type_id.is_empty():
		return Result.failure("RulesetV2: marketing type_id 不能为空")
	if config == null or not (config is Dictionary):
		return Result.failure("RulesetV2: marketing config 类型错误（期望 Dictionary）")
	if not range_handler.is_valid():
		return Result.failure("RulesetV2: marketing range_handler 无效: %s" % type_id)

	for item_val in ruleset.marketing_type_registrations:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if str(item.get("type_id", "")) == type_id:
			return Result.failure("RulesetV2: marketing type 重复注册: %s (module:%s)" % [type_id, source_module_id])

	var requires_edge := false
	if config.has("requires_edge"):
		var v = config.get("requires_edge", false)
		if not (v is bool):
			return Result.failure("RulesetV2: marketing config.requires_edge 类型错误（期望 bool）: %s" % type_id)
		requires_edge = bool(v)

	ruleset.marketing_type_registrations.append({
		"type_id": type_id,
		"requires_edge": requires_edge,
		"range_handler": range_handler,
		"source": source_module_id,
	})
	return Result.success()

static func register_action_validator(
	ruleset,
	action_id: String,
	validator_id: String,
	callback: Callable,
	priority: int = 100,
	source_module_id: String = ""
) -> Result:
	if action_id.is_empty():
		return Result.failure("RulesetV2: action_id 不能为空")
	if validator_id.is_empty():
		return Result.failure("RulesetV2: validator_id 不能为空")
	if not callback.is_valid():
		return Result.failure("RulesetV2: action validator callback 无效")
	for item_val in ruleset.action_validators:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if str(item.get("action_id", "")) == action_id and str(item.get("validator_id", "")) == validator_id:
			return Result.failure("RulesetV2: action validator 重复注册: %s/%s (module:%s)" % [action_id, validator_id, source_module_id])
	ruleset.action_validators.append({
		"action_id": action_id,
		"validator_id": validator_id,
		"callback": callback,
		"priority": priority,
		"source": source_module_id,
	})
	return Result.success()

static func register_global_action_validator(
	ruleset,
	validator_id: String,
	callback: Callable,
	priority: int = 100,
	source_module_id: String = ""
) -> Result:
	if validator_id.is_empty():
		return Result.failure("RulesetV2: validator_id 不能为空")
	if not callback.is_valid():
		return Result.failure("RulesetV2: global action validator callback 无效")
	for item_val in ruleset.global_action_validators:
		if not (item_val is Dictionary):
			continue
		var item: Dictionary = item_val
		if str(item.get("validator_id", "")) == validator_id:
			return Result.failure("RulesetV2: global action validator 重复注册: %s (module:%s)" % [validator_id, source_module_id])
	ruleset.global_action_validators.append({
		"validator_id": validator_id,
		"callback": callback,
		"priority": priority,
		"source": source_module_id,
	})
	return Result.success()

static func register_action_availability_override(
	ruleset,
	action_id: String,
	points: Array,
	priority: int = 100,
	source_module_id: String = ""
) -> Result:
	if action_id.is_empty():
		return Result.failure("RulesetV2: action_availability_override action_id 不能为空")
	if points == null or not (points is Array):
		return Result.failure("RulesetV2: action_availability_override points 类型错误（期望 Array[Dictionary]）")

	for i in range(points.size()):
		var pv = points[i]
		if not (pv is Dictionary):
			return Result.failure("RulesetV2: action_availability_override points[%d] 类型错误（期望 Dictionary）" % i)
		var p: Dictionary = pv
		var phase_name: String = str(p.get("phase", ""))
		if phase_name.is_empty():
			return Result.failure("RulesetV2: action_availability_override points[%d].phase 不能为空" % i)
		if not p.has("sub_phase"):
			return Result.failure("RulesetV2: action_availability_override points[%d] 缺少字段: sub_phase" % i)
		var sub_name: String = str(p.get("sub_phase", ""))
		if sub_name.is_empty() and str(p.get("sub_phase", "")) != "":
			return Result.failure("RulesetV2: action_availability_override points[%d].sub_phase 类型错误（期望 String）" % i)

	ruleset.action_availability_overrides.append({
		"action_id": action_id,
		"points": points.duplicate(true),
		"priority": int(priority),
		"source": source_module_id,
	})
	ruleset.action_availability_overrides.sort_custom(func(a, b) -> bool:
		var pa: int = int(a.get("priority", 100))
		var pb: int = int(b.get("priority", 100))
		if pa != pb:
			return pa > pb
		var sa: String = str(a.get("source", ""))
		var sb: String = str(b.get("source", ""))
		return sa < sb
	)
	return Result.success()

