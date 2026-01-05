# 模块系统 V2：ModulePlanBuilder（依赖闭包/冲突检测/确定性排序）
class_name ModulePlanBuilderV2Test
extends RefCounted

const ModuleManifestClass = preload("res://core/modules/v2/module_manifest.gd")
const ModulePlanBuilderClass = preload("res://core/modules/v2/module_plan_builder.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var alpha_read := ModuleManifestClass.from_dict({
		"schema_version": 1,
		"id": "alpha",
		"version": "1.0.0",
		"priority": 100,
		"dependencies": [],
		"conflicts": [],
		"entry_script": ""
	})
	if not alpha_read.ok:
		return Result.failure("alpha manifest 解析失败: %s" % alpha_read.error)

	var beta_read := ModuleManifestClass.from_dict({
		"schema_version": 1,
		"id": "beta",
		"version": "1.0.0",
		"priority": 200,
		"dependencies": ["alpha"],
		"conflicts": [],
		"entry_script": ""
	})
	if not beta_read.ok:
		return Result.failure("beta manifest 解析失败: %s" % beta_read.error)

	var manifests := {
		"alpha": alpha_read.value,
		"beta": beta_read.value,
	}

	var plan_read := ModulePlanBuilderClass.build_plan(manifests, ["beta"])
	if not plan_read.ok:
		return Result.failure("build_plan 失败: %s" % plan_read.error)
	var order: Array = plan_read.value
	if order.size() != 2 or order[0] != "alpha" or order[1] != "beta":
		return Result.failure("依赖闭包/排序错误: %s" % str(order))

	var conflict_a_read := ModuleManifestClass.from_dict({
		"schema_version": 1,
		"id": "a",
		"version": "1.0.0",
		"dependencies": [],
		"conflicts": ["b"],
		"entry_script": ""
	})
	var conflict_b_read := ModuleManifestClass.from_dict({
		"schema_version": 1,
		"id": "b",
		"version": "1.0.0",
		"dependencies": [],
		"conflicts": [],
		"entry_script": ""
	})
	if not conflict_a_read.ok or not conflict_b_read.ok:
		return Result.failure("conflict manifests 解析失败")
	var conflict_manifests := {
		"a": conflict_a_read.value,
		"b": conflict_b_read.value,
	}
	var conflict_plan := ModulePlanBuilderClass.build_plan(conflict_manifests, ["a", "b"])
	if conflict_plan.ok:
		return Result.failure("存在冲突时应失败")

	var cycle_a_read := ModuleManifestClass.from_dict({
		"schema_version": 1,
		"id": "a",
		"version": "1.0.0",
		"dependencies": ["b"],
		"conflicts": [],
		"entry_script": ""
	})
	var cycle_b_read := ModuleManifestClass.from_dict({
		"schema_version": 1,
		"id": "b",
		"version": "1.0.0",
		"dependencies": ["a"],
		"conflicts": [],
		"entry_script": ""
	})
	if not cycle_a_read.ok or not cycle_b_read.ok:
		return Result.failure("cycle manifests 解析失败")
	var cycle_manifests := {
		"a": cycle_a_read.value,
		"b": cycle_b_read.value,
	}
	var cycle_plan := ModulePlanBuilderClass.build_plan(cycle_manifests, ["a"])
	if cycle_plan.ok:
		return Result.failure("存在依赖环时应失败")

	var missing_dep_read := ModuleManifestClass.from_dict({
		"schema_version": 1,
		"id": "x",
		"version": "1.0.0",
		"dependencies": ["missing"],
		"conflicts": [],
		"entry_script": ""
	})
	if not missing_dep_read.ok:
		return Result.failure("missing_dep manifest 解析失败")
	var missing_dep_manifests := {
		"x": missing_dep_read.value,
	}
	var missing_dep_plan := ModulePlanBuilderClass.build_plan(missing_dep_manifests, ["x"])
	if missing_dep_plan.ok:
		return Result.failure("未知依赖时应失败")

	var dup_plan := ModulePlanBuilderClass.build_plan(manifests, ["alpha", "alpha"])
	if dup_plan.ok:
		return Result.failure("重复 requested_module_ids 时应失败")

	return Result.success()

