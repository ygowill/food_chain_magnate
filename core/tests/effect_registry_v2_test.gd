# 模块系统 V2：EffectRegistry（handler 注册 + content 引用校验 + 每出现一次调用一次）
class_name EffectRegistryV2Test
extends RefCounted

const EffectRegistryClass = preload("res://core/rules/effect_registry.gd")
const DinnertimeSettlementClass = preload("res://core/rules/phase/dinnertime_settlement.gd")
const EmployeeRegistryClass = preload("res://core/data/employee_registry.gd")
const EmployeeDefClass = preload("res://core/data/employee_def.gd")
const ContentCatalogClass = preload("res://core/modules/v2/content_catalog.gd")

const FIXTURES_BASE_DIR := "res://core/tests/fixtures/modules_v2_effects_validation"

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	var r1 := _test_init_fails_when_effect_handler_missing(player_count, seed_val)
	if not r1.ok:
		return r1

	var r2 := _test_init_ok_when_effect_handler_present(player_count, seed_val)
	if not r2.ok:
		return r2

	var r3 := _test_init_fails_on_bad_effect_id_format(player_count, seed_val)
	if not r3.ok:
		return r3

	var r4 := _test_employee_effects_called_per_occurrence()
	if not r4.ok:
		return r4

	return Result.success()

static func _test_init_fails_when_effect_handler_missing(player_count: int, seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(
		player_count,
		seed_val,
		["missing_effects"],
		FIXTURES_BASE_DIR
	)
	if init.ok:
		return Result.failure("缺少 effect handler 时应初始化失败")
	if init.error.find("缺少 effect handler") == -1:
		return Result.failure("错误信息应包含“缺少 effect handler”，实际: %s" % init.error)
	if init.error.find("missing_effects:test_effect") == -1:
		return Result.failure("错误信息应包含缺失的 effect_id，实际: %s" % init.error)
	return Result.success()

static func _test_init_ok_when_effect_handler_present(player_count: int, seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(
		player_count,
		seed_val,
		["good_effects"],
		FIXTURES_BASE_DIR
	)
	if not init.ok:
		return Result.failure("应初始化成功，实际失败: %s" % init.error)
	return Result.success()

static func _test_init_fails_on_bad_effect_id_format(player_count: int, seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(
		player_count,
		seed_val,
		["bad_effect_id"],
		FIXTURES_BASE_DIR
	)
	if init.ok:
		return Result.failure("effect_id 不符合 module_id:... 时应初始化失败")
	if init.error.find("effect_ids") == -1:
		return Result.failure("错误信息应包含 effect_ids 解析失败位置，实际: %s" % init.error)
	return Result.success()

class _CounterHandler:
	extends RefCounted

	func on_tiebreaker(_state: GameState, _player_id: int, ctx: Dictionary) -> Result:
		if not ctx.has("score") or not (ctx["score"] is int):
			return Result.failure("ctx.score 缺失或类型错误（期望 int）")
		ctx["score"] = int(ctx["score"]) + 1
		return Result.success()

static func _test_employee_effects_called_per_occurrence() -> Result:
	var emp_read := EmployeeDefClass.load_from_file("res://modules/base_employees/content/employees/waitress.json")
	if not emp_read.ok:
		return Result.failure("加载 waitress 定义失败: %s" % emp_read.error)
	var catalog = ContentCatalogClass.new()
	catalog.employees["waitress"] = emp_read.value
	var cfg := EmployeeRegistryClass.configure_from_catalog(catalog)
	if not cfg.ok:
		return Result.failure("配置 EmployeeRegistry 失败: %s" % cfg.error)

	var state := GameState.new()
	state.players = [
		{
			"employees": ["waitress", "waitress"],
			"milestones": [],
		},
		{
			"employees": [],
			"milestones": [],
		}
	]

	var reg = EffectRegistryClass.new()
	var handler := _CounterHandler.new()
	var rr := reg.register_effect("base_rules:dinnertime:tiebreaker:waitress", Callable(handler, "on_tiebreaker"), "base_rules")
	if not rr.ok:
		return rr

	var ctx := {"score": 0}
	var applied := DinnertimeSettlementClass._apply_employee_effects_by_segment(state, 0, reg, ":dinnertime:tiebreaker:", ctx)
	if not applied.ok:
		return applied
	if int(ctx.get("score", -1)) != 2:
		return Result.failure("effect 应按出现次数调用：期望 score=2，实际: %s" % str(ctx.get("score", null)))
	return Result.success()
