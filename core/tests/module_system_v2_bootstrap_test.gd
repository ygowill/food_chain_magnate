# 模块系统 V2：与 GameEngine.initialize 的装配集成测试（Strict Mode）
class_name ModuleSystemV2BootstrapTest
extends RefCounted

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	var engine := GameEngine.new()

	var init := engine.initialize(
		player_count,
		seed_val,
		["beta"],  # v2 requested modules（应自动包含依赖 alpha）
		"res://core/tests/fixtures/modules_v2_valid"
	)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)

	var plan := engine.get_module_plan_v2()
	if plan != ["base_rules", "alpha", "beta"]:
		return Result.failure("module_plan_v2 不符合预期: %s" % str(plan))

	var catalog = engine.get_content_catalog_v2()
	if catalog == null:
		return Result.failure("content_catalog_v2 为空")

	if not (catalog.employees is Dictionary):
		return Result.failure("catalog.employees 类型错误（期望 Dictionary）")
	if not catalog.employees.has("alpha_emp") or not catalog.employees.has("beta_emp"):
		return Result.failure("catalog.employees 缺少 alpha_emp/beta_emp，实际: %s" % str(catalog.employees.keys()))

	if not (catalog.milestones is Dictionary):
		return Result.failure("catalog.milestones 类型错误（期望 Dictionary）")
	if not catalog.milestones.has("beta_ms"):
		return Result.failure("catalog.milestones 缺少 beta_ms，实际: %s" % str(catalog.milestones.keys()))

	var state := engine.get_state()
	if state == null:
		return Result.failure("state 为空")
	if not (state.modules is Array):
		return Result.failure("state.modules 类型错误（期望 Array[String]）")
	if state.modules != plan:
		return Result.failure("state.modules 应等于 module_plan_v2，实际: %s" % str(state.modules))

	return Result.success()
