# marketing 业务 helper 回归测试
class_name MarketingRulesDomainTest
extends RefCounted

const MarketingRulesClass = preload("res://core/rules/marketing_rules.gd")
const InitiateMarketingActionClass = preload("res://gameplay/actions/initiate_marketing_action.gd")

static func run(player_count: int = 2, seed_val: int = 12345) -> Result:
	var r := _test_require_board_spec_returns_marketing_type_and_footprint(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_require_board_spec_rejects_removed_board_for_two_players(seed_val)
	if not r.ok:
		return r
	r = _test_require_marketable_product_rejects_unknown_product(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_require_rotation_rejects_invalid_value()
	if not r.ok:
		return r
	r = _test_get_rotated_footprint_size_swaps_dimensions()
	if not r.ok:
		return r
	r = _test_require_marketing_employee_rejects_unknown_employee(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_require_marketing_employee_rejects_wrong_usage(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_require_marketing_duration_rejects_overflow(player_count, seed_val)
	if not r.ok:
		return r
	r = _test_require_airplane_axis_uses_fallback()
	if not r.ok:
		return r
	r = _test_require_airplane_axis_rejects_invalid_type(player_count, seed_val)
	if not r.ok:
		return r
	return Result.success({"cases": 10})

static func _init_engine(player_count: int, seed_val: int) -> Result:
	var engine := GameEngine.new()
	var init := engine.initialize(player_count, seed_val)
	if not init.ok:
		return Result.failure("初始化失败: %s" % init.error)
	return Result.success(engine)

static func _test_require_board_spec_returns_marketing_type_and_footprint(player_count: int, seed_val: int) -> Result:
	var engine_read := _init_engine(player_count, seed_val)
	if not engine_read.ok:
		return engine_read
	var engine: GameEngine = engine_read.value
	var result := MarketingRulesClass.require_board_spec(engine.get_state(), 11)
	if not result.ok:
		return Result.failure("board #11 不应失败: %s" % result.error)
	var spec: Dictionary = result.value
	if str(spec.get("marketing_type", "")) != "billboard":
		return Result.failure("board #11 type 应为 billboard，实际: %s" % str(spec.get("marketing_type", null)))
	var footprint_val = spec.get("footprint_size", null)
	if not (footprint_val is Vector2i) or Vector2i(footprint_val) != Vector2i(3, 2):
		return Result.failure("board #11 footprint_size 不正确，实际: %s" % str(footprint_val))
	return Result.success()

static func _test_require_board_spec_rejects_removed_board_for_two_players(seed_val: int) -> Result:
	var engine_read := _init_engine(2, seed_val)
	if not engine_read.ok:
		return engine_read
	var engine: GameEngine = engine_read.value
	var result := MarketingRulesClass.require_board_spec(engine.get_state(), 12)
	if result.ok:
		return Result.failure("2 人局 board #12 应被视为移除")
	var err := str(result.error)
	if err.find("已移除") < 0:
		return Result.failure("错误信息应包含已移除语义，实际: %s" % err)
	return Result.success()

static func _test_require_marketable_product_rejects_unknown_product(player_count: int, seed_val: int) -> Result:
	var engine_read := _init_engine(player_count, seed_val)
	if not engine_read.ok:
		return engine_read
	var result := MarketingRulesClass.require_marketable_product("unknown_product")
	if result.ok:
		return Result.failure("未知产品应失败")
	var err := str(result.error)
	if err.find("未知的产品") < 0:
		return Result.failure("错误信息应包含未知产品语义，实际: %s" % err)
	return Result.success()

static func _test_require_rotation_rejects_invalid_value() -> Result:
	var result := MarketingRulesClass.require_rotation(45)
	if result.ok:
		return Result.failure("非法 rotation 应失败")
	var err := str(result.error)
	if err.find("rotation 非法") < 0:
		return Result.failure("错误信息应包含 rotation 非法，实际: %s" % err)
	return Result.success()

static func _test_get_rotated_footprint_size_swaps_dimensions() -> Result:
	var result := MarketingRulesClass.get_rotated_footprint_size(Vector2i(3, 2), 90)
	if not result.ok:
		return Result.failure("90 度旋转不应失败: %s" % result.error)
	var size_val = result.value
	if not (size_val is Vector2i) or Vector2i(size_val) != Vector2i(2, 3):
		return Result.failure("90 度旋转后 footprint 应为 2x3，实际: %s" % str(size_val))
	return Result.success()

static func _test_require_marketing_employee_rejects_unknown_employee(player_count: int, seed_val: int) -> Result:
	var engine_read := _init_engine(player_count, seed_val)
	if not engine_read.ok:
		return engine_read
	var result := MarketingRulesClass.require_marketing_employee("ghost_employee", "billboard")
	if result.ok:
		return Result.failure("未知员工应失败")
	var err := str(result.error)
	if err.find("未知的员工类型") < 0:
		return Result.failure("错误信息应包含未知员工语义，实际: %s" % err)
	return Result.success()

static func _test_require_marketing_employee_rejects_wrong_usage(player_count: int, seed_val: int) -> Result:
	var engine_read := _init_engine(player_count, seed_val)
	if not engine_read.ok:
		return engine_read
	var result := MarketingRulesClass.require_marketing_employee("marketing_trainee", "radio")
	if result.ok:
		return Result.failure("marketing_trainee 不应能发起 radio")
	var err := str(result.error)
	if err.find("radio") < 0:
		return Result.failure("错误信息应包含 radio 语义，实际: %s" % err)
	return Result.success()

static func _test_require_marketing_duration_rejects_overflow(player_count: int, seed_val: int) -> Result:
	var engine_read := _init_engine(player_count, seed_val)
	if not engine_read.ok:
		return engine_read
	var action = InitiateMarketingActionClass.new()
	var command := Command.create("initiate_marketing", 0, {"duration": 99})
	var result := MarketingRulesClass.require_marketing_duration(action, command, 2)
	if result.ok:
		return Result.failure("超出上限的 duration 应失败")
	var err := str(result.error)
	if err.find("持续时间超出上限") < 0:
		return Result.failure("错误信息应包含 duration 上限语义，实际: %s" % err)
	return Result.success()

static func _test_require_airplane_axis_uses_fallback() -> Result:
	var action = InitiateMarketingActionClass.new()
	var command := Command.create("initiate_marketing", 0, {})
	var result := MarketingRulesClass.require_airplane_axis(action, command, "row")
	if not result.ok:
		return Result.failure("使用 fallback axis 时不应失败: %s" % result.error)
	if str(result.value) != "row":
		return Result.failure("fallback axis 应为 row，实际: %s" % str(result.value))
	return Result.success()

static func _test_require_airplane_axis_rejects_invalid_type(player_count: int, seed_val: int) -> Result:
	var engine_read := _init_engine(player_count, seed_val)
	if not engine_read.ok:
		return engine_read
	var action = InitiateMarketingActionClass.new()
	var command := Command.create("initiate_marketing", 0, {"axis": 1})
	var result := MarketingRulesClass.require_airplane_axis(action, command, "")
	if result.ok:
		return Result.failure("非法 axis 类型应失败")
	return Result.success()
