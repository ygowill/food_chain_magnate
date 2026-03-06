# initiate_marketing airplane overlap 状态访问回归测试
class_name InitiateMarketingAirplaneOverlapStateAccessTest
extends RefCounted

const ValidationClass = preload("res://gameplay/actions/initiate_marketing/validation.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var r := _test_overlap_rejects_same_side_segment_overlap()
	if not r.ok:
		return r
	r = _test_overlap_allows_other_side_segments()
	if not r.ok:
		return r
	r = _test_overlap_fails_fast_without_marketing_placements()
	if not r.ok:
		return r
	r = _test_overlap_fails_fast_on_invalid_marketing_placements_type()
	if not r.ok:
		return r
	return Result.success({"cases": 4})

static func _make_state() -> GameState:
	var state := GameState.new()
	state.map = {
		"grid_size": Vector2i(5, 5),
		"marketing_placements": {
			"6": {
				"type": "airplane",
				"world_pos": Vector2i(0, 0),
				"axis": "row",
				"footprint_size": Vector2i(5, 2),
			}
		}
	}
	return state

static func _test_overlap_rejects_same_side_segment_overlap() -> Result:
	var result := ValidationClass._validate_airplane_overlap(_make_state(), Vector2i(0, 1), "row", 2, 3)
	if result.ok:
		return Result.failure("同边 segment overlap 时应失败")
	var err := str(result.error)
	if err.find("同一边并重叠") < 0:
		return Result.failure("错误信息应包含 overlap 语义，实际: %s" % err)
	return Result.success()

static func _test_overlap_allows_other_side_segments() -> Result:
	var result := ValidationClass._validate_airplane_overlap(_make_state(), Vector2i(4, 1), "row", 2, 3)
	if not result.ok:
		return Result.failure("另一边的 segment 不应被误判重叠: %s" % result.error)
	return Result.success()

static func _test_overlap_fails_fast_without_marketing_placements() -> Result:
	var state := _make_state()
	state.map.erase("marketing_placements")
	var result := ValidationClass._validate_airplane_overlap(state, Vector2i(0, 1), "row", 2, 3)
	if result.ok:
		return Result.failure("缺失 marketing_placements 时应失败")
	var err := str(result.error)
	if err.find("state.map.marketing_placements") < 0:
		return Result.failure("错误信息应包含 state.map.marketing_placements，实际: %s" % err)
	return Result.success()

static func _test_overlap_fails_fast_on_invalid_marketing_placements_type() -> Result:
	var state := _make_state()
	state.map["marketing_placements"] = []
	var result := ValidationClass._validate_airplane_overlap(state, Vector2i(0, 1), "row", 2, 3)
	if result.ok:
		return Result.failure("marketing_placements 类型错误时应失败")
	var err := str(result.error)
	if err.find("state.map.marketing_placements") < 0:
		return Result.failure("错误信息应包含 state.map.marketing_placements，实际: %s" % err)
	return Result.success()
