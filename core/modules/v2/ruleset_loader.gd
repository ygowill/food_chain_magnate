# 模块系统 V2：从启用模块集合加载 rules/entry.gd 并构建 Ruleset
class_name RulesetLoaderV2
extends RefCounted

const RulesetBuilderV2Class = preload("res://core/modules/v2/ruleset_builder.gd")

static func build_for_plan(manifests: Dictionary, module_plan: Array[String]) -> Result:
	var builder = RulesetBuilderV2Class.new()
	var warnings: Array[String] = []

	for i in range(module_plan.size()):
		var mid_val = module_plan[i]
		if not (mid_val is String):
			return Result.failure("RulesetLoaderV2: module_plan[%d] 类型错误（期望 String）" % i)
		var module_id: String = str(mid_val)
		if module_id.is_empty():
			return Result.failure("RulesetLoaderV2: module_plan[%d] 不能为空" % i)

		var manifest = manifests.get(module_id, null)
		if manifest == null:
			return Result.failure("RulesetLoaderV2: 缺少 manifest: %s" % module_id)

		var entry_path: String = str(manifest.entry_script)
		if entry_path.is_empty():
			continue

		var script = load(entry_path)
		if script == null:
			return Result.failure("RulesetLoaderV2: 无法加载 entry_script: %s (%s)" % [module_id, entry_path])
		var inst = script.new()
		if inst == null:
			return Result.failure("RulesetLoaderV2: 无法实例化 entry_script: %s (%s)" % [module_id, entry_path])
		builder.ruleset.retain_entry_instance(inst)
		if not inst.has_method("register"):
			return Result.failure("RulesetLoaderV2: entry_script 缺少 register(registrar): %s (%s)" % [module_id, entry_path])

		var registrar = builder.for_module(module_id)
		var r = inst.call("register", registrar)
		if r is Result:
			var rr: Result = r
			if not rr.ok:
				return Result.failure("RulesetLoaderV2: 模块 rules 注册失败: %s (%s)" % [module_id, rr.error])
			warnings.append_array(rr.warnings)
		elif r != null:
			return Result.failure("RulesetLoaderV2: entry_script.register 返回值类型错误（期望 Result 或 null）: %s (%s)" % [module_id, entry_path])

	return Result.success(builder.ruleset).with_warnings(warnings)
