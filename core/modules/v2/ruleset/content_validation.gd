# RulesetV2：将 content validation 逻辑下沉
class_name RulesetV2ContentValidation
extends RefCounted

const EmployeeDefClass = preload("res://core/data/employee_def.gd")
const MilestoneDefClass = preload("res://core/data/milestone_def.gd")

static func validate_effect_handlers(ruleset, catalog) -> Result:
	if catalog == null:
		return Result.failure("RulesetV2: catalog 为空")
	if not (catalog.employees is Dictionary):
		return Result.failure("RulesetV2: catalog.employees 类型错误（期望 Dictionary）")
	if not (catalog.employee_sources is Dictionary):
		return Result.failure("RulesetV2: catalog.employee_sources 类型错误（期望 Dictionary）")
	if not (catalog.milestones is Dictionary):
		return Result.failure("RulesetV2: catalog.milestones 类型错误（期望 Dictionary）")
	if not (catalog.milestone_sources is Dictionary):
		return Result.failure("RulesetV2: catalog.milestone_sources 类型错误（期望 Dictionary）")

	var missing: Dictionary = {}  # effect_id -> Array[String] refs

	for emp_id_val in catalog.employees.keys():
		if not (emp_id_val is String):
			return Result.failure("RulesetV2: catalog.employees key 类型错误（期望 String）")
		var emp_id: String = str(emp_id_val)
		var def_val = catalog.employees.get(emp_id, null)
		if def_val == null:
			return Result.failure("RulesetV2: catalog.employees[%s] 为空" % emp_id)
		if not (def_val is EmployeeDefClass):
			return Result.failure("RulesetV2: catalog.employees[%s] 类型错误（期望 EmployeeDef）" % emp_id)
		var def: EmployeeDef = def_val
		for i in range(def.effect_ids.size()):
			var eid: String = def.effect_ids[i]
			if ruleset.effect_registry.has_handler(eid):
				continue
			if not missing.has(eid):
				missing[eid] = []
			var src: String = str(catalog.employee_sources.get(emp_id, ""))
			var refs: Array = missing[eid]
			refs.append("employee:%s (module:%s)" % [emp_id, src])
			missing[eid] = refs

	for ms_id_val in catalog.milestones.keys():
		if not (ms_id_val is String):
			return Result.failure("RulesetV2: catalog.milestones key 类型错误（期望 String）")
		var ms_id: String = str(ms_id_val)
		var def_val = catalog.milestones.get(ms_id, null)
		if def_val == null:
			return Result.failure("RulesetV2: catalog.milestones[%s] 为空" % ms_id)
		if not (def_val is MilestoneDefClass):
			return Result.failure("RulesetV2: catalog.milestones[%s] 类型错误（期望 MilestoneDef）" % ms_id)
		var def: MilestoneDef = def_val
		for i in range(def.effect_ids.size()):
			var eid: String = def.effect_ids[i]
			if ruleset.effect_registry.has_handler(eid):
				continue
			if not missing.has(eid):
				missing[eid] = []
			var src: String = str(catalog.milestone_sources.get(ms_id, ""))
			var refs: Array = missing[eid]
			refs.append("milestone:%s (module:%s)" % [ms_id, src])
			missing[eid] = refs

	if missing.is_empty():
		return Result.success()

	var effect_ids: Array[String] = []
	for k in missing.keys():
		if k is String:
			effect_ids.append(str(k))
	effect_ids.sort()

	var parts: Array[String] = []
	for eid in effect_ids:
		var refs: Array = missing.get(eid, [])
		refs.sort()
		var refs_str := ", ".join(Array(refs, TYPE_STRING, "", null))
		parts.append("%s <- %s" % [eid, refs_str])

	return Result.failure("缺少 effect handler: %s" % " | ".join(parts))

static func validate_milestone_effect_handlers(ruleset, catalog) -> Result:
	if catalog == null:
		return Result.failure("RulesetV2: catalog 为空")
	if not (catalog.milestones is Dictionary):
		return Result.failure("RulesetV2: catalog.milestones 类型错误（期望 Dictionary）")
	if not (catalog.milestone_sources is Dictionary):
		return Result.failure("RulesetV2: catalog.milestone_sources 类型错误（期望 Dictionary）")

	var missing: Dictionary = {}  # effect_type -> Array[String] refs

	for ms_id_val in catalog.milestones.keys():
		if not (ms_id_val is String):
			return Result.failure("RulesetV2: catalog.milestones key 类型错误（期望 String）")
		var ms_id: String = str(ms_id_val)
		var def_val = catalog.milestones.get(ms_id, null)
		if def_val == null:
			return Result.failure("RulesetV2: catalog.milestones[%s] 为空" % ms_id)
		if not (def_val is MilestoneDefClass):
			return Result.failure("RulesetV2: catalog.milestones[%s] 类型错误（期望 MilestoneDef）" % ms_id)
		var def: MilestoneDef = def_val

		for e_i in range(def.effects.size()):
			var eff_val = def.effects[e_i]
			if not (eff_val is Dictionary):
				return Result.failure("RulesetV2: %s.effects[%d] 类型错误（期望 Dictionary）" % [ms_id, e_i])
			var eff: Dictionary = eff_val
			var type_val = eff.get("type", null)
			if not (type_val is String):
				return Result.failure("RulesetV2: %s.effects[%d].type 类型错误（期望 String）" % [ms_id, e_i])
			var t: String = str(type_val)
			if t.is_empty():
				return Result.failure("RulesetV2: %s.effects[%d].type 不能为空" % [ms_id, e_i])
			if ruleset.milestone_effect_registry.has_handler(t):
				continue

			if not missing.has(t):
				missing[t] = []
			var src: String = str(catalog.milestone_sources.get(ms_id, ""))
			var refs: Array = missing[t]
			refs.append("%s.effects[%d] (module:%s)" % [ms_id, e_i, src])
			missing[t] = refs

	if missing.is_empty():
		return Result.success()

	var types: Array[String] = []
	for k in missing.keys():
		if k is String:
			types.append(str(k))
	types.sort()

	var parts: Array[String] = []
	for t in types:
		var refs: Array = missing.get(t, [])
		refs.sort()
		var refs_str := ", ".join(Array(refs, TYPE_STRING, "", null))
		parts.append("%s <- %s" % [t, refs_str])

	return Result.failure("缺少 milestone effect handler: %s" % " | ".join(parts))
