class_name EffectIdsSegmentInvoker
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

static func invoke_effect_ids_by_segment(
	effect_registry,
	effect_ids: Array,
	segment: String,
	invoke_args: Array,
	prefix_label: String,
	effect_ids_label: String = "effect_ids"
) -> Result:
	var prefix := _prefix(prefix_label)
	if effect_registry == null:
		return Result.failure("%sEffectRegistry 未设置" % prefix)
	if segment.is_empty():
		return Result.failure("%seffect segment 不能为空" % prefix)
	if effect_ids == null:
		return Result.failure("%s%s 为空" % [prefix, effect_ids_label])
	if invoke_args == null or not (invoke_args is Array):
		return Result.failure("%sinvoke_args 类型错误（期望 Array）" % prefix)

	var warnings: Array[String] = []
	for i in range(effect_ids.size()):
		var effect_id_val = effect_ids[i]
		if not (effect_id_val is String):
			return Result.failure("%s%s[%d] 类型错误（期望 String）" % [prefix, effect_ids_label, i])
		var effect_id: String = str(effect_id_val)
		if effect_id.find(segment) == -1:
			continue
		var r = effect_registry.invoke(effect_id, invoke_args)
		if not r.ok:
			return r
		warnings.append_array(r.warnings)

	return Result.success().with_warnings(warnings)
