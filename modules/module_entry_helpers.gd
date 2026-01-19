# 模块入口辅助
# 用途：消除多个 modules/*/rules/entry.gd 中重复的 “parts 组装 + 逐个 register + if not r.ok” 样板。
class_name ModuleEntryHelpers
extends RefCounted

static func register_parts(registrar, parts: Array) -> Result:
	if not (parts is Array):
		return Result.failure("ModuleEntryHelpers.register_parts: parts 类型错误（期望 Array）")

	for i in range(parts.size()):
		var part = parts[i]
		if part == null or not (part is Object) or not part.has_method("register"):
			return Result.failure("ModuleEntryHelpers.register_parts: parts[%d] 缺少 register()" % i)
		if registrar != null and registrar is Object and registrar.has_method("retain_entry_instance"):
			registrar.retain_entry_instance(part)
		var r: Result = part.register(registrar)
		if not r.ok:
			return r

	return Result.success()
