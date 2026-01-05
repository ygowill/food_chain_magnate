# Effect 注册表（模块化 effect handlers，Fail Fast）
# 说明：
# - effect_id 必须为 `module_id:...`（至少包含一个 ':'）
# - 1 个 effect_id 只能注册 1 个 handler；重复注册直接失败
class_name EffectRegistry
extends RefCounted

var _handlers: Dictionary = {}  # effect_id -> {callback, source}

func reset() -> void:
	_handlers.clear()

func has_handler(effect_id: String) -> bool:
	return _handlers.has(effect_id)

func get_registered_effect_ids() -> Array[String]:
	var out: Array[String] = []
	for k in _handlers.keys():
		if k is String:
			out.append(str(k))
	out.sort()
	return out

func register_effect(effect_id: String, callback: Callable, source_module_id: String = "") -> Result:
	if effect_id.is_empty():
		return Result.failure("EffectRegistry: effect_id 不能为空")
	if effect_id.find(":") <= 0:
		return Result.failure("EffectRegistry: effect_id 必须为 module_id:...，实际: %s" % effect_id)
	if not callback.is_valid():
		return Result.failure("EffectRegistry: handler callback 无效: %s" % effect_id)

	if not source_module_id.is_empty():
		var prefix := "%s:" % source_module_id
		if not effect_id.begins_with(prefix):
			return Result.failure("EffectRegistry: effect_id 必须以 source module_id 作为前缀: %s (expected_prefix=%s)" % [effect_id, prefix])

	if _handlers.has(effect_id):
		var prev: Dictionary = _handlers[effect_id]
		var prev_src: String = str(prev.get("source", ""))
		return Result.failure("EffectRegistry: effect_id 重复注册: %s (prev=%s, new=%s)" % [effect_id, prev_src, source_module_id])

	_handlers[effect_id] = {
		"callback": callback,
		"source": source_module_id,
	}
	return Result.success()

func invoke(effect_id: String, args: Array = []) -> Result:
	if not _handlers.has(effect_id):
		return Result.failure("EffectRegistry: 缺少 handler: %s" % effect_id)
	var meta: Dictionary = _handlers[effect_id]
	var cb: Callable = meta.get("callback", Callable())
	var src: String = str(meta.get("source", ""))
	if not cb.is_valid():
		return Result.failure("EffectRegistry: handler callback 无效: %s (source=%s)" % [effect_id, src])

	var r = cb.callv(args)
	if r is Result:
		var rr: Result = r
		if not rr.ok:
			return Result.failure("EffectRegistry: handler 失败: %s (source=%s): %s" % [effect_id, src, rr.error])
		return Result.success(rr.value).with_warnings(rr.warnings)
	if r == null:
		return Result.success()
	return Result.failure("EffectRegistry: handler 返回值类型错误（期望 Result 或 null）: %s (source=%s)" % [effect_id, src])

