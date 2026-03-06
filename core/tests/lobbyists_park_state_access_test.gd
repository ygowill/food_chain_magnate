# lobbyists park 状态访问回归测试
class_name LobbyistsParkStateAccessTest
extends RefCounted

const ActionClass = preload("res://modules/lobbyists/actions/place_lobbyists_park_action.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var r := _test_is_adjacent_returns_false_with_empty_restaurants()
	if not r.ok:
		return r
	r = _test_is_adjacent_fails_fast_on_missing_restaurants()
	if not r.ok:
		return r
	r = _test_build_map_context_succeeds_with_valid_map()
	if not r.ok:
		return r
	r = _test_build_map_context_fails_fast_on_missing_houses()
	if not r.ok:
		return r
	r = _test_build_map_context_fails_fast_on_missing_marketing_placements()
	if not r.ok:
		return r
	r = _test_build_map_context_fails_fast_on_invalid_marketing_placements_type()
	if not r.ok:
		return r
	return Result.success({"cases": 6})

static func _make_state() -> GameState:
	var state := GameState.new()
	state.map = {
		"grid_size": Vector2i(3, 3),
		"cells": [],
		"boundary_index": {},
		"houses": {},
		"restaurants": {},
		"marketing_placements": {},
	}
	var cells := []
	for y in range(3):
		var row := []
		for x in range(3):
			row.append({
				"road_segments": [],
				"structure": {},
				"terrain_type": null,
				"drink_source": null,
				"tile_origin": Vector2i.ZERO,
				"blocked": false,
			})
		cells.append(row)
	state.map["cells"] = cells
	state.map["cells"][1][1]["road_segments"] = [{
		"dirs": ["N", "S"],
		"bridge": false,
	}]
	return state

static func _test_is_adjacent_returns_false_with_empty_restaurants() -> Result:
	var action = ActionClass.new()
	var state := _make_state()
	var piece_cells: Array[Vector2i] = [Vector2i(0, 0)]
	var result := action._is_adjacent_to_reachable_road(state, 0, piece_cells, 2)
	if not result.ok:
		return Result.failure("空 restaurants 时不应失败: %s" % result.error)
	if bool(result.value):
		return Result.failure("空 restaurants 时应返回 false")
	return Result.success()

static func _test_is_adjacent_fails_fast_on_missing_restaurants() -> Result:
	var action = ActionClass.new()
	var state := _make_state()
	state.map.erase("restaurants")
	var piece_cells: Array[Vector2i] = [Vector2i(0, 0)]
	var result := action._is_adjacent_to_reachable_road(state, 0, piece_cells, 2)
	if result.ok:
		return Result.failure("缺失 restaurants 时应失败")
	var err := str(result.error)
	if err.find("state.map.restaurants") < 0:
		return Result.failure("错误信息应包含 state.map.restaurants，实际: %s" % err)
	return Result.success()

static func _test_build_map_context_succeeds_with_valid_map() -> Result:
	var action = ActionClass.new()
	var result := action._build_map_context(_make_state())
	if not result.ok:
		return Result.failure("合法 map context 不应失败: %s" % result.error)
	var map_ctx: Dictionary = result.value
	if not (map_ctx.get("marketing_placements", null) is Dictionary):
		return Result.failure("map_ctx.marketing_placements 应为 Dictionary")
	return Result.success()

static func _test_build_map_context_fails_fast_on_missing_houses() -> Result:
	var action = ActionClass.new()
	var state := _make_state()
	state.map.erase("houses")
	var result := action._build_map_context(state)
	if result.ok:
		return Result.failure("缺失 houses 时应失败")
	var err := str(result.error)
	if err.find("state.map.houses") < 0:
		return Result.failure("错误信息应包含 state.map.houses，实际: %s" % err)
	return Result.success()

static func _test_build_map_context_fails_fast_on_missing_marketing_placements() -> Result:
	var action = ActionClass.new()
	var state := _make_state()
	state.map.erase("marketing_placements")
	var result := action._build_map_context(state)
	if result.ok:
		return Result.failure("缺失 marketing_placements 时应失败")
	var err := str(result.error)
	if err.find("state.map.marketing_placements") < 0:
		return Result.failure("错误信息应包含 state.map.marketing_placements，实际: %s" % err)
	return Result.success()

static func _test_build_map_context_fails_fast_on_invalid_marketing_placements_type() -> Result:
	var action = ActionClass.new()
	var state := _make_state()
	state.map["marketing_placements"] = []
	var result := action._build_map_context(state)
	if result.ok:
		return Result.failure("marketing_placements 类型错误时应失败")
	var err := str(result.error)
	if err.find("state.map.marketing_placements") < 0:
		return Result.failure("错误信息应包含 state.map.marketing_placements，实际: %s" % err)
	return Result.success()
