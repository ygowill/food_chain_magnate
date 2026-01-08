# RulesetV2：Employee/Milestone patch 应用逻辑下沉
class_name RulesetV2Patches
extends RefCounted

const EmployeeDefClass = preload("res://core/data/employee_def.gd")
const MilestoneDefClass = preload("res://core/data/milestone_def.gd")

static func register_employee_patch(ruleset, target_employee_id: String, patch: Dictionary, source_module_id: String = "") -> Result:
	if target_employee_id.is_empty():
		return Result.failure("RulesetV2: target_employee_id 不能为空")
	if patch == null or not (patch is Dictionary):
		return Result.failure("RulesetV2: patch 类型错误（期望 Dictionary）")
	ruleset.employee_patches.append({
		"target_id": target_employee_id,
		"patch": patch.duplicate(true),
		"source": source_module_id,
	})
	return Result.success()

static func register_milestone_patch(ruleset, target_milestone_id: String, patch: Dictionary, source_module_id: String = "") -> Result:
	if target_milestone_id.is_empty():
		return Result.failure("RulesetV2: target_milestone_id 不能为空")
	if patch == null or not (patch is Dictionary):
		return Result.failure("RulesetV2: milestone patch 类型错误（期望 Dictionary）")
	ruleset.milestone_patches.append({
		"target_id": target_milestone_id,
		"patch": patch.duplicate(true),
		"source": source_module_id,
	})
	return Result.success()

static func apply_employee_patches(ruleset, catalog) -> Result:
	if catalog == null:
		return Result.failure("RulesetV2: catalog 为空")
	if ruleset.employee_patches.is_empty():
		return Result.success()
	if not (catalog.employees is Dictionary):
		return Result.failure("RulesetV2: catalog.employees 类型错误（期望 Dictionary）")

	var warnings: Array[String] = []
	for i in range(ruleset.employee_patches.size()):
		var item_val = ruleset.employee_patches[i]
		if not (item_val is Dictionary):
			return Result.failure("RulesetV2: employee_patches[%d] 类型错误（期望 Dictionary）" % i)
		var item: Dictionary = item_val
		var target_val = item.get("target_id", null)
		if not (target_val is String):
			return Result.failure("RulesetV2: employee_patches[%d].target_id 类型错误（期望 String）" % i)
		var target_id: String = str(target_val)
		if target_id.is_empty():
			return Result.failure("RulesetV2: employee_patches[%d].target_id 不能为空" % i)
		if not catalog.employees.has(target_id):
			return Result.failure("RulesetV2: employee patch 目标员工不存在: %s" % target_id)

		var def_val = catalog.employees.get(target_id, null)
		if def_val == null or not (def_val is EmployeeDefClass):
			return Result.failure("RulesetV2: catalog.employees[%s] 类型错误（期望 EmployeeDef）" % target_id)
		var def: EmployeeDef = def_val

		var patch_val = item.get("patch", null)
		if not (patch_val is Dictionary):
			return Result.failure("RulesetV2: employee_patches[%d].patch 类型错误（期望 Dictionary）" % i)
		var patch_dict: Dictionary = patch_val

		var apply_r := _apply_employee_patch(def, patch_dict, target_id)
		if not apply_r.ok:
			return apply_r
		warnings.append_array(apply_r.warnings)

	return Result.success().with_warnings(warnings)

static func apply_milestone_patches(ruleset, catalog) -> Result:
	if catalog == null:
		return Result.failure("RulesetV2: catalog 为空")
	if ruleset.milestone_patches.is_empty():
		return Result.success()
	if not (catalog.milestones is Dictionary):
		return Result.failure("RulesetV2: catalog.milestones 类型错误（期望 Dictionary）")

	var warnings: Array[String] = []
	for i in range(ruleset.milestone_patches.size()):
		var item_val = ruleset.milestone_patches[i]
		if not (item_val is Dictionary):
			return Result.failure("RulesetV2: milestone_patches[%d] 类型错误（期望 Dictionary）" % i)
		var item: Dictionary = item_val
		var target_val = item.get("target_id", null)
		if not (target_val is String):
			return Result.failure("RulesetV2: milestone_patches[%d].target_id 类型错误（期望 String）" % i)
		var target_id: String = str(target_val)
		if target_id.is_empty():
			return Result.failure("RulesetV2: milestone_patches[%d].target_id 不能为空" % i)
		if not catalog.milestones.has(target_id):
			return Result.failure("RulesetV2: milestone patch 目标里程碑不存在: %s" % target_id)

		var def_val = catalog.milestones.get(target_id, null)
		if def_val == null or not (def_val is MilestoneDefClass):
			return Result.failure("RulesetV2: catalog.milestones[%s] 类型错误（期望 MilestoneDef）" % target_id)
		var def: MilestoneDef = def_val

		var patch_val = item.get("patch", null)
		if not (patch_val is Dictionary):
			return Result.failure("RulesetV2: milestone_patches[%d].patch 类型错误（期望 Dictionary）" % i)
		var patch_dict: Dictionary = patch_val

		var apply_r := _apply_milestone_patch(def, patch_dict, target_id)
		if not apply_r.ok:
			return apply_r
		warnings.append_array(apply_r.warnings)

	return Result.success().with_warnings(warnings)

static func _apply_employee_patch(def: EmployeeDef, patch: Dictionary, target_id: String) -> Result:
	assert(def != null, "RulesetV2Patches._apply_employee_patch: def 为空")
	assert(not target_id.is_empty(), "RulesetV2Patches._apply_employee_patch: target_id 不能为空")

	# 受控 patch：当前仅支持向数组字段追加（去重）
	# - add_train_to: Array[String]
	if patch.has("add_train_to"):
		var add_val = patch.get("add_train_to", null)
		if not (add_val is Array):
			return Result.failure("RulesetV2: employee patch %s.add_train_to 类型错误（期望 Array[String]）" % target_id)
		var add_any: Array = add_val
		for j in range(add_any.size()):
			var v = add_any[j]
			if not (v is String):
				return Result.failure("RulesetV2: employee patch %s.add_train_to[%d] 类型错误（期望 String）" % [target_id, j])
			var to_id: String = str(v)
			if to_id.is_empty():
				return Result.failure("RulesetV2: employee patch %s.add_train_to[%d] 不能为空" % [target_id, j])
			if not def.train_to.has(to_id):
				def.train_to.append(to_id)

	return Result.success()

static func _apply_milestone_patch(def: MilestoneDef, patch: Dictionary, target_id: String) -> Result:
	assert(def != null, "RulesetV2Patches._apply_milestone_patch: def 为空")
	assert(not target_id.is_empty(), "RulesetV2Patches._apply_milestone_patch: target_id 不能为空")

	# 受控 patch：
	# - set_expires_at: int | null
	if patch.has("set_expires_at"):
		var v = patch.get("set_expires_at", null)
		if v == null:
			def.expires_at = null
		else:
			if not (v is int):
				return Result.failure("RulesetV2: milestone patch %s.set_expires_at 类型错误（期望 int|null）" % target_id)
			var exp: int = int(v)
			if exp < 0:
				return Result.failure("RulesetV2: milestone patch %s.set_expires_at 必须 >= 0，实际: %d" % [target_id, exp])
			def.expires_at = exp

	return Result.success()

