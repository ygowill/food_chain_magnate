# initiate_marketing overlap 状态访问回归测试
class_name InitiateMarketingOverlapStateAccessTest
extends RefCounted

const ValidationClass = preload("res://gameplay/actions/initiate_marketing/validation.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var r := _test_overlap_detects_existing_non_airplane_marketing()
	if not r.ok:
		return r
	r = _test_overlap_fails_fast_without_marketing_placements()
	if not r.ok:
		return r
	r = _test_overlap_fails_fast_on_invalid_marketing_placements_type()
	if not r.ok:
		return r
	return Result.success({"cases": 3})

static func _make_state() -> GameState:
	var state := GameState.new()
	state.map = {
		"marketing_placements": {
			"1": {
				"type": "radio",
				"world_pos": Vector2i(2, 2),
				"footprint_size": Vector2i(2, 1),
				"rotation": 0,
			}
		}
	}
	return state

static func _test_overlap_detects_existing_non_airplane_marketing() -> Result:
	var result := ValidationClass._has_marketing_overlap_excluding_airplane(_make_state(), [Vector2i(2, 2)])
	if not result.ok:
		return Result.failure("有合法 marketing_placements 时不应失败: %s" % result.error)
	if not bool(result.value):
		return Result.failure("应检测到已有非 airplane 营销占地重叠")
	return Result.success()

static func _test_overlap_fails_fast_without_marketing_placements() -> Result:
	var state := _make_state()
	state.map.erase("marketing_placements")
	var result := ValidationClass._has_marketing_overlap_excluding_airplane(state, [Vector2i(2, 2)])
	if result.ok:
		return Result.failure("缺失 marketing_placements 时应失败")
	var err := str(result.error)
	if err.find("state.map.marketing_placements") < 0:
		return Result.failure("错误信息应包含 state.map.marketing_placements，实际: %s" % err)
	return Result.success()

static func _test_overlap_fails_fast_on_invalid_marketing_placements_type() -> Result:
	var state := _make_state()
	state.map["marketing_placements"] = []
	var result := ValidationClass._has_marketing_overlap_excluding_airplane(state, [Vector2i(2, 2)])
	if result.ok:
		return Result.failure("marketing_placements 类型错误时应失败")
	var err := str(result.error)
	if err.find("state.map.marketing_placements") < 0:
		return Result.failure("错误信息应包含 state.map.marketing_placements，实际: %s" % err)
	return Result.success()
