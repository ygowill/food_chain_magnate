# 模块系统 V2：ContentCatalogLoader（按启用模块加载内容）
class_name ContentCatalogV2Test
extends RefCounted

const ContentCatalogLoaderClass = preload("res://core/modules/v2/content_catalog_loader.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var base_dir := "res://core/tests/fixtures/modules_v2_valid"
	var read := ContentCatalogLoaderClass.load_for_modules(base_dir, ["alpha", "beta"])
	if not read.ok:
		return Result.failure("load_for_modules(valid) 失败: %s" % read.error)
	var catalog = read.value
	if catalog == null:
		return Result.failure("catalog 为空")

	if not catalog.employees.has("alpha_emp") or not catalog.employees.has("beta_emp"):
		return Result.failure("employees 应包含 alpha_emp/beta_emp，实际: %s" % str(catalog.employees.keys()))
	if str(catalog.employee_sources.get("alpha_emp", "")) != "alpha":
		return Result.failure("alpha_emp 来源错误: %s" % str(catalog.employee_sources))
	if str(catalog.employee_sources.get("beta_emp", "")) != "beta":
		return Result.failure("beta_emp 来源错误: %s" % str(catalog.employee_sources))

	if not catalog.milestones.has("beta_ms"):
		return Result.failure("milestones 应包含 beta_ms，实际: %s" % str(catalog.milestones.keys()))
	if str(catalog.milestone_sources.get("beta_ms", "")) != "beta":
		return Result.failure("beta_ms 来源错误: %s" % str(catalog.milestone_sources))

	var nonexist := ContentCatalogLoaderClass.load_for_modules(base_dir, ["no_such_module"])
	if nonexist.ok:
		return Result.failure("不存在的模块包应导致失败")

	var dup_dir := "res://core/tests/fixtures/modules_v2_content_invalid_duplicate"
	var dup := ContentCatalogLoaderClass.load_for_modules(dup_dir, ["a", "b"])
	if dup.ok:
		return Result.failure("重复 employee_id 应导致失败")

	return Result.success()

