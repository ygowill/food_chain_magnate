# marketing 业务 helper 回归测试
class_name MarketingRulesDomainTest
extends RefCounted

const MarketingRulesClass = preload("res://core/rules/marketing_rules.gd")

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
	return Result.success({"cases": 5})

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
