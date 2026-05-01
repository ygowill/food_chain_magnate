# rural offramp airplane overlap 状态访问回归测试
class_name RuralOfframpAirplaneOverlapStateAccessTest
extends RefCounted

const ActionClass = preload("res://modules/rural_marketeers/actions/place_highway_offramp_action.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var r := _test_overlap_detects_airplane_segment()
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
		"grid_size": Vector2i(5, 5),
		"marketing_placements": {
			"a": {
				"type": "airplane",
				"world_pos": Vector2i(0, 0),
				"axis": "col",
				"footprint_size": Vector2i(5, 2),
			}
		}
	}
	return state

static func _test_overlap_detects_airplane_segment() -> Result:
	var result := ActionClass._has_airplane_overlap_at_connection_cell(_make_state(), Vector2i(2, 0), "N")
	if not result.ok:
		return Result.failure("有合法 marketing_placements 时不应失败: %s" % result.error)
	if not bool(result.value):
		return Result.failure("应检测到 airplane segment overlap")
	return Result.success()

static func _test_overlap_fails_fast_without_marketing_placements() -> Result:
	var state := _make_state()
	state.map.erase("marketing_placements")
	var result := ActionClass._has_airplane_overlap_at_connection_cell(state, Vector2i(2, 0), "N")
	if result.ok:
		return Result.failure("缺失 marketing_placements 时应失败")
	var err := str(result.error)
	if err.find("state.map.marketing_placements") < 0:
		return Result.failure("错误信息应包含 state.map.marketing_placements，实际: %s" % err)
	return Result.success()

static func _test_overlap_fails_fast_on_invalid_marketing_placements_type() -> Result:
	var state := _make_state()
	state.map["marketing_placements"] = []
	var result := ActionClass._has_airplane_overlap_at_connection_cell(state, Vector2i(2, 0), "N")
	if result.ok:
		return Result.failure("marketing_placements 类型错误时应失败")
	var err := str(result.error)
	if err.find("state.map.marketing_placements") < 0:
		return Result.failure("错误信息应包含 state.map.marketing_placements，实际: %s" % err)
	return Result.success()
