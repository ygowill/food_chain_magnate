# lobbyists extra tile 状态访问回归测试
class_name LobbyistsExtraTileStateAccessTest
extends RefCounted

const ActionClass = preload("res://modules/lobbyists/actions/place_lobbyists_extra_map_tile_action.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var r := _test_edge_conflicts_detects_airplane_overlap()
	if not r.ok:
		return r
	r = _test_edge_conflicts_fails_fast_on_missing_marketing_placements()
	if not r.ok:
		return r
	r = _test_edge_conflicts_fails_fast_on_invalid_marketing_placements_type()
	if not r.ok:
		return r
	return Result.success({"cases": 3})

static func _make_state() -> GameState:
	var state := GameState.new()
	state.map = {
		"grid_size": Vector2i(5, 5),
		"external_cells": {},
		"marketing_placements": {
			"airplane": {
				"type": "airplane",
				"world_pos": Vector2i(0, 0),
				"axis": "col",
				"footprint_size": Vector2i(5, 2),
			}
		}
	}
	return state

static func _test_edge_conflicts_detects_airplane_overlap() -> Result:
	var action = ActionClass.new()
	var result := action._check_edge_conflicts(_make_state(), Vector2i(0, 0), "N")
	if result.ok:
		return Result.failure("airplane 冲突时应失败")
	var err := str(result.error)
	if err.find("airplane") < 0:
		return Result.failure("错误信息应包含 airplane，实际: %s" % err)
	return Result.success()

static func _test_edge_conflicts_fails_fast_on_missing_marketing_placements() -> Result:
	var action = ActionClass.new()
	var state := _make_state()
	state.map.erase("marketing_placements")
	var result := action._check_edge_conflicts(state, Vector2i(0, 0), "N")
	if result.ok:
		return Result.failure("缺失 marketing_placements 时应失败")
	var err := str(result.error)
	if err.find("state.map.marketing_placements") < 0:
		return Result.failure("错误信息应包含 state.map.marketing_placements，实际: %s" % err)
	return Result.success()

static func _test_edge_conflicts_fails_fast_on_invalid_marketing_placements_type() -> Result:
	var action = ActionClass.new()
	var state := _make_state()
	state.map["marketing_placements"] = []
	var result := action._check_edge_conflicts(state, Vector2i(0, 0), "N")
	if result.ok:
		return Result.failure("marketing_placements 类型错误时应失败")
	var err := str(result.error)
	if err.find("state.map.marketing_placements") < 0:
		return Result.failure("错误信息应包含 state.map.marketing_placements，实际: %s" % err)
	return Result.success()
