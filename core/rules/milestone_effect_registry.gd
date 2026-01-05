# MilestoneEffect 注册表（effects.type -> handler，Fail Fast）
# 说明：
# - effect_type 为里程碑 effects[*].type（例如 gain_card / ban_card / multi_trainer_on_one）
# - 1 个 effect_type 只能注册 1 个 handler；重复注册直接失败
class_name MilestoneEffectRegistry
extends RefCounted

static var _current = null

var _handlers: Dictionary = {}  # effect_type -> {callback, source}

static func set_current(registry) -> void:
	_current = registry

static func get_current():
	return _current

static func reset_current() -> void:
	_current = null

func reset() -> void:
	_handlers.clear()

func has_handler(effect_type: String) -> bool:
	return _handlers.has(effect_type)

func get_registered_effect_types() -> Array[String]:
	var out: Array[String] = []
	for k in _handlers.keys():
		if k is String:
			out.append(str(k))
	out.sort()
	return out

func register_effect_type(effect_type: String, callback: Callable, source_module_id: String = "") -> Result:
	if effect_type.is_empty():
		return Result.failure("MilestoneEffectRegistry: effect_type 不能为空")
	if not callback.is_valid():
		return Result.failure("MilestoneEffectRegistry: handler callback 无效: %s" % effect_type)

	if _handlers.has(effect_type):
		var prev: Dictionary = _handlers[effect_type]
		var prev_src: String = str(prev.get("source", ""))
		return Result.failure("MilestoneEffectRegistry: effect_type 重复注册: %s (prev=%s, new=%s)" % [effect_type, prev_src, source_module_id])

	_handlers[effect_type] = {
		"callback": callback,
		"source": source_module_id,
	}
	return Result.success()

func invoke(effect_type: String, args: Array = []) -> Result:
	if not _handlers.has(effect_type):
		return Result.failure("MilestoneEffectRegistry: 缺少 handler: %s" % effect_type)
	var meta: Dictionary = _handlers[effect_type]
	var cb: Callable = meta.get("callback", Callable())
	var src: String = str(meta.get("source", ""))
	if not cb.is_valid():
		return Result.failure("MilestoneEffectRegistry: handler callback 无效: %s (source=%s)" % [effect_type, src])

	var r = cb.callv(args)
	if r is Result:
		var rr: Result = r
		if not rr.ok:
			return Result.failure("MilestoneEffectRegistry: handler 失败: %s (source=%s): %s" % [effect_type, src, rr.error])
		return Result.success(rr.value).with_warnings(rr.warnings)
	if r == null:
		return Result.success()
	return Result.failure("MilestoneEffectRegistry: handler 返回值类型错误（期望 Result 或 null）: %s (source=%s)" % [effect_type, src])

