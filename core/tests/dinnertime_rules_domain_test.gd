# 晚餐领域 helper 回归测试
class_name DinnertimeRulesDomainTest
extends RefCounted

const DinnertimeInventoryClass = preload("res://modules/base_rules/rules/phase/dinnertime/dinnertime_inventory.gd")
const DinnertimeEffectsClass = preload("res://modules/base_rules/rules/phase/dinnertime/dinnertime_effects.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	if player_count != 2:
		return Result.failure("本测试固定为 2 人局（实际: %d）" % player_count)

	var r := _test_required_has_non_drink_food_returns_false_for_drink_only(seed_val)
	if not r.ok:
		return r
	r = _test_required_has_non_drink_food_rejects_unknown_product(seed_val)
	if not r.ok:
		return r
	r = _test_apply_employee_effects_fails_fast_on_unknown_employee()
	if not r.ok:
		return r
	r = _test_apply_milestone_effects_fails_fast_on_unknown_milestone()
	if not r.ok:
		return r

	return Result.success({"cases": 4})

static func _init_base_engine(seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(2, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	return Result.success(engine)

static func _test_required_has_non_drink_food_returns_false_for_drink_only(seed_val: int) -> Result:
	var engine_read := _init_base_engine(seed_val)
	if not engine_read.ok:
		return engine_read
	var result := DinnertimeInventoryClass.required_has_non_drink_food({"soda": 1, "lemonade": 2})
	if not result.ok:
		return Result.failure("drink-only required 检查失败: %s" % result.error)
	if bool(result.value):
		return Result.failure("纯饮品需求不应被视为 non-drink food")
	return Result.success()

static func _test_required_has_non_drink_food_rejects_unknown_product(seed_val: int) -> Result:
	var engine_read := _init_base_engine(seed_val)
	if not engine_read.ok:
		return engine_read
	var result := DinnertimeInventoryClass.required_has_non_drink_food({"ghost_product": 1})
	if result.ok:
		return Result.failure("未知产品时应失败")
	var err := str(result.error)
	if err.find("未知产品定义: ghost_product") < 0:
		return Result.failure("错误信息应包含未知产品定义，实际: %s" % err)
	return Result.success()

static func _test_apply_employee_effects_fails_fast_on_unknown_employee() -> Result:
	var state := GameState.new()
	state.players = [{"employees": ["ghost_employee"]}]
	var result := DinnertimeEffectsClass.apply_employee_effects_by_segment(
		state,
		0,
		RefCounted.new(),
		":dinnertime:tips:",
		{}
	)
	if result.ok:
		return Result.failure("未知员工时应失败")
	var err := str(result.error)
	if err.find("未知员工定义: ghost_employee") < 0:
		return Result.failure("错误信息应包含 ghost_employee，实际: %s" % err)
	return Result.success()

static func _test_apply_milestone_effects_fails_fast_on_unknown_milestone() -> Result:
	var state := GameState.new()
	state.players = [{"milestones": ["ghost_milestone"]}]
	var result := DinnertimeEffectsClass.apply_milestone_effects_by_segment(
		state,
		0,
		RefCounted.new(),
		":dinnertime:tips:",
		{}
	)
	if result.ok:
		return Result.failure("未知里程碑时应失败")
	var err := str(result.error)
	if err.find("未知里程碑定义: ghost_milestone") < 0:
		return Result.failure("错误信息应包含 ghost_milestone，实际: %s" % err)
	return Result.success()
