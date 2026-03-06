# map context builder 状态访问回归测试
class_name MapContextBuilderStateAccessTest
extends RefCounted

const BuilderClass = preload("res://core/map/map_context_builder.gd")

static func run(_player_count: int = 2, _seed_val: int = 12345) -> Result:
	var r := _test_build_context_result_succeeds_with_valid_map()
	if not r.ok:
		return r
	r = _test_build_context_result_fails_fast_on_missing_houses()
	if not r.ok:
		return r
	r = _test_build_context_result_fails_fast_on_missing_restaurants()
	if not r.ok:
		return r
	r = _test_build_context_result_fails_fast_on_missing_marketing_placements()
	if not r.ok:
		return r
	r = _test_build_context_result_fails_fast_on_invalid_marketing_placements_type()
	if not r.ok:
		return r
	return Result.success({"cases": 5})

static func _make_state() -> GameState:
	var state := GameState.new()
	state.map = {
		"grid_size": Vector2i(3, 3),
		"cells": [],
		"houses": {},
		"restaurants": {},
		"marketing_placements": {},
		"drink_sources": [],
	}
	for y in range(3):
		var row: Array = []
		for x in range(3):
			row.append({
				"structure": {},
				"road_segments": [],
				"blocked": false,
			})
		state.map["cells"].append(row)
	return state

static func _test_build_context_result_succeeds_with_valid_map() -> Result:
	var result := BuilderClass.build_context_result(_make_state(), "map_context_builder_test")
	if not result.ok:
		return Result.failure("合法 map context 不应失败: %s" % result.error)
	var map_ctx: Dictionary = result.value
	if not (map_ctx.get("marketing_placements", null) is Dictionary):
		return Result.failure("map_ctx.marketing_placements 应为 Dictionary")
	return Result.success()

static func _test_build_context_result_fails_fast_on_missing_houses() -> Result:
	var state := _make_state()
	state.map.erase("houses")
	var result := BuilderClass.build_context_result(state, "map_context_builder_test")
	if result.ok:
		return Result.failure("缺失 houses 时应失败")
	var err := str(result.error)
	if err.find("state.map.houses") < 0:
		return Result.failure("错误信息应包含 state.map.houses，实际: %s" % err)
	return Result.success()

static func _test_build_context_result_fails_fast_on_missing_restaurants() -> Result:
	var state := _make_state()
	state.map.erase("restaurants")
	var result := BuilderClass.build_context_result(state, "map_context_builder_test")
	if result.ok:
		return Result.failure("缺失 restaurants 时应失败")
	var err := str(result.error)
	if err.find("state.map.restaurants") < 0:
		return Result.failure("错误信息应包含 state.map.restaurants，实际: %s" % err)
	return Result.success()

static func _test_build_context_result_fails_fast_on_missing_marketing_placements() -> Result:
	var state := _make_state()
	state.map.erase("marketing_placements")
	var result := BuilderClass.build_context_result(state, "map_context_builder_test")
	if result.ok:
		return Result.failure("缺失 marketing_placements 时应失败")
	var err := str(result.error)
	if err.find("state.map.marketing_placements") < 0:
		return Result.failure("错误信息应包含 state.map.marketing_placements，实际: %s" % err)
	return Result.success()

static func _test_build_context_result_fails_fast_on_invalid_marketing_placements_type() -> Result:
	var state := _make_state()
	state.map["marketing_placements"] = []
	var result := BuilderClass.build_context_result(state, "map_context_builder_test")
	if result.ok:
		return Result.failure("marketing_placements 类型错误时应失败")
	var err := str(result.error)
	if err.find("state.map.marketing_placements") < 0:
		return Result.failure("错误信息应包含 state.map.marketing_placements，实际: %s" % err)
	return Result.success()
