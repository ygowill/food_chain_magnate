# ContentCatalog -> Registry 的通用装配辅助
# 用途：消除多个 *Registry.configure_from_catalog 中重复的“遍历字典 + 校验 + 写入 out”样板。
class_name CatalogRegistryHelpers
extends RefCounted

static func build_string_keyed_defs(
	items: Dictionary,
	expected_def_script,
	error_prefix: String,
	container_label: String,
	expected_type_label: String
) -> Result:
	if not (items is Dictionary):
		return Result.failure("%s: %s 类型错误（期望 Dictionary）" % [error_prefix, container_label])

	var out: Dictionary = {}
	for id_val in items.keys():
		if not (id_val is String):
			return Result.failure("%s: %s key 类型错误（期望 String）" % [error_prefix, container_label])
		var id: String = str(id_val)
		if id.is_empty():
			return Result.failure("%s: %s key 不能为空" % [error_prefix, container_label])

		var def_val = items.get(id, null)
		if def_val == null:
			return Result.failure("%s: %s[%s] 为空" % [error_prefix, container_label, id])
		if not (def_val is Object):
			return Result.failure("%s: %s[%s] 类型错误（期望 %s）" % [error_prefix, container_label, id, expected_type_label])
		var script = def_val.get_script()
		if script != expected_def_script:
			return Result.failure("%s: %s[%s] 类型错误（期望 %s）" % [error_prefix, container_label, id, expected_type_label])

		var def_id: String = str(def_val.id)
		if def_id != id:
			return Result.failure("%s: %s[%s].id 不一致: %s" % [error_prefix, container_label, id, def_id])

		out[id] = def_val

	return Result.success(out)
